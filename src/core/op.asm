; SPDX-License-Identifier: MIT
;
; Operator semantics. The parser decides structure; every value actually
; produced comes from here. Dispatch is a jump table indexed by token kind,
; which is the same shape the bytecode VM will want later.

%include "tsafoshi.inc"

    global  op_apply
    global  op_neg
    global  op_add
    global  op_sub
    global  op_mul
    global  op_div
    global  op_mod

    extern  err_divzero

    section .text

; rdi = lhs, rsi = rhs, rdx = operator token kind, rcx = position for
; diagnostics -> rax
op_apply:
    sub     rdx, TK_OP_FIRST
    cmp     rdx, TK_OP_LAST - TK_OP_FIRST
    ja      .bad
    lea     r8, [op_table]
    jmp     [r8 + rdx * 8]
.bad:
    xor     eax, eax
    ret

; rdi = operand -> rax
op_neg:
    mov     rax, rdi
    neg     rax
    ret

op_add:
    lea     rax, [rdi + rsi]
    ret

op_sub:
    mov     rax, rdi
    sub     rax, rsi
    ret

op_mul:
    mov     rax, rdi
    imul    rax, rsi
    ret

op_div:
    test    rsi, rsi
    jz      .divzero
    cmp     rsi, -1                     ; INT64_MIN / -1 would trap idiv
    je      .neg
    mov     rax, rdi
    cqo
    idiv    rsi
    ret
.neg:
    mov     rax, rdi
    neg     rax
    ret
.divzero:
    mov     rdi, rcx
    call    err_divzero
    xor     eax, eax
    ret

op_mod:
    test    rsi, rsi
    jz      op_div.divzero
    cmp     rsi, -1                     ; same trap; remainder is always 0
    je      .zero
    mov     rax, rdi
    cqo
    idiv    rsi
    mov     rax, rdx
    ret
.zero:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
op_table:
    dq      op_add                      ; TK_PLUS
    dq      op_sub                      ; TK_MINUS
    dq      op_mul                      ; TK_STAR
    dq      op_div                      ; TK_SLASH
    dq      op_mod                      ; TK_PERCENT
