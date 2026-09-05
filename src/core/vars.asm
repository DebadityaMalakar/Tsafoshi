; SPDX-License-Identifier: MIT
;
; Variable storage: one cell per storage slot, and the ":vars" listing.
;
; Slots come from scope.asm and this file never looks at the name behind one,
; which is the seam that matters: the parser resolves an identifier once, and
; every engine after it only ever indexes. Everything starts at zero because
; .bss does, so a slot handed back out by a closed block reads as zero rather
; than as whatever the last block left in it.
;
; The listing is the one place a name is wanted again, and it asks scope.asm
; rather than keeping a second copy of the answer.
;
; Locals live somewhere else entirely: on the managed C stack below, addressed
; as an offset from the frame pointer of the call that is running. That is what
; makes recursion work at all -- the same offset is a different cell on every
; call -- and it is a separate array from the globals rather than a region of
; one, because the two have nothing to say to each other.
;
; Both engines share this stack. The VM keeps a frame pointer in a register and
; the tree walker keeps one on the machine stack, but the cells they index are
; the same cells, so a bug in either shows up as the two disagreeing rather
; than as one of them being quietly wrong.

%include "tsafoshi.inc"

    global  var_get
    global  var_set
    global  var_local_get
    global  var_local_set
    global  frame_enter
    global  frame_leave
    global  frame_args
    global  frame_reset
    global  frame_ptr
    global  vars_command

    extern  match_word
    extern  name_text
    extern  scope_global_count
    extern  scope_global_name
    extern  scope_global_slot
    extern  fmt_i64
    extern  err_stackfull
    extern  sys_write_stdout

    section .text

; rdi = slot -> rax
var_get:
    lea     rax, [var_val]
    mov     rax, [rax + rdi * CELL]
    ret

; rdi = slot, rsi = value
var_set:
    lea     rax, [var_val]
    mov     [rax + rdi * CELL], rsi
    ret

; rdi = frame offset -> rax
var_local_get:
    add     rdi, [frame_ptr]
    lea     rax, [frames]
    mov     rax, [rax + rdi * CELL]
    ret

; rdi = frame offset, rsi = value
var_local_set:
    add     rdi, [frame_ptr]
    lea     rax, [frames]
    mov     [rax + rdi * CELL], rsi
    ret

; rdi = how many cells the frame needs, rsi = position for errors
; -> rax = the caller's frame pointer, to be handed back to frame_leave, or -1
; if the stack is full.
;
; The frame is zeroed. C99 calls an uninitialised local indeterminate, and it
; would be within its rights to leave whatever the last call left here -- but
; every declaration writes its slot anyway, so the only thing that changes is
; whether a bug is reproducible, and zero makes it so.
frame_enter:
    push    rbx
    mov     rax, [frame_top]
    mov     rcx, rax
    add     rcx, rdi
    cmp     rcx, FRAME_CAP
    ja      .full
    lea     rbx, [frames]
.zero:
    test    rdi, rdi
    jz      .zeroed
    dec     rdi
    mov     qword [rbx + rax * CELL + 0], 0
    inc     rax
    jmp     .zero
.zeroed:
    mov     rax, [frame_ptr]
    push    rax
    mov     rax, [frame_top]
    mov     [frame_ptr], rax
    mov     [frame_top], rcx
    pop     rax
    pop     rbx
    ret
.full:
    mov     rdi, rsi
    call    err_stackfull
    mov     rax, -1
    pop     rbx
    ret

; rdi = where the arguments are sitting, rsi = how many. Copies them into the
; first slots of the frame just entered, which is where the parameters were
; declared -- so "the calling convention" is one memcpy and an agreement about
; declaration order.
frame_args:
    lea     rax, [frames]
    mov     rcx, [frame_ptr]
    lea     rax, [rax + rcx * CELL]
    xor     ecx, ecx
.next:
    cmp     rcx, rsi
    jae     .done
    mov     rdx, [rdi + rcx * CELL]
    mov     [rax + rcx * CELL], rdx
    inc     rcx
    jmp     .next
.done:
    ret

; Back to no call in progress. A line that failed half way down a call chain
; leaves frames behind, and the next line should not inherit them.
frame_reset:
    mov     qword [frame_ptr], 0
    mov     qword [frame_top], 0
    ret

; rdi = the frame pointer frame_enter handed back
frame_leave:
    mov     rax, [frame_ptr]
    mov     [frame_top], rax
    mov     [frame_ptr], rdi
    ret

; rdi = the command text -> rax = 1 if it was ours
vars_command:
    lea     rsi, [w_vars]
    call    match_word
    test    rax, rax
    jz      .not_ours

    push    rbx
    xor     ebx, ebx
    call    scope_global_count
    test    rax, rax
    jz      .empty
.next:
    call    scope_global_count
    cmp     rbx, rax
    jae     .done
    lea     rsi, [t_indent]
    mov     rdx, t_indent.len
    call    sys_write_stdout
    mov     rdi, rbx
    call    scope_global_name
    mov     rdi, rax
    call    name_text
    mov     rsi, rax
    call    sys_write_stdout
    lea     rsi, [t_equals]
    mov     rdx, t_equals.len
    call    sys_write_stdout
    mov     rdi, rbx
    call    scope_global_slot
    mov     rdi, rax
    call    var_get
    call    fmt_i64
    call    sys_write_stdout
    lea     rsi, [t_newline]
    mov     rdx, 1
    call    sys_write_stdout
    inc     rbx
    jmp     .next

.empty:
    lea     rsi, [m_none]
    mov     rdx, m_none.len
    call    sys_write_stdout
.done:
    pop     rbx
    mov     eax, 1
.not_ours:
    ret

; ---------------------------------------------------------------------------
    section .data

w_vars:
    db      "vars", 0

t_indent:
    db      "  "
.len                equ $ - t_indent
t_equals:
    db      " = "
.len                equ $ - t_equals
t_newline:
    db      10
m_none:
    db      "  no variables yet", 10
.len                equ $ - m_none

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
var_val:
    resq    VAR_CAP
frame_ptr:
    resq    1
frame_top:
    resq    1
frames:
    resq    FRAME_CAP
