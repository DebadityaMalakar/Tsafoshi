; SPDX-License-Identifier: MIT
;
; Tree walk. One recursive pass turns a node into a value; every value still
; comes from op.asm, every variable from vars.asm and every conversion from
; printf.asm, so this file knows about shape and nothing else. Dispatch is a
; jump table on the node kind, the same shape the VM's inner loop uses.
;
; This is the oracle engine: it and vm.asm must agree on every input, which is
; the only reason it is still here now that there is a compiler.

%include "tsafoshi.inc"

    global  ast_eval

    extern  op_apply
    extern  op_neg
    extern  var_get
    extern  var_set
    extern  str_addr
    extern  printf_run
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

.str:
    mov     rdi, [rdi + NODE_VAL]
    jmp     str_addr

.var:
    mov     rdi, [rdi + NODE_VAL]
    jmp     var_get

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

; Statements in sequence: everything but the last value is discarded, which is
; what the VM's POP does with the same tree.
.seq:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + NODE_LHS]
    call    ast_eval
    cmp     qword [err_code], 0
    jne     .seq_failed
    mov     rdi, [rbx + NODE_RHS]
    call    ast_eval
    pop     rbx
    ret
.seq_failed:
    xor     eax, eax
    pop     rbx
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
    dq      ast_eval.seq                ; NT_SEQ
