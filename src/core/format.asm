; SPDX-License-Identifier: MIT
;
; Number formatting and small output helpers.

%include "tsafoshi.inc"

    global  fmt_i64
    global  fmt_u64
    global  print_result
    global  print_value
    global  write_spaces
    global  pad_spaces
    global  pad_zeros

    extern  sys_write_stdout
    extern  sys_write_stderr
    extern  type_unsigned

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

; rax = value, rdi = base, sil = 1 for upper-case digits -> rsi = text,
; rdx = length. Unsigned throughout, which is the point: %u and %x have to
; read the same bits as a plain 64-bit cell without a sign creeping in.
fmt_u64:
    lea     r8, [num_buf + NUM_CAP]
    mov     r11, r8
    movzx   r10d, sil
    mov     r9, rdi
.digit:
    xor     edx, edx
    div     r9
    cmp     dl, 10
    jb      .decimal
    sub     dl, 10
    test    r10d, r10d
    jz      .lower
    add     dl, 'A'
    jmp     .put
.lower:
    add     dl, 'a'
    jmp     .put
.decimal:
    add     dl, '0'
.put:
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .digit
    mov     rsi, r8
    mov     rdx, r11
    sub     rdx, r8
    ret

; rax = value, rdi = its type.
;
; The type is what decides how the digits come out, and it has to: a cell
; holding an unsigned int that came from -1 holds 4294967295, and printing that
; as a signed 64-bit number would say -1 and be wrong about what the variable
; actually contains.
;
; rbx = the value, r12 = its type
print_result:
    push    rbx
    push    r12
    mov     rbx, rax
    mov     r12, rdi
    lea     rsi, [msg_equals]
    mov     rdx, msg_equals.len
    call    sys_write_stdout
    mov     rax, rbx
    mov     rdi, r12
    call    print_value
    lea     rsi, [msg_newline]
    mov     rdx, 1
    call    sys_write_stdout
    pop     r12
    pop     rbx
    ret

; rax = value, rdi = its type. The digits and nothing else, so ":vars" and the
; prompt can print the same value the same way without agreeing on a prefix.
print_value:
    push    rbx
    mov     rbx, rax
    call    type_unsigned
    mov     rdi, rax
    mov     rax, rbx
    test    rdi, rdi
    jnz     .unsigned
    call    fmt_i64
    jmp     .emit
.unsigned:
    mov     edi, 10
    xor     esi, esi
    call    fmt_u64
.emit:
    pop     rbx
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

; rdi = count, written to stdout. Padding is the only reason printf.asm needs
; to emit the same byte many times, and doing it here keeps the block buffers
; next to the only other code that has one.
pad_spaces:
    lea     rsi, [blanks]
    jmp     write_block
pad_zeros:
    lea     rsi, [zeros]
    ; fall through

; rdi = count, rsi = a 32-byte block to repeat
write_block:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
.more:
    test    rbx, rbx
    jle     .out
    mov     rdx, rbx
    cmp     rdx, 32
    jbe     .go
    mov     edx, 32
.go:
    sub     rbx, rdx
    mov     rsi, r12
    call    sys_write_stdout
    jmp     .more
.out:
    pop     r12
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
zeros:
    db      "00000000000000000000000000000000"

; ---------------------------------------------------------------------------
    section .bss

num_buf:
    resb    NUM_CAP
