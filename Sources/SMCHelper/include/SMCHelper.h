#ifndef SMC_HELPER_H
#define SMC_HELPER_H
#include <stdint.h>
int smc_write_u8(const char key[5], uint8_t value);
int smc_read_u8(const char key[5], uint8_t *value);
#endif
