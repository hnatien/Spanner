#include "CSMC.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
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

static UInt32 fourcc(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}

static kern_return_t call(io_connect_t connection, SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    return IOConnectCallStructMethod(connection, KERNEL_INDEX_SMC, in, sizeof(SMCParam), out, &outSize);
}

bool smc_open(uint32_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return false;
    io_connect_t handle = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &handle);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) return false;
    *connection = handle;
    return true;
}

void smc_close(uint32_t connection) {
    IOServiceClose(connection);
}

bool smc_read_number(uint32_t connection, const char key[4], double *value) {
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (call(connection, &in, &out) != KERN_SUCCESS || out.result != 0) return false;
    SMCKeyInfo info = out.keyInfo;
    if (info.dataSize == 0 || info.dataSize > 32) return false;

    memset(&out, 0, sizeof(out));
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (call(connection, &in, &out) != KERN_SUCCESS || out.result != 0) return false;

    // Apple Silicon SMC values are little-endian (B0AC "c704" = 1223 mA, as
    // measured in Phase 0), unlike the big-endian Intel SMC.
    const unsigned char *b = out.bytes;
    switch (info.dataType) {
    case 'flt ': {
        if (info.dataSize != 4) return false;
        float f;
        memcpy(&f, b, 4);
        *value = f;
        return true;
    }
    case 'ui8 ': *value = b[0]; return true;
    case 'ui16': *value = (UInt16)(b[0] | (b[1] << 8)); return true;
    case 'ui32': *value = (UInt32)(b[0] | ((UInt32)b[1] << 8) | ((UInt32)b[2] << 16) | ((UInt32)b[3] << 24)); return true;
    case 'si8 ': *value = (SInt8)b[0]; return true;
    case 'si16': *value = (SInt16)(b[0] | (b[1] << 8)); return true;
    default: return false;
    }
}
