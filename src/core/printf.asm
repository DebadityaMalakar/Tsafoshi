; SPDX-License-Identifier: MIT
;
; The format-string interpreter behind printf().
;
; This is core, not platform code, and deliberately so: everything here is
; scanning and arithmetic, and the only thing it does to the outside world is
; call sys_write_stdout -- which the Linux and Windows layers already provide.
; A per-platform copy would fork the whole conversion loop in order to
; abstract a call that is abstracted already.
;
; Supported: the flags "-" and "0", a decimal width, a precision (applied to
; %s), the length modifiers l h z j t (accepted and ignored, because every
; value here is one 64-bit cell), and the conversions d i u x X o c s p and
; a literal percent.
;
; Unlike C, running out of arguments is an error rather than undefined: the
; count is known at run time, so there is no reason to read past the end.

%include "tsafoshi.inc"

    global  printf_run

    extern  fmt_i64
    extern  fmt_u64
    extern  pad_spaces
    extern  pad_zeros
    extern  err_badconv
    extern  err_missingarg
    extern  sys_write_stdout

    section .text

; rdi = argument array, rsi = count, rdx = position for errors -> rax = the
; number of bytes written, or 0 with an error recorded.
; rbx = the format cursor, r12 = the arguments, r13 = how many there are,
; r14 = the next one to consume, r15 = bytes written so far
printf_run:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
    mov     [pf_pos], rdx
    mov     qword [pf_fail], 0
    mov     rbx, [rdi]                  ; argument zero is the format itself
    mov     r14, 1
    xor     r15, r15

.next:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .done
    cmp     al, '%'
    je      .conversion

; A run of ordinary characters goes out in one write rather than one each.
    mov     rcx, rbx
.run:
    inc     rcx
    movzx   eax, byte [rcx]
    test    al, al
    jz      .run_end
    cmp     al, '%'
    jne     .run
.run_end:
    mov     rsi, rbx
    mov     rdx, rcx
    sub     rdx, rbx
    mov     rbx, rcx
    add     r15, rdx
    call    sys_write_stdout
    jmp     .next

.conversion:
    inc     rbx
    call    read_spec
    movzx   eax, byte [rbx]
    test    al, al
    jz      .bad
    inc     rbx
    lea     rcx, [conv_from]
    xor     edx, edx
.find:
    movzx   r8d, byte [rcx + rdx]
    test    r8b, r8b
    jz      .bad
    cmp     r8b, al
    je      .found
    inc     rdx
    jmp     .find
.found:
    lea     rcx, [conv_table]
    jmp     [rcx + rdx * 8]

; A literal percent consumes no argument and takes no width.
.percent:
    lea     rsi, [t_percent]
    mov     rdx, 1
    inc     r15
    call    sys_write_stdout
    jmp     .next

.signed:
    call    next_arg
    call    fmt_i64
    jmp     .emit_number

.unsigned:
    call    next_arg
    mov     edi, 10
    xor     esi, esi
    jmp     .emit_radix
.hex_lower:
    call    next_arg
    mov     edi, 16
    xor     esi, esi
    jmp     .emit_radix
.hex_upper:
    call    next_arg
    mov     edi, 16
    mov     esi, 1
    jmp     .emit_radix
.octal:
    call    next_arg
    mov     edi, 8
    xor     esi, esi
.emit_radix:
    call    fmt_u64
    jmp     .emit_number

; A pointer is hexadecimal with the prefix always on. The prefix is written
; before the padding rather than inside it, so a width applies to the digits.
.pointer:
    call    next_arg
    push    rax
    lea     rsi, [t_hex_prefix]
    mov     rdx, t_hex_prefix.len
    add     r15, rdx
    call    sys_write_stdout
    pop     rax
    mov     edi, 16
    xor     esi, esi
    call    fmt_u64
    jmp     .emit_number

.character:
    call    next_arg
    lea     rcx, [pf_char]
    mov     [rcx], al
    mov     rsi, rcx
    mov     rdx, 1
    jmp     .emit_text

; The precision, where there is one, caps the length rather than the value.
.string:
    call    next_arg
    mov     rsi, rax
    xor     edx, edx
.length:
    cmp     qword [pf_prec], 0
    jl      .unbounded
    cmp     rdx, [pf_prec]
    jae     .emit_text
.unbounded:
    cmp     byte [rsi + rdx], 0
    je      .emit_text
    inc     rdx
    jmp     .length

.emit_number:
    mov     qword [pf_numeric], 1
    jmp     .padded
.emit_text:
    mov     qword [pf_numeric], 0
