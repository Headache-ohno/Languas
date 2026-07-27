#include "debug.h"
#include "screen.h"

void debug_init(void) {
    /* Ready */
}

void debug_hex(lg_u8 val) {
    const char hex_chars[] = "0123456789ABCDEF";
    screen_putc(hex_chars[(val >> 4) & 0x0Fu]);
    screen_putc(hex_chars[val & 0x0Fu]);
}

void debug_print(const char *msg) {
    screen_print("[DBG] ");
    screen_print(msg);
    screen_print("\r\n");
}
