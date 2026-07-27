#include "languas_core.h"

#define SIM_GPIO_IN     (*(volatile lg_u8  *)0x20000000u)
#define SIM_GPIO_OUT    (*(volatile lg_u8  *)0x20000004u)
#define SIM_UART_TX     (*(volatile lg_u8  *)0x20000008u)
#define SIM_UART_RX     (*(volatile lg_u8  *)0x2000000Cu)
#define SIM_PANIC_CODE  (*(volatile lg_u8  *)0x20000010u)

lg_u8 lg_platform_read(lg_u8 port) {
    switch (port) {
        case LG_PORT_GPIO_IN:
            return SIM_GPIO_IN;

        case LG_PORT_UART_RX:
            return SIM_UART_RX;

        default:
            return 0x00u;
    }
}

void lg_platform_write(lg_u8 port, lg_u8 value) {
    switch (port) {
        case LG_PORT_GPIO_OUT:
            SIM_GPIO_OUT = value;
            break;

        case LG_PORT_UART_TX:
            SIM_UART_TX = value;
            break;

        case LG_PORT_UART_RX:
            SIM_UART_RX = value;
            break;

        default:
            lg_panic(LG_PANIC_INVALID_PORT);
            break;
    }
}

void lg_platform_panic(lg_u8 code) {
    SIM_PANIC_CODE = code;

    for (;;) {
    }
}

void lg_platform_idle(void) {
    __asm__ volatile ("nop");
}
