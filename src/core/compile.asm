; SPDX-License-Identifier: MIT
;
; Tree -> bytecode. A postorder walk that emits operands before the operator
; that consumes them, which is all a stack machine needs.
;
; This is the second consumer of the same tree eval.asm walks, and it is the
; reason the parser was made to stop producing values: nothing here re-reads a
; token, and nothing in the parser had to change to gain a compiler.
;
; Two invariants hold the whole file up. An expression leaves exactly one cell
; behind; a statement leaves none. Everything else -- why a declaration ends in
; a POP, why an expression statement does too, why the list needs no cleanup at
; the end -- follows from those two, and the operand stack is never checked at
; run time because of them.
;
; A function is compiled into the same buffer and then kept, by raising the
; arena's watermark past it. Everything the session has defined therefore sits
; below the current line's code, in definition order, never moving -- which is
; what lets an entry point be a plain offset that stays valid for good.
;
; Control flow is where a tree stops being convenient and jumps have to be
; invented. Two things make that manageable. A forward jump is emitted with a
; hole where its target goes, and the hole is filled in once the target is
; known. And the holes of a loop's unfinished breaks are chained *through each
; other* -- each one holds the offset of the previous -- so an arbitrary number
; of them costs one word per loop and no allocation at all.

%include "tsafoshi.inc"

    global  code_compile
    global  code_compile_function

    extern  code_reset
    extern  code_commit
    extern  func_frame
    extern  func_set_entry
    extern  code_op
    extern  code_i64
    extern  code_u32
    extern  code_here
    extern  code_jump
    extern  code_patch
    extern  code_buf
    extern  src_buf
    extern  func_body
    extern  err_code
    extern  err_toodeep

    section .text

; rdi = the statement list, rsi = the trailing expression or zero. Leaves a
; complete program in the code buffer; the caller checks err_code before
; running it.
;
; HALT reads the top of the stack, so there has to be something there: a line
; that was all statements still answers, and its answer is zero.
; rdi = function id. Compiles its body into the arena and keeps it, recording
; where it starts. Called once per definition, whichever engine is active: the
; user may switch to the VM later, and a function with no code is not something
; to discover at that point.
;
; Falling off the end of a function is "return 0", exactly as C99 says of main
; -- so the body is always followed by one, and a body that already returned
; simply never reaches it.
code_compile_function:
    push    rbx
    mov     rbx, rdi
    call    code_reset
    mov     qword [loop_top], 0
    mov     rdi, rbx
    mov     rsi, rax
    call    func_set_entry
    mov     rdi, rbx
    call    func_body
    mov     rdi, rax
    call    emit_node
    mov     edi, OP_PUSH
    call    code_op
    xor     edi, edi
    call    code_i64
    mov     edi, OP_RET
    call    code_op
    call    code_commit
    pop     rbx
    ret

; -> rax = where the program starts, for vm_run
code_compile:
    push    rbx
    push    r12
    mov     rbx, rsi
    push    rdi
    call    code_reset
    mov     r12, rax
    mov     qword [loop_top], 0
    pop     rdi
    call    emit_node
    test    rbx, rbx
    jz      .no_value
    mov     rdi, rbx
    call    emit_node
    jmp     .halt
.no_value:
    mov     edi, OP_PUSH
    call    code_op
    xor     edi, edi
    call    code_i64
.halt:
    mov     edi, OP_HALT
    call    code_op
    mov     rax, r12
    pop     r12
    pop     rbx
    ret

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

; The arena is static, so an offset is enough and the listing stays readable.
.str:
    mov     edi, OP_STR
    call    code_op
    mov     rdi, [rbx + NODE_VAL]
    call    code_u32
    jmp     .out

;
; A global is an index into one array that outlives everything; a local is an
; offset from the frame of the call that is running. Same slot number, two
; different opcodes, and the node said which back when a scope still existed.
.var:
    mov     edi, OP_LOAD
    cmp     qword [rbx + NODE_RHS], VAR_LOCAL
    jne     .var_emit
    mov     edi, OP_LOADL
.var_emit:
    call    code_op
    mov     rdi, [rbx + NODE_VAL]
    call    code_u32
    jmp     .out

; STORE leaves its value on the stack, because an assignment is an expression.
.assign:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    call    emit_store
    jmp     .out

.unary:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     rax, [rbx + NODE_VAL]
    mov     edi, OP_NEG
    cmp     rax, TK_BANG
    je      .unary_not
    cmp     rax, TK_TILDE
    jne     .unary_emit
    mov     edi, OP_BNOT
    jmp     .unary_emit
