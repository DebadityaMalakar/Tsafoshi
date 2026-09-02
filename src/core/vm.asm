; SPDX-License-Identifier: MIT
;
; The dispatch loop. A stack machine over 64-bit cells: fetch a byte, index a
; table, run a handler, go round again.
;
; Every value still comes from op.asm, exactly as it did for the tree walker.
; The VM decides when an operation happens and where its operands live; it has
; no opinion about what any operator means.
;
; The operand stack is never checked for underflow. compile.asm only ever
; emits well-formed postfix, so an operator always has its operands; a check
; here would be testing the compiler from inside the hot loop.

%include "tsafoshi.inc"

    global  vm_run

    extern  code_buf
    extern  code_len
    extern  line_buf
    extern  op_add
    extern  op_sub
    extern  op_mul
    extern  op_div
    extern  op_mod
    extern  op_neg
    extern  var_get
    extern  var_set
    extern  str_addr
    extern  printf_run
    extern  err_code
    extern  err_deep

    section .text

; -> rax = the value HALT finds on the stack.
; rbx = instruction pointer, r12 = one past the top of the operand stack
vm_run:
    push    rbx
    push    r12
    lea     rbx, [code_buf]
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

.op_neg:
    mov     rdi, [r12 - CELL]
    call    op_neg
    mov     [r12 - CELL], rax
    jmp     .step

; The five binary handlers differ only in which routine they call, and the two
; that can fail also pick a source column out of the stream first.
.op_add:
    call    pop2
    call    op_add
    jmp     .push_back
.op_sub:
    call    pop2
    call    op_sub
    jmp     .push_back
.op_mul:
    call    pop2
    call    op_mul
    jmp     .push_back
.op_div:
    call    fetch_pos
    call    pop2
    call    op_div
    jmp     .push_checked
.op_mod:
    call    fetch_pos
    call    pop2
    call    op_mod
    jmp     .push_checked

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

; Both helpers work on the loop's registers directly, which is why they are
; here and not in a header. rdi = lhs, rsi = rhs, r12 lowered by two cells.
pop2:
    sub     r12, CELL * 2
    mov     rdi, [r12]
    mov     rsi, [r12 + CELL]
    ret

; -> eax = the next four bytes of operand
fetch_u32:
    mov     eax, dword [rbx]
    add     rbx, 4
    ret

; rcx = where in the line this operator came from, for the caret
fetch_pos:
    mov     ecx, dword [rbx]
    add     rbx, 4
    lea     rax, [line_buf]
    add     rcx, rax
    ret

; ---------------------------------------------------------------------------
    section .data

    align   8
vm_table:
    dq      vm_run.op_halt              ; OP_HALT
    dq      vm_run.op_push              ; OP_PUSH
    dq      vm_run.op_add               ; OP_ADD
    dq      vm_run.op_sub               ; OP_SUB
    dq      vm_run.op_mul               ; OP_MUL
    dq      vm_run.op_div               ; OP_DIV
    dq      vm_run.op_mod               ; OP_MOD
    dq      vm_run.op_neg               ; OP_NEG
    dq      vm_run.op_pop               ; OP_POP
    dq      vm_run.op_load              ; OP_LOAD
    dq      vm_run.op_store             ; OP_STORE
    dq      vm_run.op_str               ; OP_STR
    dq      vm_run.op_printf            ; OP_PRINTF

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
vm_stack:
    resq    VM_STACK_CAP
vm_stack_end:
