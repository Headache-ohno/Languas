ENTRY(Reset_Handler)

STACK_SIZE = 0x00000200;

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 0x00001000
    RAM (rwx) : ORIGIN = 0x20000020, LENGTH = 0x00000DE0
}

SECTIONS
{
    . = ORIGIN(ROM);

    .vectors : {
        KEEP(*(.vectors))
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

    ASSERT(SIZEOF(.vectors) == 8,
           "Bootex vector table must contain SP and Reset_Handler")
    ASSERT(__bss_end__ <= __stack_limit__,
           "Bootex static RAM overlaps the reserved stack")
    ASSERT(__stack_top__ == 0x20001000,
           "stack top no longer matches the Bootex vector")
}