.unary_not:
    mov     edi, OP_NOT
.unary_emit:
    call    code_op
    jmp     .out

.binary:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     rdi, [rbx + NODE_RHS]
    call    emit_node
    mov     rdi, [rbx + NODE_VAL]       ; token kind -> opcode, same order
    sub     rdi, TK_OP_FIRST
    add     rdi, OP_BIN_FIRST
    push    rdi
    call    code_op
    pop     rdi
    cmp     rdi, OP_DIV                 ; only these two can fail, so only
    je      .position                   ; these two carry a source column
    cmp     rdi, OP_MOD
    jne     .out

; A pointer would not survive being stored in four bytes; an offset does.
.position:
    mov     rdi, [rbx + NODE_POS]
    lea     rax, [src_buf]
    sub     rdi, rax
    call    code_u32
    jmp     .out

; "&&" and "||" have no opcode. They are a branch and two constants, which is
; the only honest way to say "do not evaluate that" on a stack machine.
;
; r12 = the jump out of the left operand, r13 = the one out of the right,
; r14 = the jump over the answer that was not taken
.logical:
    push    r12
    push    r13
    push    r14
    mov     edi, OP_JZ                  ; "&&" leaves early when false
    cmp     qword [rbx + NODE_VAL], TK_ANDAND
    je      .logical_op
    mov     edi, OP_JNZ                 ; "||" leaves early when true
.logical_op:
    push    rdi
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    pop     rdi
    push    rdi
    call    code_jump
    mov     r12, rax
    pop     rdi
    push    rdi
    mov     rdi, [rbx + NODE_RHS]
    call    emit_node
    pop     rdi
    call    code_jump
    mov     r13, rax

; Falling through both tests means the operator did not leave early, so the
; answer is the opposite of whatever the early exit would have given.
    mov     edi, OP_PUSH
    call    code_op
    mov     edi, 1
    cmp     qword [rbx + NODE_VAL], TK_ANDAND
    je      .logical_fall
    xor     edi, edi
.logical_fall:
    call    code_i64
    mov     edi, OP_JMP
    call    code_jump
    mov     r14, rax

    call    code_here
    mov     rdi, r12
    mov     rsi, rax
    push    rax
    call    code_patch
    pop     rsi
    mov     rdi, r13
    call    code_patch
    mov     edi, OP_PUSH
    call    code_op
    xor     edi, edi
    cmp     qword [rbx + NODE_VAL], TK_ANDAND
    je      .logical_early
    mov     edi, 1
.logical_early:
    call    code_i64
    call    code_here
    mov     rdi, r14
    mov     rsi, rax
    call    code_patch
    pop     r14
    pop     r13
    pop     r12
    jmp     .out

; --- statements. Every one of these leaves the operand stack as it found it.

.seq:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     rdi, [rbx + NODE_RHS]
    call    emit_node
    jmp     .out

; An expression run for its effect: compute it, then throw it away. POP is the
; whole difference between "x + 1" and "x + 1;".
.expr:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     edi, OP_POP
    call    code_op
    jmp     .out

; A declaration is an assignment with a zero default, and the POP is there for
; the same reason it is above: STORE is an expression's opcode.
.decl:
    mov     rdi, [rbx + NODE_LHS]
    test    rdi, rdi
    jnz     .decl_init
    mov     edi, OP_PUSH
    call    code_op
    xor     edi, edi
    call    code_i64
    jmp     .decl_store
.decl_init:
    call    emit_node
.decl_store:
    call    emit_store
    mov     edi, OP_POP
    call    code_op
    jmp     .out

; r12 = the jump over the then branch, r13 = the jump over the else branch
.if:
    push    r12
    push    r13
    sub     rsp, 8
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     edi, OP_JZ
    call    code_jump
    mov     r12, rax
    mov     rdi, [rbx + NODE_RHS]
    call    emit_node
    cmp     qword [rbx + NODE_VAL], 0
    je      .if_done

    mov     edi, OP_JMP
    call    code_jump
    mov     r13, rax
    call    code_here
    mov     rdi, r12
    mov     rsi, rax
    call    code_patch
    mov     rdi, [rbx + NODE_VAL]
    call    emit_node
    call    code_here
    mov     rdi, r13
    mov     rsi, rax
    call    code_patch
    jmp     .if_out
.if_done:
    call    code_here
    mov     rdi, r12
    mov     rsi, rax
    call    code_patch
