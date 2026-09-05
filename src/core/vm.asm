; SPDX-License-Identifier: MIT
;
; The dispatch loop. A stack machine over 64-bit cells: fetch a byte, index a
; table, run a handler, go round again.
;
; Every value still comes from op.asm, exactly as it did for the tree walker.
; The VM decides when an operation happens and where its operands live; it has
; no opinion about what any operator means.
;
; The sixteen binary opcodes share one handler. They were laid out contiguously
; and in token order for the compiler's sake, and that same ordering pays here:
; the opcode is still in eax when the handler is entered, so it indexes a table
; of op.asm routines directly and the loop needs one arm rather than sixteen.
;
; The operand stack is never checked for underflow. compile.asm only ever emits
; well-formed postfix -- an expression leaves one cell, a statement leaves none
; -- so an operator always has its operands; a check here would be testing the
; compiler from inside the hot loop.

%include "tsafoshi.inc"

    global  vm_run

    extern  code_buf
    extern  code_len
    extern  src_buf
    extern  op_mul
    extern  op_div
    extern  op_mod
    extern  op_add
    extern  op_sub
    extern  op_shl
    extern  op_shr
    extern  op_lt
    extern  op_gt
    extern  op_le
    extern  op_ge
    extern  op_eq
    extern  op_ne
    extern  op_and
    extern  op_xor
    extern  op_or
    extern  op_neg
    extern  op_not
    extern  op_bnot
    extern  var_get
    extern  var_set
    extern  var_local_get
    extern  var_local_set
    extern  frame_enter
    extern  frame_leave
    extern  frame_args
    extern  frame_reset
    extern  func_arity
    extern  func_frame
    extern  func_entry
    extern  str_addr
    extern  printf_run
    extern  err_code
    extern  err_deep
    extern  err_stackfull

    section .text

; rdi = where to start -> rax = the value HALT finds on the stack.
; rbx = instruction pointer, r12 = one past the top of the operand stack
vm_run:
    push    rbx
    push    r12
    push    rdi
    call    frame_reset
    pop     rdi
    mov     qword [vm_depth], 0
    lea     rbx, [code_buf]
    add     rbx, rdi
    lea     r12, [vm_stack]

.step:
    movzx   eax, byte [rbx]
    inc     rbx
    lea     rcx, [vm_table]
    jmp     [rcx + rax * 8]

.op_push:
    mov     rax, [rbx]
    add     rbx, 8
    jmp     .push_grow

; A literal's address, rebuilt from an offset so the stream stays readable.
.op_str:
    call    fetch_u32
    mov     rdi, rax
    call    str_addr
    jmp     .push_grow

.op_load:
    call    fetch_u32
    mov     rdi, rax
    call    var_get
    jmp     .push_grow

; STORE leaves the value where it found it: an assignment is an expression,
; and POP is what discards the ones nobody wanted.
.op_store:
    call    fetch_u32
    mov     rdi, rax
    mov     rsi, [r12 - CELL]
    call    var_set
    jmp     .step

.op_pop:
    sub     r12, CELL
    jmp     .step

; The arguments are already contiguous and in order on the operand stack, so
; the call needs no marshalling at all -- just a pointer into it.  r8 = count
.op_printf:
    call    fetch_u32
    mov     r8, rax
    call    fetch_pos
    mov     rdx, rcx
    mov     rax, r8
    imul    rax, rax, CELL
    sub     r12, rax
    mov     rdi, r12
    mov     rsi, r8
    call    printf_run
    jmp     .push_checked

; The three unary operators rewrite the top of the stack in place, so none of
; them can change its height and none of them needs checking.
.op_neg:
    mov     rdi, [r12 - CELL]
    call    op_neg
    mov     [r12 - CELL], rax
    jmp     .step
.op_not:
    mov     rdi, [r12 - CELL]
    call    op_not
    mov     [r12 - CELL], rax
    jmp     .step
