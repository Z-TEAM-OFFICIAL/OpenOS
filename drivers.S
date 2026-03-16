/*
 * Enhanced keyboard and VGA driver for OpenOS
 * Features:
 *   - Shift handling (left and right) for uppercase/symbols
 *   - Caps Lock toggle (only affects letters)
 *   - Hardware cursor update via VGA CRT controller
 *   - Scrolling when bottom of screen reached (instead of clear)
 *   - Improved scancode translation with separate normal/shift maps
 */

#include "kernel.h"

.section .data
.global cursor_x
.global cursor_y

cursor_x:          .long 0
cursor_y:          .long 0

/* Keyboard state variables */
.global shift_pressed
.global caps_lock_active

shift_pressed:     .byte 0      /* bit0: left shift, bit1: right shift */
caps_lock_active:  .byte 0

/* Normal (unshifted) scancode to ASCII mapping (US QWERTY, Set 1) */
kbd_map_normal:
    .ascii "??"                  /* 0x00, 0x01 (ESC) */
    .ascii "1234567890-="        /* 0x02 - 0x0D */
    .ascii "\177"                /* 0x0E (Backspace) */
    .ascii "\t"                  /* 0x0F (Tab) */
    .ascii "qwertyuiop[]"        /* 0x10 - 0x1B (lowercase) */
    .ascii "\n"                  /* 0x1C (Enter) */
    .ascii "?"                   /* 0x1D (Left Ctrl) */
    .ascii "asdfghjkl;'`"        /* 0x1E - 0x29 (lowercase) */
    .ascii "?"                   /* 0x2A (Left Shift) */
    .ascii "\\zxcvbnm,./"        /* 0x2B - 0x35 (lowercase) */
    .ascii "?"                   /* 0x36 (Right Shift) */
    .ascii "*"                   /* 0x37 (Keypad *) */
    .ascii "?"                   /* 0x38 (Left Alt) */
    .ascii " "                   /* 0x39 (Space) */
    .fill 70, 1, '?'             /* Fill remaining up to 0x58 (some keys) */

/* Shifted scancode to ASCII mapping (for when shift is held) */
kbd_map_shifted:
    .ascii "??"                  /* 0x00, 0x01 */
    .ascii "!@#$%^&*()_+"        /* 0x02 - 0x0D (shifted number row) */
    .ascii "\177"                /* 0x0E (Backspace) */
    .ascii "\t"                  /* 0x0F (Tab) */
    .ascii "QWERTYUIOP{}"        /* 0x10 - 0x1B (uppercase) */
    .ascii "\n"                  /* 0x1C (Enter) */
    .ascii "?"                   /* 0x1D (Left Ctrl) */
    .ascii "ASDFGHJKL:\"~"       /* 0x1E - 0x29 (uppercase and shifted symbols) */
    .ascii "?"                   /* 0x2A (Left Shift) */
    .ascii "|ZXCVBNM<>?"         /* 0x2B - 0x35 (uppercase and shifted symbols) */
    .ascii "?"                   /* 0x36 (Right Shift) */
    .ascii "*"                   /* 0x37 (Keypad *) */
    .ascii "?"                   /* 0x38 (Left Alt) */
    .ascii " "                   /* 0x39 (Space) */
    .fill 70, 1, '?'             /* Fill remaining */

.section .text
.global clear_screen
.global put_char_vga
.global get_char
.global move_cursor_back
.global update_cursor
.global scroll_screen

/* --- VGA Driver with Scrolling and Hardware Cursor --- */

/* Clear the entire screen (80x25) with spaces */
clear_screen:
    push %ebp
    mov %esp, %ebp
    push %edi
    push %ecx
    push %eax

    mov $0xB8000, %edi
    mov $(80 * 25), %ecx
    mov $0x0720, %ax          /* Light grey on black, space */
    rep stosw

    movl $0, cursor_x
    movl $0, cursor_y

    call update_cursor

    pop %eax
    pop %ecx
    pop %edi
    pop %ebp
    ret

/* Scroll the screen up by one line */
scroll_screen:
    push %ebp
    mov %esp, %ebp
    push %esi
    push %edi
    push %ecx

    /* Copy line 1..24 to line 0..23 */
    mov $0xB8000 + 80*2, %esi    /* start of second line */
    mov $0xB8000, %edi           /* start of first line */
    mov $(80 * 24 * 2), %ecx     /* 24 lines * 80 columns * 2 bytes */
    rep movsb

    /* Clear the last line (line 24) */
    mov $0xB8000 + 80*24*2, %edi
    mov $80, %ecx
    mov $0x0720, %ax
    rep stosw

    /* Cursor remains at same column, but row decreased by 1 */
    decl cursor_y

    pop %ecx
    pop %edi
    pop %esi
    pop %ebp
    ret

/* Update the hardware cursor position using VGA CRT controller */
update_cursor:
    push %ebp
    mov %esp, %ebp
    
    /* Calculate position = y * 80 + x */
    movl cursor_y, %eax
    imul $80, %eax
    addl cursor_x, %eax
    mov %ax, %bx               /* Store 16-bit pos in BX */

    /* Send High Byte (Register 0x0E) */
    mov $0x3D4, %dx
    mov $0x0E, %al
    out %al, %dx               /* Select High Byte register */
    
    mov $0x3D5, %dx
    mov %bh, %al               /* Get high byte from BH */
    out %al, %dx

    /* Send Low Byte (Register 0x0F) */
    mov $0x3D4, %dx
    mov $0x0F, %al
    out %al, %dx               /* Select Low Byte register */
    
    mov $0x3D5, %dx
    mov %bl, %al               /* Get low byte from BL */
    out %al, %dx

    pop %ebp
    ret