.if_out:
    add     rsp, 8
    pop     r13
    pop     r12
    jmp     .out

; One emitter for all three loops. They differ in where the condition is
; tested and whether there is a step, and in nothing else:
;
; while   top: cond, JZ end,  body, cont:        JMP top,  end:
; for     top: cond, JZ end,  body, cont: step,  JMP top,  end:
; do      top:                body, cont: cond,  JNZ top,  end:
;
; "cont" lands where it does on purpose. In a for loop the step still runs
; after a continue, which is the whole reason for is not a while with the step
; written at the bottom; in a do-while the condition still gets tested.
;
; r12 = the top of the loop, r13 = the jump out of the condition
.while:
.do:
.for:
    push    r12
    push    r13
    sub     rsp, 8
    call    code_here
    mov     r12, rax
    xor     r13, r13
    cmp     qword [rbx + NODE_KIND], NT_DO
    je      .loop_open
    mov     rdi, [rbx + NODE_LHS]
    test    rdi, rdi
    jz      .loop_open                  ; "for (;;)": no test, no exit
    call    emit_node
    mov     edi, OP_JZ
    call    code_jump
    mov     r13, rax

.loop_open:
    call    loop_push
    cmp     qword [err_code], 0
    jne     .loop_out
    mov     rdi, [rbx + NODE_RHS]
    call    emit_node

    call    code_here                   ; where "continue" lands
    mov     rdi, rax
    call    loop_continue_here
    cmp     qword [rbx + NODE_KIND], NT_FOR
    jne     .loop_back
    mov     rdi, [rbx + NODE_VAL]
    call    emit_node                   ; the step is already an NT_EXPR

.loop_back:
    cmp     qword [rbx + NODE_KIND], NT_DO
    je      .loop_bottom_test
    mov     edi, OP_JMP
    call    code_jump
    mov     rsi, r12
    mov     rdi, rax
    call    code_patch
    jmp     .loop_end
.loop_bottom_test:
    mov     rdi, [rbx + NODE_LHS]
    call    emit_node
    mov     edi, OP_JNZ
    call    code_jump
    mov     rsi, r12
    mov     rdi, rax
    call    code_patch

.loop_end:
    call    code_here
    push    rax
    test    r13, r13
    jz      .loop_breaks
    mov     rdi, r13
    mov     rsi, rax
    call    code_patch
.loop_breaks:
    pop     rdi
    call    loop_pop
.loop_out:
    add     rsp, 8
    pop     r13
    pop     r12
    jmp     .out

; A break or a continue is a jump whose target is not merely unknown but does
; not exist yet, so the hole it leaves is used to remember the previous one.
.break:
    lea     rdi, [loop_break]
    jmp     .jump
.continue:
    lea     rdi, [loop_cont]
.jump:
    mov     rax, [loop_top]
    dec     rax                         ; the parser proved there is one
    lea     rdi, [rdi + rax * CELL]
    push    rdi
    mov     edi, OP_JMP
    call    code_jump
    pop     rcx
    mov     rsi, [rcx]                  ; the chain so far, zero if empty
    mov     [rcx], rax
    mov     rdi, rax
    call    code_patch
    jmp     .out

; "return" with no expression still leaves a value, because RET expects one and
; because every function is an int function until stage 3 says otherwise.
.return:
    mov     rdi, [rbx + NODE_LHS]
    test    rdi, rdi
    jnz     .return_value
    mov     edi, OP_PUSH
    call    code_op
    xor     edi, edi
    call    code_i64
    jmp     .return_emit
.return_value:
    call    emit_node
.return_emit:
    mov     edi, OP_RET
    call    code_op
    jmp     .out

; A call. The arguments are pushed in order and left there; CALL takes them off
; into the new frame, which is why the parameters were declared first and so
; occupy offsets 0, 1, 2 ... There is no argument-passing convention to speak
; of, only an agreement about where a frame starts.
;
; r12 = the chain
.icall:
    push    r12
    mov     r12, [rbx + NODE_LHS]
.icall_arg:
    test    r12, r12
    jz      .icall_go
    mov     rdi, [r12 + NODE_LHS]
    call    emit_node
    mov     r12, [r12 + NODE_RHS]
    jmp     .icall_arg
.icall_go:
    pop     r12
    mov     edi, OP_CALL
    call    code_op
    mov     rdi, [rbx + NODE_VAL]
    call    code_u32
    jmp     .out

