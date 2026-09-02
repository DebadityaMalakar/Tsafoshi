; SPDX-License-Identifier: MIT
;
; Number formatting and small output helpers.

%include "tsafoshi.inc"

    global  fmt_i64
    global  print_result
    global  write_spaces

    extern  sys_write_stdout
    extern  sys_write_stderr

    section .text

; rax = signed value -> rsi = text, rdx = length.
; Negating then dividing *unsigned* is what makes INT64_MIN come out right:
; it wraps to 0x8000000000000000, which is its own magnitude unsigned.
fmt_i64:
    lea     r8, [num_buf + NUM_CAP]
    mov     rdi, r8
    xor     r10d, r10d
    test    rax, rax
    jns     .positive
    mov     r10d, 1
    neg     rax
.positive:
    mov     r9d, 10
.digit:
    xor     edx, edx
    div     r9
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    rax, rax
    jnz     .digit
    test    r10d, r10d
    jz      .done
    dec     rdi
    mov     byte [rdi], '-'
.done:
    mov     rsi, rdi
    mov     rdx, r8
    sub     rdx, rdi
    ret

; rax = value
print_result:
    push    rax
    lea     rsi, [msg_equals]
    mov     rdx, msg_equals.len
    call    sys_write_stdout
    pop     rax
    call    fmt_i64
    call    sys_write_stdout
    lea     rsi, [msg_newline]
    mov     rdx, 1
    jmp     sys_write_stdout

; rdi = count, written to stderr in blocks
write_spaces:
    push    rbx
    mov     rbx, rdi
.more:
    test    rbx, rbx
    jle     .out
    mov     rdx, rbx
    cmp     rdx, 32
    jbe     .go
    mov     edx, 32
.go:
    sub     rbx, rdx
    lea     rsi, [blanks]
    call    sys_write_stderr
    jmp     .more
.out:
    pop     rbx
    ret

; ---------------------------------------------------------------------------
    section .data

msg_equals:
    db      "= "
.len                equ $ - msg_equals
msg_newline:
    db      10
blanks:
    db      "                                "

; ---------------------------------------------------------------------------
    section .bss

num_buf:
    resb    NUM_CAP
