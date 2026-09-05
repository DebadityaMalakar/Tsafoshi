; SPDX-License-Identifier: MIT
;
; The syntax tree: storage and constructors, nothing else. Nodes come out of a
; bump-allocated arena that the REPL resets once per line, so a tree costs one
; pointer bump per node and nothing at all to free.
;
; The parser builds these; eval.asm and compile.asm walk them. None of them
; knows how the others work, which is the whole point of having the tree in
; between.
;
; Every node is the same five cells whatever its kind: the three pointer slots
; are reused rather than added to, so a while loop and a binary operator cost
; the same. tsafoshi.inc records which slot means what for each kind.
;
; Because every node is the same shape, every constructor is the same routine
; with different arguments -- so they are all one routine, and each public name
; is the argument order the parser finds natural at that call site.

%include "tsafoshi.inc"

    global  ast_reset
    global  ast_num
    global  ast_unary
    global  ast_binary
    global  ast_var
    global  ast_assign
    global  ast_str
    global  ast_call
    global  ast_arg
    global  ast_seq
    global  ast_logical
    global  ast_expr
    global  ast_decl
    global  ast_if
    global  ast_loop
    global  ast_leaf

    extern  err_toobig

    section .text

ast_reset:
    lea     rax, [ast_arena]
    mov     [ast_next], rax
    ret

; rdi = kind, rsi = VAL, rdx = LHS, rcx = RHS, r8 = position -> rax = the node,
; or 0 with the error already recorded.
ast_make:
    mov     rax, [ast_next]
    lea     r9, [ast_end]
    cmp     rax, r9
    jae     .full
    add     qword [ast_next], NODE_SIZE
    mov     [rax + NODE_KIND], rdi
    mov     [rax + NODE_VAL], rsi
    mov     [rax + NODE_LHS], rdx
    mov     [rax + NODE_RHS], rcx
    mov     [rax + NODE_POS], r8
    ret
.full:
    mov     rdi, r8
    call    err_toobig
    xor     eax, eax
    ret

; rdi = value, rsi = position -> rax
ast_num:
    mov     r8, rsi
    mov     rsi, rdi
    xor     edx, edx
    xor     ecx, ecx
    mov     edi, NT_NUM
    jmp     ast_make

; rdi = operator token kind, rsi = operand, rdx = position -> rax
ast_unary:
    mov     r8, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    xor     ecx, ecx
    mov     edi, NT_UNARY
    jmp     ast_make

; rdi = operator token kind, rsi = lhs, rdx = rhs, rcx = position -> rax
ast_binary:
    mov     r8, rcx
    mov     rcx, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    mov     edi, NT_BINARY
    jmp     ast_make

; The same shape as a binary operator and a different node, because "&&" must
; not evaluate its right operand until it knows it has to.
; rdi = operator token kind, rsi = lhs, rdx = rhs, rcx = position -> rax
ast_logical:
    mov     r8, rcx
    mov     rcx, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    mov     edi, NT_LOGICAL
    jmp     ast_make

; rdi = storage slot, rsi = position -> rax
ast_var:
    mov     r8, rsi
    mov     rsi, rdi
    xor     edx, edx
    xor     ecx, ecx
    mov     edi, NT_VAR
    jmp     ast_make

; rdi = storage slot, rsi = the value expression, rdx = position -> rax
ast_assign:
    mov     r8, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    xor     ecx, ecx
    mov     edi, NT_ASSIGN
    jmp     ast_make

; rdi = offset into the string arena, rsi = position -> rax
ast_str:
    mov     r8, rsi
    mov     rsi, rdi
    xor     edx, edx
    xor     ecx, ecx
    mov     edi, NT_STR
    jmp     ast_make

; rdi = builtin id, rsi = argument chain, rdx = count, rcx = position -> rax
ast_call:
    mov     r8, rcx
    mov     rcx, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    mov     edi, NT_CALL
    jmp     ast_make

; rdi = one argument, rsi = position -> rax. The chain is linked afterwards,
; through NODE_RHS, by whoever is collecting the list.
ast_arg:
    mov     r8, rsi
    mov     rdx, rdi
    xor     esi, esi
    xor     ecx, ecx
    mov     edi, NT_ARG
    jmp     ast_make

; rdi = this statement, rsi = the rest of the list, rdx = position -> rax
ast_seq:
    mov     r8, rdx
    mov     rcx, rsi
    mov     rdx, rdi
    xor     esi, esi
    mov     edi, NT_SEQ
    jmp     ast_make

; An expression used as a statement. The wrapper is what says "and throw the
; value away", which is the whole difference between "x + 1" and "x + 1;".
; rdi = the expression, rsi = position -> rax
ast_expr:
    mov     r8, rsi
    mov     rdx, rdi
    xor     esi, esi
    xor     ecx, ecx
    mov     edi, NT_EXPR
    jmp     ast_make

; rdi = storage slot, rsi = the initialiser or zero, rdx = position -> rax
ast_decl:
    mov     r8, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    xor     ecx, ecx
    mov     edi, NT_DECL
    jmp     ast_make

; rdi = condition, rsi = the then branch, rdx = the else branch or zero,
; rcx = position -> rax
ast_if:
    mov     r8, rcx
    mov     rcx, rsi
    mov     rsi, rdx
    mov     rdx, rdi
    mov     edi, NT_IF
    jmp     ast_make

; One constructor for all three loops: they differ in when the condition is
; tested and whether there is a step, and not at all in shape.
; rdi = node kind, rsi = condition or zero, rdx = body, rcx = step or zero,
; r8 = position -> rax
ast_loop:
    mov     r9, rsi
    mov     rsi, rcx
    mov     rcx, rdx
    mov     rdx, r9
    jmp     ast_make

; rdi = node kind, rsi = position -> rax. For the statements that are nothing
; but themselves: break, continue and the empty statement.
ast_leaf:
    mov     r8, rsi
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    jmp     ast_make

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
ast_next:
    resq    1
ast_arena:
    resb    AST_CAP * NODE_SIZE
ast_end:
