#include <limits.h>

#if UCHAR_MAX != 0xFFu || USHRT_MAX != 0xFFFFu || UINT_MAX != 0xFFFFFFFFu
#error "Bootex requires 8/16/32-bit unsigned integer types"
#endif

typedef unsigned char  bx_u8;
typedef unsigned short bx_u16;
typedef unsigned int   bx_u32;

typedef char bx_integer_layout_must_match[(sizeof(bx_u8) == 1u &&
                                         sizeof(bx_u16) == 2u &&
                                         sizeof(bx_u32) == 4u) ? 1 : -1];

#define LANGUAS_BASE       0x00001000u
#define LANGUAS_HEADER_LEN 12u
#define LANGUAS_ENTRY_CODE (LANGUAS_BASE + LANGUAS_HEADER_LEN)
#define LANGUAS_ENTRY_ARM  (LANGUAS_ENTRY_CODE | 1u)

#define BX_VERSION_MAJOR   0u

#define BX_CLASS_NANO      0x01u
#define BX_CLASS_ALPHA     0x02u
#define BX_CLASS_PLUS      0x03u

typedef struct {
    bx_u8  magic[4];
    bx_u8  version_major;
    bx_u8  version_minor;
    bx_u8  target_class;
    bx_u8  flags;
    bx_u16 header_size;
    bx_u16 reserved;
} bx_header_t;

typedef char bx_header_layout_must_be_12_bytes[(sizeof(bx_header_t) == 12u) ? 1 : -1];

typedef void (*bx_entry_fn)(void);

__attribute__((noreturn))
static void bx_halt(void) {
    for (;;) {
    }
}

static int bx_valid_class(bx_u8 c) {
    return c == BX_CLASS_NANO ||
           c == BX_CLASS_ALPHA ||
           c == BX_CLASS_PLUS;
}

static int bx_check_header(const bx_header_t *h) {
    if (h->magic[0] != 'L') return 0;
    if (h->magic[1] != 'G') return 0;
    if (h->magic[2] != 'U') return 0;
    if (h->magic[3] != 'S') return 0;

    if (h->version_major != BX_VERSION_MAJOR) return 0;
    if (!bx_valid_class(h->target_class)) return 0;

    if (h->flags != 0u) return 0;
    if (h->header_size != LANGUAS_HEADER_LEN) return 0;
    if (h->reserved != 0u) return 0;

    return 1;
}

__attribute__((noreturn))
void bx_boot(void) {
    const bx_header_t *h = (const bx_header_t *)LANGUAS_BASE;

    if (!bx_check_header(h)) {
        bx_halt();
    }

    ((bx_entry_fn)LANGUAS_ENTRY_ARM)();

    bx_halt();
}
