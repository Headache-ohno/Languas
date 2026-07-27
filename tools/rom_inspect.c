#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if CHAR_BIT != 8
#error "rom_inspect requires 8-bit bytes"
#endif

#define BOOTEX_SIZE       0x1000L
#define LANGUAS_BASE      0x1000L
#define HEADER_SIZE       12u
#define ENTRY_CODE        0x100Cu
#define ROM_MIN_SIZE      0x100EL
#define ROM_MAX_SIZE      0x8000L
#define EXPECTED_STACK    UINT32_C(0x20001000)

static int read_u8(FILE *file, uint8_t *value) {
    int byte = fgetc(file);
    if (byte == EOF) return 0;
    *value = (uint8_t)byte;
    return 1;
}

static int read_u16_le(FILE *file, uint16_t *value) {
    uint8_t bytes[2];
    if (fread(bytes, 1u, sizeof(bytes), file) != sizeof(bytes)) return 0;
    *value = (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8u));
    return 1;
}

static int read_u32_le(FILE *file, uint32_t *value) {
    uint8_t bytes[4];
    if (fread(bytes, 1u, sizeof(bytes), file) != sizeof(bytes)) return 0;
    *value = (uint32_t)bytes[0] |
             ((uint32_t)bytes[1] << 8u) |
             ((uint32_t)bytes[2] << 16u) |
             ((uint32_t)bytes[3] << 24u);
    return 1;
}

static int valid_profile(uint8_t profile) {
    return profile >= 0x01u && profile <= 0x03u;
}

static int fail(FILE *file, const char *message) {
    printf("FAIL: %s\n", message);
    (void)fclose(file);
    return 1;
}

int main(int argc, char **argv) {
    FILE *file;
    long size;
    uint32_t stack_pointer;
    uint32_t reset_handler;
    uint32_t reset_code;
    uint8_t magic[4];
    uint8_t version_major;
    uint8_t version_minor;
    uint8_t image_profile;
    uint8_t flags;
    uint16_t header_size;
    uint16_t reserved;
    const char *profile_name;

    if (argc != 3 || strcmp(argv[1], "verify") != 0) {
        fprintf(stderr, "Usage: %s verify <rom_file>\n", argv[0]);
        return 1;
    }
    file = fopen(argv[2], "rb");
    if (file == NULL) {
        fprintf(stderr, "Error: file not found: %s\n", argv[2]);
        return 1;
    }
    if (fseek(file, 0L, SEEK_END) != 0 || (size = ftell(file)) < 0L ||
        fseek(file, 0L, SEEK_SET) != 0) {
        return fail(file, "unable to determine ROM size");
    }
    if (size < ROM_MIN_SIZE) return fail(file, "ROM is too small");
    if (size > ROM_MAX_SIZE) return fail(file, "ROM exceeds the 32 KiB address space");

    if (!read_u32_le(file, &stack_pointer) || !read_u32_le(file, &reset_handler)) {
        return fail(file, "unable to read the vector table");
    }
    if (stack_pointer != EXPECTED_STACK) {
        return fail(file, "initial stack pointer is not 0x20001000");
    }
    if ((reset_handler & UINT32_C(1)) == 0u) {
        return fail(file, "Reset_Handler Thumb bit is not set");
    }
    reset_code = reset_handler & ~UINT32_C(1);
    if (reset_code < UINT32_C(8) || reset_code >= (uint32_t)BOOTEX_SIZE) {
        return fail(file, "Reset_Handler is outside Bootex");
    }

    if (fseek(file, LANGUAS_BASE, SEEK_SET) != 0 ||
        fread(magic, 1u, sizeof(magic), file) != sizeof(magic) ||
        !read_u8(file, &version_major) || !read_u8(file, &version_minor) ||
        !read_u8(file, &image_profile) || !read_u8(file, &flags) ||
        !read_u16_le(file, &header_size) || !read_u16_le(file, &reserved)) {
        return fail(file, "unable to read the Languas header");
    }

    if (memcmp(magic, "LGUS", sizeof(magic)) != 0) return fail(file, "bad magic");
    if (version_major != 0u) return fail(file, "unsupported major version");
    if (!valid_profile(image_profile)) return fail(file, "profile is rejected by Bootex");
    if (flags != 0u) return fail(file, "flags must be zero");
    if (header_size != HEADER_SIZE) return fail(file, "header size must be 12");
    if (reserved != 0u) return fail(file, "reserved field must be zero");

    profile_name = image_profile == 0x01u ? "CORE" :
                   image_profile == 0x02u ? "VANILLA" : "COMMANDER";

    printf("=== Inspecting Languas ROM: %s ===\n", argv[2]);
    printf("Initial SP       : 0x%08" PRIX32 "\n", stack_pointer);
    printf("Reset Handler    : 0x%08" PRIX32 "\n", reset_handler);
    printf("Magic            : 'LGUS'\n");
    printf("Version          : %u.%u\n", (unsigned int)version_major,
           (unsigned int)version_minor);
    printf("Image Profile    : %s (0x%02X)\n", profile_name,
           (unsigned int)image_profile);
    printf("Flags            : 0x%02X\n", (unsigned int)flags);
    printf("Header size      : %u\n", (unsigned int)header_size);
    printf("Reserved         : 0x%04X\n", (unsigned int)reserved);
    printf("lg_entry code    : 0x%08X\n", ENTRY_CODE);
    printf("lg_entry Thumb   : 0x%08X\n", ENTRY_CODE | 1u);
    printf("Total ROM Size   : %ld bytes (%.2f KiB)\n", size, (double)size / 1024.0);
    printf("OK: Bootex/Languas ROM layout valid\n");

    if (fclose(file) != 0) {
        fprintf(stderr, "FAIL: unable to close ROM file\n");
        return 1;
    }
    return 0;
}
