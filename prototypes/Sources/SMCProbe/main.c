// Spike (b): which charge-control SMC keys exist and accept writes on this
// firmware? Key list and byte values come from Battery-Toolkit and batt #152.
//
//   smc-probe [read]                      read-only: key sizes/types/values
//   sudo smc-probe write KEY HEX [SECS]   write KEY, watch the battery for
//                                         SECS (default 10), then restore
//
// Writes are limited to CHIE, CH0J and ACLC, and the original value is
// restored on exit and on SIGINT/SIGTERM/SIGHUP.

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9

typedef struct { char major, minor, build, reserved[1]; UInt16 release; } SMCVersion;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { UInt32 dataSize; UInt32 dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    UInt32 key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    char result, status, data8;
    UInt32 data32;
    unsigned char bytes[32];
} SMCParam;
_Static_assert(sizeof(SMCParam) == 80, "SMCParam must match the AppleSMC user client layout");

static io_connect_t connection;

static UInt32 fourcc(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}

static void typeString(UInt32 type, char out[5]) {
    for (int i = 0; i < 4; i++) out[i] = (char)((type >> (24 - 8 * i)) & 0xff);
    out[4] = 0;
}

static kern_return_t call(SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    return IOConnectCallStructMethod(connection, KERNEL_INDEX_SMC, in, sizeof(SMCParam), out, &outSize);
}

// Returns the IOKit status; *smcResult carries the SMC's own result byte.
static kern_return_t readKey(const char *key, SMCKeyInfo *info, unsigned char bytes[32], int *smcResult) {
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t kr = call(&in, &out);
    *smcResult = out.result;
    if (kr != KERN_SUCCESS || out.result != 0) return kr;
    *info = out.keyInfo;
    if (info->dataSize == 0) return KERN_SUCCESS;

    memset(&out, 0, sizeof(out));
    in.keyInfo.dataSize = info->dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    kr = call(&in, &out);
    *smcResult = out.result;
    memcpy(bytes, out.bytes, 32);
    return kr;
}

static kern_return_t writeKey(const char *key, const unsigned char *bytes, UInt32 size, int *smcResult) {
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.keyInfo.dataSize = size;
    memcpy(in.bytes, bytes, size);
    kern_return_t kr = call(&in, &out);
    *smcResult = out.result;
    return kr;
}

static void printKey(const char *key) {
    SMCKeyInfo info = {0};
    unsigned char bytes[32] = {0};
    int smcResult = 0;
    kern_return_t kr = readKey(key, &info, bytes, &smcResult);
    if (kr != KERN_SUCCESS) {
        printf("  %-4s  IOKit error 0x%08x\n", key, kr);
        return;
    }
    if (smcResult != 0) {
        printf("  %-4s  missing (SMC result 0x%02x)\n", key, smcResult & 0xff);
        return;
    }
    char type[5];
    typeString(info.dataType, type);
    printf("  %-4s  size=%-2u type=%-4s value=", key, info.dataSize, type);
    if (info.dataSize == 0) printf("(zero-size placeholder)");
    for (UInt32 i = 0; i < info.dataSize && i < 32; i++) printf("%02x", bytes[i]);
    printf("\n");
}

static void printBattery(const char *label) {
    io_service_t battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!battery) {
        printf("%s: no AppleSmartBattery\n", label);
        return;
    }
    const char *names[] = {"ExternalConnected", "IsCharging", "CurrentCapacity", "Amperage"};
    printf("%s:", label);
    for (int i = 0; i < 4; i++) {
        CFStringRef name = CFStringCreateWithCString(NULL, names[i], kCFStringEncodingUTF8);
        CFTypeRef value = IORegistryEntryCreateCFProperty(battery, name, NULL, 0);
        long long number = 0;
        if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) number = CFBooleanGetValue(value);
        else if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberLongLongType, &number);
        printf(" %s=%lld", names[i], number);
        if (value) CFRelease(value);
        CFRelease(name);
    }
    CFDictionaryRef charger = IORegistryEntryCreateCFProperty(battery, CFSTR("ChargerData"), NULL, 0);
    if (charger && CFGetTypeID(charger) == CFDictionaryGetTypeID()) {
        CFNumberRef reason = CFDictionaryGetValue(charger, CFSTR("NotChargingReason"));
        long long number = 0;
        if (reason) CFNumberGetValue(reason, kCFNumberLongLongType, &number);
        printf(" NotChargingReason=0x%llx", number);
    }
    if (charger) CFRelease(charger);
    printf("\n");
    IOObjectRelease(battery);
}

