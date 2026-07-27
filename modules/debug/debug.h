#ifndef DEBUG_H
#define DEBUG_H

#include "languas_types.h"

void debug_init(void);
void debug_hex(lg_u8 val);
void debug_print(const char *msg);

#endif
