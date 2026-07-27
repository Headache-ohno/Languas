#ifndef LANGUAS_TYPES_H
#define LANGUAS_TYPES_H

#include <limits.h>

#if UCHAR_MAX != 0xFFu
#error "Languas requires 8-bit bytes"
#endif

#if USHRT_MAX != 0xFFFFu
#error "Languas requires a 16-bit unsigned short"
#endif

#if UINT_MAX != 0xFFFFFFFFu
#error "Languas requires a 32-bit unsigned int"
#endif

typedef unsigned char  lg_u8;
typedef unsigned short lg_u16;
typedef unsigned int   lg_u32;
typedef unsigned char  lg_bool;
typedef unsigned char  lg_port;
typedef unsigned char  lg_code;

#define LG_TRUE  1u
#define LG_FALSE 0u
#define LG_NULL  0u

/* Stable logical I/O ports shared by every platform. */
#define LG_PORT_GPIO_IN   0x00u
#define LG_PORT_GPIO_OUT  0x01u
#define LG_PORT_UART_TX   0x10u
#define LG_PORT_UART_RX   0x11u

/* Stable panic codes. */
#define LG_PANIC_ASSERT        0x01u
#define LG_PANIC_NULL_POINTER  0x02u
#define LG_PANIC_INVALID_PORT  0x04u

/* Image Profiles */
#define LG_PROFILE_CORE       0x01u
#define LG_PROFILE_VANILLA    0x02u
#define LG_PROFILE_COMMANDER  0x03u
#define LG_PROFILE_DEBUG      0x04u
#define LG_PROFILE_CUSTOM     0x7Fu

#endif
