#ifndef LANGUAS_CORE_H
#define LANGUAS_CORE_H

#include "languas_types.h"

void  lg_init(void);
void  lg_tick(void);
void  lg_idle(void);
void  lg_run(void) __attribute__((noreturn));
void  lg_entry(void) __attribute__((noreturn));
lg_u8 lg_read(lg_u8 port);
void  lg_write(lg_u8 port, lg_u8 value);
void  lg_panic(lg_u8 code) __attribute__((noreturn));

/* Implemented by the selected application module and baked into the image. */
extern void lg_app_run(void) __attribute__((noreturn));

/* Platform driver declarations */
extern lg_u8 lg_platform_read(lg_u8 port);
extern void  lg_platform_write(lg_u8 port, lg_u8 value);
extern void  lg_platform_idle(void);
extern void  lg_platform_panic(lg_u8 code) __attribute__((noreturn));

#endif
