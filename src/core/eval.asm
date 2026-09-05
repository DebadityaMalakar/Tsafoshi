; SPDX-License-Identifier: MIT
;
; Tree walk. One recursive pass turns a node into a value; every value still
; comes from op.asm, every variable from vars.asm and every conversion from
; printf.asm, so this file knows about shape and nothing else. Dispatch is a
; jump table on the node kind, the same shape the VM's inner loop uses.
;
; This is the oracle engine: it and vm.asm must agree on every input, which is
; the only reason it is still here now that there is a compiler.
;
; Control flow is where the two engines stop resembling each other, and that is
; exactly why keeping both is worth the trouble. The VM jumps: "break" is an
; address. A recursive walker cannot jump out of its own call chain, so it sets
; eval_flow instead and every statement rule tests it on the way back out --
; a different mechanism entirely, which must still produce the same answer.

%include "tsafoshi.inc"

    global  eval_program
    global  ast_eval

    extern  op_apply
    extern  op_unary
    extern  var_get
    extern  var_set
    extern  str_addr
    extern  printf_run
    extern  err_code

    section .text

; rdi = the statement list, rsi = the trailing expression or zero -> rax.
; Statements are run for effect; the line's value is that last expression, or
; zero when there was not one.
eval_program:
    push    rbx
    mov     rbx, rsi
    mov     qword [eval_flow], FLOW_NORMAL
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .zero
    test    rbx, rbx
    jz      .zero
    mov     rdi, rbx
    call    ast_eval
    pop     rbx
    ret
.zero:
    xor     eax, eax
    pop     rbx
    ret

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

.str:
    mov     rdi, [rdi + NODE_VAL]
    jmp     str_addr

.var:
    mov     rdi, [rdi + NODE_VAL]
    jmp     var_get

.unary:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    mov     rsi, [rbx + NODE_VAL]
    mov     rdi, rax
    pop     rbx
    jmp     op_unary

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

; "&&" and "||" evaluate their right operand only when the left one has not
; already settled the question, and yield the 1 or 0 that C says they do.
.logical:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .logical_false
    cmp     qword [rbx + NODE_VAL], TK_ANDAND
    je      .logical_and
    test    rax, rax                    ; "||": a true left settles it
    jnz     .logical_true
    jmp     .logical_rhs
.logical_and:
    test    rax, rax                    ; "&&": a false left settles it
    jz      .logical_false
