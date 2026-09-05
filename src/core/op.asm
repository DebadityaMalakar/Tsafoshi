; SPDX-License-Identifier: MIT
;
; Operators: what they mean. The parser decides structure and the engine
; decides order, but every value actually produced comes from here. Dispatch is
; a jump table indexed by token kind, which is the same shape the bytecode VM
; uses -- and the reason the two engines cannot disagree about what "%" is.
;
; The short-circuiting operators are absent on purpose. "&&" never becomes a
; call to anything here, because by the time both operands existed as values
; the question it asks would already have been answered the wrong way.

%include "tsafoshi.inc"

    global  op_apply
    global  op_unary
    global  op_neg
    global  op_not
    global  op_bnot
    global  op_mul
    global  op_div
    global  op_mod
    global  op_add
    global  op_sub
    global  op_shl
    global  op_shr
    global  op_lt
    global  op_gt
    global  op_le
    global  op_ge
    global  op_eq
    global  op_ne
    global  op_and
    global  op_xor
    global  op_or

    extern  err_divzero

    section .text

; rdi = lhs, rsi = rhs, rdx = operator token kind, rcx = position for
; diagnostics -> rax
op_apply:
    sub     rdx, TK_OP_FIRST
    cmp     rdx, TK_VAL_LAST - TK_OP_FIRST
    ja      .bad
    lea     r8, [op_table]
    jmp     [r8 + rdx * 8]
.bad:
    xor     eax, eax
    ret

; rdi = operand, rsi = operator token kind -> rax
op_unary:
    cmp     rsi, TK_BANG
    je      op_not
    cmp     rsi, TK_TILDE
    je      op_bnot
    ; fall through: TK_MINUS

; rdi = operand -> rax
op_neg:
    mov     rax, rdi
    neg     rax
    ret

; C's "!" is a test, not a bit operation: its result is 0 or 1 and nothing
; else, which is what makes "!!x" the idiom for "x, as a truth value".
op_not:
    xor     eax, eax
    test    rdi, rdi
    sete    al
    ret

op_bnot:
    mov     rax, rdi
    not     rax
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

; A shift count outside 0 .. 63 is undefined behaviour in C99. Here it is
; whatever the hardware does, which is to use the low six bits of the count --
; the same conscious shortcut as wrapping signed overflow.
op_shl:
    mov     rax, rdi
    mov     rcx, rsi
    shl     rax, cl
    ret

; Arithmetic, not logical: every cell is a signed 64-bit value until stage 3
; brings types, so ">>" has to keep the sign it was given.
op_shr:
    mov     rax, rdi
    mov     rcx, rsi
    sar     rax, cl
    ret

; The six comparisons differ in one letter each, and all of them produce the
; 0 or 1 that C says a relational operator produces.
op_lt:
    xor     eax, eax
    cmp     rdi, rsi
    setl    al
    ret
op_gt:
    xor     eax, eax
    cmp     rdi, rsi
    setg    al
    ret
op_le:
    xor     eax, eax
    cmp     rdi, rsi
    setle   al
    ret
op_ge:
    xor     eax, eax
    cmp     rdi, rsi
    setge   al
    ret
op_eq:
    xor     eax, eax
    cmp     rdi, rsi
    sete    al
    ret
op_ne:
    xor     eax, eax
    cmp     rdi, rsi
    setne   al
    ret

op_and:
    mov     rax, rdi
    and     rax, rsi
    ret

op_xor:
    mov     rax, rdi
    xor     rax, rsi
    ret

op_or:
    mov     rax, rdi
    or      rax, rsi
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
op_table:
    dq      op_mul                      ; TK_STAR
    dq      op_div                      ; TK_SLASH
    dq      op_mod                      ; TK_PERCENT
    dq      op_add                      ; TK_PLUS
    dq      op_sub                      ; TK_MINUS
    dq      op_shl                      ; TK_SHL
    dq      op_shr                      ; TK_SHR
    dq      op_lt                       ; TK_LT
    dq      op_gt                       ; TK_GT
    dq      op_le                       ; TK_LE
    dq      op_ge                       ; TK_GE
    dq      op_eq                       ; TK_EQ
    dq      op_ne                       ; TK_NE
    dq      op_and                      ; TK_AMP
    dq      op_xor                      ; TK_CARET
    dq      op_or                       ; TK_PIPE