.op_bnot:
    mov     rdi, [r12 - CELL]
    call    op_bnot
    mov     [r12 - CELL], rax
    jmp     .step

; Division is the only arithmetic that can fail, so it is the only arithmetic
; that pays for a source column. rcx carries it into op.asm, and stays zero for
; every other operator because nothing there will ever read it.
.op_div:
.op_mod:
    push    rax
    call    fetch_pos
    pop     rax
    jmp     .binary_go
.op_binary:
    xor     ecx, ecx
.binary_go:
    lea     r9, [op_routines]
    sub     eax, OP_BIN_FIRST
    mov     r9, [r9 + rax * 8]
    sub     r12, CELL * 2
    mov     rdi, [r12]
    mov     rsi, [r12 + CELL]
    call    r9
    ; fall through

.push_checked:
    cmp     qword [err_code], 0
    jne     .fail

; Only the instructions that make the stack taller have to test it. A binary
; operator pops two and pushes one, so it cannot be the one to overflow.
.push_grow:
    lea     rcx, [vm_stack_end]
    cmp     r12, rcx
    jae     .overflow
.push_back:
    mov     [r12], rax
    add     r12, CELL
    jmp     .step

; A local is an offset from the frame of the call that is running, so the same
; instruction reads a different cell on every recursion. That is the whole of
; what a frame pointer buys, and the only reason these two opcodes exist
; alongside LOAD and STORE.
.op_loadl:
    call    fetch_u32
    mov     rdi, rax
    call    var_local_get
    jmp     .push_grow
.op_storel:
    call    fetch_u32
    mov     rdi, rax
    mov     rsi, [r12 - CELL]
    call    var_local_set
    jmp     .step

; A call: enter a frame, move the arguments into its first slots, remember
; where to come back to, and jump. The arguments are already contiguous and in
; order on the operand stack, so moving them is one copy.
;
; r8 = the function, r9 = its arity
.op_call:
    call    fetch_u32
    mov     r8, rax
    mov     rdi, r8
    call    func_arity
    mov     r9, rax
    mov     rcx, [vm_depth]
    cmp     rcx, CALL_DEPTH
    jae     .too_deep
    mov     rdi, r8
    call    func_frame
    push    r8
    push    r9
    mov     rdi, rax
    lea     rsi, [src_buf]
    call    frame_enter                 ; rax = the caller's frame pointer
    pop     r9
    pop     r8
    cmp     rax, -1
    je      .fail

    mov     rcx, [vm_depth]
    shl     rcx, 4                      ; two cells per record
    lea     rdx, [vm_calls]
    add     rdx, rcx
    mov     [rdx + CELL], rax
    lea     rcx, [code_buf]
    mov     rsi, rbx
    sub     rsi, rcx                    ; the return address, as an offset
    mov     [rdx], rsi
    inc     qword [vm_depth]

    mov     rax, r9
    imul    rax, rax, CELL
    sub     r12, rax                    ; the arguments come off the stack
    mov     rdi, r12
    mov     rsi, r9
    call    frame_args
    mov     rdi, r8
    call    func_entry
    jmp     .jump_to

; The return value is already on top of the operand stack and stays there,
; which is exactly what the caller's expression was waiting for.
.op_ret:
    dec     qword [vm_depth]
    mov     rcx, [vm_depth]
    shl     rcx, 4
    lea     rdx, [vm_calls]
    add     rdx, rcx
    mov     rsi, [rdx]
    mov     rdi, [rdx + CELL]
    call    frame_leave
    mov     rax, rsi
    jmp     .jump_to

.too_deep:
    lea     rdi, [src_buf]
    call    err_stackfull
    jmp     .fail

; A jump's operand is an absolute offset into the stream, so the target is
; where it says and not where it happens to be relative to. Both conditional
; forms consume the cell they tested, which is why an "if" needs no POP.
.op_jmp:
    call    fetch_u32
    jmp     .jump_to