.logical_rhs:
    mov     rdi, [rbx + NODE_RHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .logical_false
    test    rax, rax
    jz      .logical_false
.logical_true:
    mov     eax, 1
    pop     rbx
    ret
.logical_false:
    xor     eax, eax
    pop     rbx
    ret

; An assignment is an expression, so the value stays: x = y = 3 works, and so
; does echoing what the prompt was just handed.
.assign:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .assign_failed
    mov     rsi, rax
    mov     rdi, [rbx + NODE_VAL]
    push    rsi
    call    var_set
    pop     rax
    pop     rbx
    ret
.assign_failed:
    xor     eax, eax
    pop     rbx
    ret

; --- statements. Each leaves no value and each stops early if the walk is
; --- unwinding, whether towards an error or out of a loop.

; Statements in sequence, which is also what the VM does with the same tree --
; except that the VM reaches the end of the list by running off it, and this
; has to be told to stop.
.seq:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .stmt_out
    cmp     qword [eval_flow], FLOW_NORMAL
    jne     .stmt_out
    mov     rdi, [rbx + NODE_RHS]
    call    ast_eval
.stmt_out:
    xor     eax, eax
    pop     rbx
    ret

; An expression run for its effect. The value is computed and dropped, which
; is the one thing that separates "printf(...)" from "printf(...);".
.expr:
    mov     rdi, [rdi + NODE_LHS]
    call    ast_eval
    xor     eax, eax
    ret

; A declaration with no initialiser still writes: the slot may have been used
; by a block that has since closed, and C99's "indeterminate" is not something
; worth reproducing when zero is free.
.decl:
    push    rbx
    mov     rbx, rdi
    xor     eax, eax
    mov     rdi, [rbx + NODE_LHS]
    test    rdi, rdi
    jz      .decl_store
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .stmt_out
.decl_store:
    mov     rsi, rax
    mov     rdi, [rbx + NODE_VAL]
    call    var_set
    xor     eax, eax
    pop     rbx
    ret

.if:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .stmt_out
    test    rax, rax
    jnz     .if_then
    mov     rdi, [rbx + NODE_VAL]       ; the else branch, or nothing
    jmp     .if_run
.if_then:
    mov     rdi, [rbx + NODE_RHS]
.if_run:
    call    ast_eval
    jmp     .stmt_out

; while, do and for are one loop with the tests moved. r12 tells the shared
; body from the three entries which of them is running.
.while:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, NT_WHILE
    jmp     .loop_test
.do:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, NT_DO
    jmp     .loop_body
.for:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, NT_FOR

; An absent condition -- "for (;;)" -- is true, which is why the node stores
; zero for it rather than a literal one.
.loop_test:
    mov     rdi, [rbx + NODE_LHS]
    test    rdi, rdi
    jz      .loop_body
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .loop_out
    test    rax, rax
    jz      .loop_done

.loop_body:
    mov     rdi, [rbx + NODE_RHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .loop_out
    mov     rax, [eval_flow]
    cmp     rax, FLOW_BREAK
    je      .loop_broken
    mov     qword [eval_flow], FLOW_NORMAL

; The step runs on the way round, including after a "continue" -- which is the
; whole reason for is not just a while with the step written at the bottom.
    mov     rdi, [rbx + NODE_VAL]
    test    rdi, rdi
    jz      .loop_tail
    cmp     r12, NT_FOR
    jne     .loop_tail
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .loop_out

.loop_tail:
    cmp     r12, NT_DO
    jne     .loop_test
    mov     rdi, [rbx + NODE_LHS]       ; do-while tests at the bottom
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .loop_out
    test    rax, rax
    jnz     .loop_body

.loop_done:
.loop_broken:
    mov     qword [eval_flow], FLOW_NORMAL
.loop_out:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

.break:
    mov     qword [eval_flow], FLOW_BREAK
    xor     eax, eax
    ret
.continue:
    mov     qword [eval_flow], FLOW_CONTINUE
    xor     eax, eax
    ret

; Arguments are gathered into a contiguous block before the call, because that
; is the shape printf_run wants -- and it is the shape they are already in on
; the VM's operand stack, which is why one routine serves both engines.
; rbx = the call node, r12 = the next argument, r13 = how many so far
.call:
    push    rbx
    push    r12
    push    r13
    sub     rsp, ARG_MAX * CELL
    mov     rbx, rdi
    mov     r12, [rbx + NODE_LHS]
    xor     r13, r13
.argument:
    test    r12, r12
    jz      .invoke
    mov     rdi, [r12 + NODE_LHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .call_failed
    mov     [rsp + r13 * CELL], rax
    inc     r13
    mov     r12, [r12 + NODE_RHS]
    jmp     .argument
.invoke:
    mov     rdi, rsp
    mov     rsi, r13
    mov     rdx, [rbx + NODE_POS]
    call    printf_run                  ; BI_PRINTF is the only builtin
    jmp     .call_out
.call_failed:
    xor     eax, eax
.call_out:
    add     rsp, ARG_MAX * CELL
    pop     r13
    pop     r12
    pop     rbx
    ret

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
    dq      ast_eval.var                ; NT_VAR
    dq      ast_eval.assign             ; NT_ASSIGN
    dq      ast_eval.str                ; NT_STR
    dq      ast_eval.call               ; NT_CALL
    dq      ast_eval.zero               ; NT_ARG, only ever walked by NT_CALL
    dq      ast_eval.logical            ; NT_LOGICAL
    dq      ast_eval.seq                ; NT_SEQ
    dq      ast_eval.expr               ; NT_EXPR
    dq      ast_eval.decl               ; NT_DECL
    dq      ast_eval.if                 ; NT_IF
    dq      ast_eval.while              ; NT_WHILE
    dq      ast_eval.do                 ; NT_DO
    dq      ast_eval.for                ; NT_FOR
    dq      ast_eval.break              ; NT_BREAK
    dq      ast_eval.continue           ; NT_CONTINUE
    dq      ast_eval.zero               ; NT_EMPTY

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
eval_flow:
    resq    1
