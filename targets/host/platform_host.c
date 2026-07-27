#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include "languas_core.h"

#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#include <conio.h>
#include <windows.h>
#else
#include <signal.h>
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>
#endif

#if !defined(_WIN32)
static struct termios s_original_terminal;
static int s_terminal_configured;

static void restore_terminal(void) {
    if (s_terminal_configured) {
        (void)tcsetattr(STDIN_FILENO, TCSANOW, &s_original_terminal);
        s_terminal_configured = 0;
    }
}

static void handle_terminal_signal(int signal_number) {
    restore_terminal();
    (void)signal(signal_number, SIG_DFL);
    (void)raise(signal_number);
}

static void configure_terminal(void) {
    struct termios terminal;

    if (s_terminal_configured || !isatty(STDIN_FILENO)) {
        return;
    }
    if (tcgetattr(STDIN_FILENO, &s_original_terminal) != 0) {
        return;
    }

    terminal = s_original_terminal;
    terminal.c_lflag &= (tcflag_t)~(ICANON | ECHO);
    terminal.c_cc[VMIN] = 0;
    terminal.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &terminal) != 0) {
        return;
    }

    s_terminal_configured = 1;
    (void)atexit(restore_terminal);
    (void)signal(SIGINT, handle_terminal_signal);
    (void)signal(SIGTERM, handle_terminal_signal);
}
#endif

lg_u8 lg_platform_read(lg_u8 port) {
    switch (port) {
        case LG_PORT_GPIO_IN:
            return 0x00u;

        case LG_PORT_UART_RX:
#if defined(_WIN32)
            if (_kbhit()) {
                return (lg_u8)_getch();
            }
#else
            {
                fd_set read_set;
                struct timeval timeout = { 0, 0 };
                unsigned char character;

                configure_terminal();
                FD_ZERO(&read_set);
                FD_SET(STDIN_FILENO, &read_set);
                if (select(STDIN_FILENO + 1, &read_set, NULL, NULL, &timeout) > 0 &&
                    read(STDIN_FILENO, &character, 1u) == 1) {
                    return (lg_u8)character;
                }
            }
#endif
            return 0x00u;

        default:
            return 0x00u;
    }
}

void lg_platform_write(lg_u8 port, lg_u8 value) {
    switch (port) {
        case LG_PORT_GPIO_OUT:
            /* GPIO is intentionally silent in the hosted simulator. */
            break;

        case LG_PORT_UART_TX:
            (void)putchar((int)value);
            (void)fflush(stdout);
            break;

        case LG_PORT_UART_RX:
            /* Reading from the host terminal already consumes the character. */
            break;

        default:
            lg_panic(LG_PANIC_INVALID_PORT);
            break;
    }
}

void lg_platform_idle(void) {
#if defined(_WIN32)
    Sleep(1u);
#else
    struct timeval timeout = { 0, 1000 };
    (void)select(0, NULL, NULL, NULL, &timeout);
#endif
}

void lg_platform_panic(lg_u8 code) {
    fprintf(stderr, "\n[PANIC] OS panic: 0x%02X\n", code);
    exit((int)code);
}
