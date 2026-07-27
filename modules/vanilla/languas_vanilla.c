#include "languas_core.h"

__attribute__((noreturn))
void lg_app_run(void) {
    for (;;) {
        lg_tick();

        lg_u8 input = lg_read(LG_PORT_GPIO_IN);
        lg_write(LG_PORT_GPIO_OUT, input);
        lg_idle();
    }
}
