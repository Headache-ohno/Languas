#include "screen.h"
#include "languas_core.h"

void screen_init(void) {
    // Standard terminal init can go here
}

void screen_putc(char c) {
    lg_write(LG_PORT_UART_TX, (lg_u8)c);
}

void screen_print(const char *str) {
    if (str == (const char *)0) {
        lg_panic(LG_PANIC_NULL_POINTER);
    }
    while (*str) {
        screen_putc(*str++);
    }
}

void screen_clear(void) {
    // ANSI clear screen and home cursor
    screen_print("\x1b[2J\x1b[H");
}
