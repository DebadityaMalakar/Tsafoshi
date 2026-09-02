; SPDX-License-Identifier: MIT
;
; Tree -> bytecode. A postorder walk that emits operands before the operator
; that consumes them, which is all a stack machine needs.
;
; This is the second consumer of the same tree eval.asm walks, and it is the
; reason the parser was made to stop producing values: nothing here re-reads a
; token, and nothing in the parser had to change to gain a compiler.

%include "tsafoshi.inc"

    global  code_compile

    extern  code_reset
    extern  code_op
    extern  code_i64
    extern  code_u32
    extern  line_buf

    section .text

; rdi = root node. Leaves a complete program in the code buffer; the caller
; checks err_code before running it.
code_compile:
    push    rdi
    call    code_reset
    pop     rdi
    call    emit_node
    mov     edi, OP_HALT
    jmp     code_op

; rdi = node.  rbx = the node being emitted
emit_node:
    test    rdi, rdi
    jz      .nothing
    push    rbx
    mov     rbx, rdi
    mov     rax, [rbx + NODE_KIND]
    lea     rcx, [emit_table]
    jmp     [rcx + rax * 8]

.num:
    mov     edi, OP_PUSH
    call    code_op
    mov     rdi, [rbx + NODE_VAL]
    call    code_i64
    jmp     .out

.unary:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     edi, OP_NEG
    call    code_op
    jmp     .out

.binary:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     rdi, [rbx + NODE_RHS]
    call    emit_node
    mov     rdi, [rbx + NODE_VAL]       ; token kind -> opcode, same order
    sub     rdi, TK_OP_FIRST
    add     rdi, OP_ADD
    push    rdi
    call    code_op
    pop     rdi
    cmp     rdi, OP_DIV                 ; only these two can fail, so only
    je      .position                   ; these two carry a source column
    cmp     rdi, OP_MOD
    jne     .out
.position:
    mov     rdi, [rbx + NODE_POS]
    lea     rax, [line_buf]
    sub     rdi, rax                    ; an offset survives being stored in 4
    call    code_u32                    ; bytes; a pointer would not

.out:
    pop     rbx
.nothing:
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
emit_table:
    dq      emit_node.num               ; NT_NUM
    dq      emit_node.unary             ; NT_UNARY
    dq      emit_node.binary            ; NT_BINARY
