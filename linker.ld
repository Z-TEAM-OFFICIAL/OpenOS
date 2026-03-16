ENTRY(_start)
SECTIONS
{
    /* BIOS loads the MBR here */
    . = 0x7C00;
    _kernel_start = .;

    .text : { 
        boot.o(.text)   /* Ensure bootloader code is first! */
        *(.text) 
    }
    .rodata : { *(.rodata) }
    .data   : { *(.data) }
    .bss    : { *(.bss) }

    /* Pad to 8MB so it stays a large disk image */
    .padding : 
    {
        FILL(0x00);
        . = _kernel_start + (8 * 1024 * 1024) - 1;
        BYTE(0x00);
    }
}