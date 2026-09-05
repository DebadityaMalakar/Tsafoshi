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

%include "tsafoshi.inc"

    global  var_get
    global  var_set
    global  vars_command

    extern  match_word
    extern  name_text
    extern  scope_global_count
    extern  scope_global_name
    extern  scope_global_slot
    extern  fmt_i64
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
