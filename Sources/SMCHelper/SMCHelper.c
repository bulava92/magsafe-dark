#include "SMCHelper.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

static uint32_t fourcc(const char key[5]) {
    return ((uint32_t)key[0] << 24) | ((uint32_t)key[1] << 16) | ((uint32_t)key[2] << 8) | (uint32_t)key[3];
}

static kern_return_t smc_open(io_connect_t *conn) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, conn);
    IOObjectRelease(service);
    return kr;
}

static kern_return_t smc_call(io_connect_t conn, SMCParamStruct *input, SMCParamStruct *output) {
    size_t inSize = sizeof(*input), outSize = sizeof(*output);
    memset(output, 0, sizeof(*output));
    return IOConnectCallStructMethod(conn, 2, input, inSize, output, &outSize);
}

static kern_return_t get_key_info(io_connect_t conn, uint32_t key, SMCKeyInfoData *info) {
    SMCParamStruct in = {0}, out = {0};
    in.key = key;
    in.data8 = 9;
    kern_return_t kr = smc_call(conn, &in, &out);
    if (kr == KERN_SUCCESS) *info = out.keyInfo;
    return kr;
}

int smc_write_u8(const char key[5], uint8_t value) {
    io_connect_t conn = IO_OBJECT_NULL;
    kern_return_t kr = smc_open(&conn);
    if (kr != KERN_SUCCESS) return (int)kr;

    SMCKeyInfoData info = {0};
    uint32_t k = fourcc(key);
    kr = get_key_info(conn, k, &info);
    if (kr != KERN_SUCCESS) { IOServiceClose(conn); return (int)kr; }

    SMCParamStruct in = {0}, out = {0};
    in.key = k;
    in.data8 = 6;
    in.keyInfo.dataSize = info.dataSize ? info.dataSize : 1;
    in.bytes[0] = value;
    kr = smc_call(conn, &in, &out);
    IOServiceClose(conn);
    return (int)kr;
}

int smc_read_u8(const char key[5], uint8_t *value) {
    if (!value) return -1;
    io_connect_t conn = IO_OBJECT_NULL;
    kern_return_t kr = smc_open(&conn);
    if (kr != KERN_SUCCESS) return (int)kr;

    SMCKeyInfoData info = {0};
    uint32_t k = fourcc(key);
    kr = get_key_info(conn, k, &info);
    if (kr != KERN_SUCCESS) { IOServiceClose(conn); return (int)kr; }

    SMCParamStruct in = {0}, out = {0};
    in.key = k;
    in.data8 = 5;
    in.keyInfo.dataSize = info.dataSize ? info.dataSize : 1;
    kr = smc_call(conn, &in, &out);
    if (kr == KERN_SUCCESS) *value = out.bytes[0];
    IOServiceClose(conn);
    return (int)kr;
}
