# boot.S - Master Boot Record & 16-bit to 32-bit Transition
.code16
.section .text
.global _start

_start:
    /* Step 1: Normalize Segments */
    cli                         /* Disable interrupts during setup */
    xor %ax, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov $0x7C00, %sp            /* Set stack pointer below bootloader */

    /* Save the boot drive ID passed by BIOS in DL */
    movb %dl, (boot_drive)

    /* Step 2: Visual Heartbeat (Print '!' to VGA) */
    mov $0xB800, %ax            /* VGA Segment */
    mov %ax, %gs
    movw $0x0F21, %gs:(0)       /* White '!' on Black background */

    /* Step 3: Load the Kernel from Disk */
    /* We start reading from Sector 2 (where kernel.o/commands.o live) */
    mov $0x07E0, %ax            /* Destination segment (just after bootloader) */
    mov %ax, %es
    xor %bx, %bx                /* Offset 0 within ES */
    
    mov $0x02, %ah              /* BIOS Read Sectors function */
    mov $62, %al                /* Load 62 sectors (~31KB) */
    mov $0, %ch                 /* Cylinder 0 */
    mov $0, %dh                 /* Head 0 */
    mov $2, %cl                 /* Starting Sector (Sector 1 is MBR) */
    movb (boot_drive), %dl      /* Use the drive we booted from */
    int $0x13
    jc disk_error               /* Jump if Carry Flag is set (error) */

    /* Step 4: Enable A20 Line (Fast Gate A20) */
    inb $0x92, %al
    orb $0x02, %al
    outb %al, $0x92

    /* Step 5: Load Global Descriptor Table */
    lgdt gdt_descriptor

    /* Step 6: Switch to Protected Mode */
    mov %cr0, %eax
    or $1, %eax
    mov %eax, %cr0

    /* Step 7: Far Jump to 32-bit Code */
    /* 0x08 is the offset of the code segment in our GDT */
    ljmp $0x08, $init_pm

disk_error:
    /* Print a Red 'E' on the screen if disk read fails */
    mov $0xB800, %ax
    mov %ax, %gs
    movw $0x0C45, %gs:(0)
    hlt

.code32
init_pm:
    /* Step 8: Initialize 32-bit Data Segments */
    mov $0x10, %ax              /* 0x10 is the data segment offset in GDT */
    mov %ax, %ds
    mov %ax, %ss
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs

    /* Set up a stable 32-bit stack */
    mov $0x90000, %esp
    
    /* Step 9: Call the C/ASM Kernel */
    call kernel_main

    /* Final Safety Halt */
freeze:
    hlt
    jmp freeze

/* --- Data and Descriptors --- */

boot_drive: .byte 0

.align 4
gdt_start:
    .quad 0x0000000000000000    /* Null Descriptor */
gdt_code:
    .quad 0x00cf9a000000ffff    /* Code: Base 0, Limit 4G, Exec/Read */
gdt_data:
    .quad 0x00cf92000000ffff    /* Data: Base 0, Limit 4G, Read/Write */
gdt_end:

gdt_descriptor:
    .word gdt_end - gdt_start - 1
    .long gdt_start

/* --- MBR Signature --- */
.org 510
.word 0xAA55