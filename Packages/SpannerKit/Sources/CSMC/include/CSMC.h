#ifndef CSMC_H
#define CSMC_H

#include <stdbool.h>
#include <stdint.h>

// Read-only access to AppleSMC keys. Reads need no root on Apple Silicon;
// writes are deliberately not exposed (charge control lives in a future
// privileged helper, see docs/Phase 0 results.md).

/// Opens a connection to AppleSMC. Returns false if the service is missing.
bool smc_open(uint32_t *connection);

/// Closes a connection returned by smc_open.
void smc_close(uint32_t connection);

/// Reads a four-character key as a number. Supports the flt, ui8/16/32 and
/// si8/16 types, decoded little-endian as on Apple Silicon. Returns false when the key is missing, unreadable
/// without privileges, zero-sized, or of an unsupported type.
bool smc_read_number(uint32_t connection, const char key[4], double *value);

#endif
