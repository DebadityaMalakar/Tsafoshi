; SPDX-License-Identifier: MIT
;
; Variable storage: one cell per name slot, and the ":vars" listing.
;
; Slots come from names.asm and this file never looks at the text behind one,
; which is the seam that matters: the compiler resolves a name once, at compile
; time, and the VM only ever indexes. Everything starts at zero because .bss
; does, so reading a variable before assigning it yields 0 rather than garbage.

%include "tsafoshi.inc"

    global  var_get
    global  var_set
    global  vars_command

    extern  match_word
    extern  name_text
    extern  name_count
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
    mov     ebx, BI_COUNT               ; the builtins are not variables
    cmp     rbx, [name_count]
    jae     .empty
.next:
    cmp     rbx, [name_count]
    jae     .done
    lea     rsi, [t_indent]
    mov     rdx, t_indent.len
    call    sys_write_stdout
    mov     rdi, rbx
    call    name_text
    mov     rsi, rax
    call    sys_write_stdout
    lea     rsi, [t_equals]
    mov     rdx, t_equals.len
    call    sys_write_stdout
    mov     rdi, rbx
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
    resq    NAME_CAP
