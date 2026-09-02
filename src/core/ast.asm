; SPDX-License-Identifier: MIT
;
; The syntax tree: storage and constructors, nothing else. Nodes come out of a
; bump-allocated arena that the REPL resets once per line, so a tree costs one
; pointer bump per node and nothing at all to free.
;
; The parser builds these; eval.asm walks them. Neither knows how the other
; works, which is the whole point of having the tree in between.

%include "tsafoshi.inc"

    global  ast_reset
    global  ast_num
    global  ast_unary
    global  ast_binary

    extern  err_toobig

    section .text

ast_reset:
    lea     rax, [ast_arena]
    mov     [ast_next], rax
    ret

; rdi = position -> rax = cleared node, or 0 with the error already recorded
ast_alloc:
    mov     rax, [ast_next]
    lea     rcx, [ast_end]
    cmp     rax, rcx
    jae     .full
    add     qword [ast_next], NODE_SIZE
    mov     qword [rax + NODE_VAL], 0
    mov     qword [rax + NODE_LHS], 0
    mov     qword [rax + NODE_RHS], 0
    mov     [rax + NODE_POS], rdi
    ret
.full:
    call    err_toobig                  ; rdi already holds the position
    xor     eax, eax
    ret

; rdi = value, rsi = position -> rax
ast_num:
    push    rdi
    mov     rdi, rsi
    call    ast_alloc
    pop     rdi
    test    rax, rax
    jz      .out
    mov     qword [rax + NODE_KIND], NT_NUM
    mov     [rax + NODE_VAL], rdi
.out:
    ret

; rdi = operator token kind, rsi = operand, rdx = position -> rax
ast_unary:
    push    rdi
    push    rsi
    mov     rdi, rdx
    call    ast_alloc
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .out
    mov     qword [rax + NODE_KIND], NT_UNARY
    mov     [rax + NODE_VAL], rdi
    mov     [rax + NODE_LHS], rsi
.out:
    ret

; rdi = operator token kind, rsi = lhs, rdx = rhs, rcx = position -> rax
ast_binary:
    push    rdi
    push    rsi
    push    rdx
    sub     rsp, 8
    mov     rdi, rcx
    call    ast_alloc
    add     rsp, 8
    pop     rdx
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .out
    mov     qword [rax + NODE_KIND], NT_BINARY
    mov     [rax + NODE_VAL], rdi
    mov     [rax + NODE_LHS], rsi
    mov     [rax + NODE_RHS], rdx
.out:
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
ast_next:
    resq    1
ast_arena:
    resb    AST_CAP * NODE_SIZE
ast_end:
