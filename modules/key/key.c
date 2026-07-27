#include "key.h"
#include "languas_core.h"

void key_init(void) {
    lg_write(LG_PORT_UART_RX, 0u);
}

lg_u8 key_getc(void) {
    lg_u8 val = lg_read(LG_PORT_UART_RX);
    if (val != 0u) {
        /* Acknowledge character read by clearing input register */
        lg_write(LG_PORT_UART_RX, 0u);
    }
    return val;
}
