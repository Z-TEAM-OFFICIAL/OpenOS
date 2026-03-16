#include "kernel.h"

.section .text
.global kernel_main
.global print

/* ---------------------------------------------------------
   print: Standard string output routine
   --------------------------------------------------------- */
print:
    push %ebp
    mov %esp, %ebp
    push %ebx
    
    mov 8(%ebp), %ebx       /* Pointer to string */
1:  movb (%ebx), %al
    test %al, %al           /* Check for null terminator */
    jz 2f
    
    push %eax
    call put_char_vga       /* Defined in drivers.S */
    add $4, %esp
    
    inc %ebx
    jmp 1b
2:  
    pop %ebx
    mov %ebp, %esp
    pop %ebp
    ret

/* ---------------------------------------------------------
   kernel_main: Entry point after boot.S
   --------------------------------------------------------- */
kernel_main:
    /* Initialize the screen and hardware cursor */
    call clear_screen       
    call update_cursor      

    pushl $msg_welcome
    call print
    add $4, %esp

shell_prompt:
    pushl $msg_prompt
    call print
    add $4, %esp

    /* Prepare buffer for input */
    mov $cmd_buffer, %edi
    mov $0, %ecx            /* Character count */

read_loop:
    call get_char           /* Now handles Shift/Caps in drivers.S */
    
    /* Handle Enter (ASCII 10 or 13) */
    cmpb $10, %al
    je finalize_command
    cmpb $13, %al
    je finalize_command

    /* Handle Backspace (ASCII 0x7F or 0x08) */
    cmpb $127, %al          /* Our kbd_map uses 127 for backspace */
    je handle_backspace
    cmpb $8, %al
    je handle_backspace

    /* Ignore other special characters (marked as '?' in drivers.S) */
    cmpb $'?', %al
    je read_loop

    /* Buffer limit check (leaving room for null terminator) */
    cmpl $63, %ecx
    jge read_loop

    /* Store and Echo */
    movb %al, (%edi)
    
    push %eax
    call put_char_vga
    add $4, %esp
    
    inc %edi
    incl %ecx
    jmp read_loop

handle_backspace:
    testl %ecx, %ecx        /* Don't backspace if buffer is empty */
    jz read_loop
    
    dec %edi
    decl %ecx
    movb $0, (%edi)
    
    call move_cursor_back   /* Defined in drivers.S */
    jmp read_loop

finalize_command:
    movb $0, (%edi)         /* Null-terminate the command string */
    
    pushl $msg_newline
    call print
    add $4, %esp

    /* If command is empty, just show prompt again */
    testl %ecx, %ecx
    jz shell_prompt

    /* Pass the buffer to your C command handler */
    pushl $cmd_buffer
    call handle_command     
    add $4, %esp
    
    jmp shell_prompt

.section .data
.align 4
cmd_buffer: .skip 64

.section .rodata
msg_welcome: .asciz "OpenOS Kernel v2.0 (8MB Image) - VGA Text Mode Ready\n"
msg_prompt:  .asciz "OpenOS ~ "
msg_newline: .asciz "\n"