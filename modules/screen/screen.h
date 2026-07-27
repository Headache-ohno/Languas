#ifndef SCREEN_H
#define SCREEN_H

#include "languas_types.h"

void screen_init(void);
void screen_putc(char c);
void screen_print(const char *str);
void screen_clear(void);

#endif
