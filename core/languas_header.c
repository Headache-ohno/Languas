#include "languas_types.h"

typedef struct __attribute__((packed)) {
    lg_u8  magic[4];
    lg_u8  version_major;
    lg_u8  version_minor;
    lg_u8  target_class;
    lg_u8  flags;
    lg_u16 header_size;
    lg_u16 reserved;
} bx_header_t;

#ifndef CONFIG_PROFILE
#define CONFIG_PROFILE 0x01u
#endif

#if CONFIG_PROFILE < LG_PROFILE_CORE || CONFIG_PROFILE > LG_PROFILE_COMMANDER
#error "CONFIG_PROFILE is not accepted by the Bootex loader"
#endif

typedef char lg_header_must_be_12_bytes[(sizeof(bx_header_t) == 12u) ? 1 : -1];

__attribute__((section(".header"), used, aligned(1)))
const bx_header_t languas_header = {
    { 'L', 'G', 'U', 'S' },
    0,
    1,
    CONFIG_PROFILE,
    0,
    12,
    0
};
