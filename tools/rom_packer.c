#include <limits.h>
#include <stdio.h>
#include <string.h>

#if CHAR_BIT != 8
#error "rom_packer requires 8-bit bytes"
#endif

#define BOOTEX_SIZE      4096L
#define BOOTEX_MIN_SIZE  10L
#define LANGUAS_MAX_SIZE 28672L
#define LANGUAS_MIN_SIZE 14L
#define COPY_BUFFER_SIZE 4096u

static int file_size(FILE *file, long *result) {
    long size;

    if (fseek(file, 0L, SEEK_END) != 0) return 0;
    size = ftell(file);
    if (size < 0L) return 0;
    if (fseek(file, 0L, SEEK_SET) != 0) return 0;
    *result = size;
    return 1;
}

static int copy_exact(FILE *input, FILE *output, long byte_count) {
    unsigned char buffer[COPY_BUFFER_SIZE];
    long remaining = byte_count;

    while (remaining > 0L) {
        size_t wanted = remaining > (long)sizeof(buffer)
            ? sizeof(buffer)
            : (size_t)remaining;
        size_t count = fread(buffer, 1u, wanted, input);
        if (count != wanted) return 0;
        if (fwrite(buffer, 1u, count, output) != count) return 0;
        remaining -= (long)count;
    }
    return ferror(input) == 0 && ferror(output) == 0;
}

static unsigned long read_u32_le(const unsigned char bytes[4]) {
    return (unsigned long)bytes[0] |
           ((unsigned long)bytes[1] << 8u) |
           ((unsigned long)bytes[2] << 16u) |
           ((unsigned long)bytes[3] << 24u);
}

int main(int argc, char **argv) {
    FILE *bootex;
    FILE *languas;
    FILE *output;
    long bootex_size;
    long languas_size;
    unsigned char vectors[8];
    unsigned long stack_pointer;
    unsigned long reset_handler;
    unsigned long reset_code;
    unsigned char padding[COPY_BUFFER_SIZE] = { 0 };
    int success = 0;

    if (argc != 4) {
        fprintf(stderr, "Usage: %s <bootex.bin> <languas.bin> <output.rom>\n", argv[0]);
        return 1;
    }
    if (strcmp(argv[1], argv[3]) == 0 || strcmp(argv[2], argv[3]) == 0) {
        fprintf(stderr, "Error: output path must differ from both input paths\n");
        return 1;
    }

    bootex = fopen(argv[1], "rb");
    if (bootex == NULL) {
        fprintf(stderr, "Error opening %s\n", argv[1]);
        return 1;
    }
    languas = fopen(argv[2], "rb");
    if (languas == NULL) {
        fprintf(stderr, "Error opening %s\n", argv[2]);
        (void)fclose(bootex);
        return 1;
    }

    if (!file_size(bootex, &bootex_size) || !file_size(languas, &languas_size)) {
        fprintf(stderr, "Error: unable to determine input size\n");
        goto close_inputs;
    }
    if (bootex_size < BOOTEX_MIN_SIZE || bootex_size > BOOTEX_SIZE) {
        fprintf(stderr, "Error: Bootex must be between %ld and %ld bytes\n",
                BOOTEX_MIN_SIZE, BOOTEX_SIZE);
        goto close_inputs;
    }
    if (languas_size < LANGUAS_MIN_SIZE || languas_size > LANGUAS_MAX_SIZE) {
        fprintf(stderr, "Error: Languas image must be between %ld and %ld bytes\n",
                LANGUAS_MIN_SIZE, LANGUAS_MAX_SIZE);
        goto close_inputs;
    }
    if (fread(vectors, 1u, sizeof(vectors), bootex) != sizeof(vectors) ||
        fseek(bootex, 0L, SEEK_SET) != 0) {
        fprintf(stderr, "Error: unable to read the Bootex vector table\n");
        goto close_inputs;
    }
    stack_pointer = read_u32_le(vectors);
    reset_handler = read_u32_le(vectors + 4);
    reset_code = reset_handler & ~1UL;
    if (stack_pointer != 0x20001000UL || (reset_handler & 1UL) == 0UL ||
        reset_code < 8UL || reset_code > (unsigned long)bootex_size - 2UL) {
        fprintf(stderr, "Error: invalid Bootex vector table\n");
        goto close_inputs;
    }

    output = fopen(argv[3], "wb");
    if (output == NULL) {
        fprintf(stderr, "Error opening %s\n", argv[3]);
        goto close_inputs;
    }
    if (!copy_exact(bootex, output, bootex_size)) {
        fprintf(stderr, "Error while copying Bootex\n");
        goto close_output;
    }
    if (bootex_size < BOOTEX_SIZE &&
        fwrite(padding, 1u, (size_t)(BOOTEX_SIZE - bootex_size), output) !=
            (size_t)(BOOTEX_SIZE - bootex_size)) {
        fprintf(stderr, "Error while padding Bootex\n");
        goto close_output;
    }
    if (!copy_exact(languas, output, languas_size)) {
        fprintf(stderr, "Error while copying Languas image\n");
        goto close_output;
    }
    if (fclose(output) != 0) {
        output = NULL;
        fprintf(stderr, "Error while closing %s\n", argv[3]);
        (void)remove(argv[3]);
        goto close_inputs;
    }
    output = NULL;
    success = 1;
    printf("ROM packaged successfully -> %s\n", argv[3]);

close_output:
    if (output != NULL) {
        (void)fclose(output);
        if (!success) (void)remove(argv[3]);
    }
close_inputs:
    (void)fclose(bootex);
    (void)fclose(languas);
    return success ? 0 : 1;
}
