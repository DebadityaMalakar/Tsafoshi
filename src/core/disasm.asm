; SPDX-License-Identifier: MIT
;
; Bytecode listing. A second decoder over the same stream vm.asm executes,
; which is the cheapest way to keep the compiler honest: if the listing reads
; wrong, the encoding is wrong.

%include "tsafoshi.inc"

    global  disasm_all

    extern  code_buf
    extern  code_len
    extern  fmt_i64
    extern  sys_write_stdout

MNEMONIC_LEN        equ 4               ; padded, so indexing is a shift
OFF_DIGITS          equ 4

    section .text

; rbx = offset into the stream, r12 = the opcode being decoded
disasm_all:
    push    rbx
    push    r12
    xor     ebx, ebx

.next:
    cmp     rbx, [code_len]
    jae     .done

    mov     rdi, rbx
    call    put_offset
    lea     rcx, [code_buf]
    movzx   eax, byte [rcx + rbx]
    inc     rbx
    mov     r12, rax
    cmp     rax, OP_COUNT               ; a stream we cannot read is a bug
    jae     .done
    lea     rsi, [mnemonics]
    lea     rsi, [rsi + rax * MNEMONIC_LEN]
    mov     rdx, MNEMONIC_LEN
    cmp     byte [rsi + MNEMONIC_LEN - 1], ' '
    jne     .name
    dec     rdx                         ; three-letter name, drop the padding
.name:
    call    sys_write_stdout

    cmp     r12, OP_PUSH
    je      .immediate
    cmp     r12, OP_DIV
    je      .column
    cmp     r12, OP_MOD
    je      .column

.endline:
    lea     rsi, [t_newline]
    mov     rdx, 1
    call    sys_write_stdout
    jmp     .next

.immediate:
    lea     rsi, [t_space]
    mov     rdx, 1
    call    sys_write_stdout
    lea     rcx, [code_buf]
    mov     rax, [rcx + rbx]
    add     rbx, 8
    call    fmt_i64
    call    sys_write_stdout
    jmp     .endline

.column:
    lea     rsi, [t_at]
    mov     rdx, t_at.len
    call    sys_write_stdout
    lea     rcx, [code_buf]
    mov     eax, dword [rcx + rbx]
    add     rbx, 4
    call    fmt_i64
    call    sys_write_stdout
    jmp     .endline

.done:
    pop     r12
    pop     rbx
    ret

; rdi = offset, printed as four digits with the indent in front of it
put_offset:
    lea     rsi, [t_indent]
    mov     rdx, t_indent.len
    push    rdi
    call    sys_write_stdout
    pop     rax
    lea     r8, [off_buf]
    mov     r9d, 10
    mov     rcx, OFF_DIGITS
.digit:
    xor     edx, edx
    div     r9
    add     dl, '0'
    dec     rcx
    mov     [r8 + rcx], dl
    test    rcx, rcx
    jnz     .digit
    lea     rsi, [off_buf]
    mov     rdx, OFF_DIGITS
    call    sys_write_stdout
    lea     rsi, [t_gap]
    mov     rdx, t_gap.len
    jmp     sys_write_stdout

; ---------------------------------------------------------------------------
    section .data

; Padded to a fixed width so the operand column lines up without a table of
; lengths, and so indexing is a shift rather than a lookup.
mnemonics:
    db      "halt"                      ; OP_HALT
    db      "push"                      ; OP_PUSH
    db      "add "                      ; OP_ADD
    db      "sub "                      ; OP_SUB
    db      "mul "                      ; OP_MUL
    db      "div "                      ; OP_DIV
    db      "mod "                      ; OP_MOD
    db      "neg "                      ; OP_NEG

t_indent:
    db      "    "
.len                equ $ - t_indent
t_gap:
    db      "  "
.len                equ $ - t_gap
t_at:
    db      " @"
.len                equ $ - t_at
t_space:
    db      " "
t_newline:
    db      10

; ---------------------------------------------------------------------------
    section .bss

off_buf:
    resb    OFF_DIGITS
