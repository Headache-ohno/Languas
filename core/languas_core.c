#include "languas_core.h"

static lg_u32 lg_ticks;

#if defined(LG_TARGET_ARMV6M)
extern lg_u8 __data_load__;
extern lg_u8 __data_start__;
extern lg_u8 __data_end__;
extern lg_u8 __bss_start__;
extern lg_u8 __bss_end__;

static void lg_runtime_init(void) {
    lg_u8 *source = &__data_load__;
    lg_u8 *destination = &__data_start__;

    while (destination < &__data_end__) {
        *destination++ = *source++;
    }
    destination = &__bss_start__;
    while (destination < &__bss_end__) {
        *destination++ = 0u;
    }
}
#endif

void lg_init(void) {
    lg_ticks = 0u;
}

void lg_tick(void) {
    lg_ticks++;
}

void lg_idle(void) {
    lg_platform_idle();
}

lg_u8 lg_read(lg_u8 port) {
    return lg_platform_read(port);
}

void lg_write(lg_u8 port, lg_u8 value) {
    lg_platform_write(port, value);
}

__attribute__((noreturn))
void lg_panic(lg_u8 code) {
    lg_platform_panic(code);
    for (;;) {}
}

__attribute__((noreturn))
void lg_run(void) {
    lg_app_run();
    for (;;) {}
}

__attribute__((section(".lg_entry"), used, noreturn))
void lg_entry(void) {
#if defined(LG_TARGET_ARMV6M)
    lg_runtime_init();
#endif
    lg_init();
    lg_run();
    for (;;) {}
}
