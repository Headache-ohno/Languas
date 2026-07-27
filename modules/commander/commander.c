#include "languas_core.h"
#include "screen.h"
#include "key.h"

#define CMD_BUFFER_SIZE 64

#if CMD_BUFFER_SIZE < 2 || CMD_BUFFER_SIZE > 256
#error "CMD_BUFFER_SIZE must fit the lg_u8 command length and leave room for NUL"
#endif

static char s_cmd_buf[CMD_BUFFER_SIZE];
static lg_u8 s_cmd_len = 0;

static int mystrcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

static int mystrncmp(const char *s1, const char *s2, lg_u16 n) {
    while (n > 0u && *s1 == *s2) {
        if (*s1 == '\0') {
            return 0;
        }
        s1++;
        s2++;
        n--;
    }
    if (n == 0u) return 0;
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

static void cmd_help(void) {
    screen_print("help    show commands\r\n");
    screen_print("ver     show version\r\n");
    screen_print("mem     show memory info\r\n");
    screen_print("clear   clear screen\r\n");
    screen_print("echo    print text\r\n");
    screen_print("panic   test panic\r\n");
}

static void cmd_ver(void) {
    screen_print("Languas OS v0.1\r\n");
}

static void cmd_mem(void) {
    screen_print("RAM: 0x20000000 - 0x20001000 (4KB)\r\n");
    screen_print("ROM: 0x00000000 - 0x00008000 (32KB)\r\n");
}

static void cmd_clear(void) {
    screen_clear();
}

static void cmd_panic(void) {
    screen_print("Triggering panic...\r\n");
    lg_panic(LG_PANIC_ASSERT);
}

static void execute_command(const char *line) {
    if (mystrcmp(line, "help") == 0) {
        cmd_help();
    } else if (mystrcmp(line, "ver") == 0) {
        cmd_ver();
    } else if (mystrcmp(line, "mem") == 0) {
        cmd_mem();
    } else if (mystrcmp(line, "clear") == 0) {
        cmd_clear();
    } else if (mystrcmp(line, "panic") == 0) {
        cmd_panic();
    } else if (mystrncmp(line, "echo ", 5u) == 0) {
        screen_print(line + 5u);
        screen_print("\r\n");
    } else if (mystrcmp(line, "echo") == 0) {
        screen_print("\r\n");
    } else {
        screen_print("Unknown command: ");
        screen_print(line);
        screen_print("\r\n");
    }
}

__attribute__((noreturn))
void lg_app_run(void) {
    s_cmd_len = 0u;
    screen_init();
    key_init();
    screen_clear();
    screen_print("Languas Commander\r\n");
    screen_print("Ultra Pure.\r\n\r\n");
    screen_print("> ");

    for (;;) {
        lg_tick();

        lg_u8 c = key_getc();
        if (c != 0u) {
            if (c == '\r' || c == '\n') {
                screen_print("\r\n");
                if (s_cmd_len > 0u) {
                    s_cmd_buf[s_cmd_len] = '\0';
                    execute_command(s_cmd_buf);
                    s_cmd_len = 0u;
                }
                screen_print("> ");
            } else if (c == '\b' || c == 127u) {
                if (s_cmd_len > 0u) {
                    s_cmd_len--;
                    screen_print("\b \b");
                }
            } else if (c >= 0x20u && c <= 0x7Eu &&
                       s_cmd_len < (lg_u8)(CMD_BUFFER_SIZE - 1)) {
                s_cmd_buf[s_cmd_len++] = (char)c;
                screen_putc((char)c);
            }
        }
        lg_idle();
    }
}
