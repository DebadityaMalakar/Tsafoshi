; SPDX-License-Identifier: MIT
;
; The code buffer: storage for one compiled expression, and the three writes
; that fill it. Like the AST arena this is reset per line and never freed.
;
; compile.asm writes here; vm.asm and disasm.asm read. None of them owns the
; memory, so adding a fourth reader costs nothing.

%include "tsafoshi.inc"

    global  code_reset
    global  code_op
    global  code_i64
    global  code_u32
    global  code_buf
    global  code_len

    extern  err_codefull

    section .text

code_reset:
    mov     qword [code_len], 0
    ret

; Each writer refuses rather than runs past the end; the first refusal records
; the error and the rest are harmless repeats of it.

; rdi = opcode byte
code_op:
    mov     rax, [code_len]
    cmp     rax, CODE_CAP - 1
    ja      err_codefull
    lea     rcx, [code_buf]
    mov     [rcx + rax], dil
    inc     qword [code_len]
    ret

; rdi = 64-bit immediate
code_i64:
    mov     rax, [code_len]
    cmp     rax, CODE_CAP - 8
    ja      err_codefull
    lea     rcx, [code_buf]
    mov     [rcx + rax], rdi
    add     qword [code_len], 8
    ret

; rdi = 32-bit operand
code_u32:
    mov     rax, [code_len]
    cmp     rax, CODE_CAP - 4
    ja      err_codefull
    lea     rcx, [code_buf]
    mov     [rcx + rax], edi
    add     qword [code_len], 4
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
code_len:
    resq    1
code_buf:
    resb    CODE_CAP