; The arguments end up contiguous on the operand stack in the order they were
; written, which is exactly the array printf_run reads.  r12 = the chain
.call:
    push    r12
    mov     r12, [rbx + NODE_LHS]
.argument:
    test    r12, r12
    jz      .invoke
    mov     rdi, [r12 + NODE_LHS]
    call    emit_node
    mov     r12, [r12 + NODE_RHS]
    jmp     .argument
.invoke:
    pop     r12
    mov     edi, OP_BI
    call    code_op
    mov     rdi, [rbx + NODE_VAL]       ; which builtin
    call    code_u32
    mov     rdi, [rbx + NODE_RHS]       ; how many arguments are on the stack
    call    code_u32
    mov     rdi, [rbx + NODE_POS]
    lea     rax, [src_buf]
    sub     rdi, rax
    call    code_u32

.out:
    pop     rbx
.nothing:
    ret

; rbx = a node whose VAL is a slot and whose RHS says which storage it is
emit_store:
    mov     edi, OP_STORE
    cmp     qword [rbx + NODE_RHS], VAR_LOCAL
    jne     .emit
    mov     edi, OP_STOREL
.emit:
    call    code_op
    mov     rdi, [rbx + NODE_VAL]
    jmp     code_u32


; ---------------------------------------------------------------------------
; The loop stack. One entry per loop being compiled, holding the head of each
; chain of jumps that is still waiting to learn where it goes.

loop_push:
    mov     rax, [loop_top]
    cmp     rax, LOOP_DEPTH
    jae     .full
    lea     rcx, [loop_break]
    mov     qword [rcx + rax * CELL], 0
    lea     rcx, [loop_cont]
    mov     qword [rcx + rax * CELL], 0
    inc     qword [loop_top]
    ret
.full:
    lea     rdi, [src_buf]
    jmp     err_toodeep

; rdi = where "continue" should land. Patches that chain now; the break chain
; has to wait for the end of the loop.
loop_continue_here:
    push    rbx
    mov     rbx, [loop_top]
    dec     rbx
    lea     rcx, [loop_cont]
    lea     rbx, [rcx + rbx * CELL]
    mov     rsi, rdi
    mov     rdi, [rbx]
    call    chain_patch
    mov     qword [rbx], 0
    pop     rbx
    ret

; rdi = where "break" should land
loop_pop:
    push    rbx
    mov     rbx, [loop_top]
    test    rbx, rbx
    jz      .none
    dec     rbx
    mov     [loop_top], rbx
    lea     rcx, [loop_break]
    lea     rbx, [rcx + rbx * CELL]
    mov     rsi, rdi
    mov     rdi, [rbx]
    call    chain_patch
    mov     qword [rbx], 0
.none:
    pop     rbx
    ret

; rdi = the head of a chain of holes, rsi = the target they all want.
; Each hole holds the offset of the next, so the next one has to be read out
; before the target is written over it.
chain_patch:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
.next:
    test    rbx, rbx
    jz      .done
    lea     rcx, [code_buf]
    mov     eax, [rcx + rbx]
    push    rax
    mov     rdi, rbx
    mov     rsi, r12
    call    code_patch
    pop     rbx
    jmp     .next
.done:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
emit_table:
    dq      emit_node.num               ; NT_NUM
    dq      emit_node.unary             ; NT_UNARY
    dq      emit_node.binary            ; NT_BINARY
    dq      emit_node.var               ; NT_VAR
    dq      emit_node.assign            ; NT_ASSIGN
    dq      emit_node.str               ; NT_STR
    dq      emit_node.call              ; NT_CALL
    dq      emit_node.out               ; NT_ARG, only ever walked by NT_CALL
    dq      emit_node.logical           ; NT_LOGICAL
    dq      emit_node.seq               ; NT_SEQ
    dq      emit_node.expr              ; NT_EXPR
    dq      emit_node.decl              ; NT_DECL
    dq      emit_node.if                ; NT_IF
    dq      emit_node.while             ; NT_WHILE
    dq      emit_node.do                ; NT_DO
    dq      emit_node.for               ; NT_FOR
    dq      emit_node.break             ; NT_BREAK
    dq      emit_node.continue          ; NT_CONTINUE
    dq      emit_node.out               ; NT_EMPTY
    dq      emit_node.return            ; NT_RETURN
    dq      emit_node.icall             ; NT_INVOKE

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
loop_top:
    resq    1
loop_break:
    resq    LOOP_DEPTH
loop_cont:
    resq    LOOP_DEPTH