.padded:
    cmp     qword [pf_fail], 0
    jne     .fail
    call    put_padded
    jmp     .next

.bad:
    mov     rdi, [pf_pos]
    call    err_badconv
.fail:
    xor     eax, eax
    jmp     .out
.done:
    mov     rax, r15
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Flags, width, precision and length modifiers: all optional, and all in the
; order C99 requires them. Advances rbx to the conversion character.
read_spec:
    mov     qword [pf_left], 0
    mov     qword [pf_zero], 0
    mov     qword [pf_width], 0
    mov     qword [pf_prec], -1
.flag:
    movzx   eax, byte [rbx]
    cmp     al, '-'
    je      .left
    cmp     al, '0'
    je      .zero
    jmp     .width
.left:
    mov     qword [pf_left], 1
    inc     rbx
    jmp     .flag
.zero:
    mov     qword [pf_zero], 1
    inc     rbx
    jmp     .flag

.width:
    lea     rdi, [pf_width]
    call    read_number
    movzx   eax, byte [rbx]
    cmp     al, '.'
    jne     .modifier
    inc     rbx
    mov     qword [pf_prec], 0
    lea     rdi, [pf_prec]
    call    read_number

; A length modifier says how wide the argument is in C. Here every argument
; is a cell, so they are read and thrown away.
.modifier:
    movzx   eax, byte [rbx]
    lea     rcx, [t_modifiers]
.try:
    movzx   edx, byte [rcx]
    test    dl, dl
    jz      .out
    cmp     dl, al
    je      .skip
    inc     rcx
    jmp     .try
.skip:
    inc     rbx
    jmp     .modifier
.out:
    ret

; rdi = where to accumulate. Stops at the first non-digit.
read_number:
    movzx   eax, byte [rbx]
    cmp     al, '0'
    jb      .out
    cmp     al, '9'
    ja      .out
    sub     eax, '0'
    mov     rcx, [rdi]
    imul    rcx, rcx, 10
    add     rcx, rax
    mov     [rdi], rcx
    inc     rbx
    jmp     read_number
.out:
    ret

; -> rax = the next argument
next_arg:
    cmp     r14, r13
    jae     .missing
    mov     rax, [r12 + r14 * CELL]
    inc     r14
    ret
.missing:
    mov     rdi, [pf_pos]
    call    err_missingarg
    mov     qword [pf_fail], 1
    xor     eax, eax
    ret

; rsi = text, rdx = length. Writes it inside the requested width, and adds
; what it wrote to r15.
;
; Zero padding goes *after* a minus sign rather than before it, which is the
; whole reason this is not one pad call and one write.
put_padded:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rsi
    mov     r12, rdx
    mov     r13, [pf_width]
    sub     r13, r12
    add     r15, r12
    cmp     r13, 0
    jle     .plain
    add     r15, r13
    cmp     qword [pf_left], 0
    jne     .trailing
    cmp     qword [pf_zero], 0
    je      .leading_spaces
    cmp     qword [pf_numeric], 0
    je      .leading_spaces

    cmp     byte [rbx], '-'
    jne     .leading_zeros
    mov     rsi, rbx
    mov     rdx, 1
    call    sys_write_stdout
    inc     rbx
    dec     r12
.leading_zeros:
    mov     rdi, r13
    call    pad_zeros
    jmp     .plain
.leading_spaces:
    mov     rdi, r13
    call    pad_spaces
    jmp     .plain

.trailing:
    mov     rsi, rbx
    mov     rdx, r12
    call    sys_write_stdout
    mov     rdi, r13
    call    pad_spaces
    jmp     .out

.plain:
    mov     rsi, rbx
    mov     rdx, r12
    call    sys_write_stdout
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
    section .data

; The conversion characters and their handlers, as two parallel rows: a hit
; in the first indexes the second.
conv_from:
    db      "%cdiuxXosp", 0

    align   8
conv_table:
    dq      printf_run.percent
    dq      printf_run.character
    dq      printf_run.signed
    dq      printf_run.signed
    dq      printf_run.unsigned
    dq      printf_run.hex_lower
    dq      printf_run.hex_upper
    dq      printf_run.octal
    dq      printf_run.string
    dq      printf_run.pointer

t_modifiers:
    db      "lhzjt", 0
t_percent:
    db      "%"
t_hex_prefix:
    db      "0x"
.len                equ $ - t_hex_prefix

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
pf_pos:
    resq    1
pf_fail:
    resq    1
pf_left:
    resq    1
pf_zero:
    resq    1
pf_width:
    resq    1
pf_prec:
    resq    1
pf_numeric:
    resq    1
pf_char:
    resq    1
