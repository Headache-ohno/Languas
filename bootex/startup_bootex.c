#include <limits.h>

#if UCHAR_MAX != 0xFFu || UINT_MAX != 0xFFFFFFFFu
#error "Bootex startup requires 8-bit bytes and a 32-bit unsigned int"
#endif

typedef unsigned int bx_u32;
typedef unsigned char bx_u8;

typedef char bx_u32_must_be_32_bits[(sizeof(bx_u32) == 4u) ? 1 : -1];

extern void Reset_Handler(void);

#define BOOTEX_STACK_TOP 0x20001000u

__attribute__((section(".vectors"), used))
const bx_u32 bootex_vectors[] = {
    BOOTEX_STACK_TOP,
    (bx_u32)Reset_Handler
};

extern void bx_boot(void);
extern bx_u8 __data_load__;
extern bx_u8 __data_start__;
extern bx_u8 __data_end__;
extern bx_u8 __bss_start__;
extern bx_u8 __bss_end__;

static void bx_runtime_init(void) {
    bx_u8 *source = &__data_load__;
    bx_u8 *destination = &__data_start__;

    while (destination < &__data_end__) {
        *destination++ = *source++;
    }
    destination = &__bss_start__;
    while (destination < &__bss_end__) {
        *destination++ = 0u;
    }
}

__attribute__((noreturn))
void Reset_Handler(void) {
    bx_runtime_init();
    bx_boot();

    for (;;) {
    }
}
