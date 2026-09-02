; SPDX-License-Identifier: MIT
;
; Tree walk. One recursive pass turns a node into a value; every value still
; comes from op.asm, so this file knows about shape and nothing about
; arithmetic. Dispatch is a jump table on the node kind, the same shape the
; bytecode VM's inner loop will want.

%include "tsafoshi.inc"

    global  ast_eval

    extern  op_apply
    extern  op_neg
    extern  err_code

    section .text

; rdi = node -> rax.  rbx = the node under evaluation, r12 = its left value
ast_eval:
    test    rdi, rdi
    jz      .zero                       ; a node the parser failed to build
    mov     rax, [rdi + NODE_KIND]
    lea     rcx, [node_table]
    jmp     [rcx + rax * 8]

.num:
    mov     rax, [rdi + NODE_VAL]
    ret

.unary:
    mov     rdi, [rdi + NODE_LHS]
    call    ast_eval
    mov     rdi, rax
    jmp     op_neg                      ; TK_MINUS is the only one so far

.binary:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    mov     r12, rax
    mov     rdi, [rbx + NODE_RHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    mov     rdi, r12
    mov     rdx, [rbx + NODE_VAL]
    mov     rcx, [rbx + NODE_POS]
    call    op_apply
.out:
    pop     r12
    pop     rbx
    ret
.fail:
    xor     eax, eax
    jmp     .out

.zero:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
node_table:
    dq      ast_eval.num                ; NT_NUM
    dq      ast_eval.unary              ; NT_UNARY
    dq      ast_eval.binary             ; NT_BINARY