.op_jz:
    call    fetch_u32
    sub     r12, CELL
    cmp     qword [r12], 0
    je      .jump_to
    jmp     .step
.op_jnz:
    call    fetch_u32
    sub     r12, CELL
    cmp     qword [r12], 0
    jne     .jump_to
    jmp     .step
.jump_to:
    lea     rcx, [code_buf]
    lea     rbx, [rcx + rax]
    jmp     .step

.op_halt:
    mov     rax, [r12 - CELL]
    jmp     .out

.overflow:
    call    err_deep
.fail:
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; -> eax = the next four bytes of operand
fetch_u32:
    mov     eax, dword [rbx]
    add     rbx, 4
    ret

; rcx = where in the source this operator came from, for the caret
fetch_pos:
    mov     ecx, dword [rbx]
    add     rbx, 4
    lea     rax, [src_buf]
    add     rcx, rax
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
vm_table:
    dq      vm_run.op_halt              ; OP_HALT
    dq      vm_run.op_push              ; OP_PUSH
    dq      vm_run.op_binary            ; OP_MUL
    dq      vm_run.op_div               ; OP_DIV
    dq      vm_run.op_mod               ; OP_MOD
    dq      vm_run.op_binary            ; OP_ADD
    dq      vm_run.op_binary            ; OP_SUB
    dq      vm_run.op_binary            ; OP_SHL
    dq      vm_run.op_binary            ; OP_SHR
    dq      vm_run.op_binary            ; OP_LT
    dq      vm_run.op_binary            ; OP_GT
    dq      vm_run.op_binary            ; OP_LE
    dq      vm_run.op_binary            ; OP_GE
    dq      vm_run.op_binary            ; OP_EQ
    dq      vm_run.op_binary            ; OP_NE
    dq      vm_run.op_binary            ; OP_AND
    dq      vm_run.op_binary            ; OP_XOR
    dq      vm_run.op_binary            ; OP_OR
    dq      vm_run.op_neg               ; OP_NEG
    dq      vm_run.op_not               ; OP_NOT
    dq      vm_run.op_bnot              ; OP_BNOT
    dq      vm_run.op_pop               ; OP_POP
    dq      vm_run.op_load              ; OP_LOAD
    dq      vm_run.op_store             ; OP_STORE
    dq      vm_run.op_str               ; OP_STR
    dq      vm_run.op_printf            ; OP_PRINTF
    dq      vm_run.op_jmp               ; OP_JMP
    dq      vm_run.op_jz                ; OP_JZ
    dq      vm_run.op_jnz               ; OP_JNZ
    dq      vm_run.op_loadl             ; OP_LOADL
    dq      vm_run.op_storel            ; OP_STOREL
    dq      vm_run.op_call              ; OP_CALL
    dq      vm_run.op_ret               ; OP_RET

; Indexed by opcode minus OP_BIN_FIRST, which is the same order the tokens
; came in -- so this table, op_table in op.asm and the row in mode.asm are all
; the same list read for three different purposes.
    align   8
op_routines:
    dq      op_mul                      ; OP_MUL
    dq      op_div                      ; OP_DIV
    dq      op_mod                      ; OP_MOD
    dq      op_add                      ; OP_ADD
    dq      op_sub                      ; OP_SUB
    dq      op_shl                      ; OP_SHL
    dq      op_shr                      ; OP_SHR
    dq      op_lt                       ; OP_LT
    dq      op_gt                       ; OP_GT
    dq      op_le                       ; OP_LE
    dq      op_ge                       ; OP_GE
    dq      op_eq                       ; OP_EQ
    dq      op_ne                       ; OP_NE
    dq      op_and                      ; OP_AND
    dq      op_xor                      ; OP_XOR
    dq      op_or                       ; OP_OR

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
vm_stack:
    resq    VM_STACK_CAP
vm_stack_end:
vm_depth:
    resq    1
vm_calls:
    resq    CALL_DEPTH * 2
