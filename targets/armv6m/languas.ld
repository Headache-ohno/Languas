ENTRY(lg_entry)

STACK_SIZE = 0x00000200;

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00001000, LENGTH = 0x00007000
    RAM (rwx) : ORIGIN = 0x20000020, LENGTH = 0x00000DE0
}

SECTIONS
{
    . = ORIGIN(ROM);

    .header : {
        __header_start__ = .;
        KEEP(*(.header))
        __header_end__ = .;
    } > ROM

    . = ORIGIN(ROM) + 0x0C;

    .lg_entry : {
        KEEP(*(.lg_entry))
    } > ROM

    .text : {
        *(.text*)
        *(.rodata*)
    } > ROM

    .data : {
        . = ALIGN(4);
        __data_start__ = .;
        *(.data*)
        . = ALIGN(4);
        __data_end__ = .;
    } > RAM AT > ROM
    __data_load__ = LOADADDR(.data);

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start__ = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > RAM

    __stack_limit__ = ORIGIN(RAM) + LENGTH(RAM);
    __stack_top__ = __stack_limit__ + STACK_SIZE;

    /DISCARD/ : {
        *(.ARM.exidx*)
        *(.ARM.extab*)
        *(.note.gnu.build-id)
    }

    ASSERT((__header_end__ - __header_start__) == 0x0C,
           "Languas header must be exactly 12 bytes")
    ASSERT(ADDR(.lg_entry) == 0x0000100C,
           "lg_entry must immediately follow the header")
    ASSERT(SIZEOF(.lg_entry) > 0,
           "lg_entry section is missing")
    ASSERT(__bss_end__ <= __stack_limit__,
           "static RAM overlaps the reserved stack")
    ASSERT(__stack_top__ == 0x20001000,
           "stack top no longer matches the Bootex vector")
}