/* Print a character to screen at current cursor, with scrolling */
put_char_vga:
    push %ebp
    mov %esp, %ebp
    push %eax
    push %edx
    push %ebx

    mov 8(%ebp), %al           /* character to print */

    /* Check for newline (LF or CR) */
    cmpb $10, %al
    je .newline
    cmpb $13, %al
    je .newline

    /* Calculate offset: (y*80 + x) * 2 */
    movl cursor_y, %edx
    imul $80, %edx
    addl cursor_x, %edx
    shl $1, %edx
    addl $0xB8000, %edx

    movb $0x07, %ah            /* attribute */
    movw %ax, (%edx)

    incl cursor_x
    cmpl $80, cursor_x
    jl .update_cursor_now

.newline:
    movl $0, cursor_x
    incl cursor_y
    cmpl $25, cursor_y
    jl .update_cursor_now
    call scroll_screen         /* instead of clear_screen */
    /* cursor_y is already decremented by scroll_screen, cursor_x=0 */

.update_cursor_now:
    call update_cursor

.done:
    pop %ebx
    pop %edx
    pop %eax
    pop %ebp
    ret

/* Erase character behind cursor and move cursor back (backspace) */
move_cursor_back:
    push %ebp
    mov %esp, %ebp
    push %eax
    push %edx

    cmpl $0, cursor_x
    jne .do_back
    cmpl $0, cursor_y
    je .done_back
    decl cursor_y
    movl $79, cursor_x
    jmp .do_erase

.do_back:
    decl cursor_x

.do_erase:
    movl cursor_y, %edx
    imul $80, %edx
    addl cursor_x, %edx
    shl $1, %edx
    addl $0xB8000, %edx
    movw $0x0720, (%edx)
    call update_cursor

.done_back:
    pop %edx
    pop %eax
    pop %ebp
    ret

/* --- Keyboard Driver with Shift/Caps Handling --- */

/* Read scancode from keyboard, translate to ASCII with shift/caps, return in %al */
get_char:
    push %ebx
    push %edx

.wait_for_key:
    in $0x64, %al              /* status register */
    testb $0x01, %al           /* output buffer full? */
    jz .wait_for_key

    in $0x60, %al              /* read scancode */

    /* Check for multi-byte scancodes (0xE0 prefix) */
    cmpb $0xE0, %al
    jne .not_extended
    /* Extended scancode: read second byte and ignore */
    call .wait_for_second
    jmp .wait_for_key

.not_extended:
    /* Check for key release (bit 7 set) */
    testb $0x80, %al
    jnz .handle_release

    /* Key press */
    push %eax
    call .update_modifiers
    pop %eax

    /* Now translate scancode to ASCII using appropriate map */
    movzbl %al, %ebx           /* EBX = scancode */

    /* Determine if shift is active */
    movb shift_pressed, %dl
    testb %dl, %dl
    jnz .use_shifted_map

    /* No shift: use normal map, but apply caps lock for letters */
    movb kbd_map_normal(%ebx), %al
    cmpb $'a', %al
    jb .check_caps_lower
    cmpb $'z', %al
    ja .check_caps_lower
    /* It's a lowercase letter: if caps lock active, make uppercase */
    cmpb $0, caps_lock_active
    je .done_translate
    subb $0x20, %al            /* convert to uppercase */
    jmp .done_translate

.check_caps_lower:
    /* Not a letter, just return as is (but filter '?') */
    jmp .done_translate

.use_shifted_map:
    /* Shift is pressed: use shifted map, but for letters caps lock inverts */
    movb kbd_map_shifted(%ebx), %al
    /* If it's a letter (A-Z after shift), caps lock toggles to lowercase */
    cmpb $'A', %al
    jb .done_translate
    cmpb $'Z', %al
    ja .done_translate
    /* It's uppercase letter from shift; if caps lock active, make lowercase */
    cmpb $0, caps_lock_active
    je .done_translate
    addb $0x20, %al            /* convert to lowercase */
    jmp .done_translate

.done_translate:
    /* Discard placeholder '?' characters */
    cmpb $'?', %al
    je .wait_for_key

    pop %edx
    pop %ebx
    ret

.handle_release:
    /* Key release: update modifier states (ignore releases of non-modifiers) */
    andb $0x7F, %al            /* clear release bit */
    call .update_modifiers_release
    jmp .wait_for_key

/* Helper: wait for second byte of extended scancode */
.wait_for_second:
    in $0x64, %al
    testb $0x01, %al
    jz .wait_for_second
    in $0x60, %al
    ret

/* Update shift and caps lock state on key press */
.update_modifiers:
    /* Scancode in %al (low byte) */
    cmpb $0x2A, %al            /* Left shift */
    je .left_shift_press
    cmpb $0x36, %al            /* Right shift */
    je .right_shift_press
    cmpb $0x3A, %al            /* Caps Lock (scancode 0x3A) */
    je .caps_lock_press
    ret

.left_shift_press:
    orb $1, shift_pressed
    ret

.right_shift_press:
    orb $2, shift_pressed
    ret

.caps_lock_press:
    /* Toggle caps lock (only on press, not release) */
    xorb $1, caps_lock_active
    /* Optionally update Caps Lock LED (not implemented) */
    ret

/* Update modifier states on key release */
.update_modifiers_release:
    cmpb $0x2A, %al
    je .left_shift_release
    cmpb $0x36, %al
    je .right_shift_release
    ret

.left_shift_release:
    andb $~1, shift_pressed
    ret

.right_shift_release:
    andb $~2, shift_pressed
    ret