// Restore state for the write path; also used from signal handlers.
static const char *restoreKey;
static unsigned char restoreBytes[32];
static UInt32 restoreSize;

static void restoreOriginal(void) {
    if (!restoreKey) return;
    int smcResult = 0;
    kern_return_t kr = writeKey(restoreKey, restoreBytes, restoreSize, &smcResult);
    printf("restore %s -> IOKit 0x%08x SMC 0x%02x\n", restoreKey, kr, smcResult & 0xff);
    restoreKey = NULL;
}

static void onSignal(int sig) {
    restoreOriginal();
    _exit(128 + sig);
}

static int parseHex(const char *hex, unsigned char out[32]) {
    size_t length = strlen(hex);
    if (length == 0 || length % 2 != 0 || length / 2 > 32) return -1;
    for (size_t i = 0; i < length / 2; i++) {
        unsigned int byte;
        if (sscanf(hex + 2 * i, "%2x", &byte) != 1) return -1;
        out[i] = (unsigned char)byte;
    }
    return (int)(length / 2);
}

static int runWrite(const char *key, const char *hex, int seconds) {
    if (strcmp(key, "CHIE") && strcmp(key, "CH0J") && strcmp(key, "ACLC")) {
        fprintf(stderr, "refusing to write %s; allowed: CHIE CH0J ACLC\n", key);
        return 64;
    }
    if (geteuid() != 0) {
        fprintf(stderr, "writes need root: sudo %s write %s %s\n", getprogname(), key, hex);
        return 77;
    }
    unsigned char value[32];
    int length = parseHex(hex, value);
    SMCKeyInfo info = {0};
    int smcResult = 0;
    kern_return_t kr = readKey(key, &info, restoreBytes, &smcResult);
    if (kr != KERN_SUCCESS || smcResult != 0 || info.dataSize == 0) {
        fprintf(stderr, "cannot read %s first (IOKit 0x%08x SMC 0x%02x size %u)\n", key, kr, smcResult & 0xff, info.dataSize);
        return 1;
    }
    if (length != (int)info.dataSize) {
        fprintf(stderr, "%s takes %u byte(s); got %d\n", key, info.dataSize, length);
        return 64;
    }
    restoreSize = info.dataSize;
    restoreKey = key;
    signal(SIGINT, onSignal);
    signal(SIGTERM, onSignal);
    signal(SIGHUP, onSignal);

    printBattery("before");
    kr = writeKey(key, value, info.dataSize, &smcResult);
    printf("write %s=%s -> IOKit 0x%08x SMC 0x%02x%s\n", key, hex, kr, smcResult & 0xff,
           kr == (kern_return_t)0xe00002c1 ? " (kIOReturnNotPrivileged)" : "");
    printKey(key);
    for (int i = 1; i <= seconds; i++) {
        sleep(1);
        if (i % 2 == 0 || i == seconds) {
            char label[16];
            snprintf(label, sizeof(label), "t+%ds", i);
            printBattery(label);
        }
    }
    restoreOriginal();
    printKey(key);
    printBattery("after restore");
    return (kr == KERN_SUCCESS && smcResult == 0) ? 0 : 2;
}

int main(int argc, const char *argv[]) {
    io_service_t smc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!smc || IOServiceOpen(smc, mach_task_self(), 0, &connection) != KERN_SUCCESS) {
        fprintf(stderr, "cannot open AppleSMC\n");
        return 1;
    }
    IOObjectRelease(smc);

    int status = 0;
    if (argc >= 4 && strcmp(argv[1], "write") == 0) {
        status = runWrite(argv[2], argv[3], argc >= 5 ? atoi(argv[4]) : 10);
    } else if (argc == 1 || strcmp(argv[1], "read") == 0) {
        printBattery("battery");
        const char *keys[] = {"CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J", "ACLC", "bfD0", "bfE0", "bfF0",
                              "CHWA", "BCLM", "BUIC", "AC-W", "PPBR", "PDTR", "TB1T", "TB2T", "B0AC"};
        puts("SMC keys:");
        for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) printKey(keys[i]);
    } else {
        fprintf(stderr, "usage: smc-probe [read] | sudo smc-probe write CHIE|CH0J|ACLC HEX [SECS]\n");
        status = 64;
    }
    IOServiceClose(connection);
    return status;
}
