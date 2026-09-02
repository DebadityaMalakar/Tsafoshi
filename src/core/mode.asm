; SPDX-License-Identifier: MIT
;
; The evaluation-order convention: how tightly each operator binds, and which
; way a run of equal operators folds. op.asm says what an operator *means*;
; this file says what order the parser applies them in, and owns the "mode"
; command that switches between conventions.
;
; bodmas  brackets, then * / %, then + -, folded left     (the default)
; ltr     one flat level, folded left to right
; rtl     one flat level, folded right to left
;
; The parser reads mode_bump directly and adds it to an operator's precedence
; to get the floor for the right operand: +1 refuses an equally strong
; operator on the right and so folds left, +0 accepts it and folds right.

%include "tsafoshi.inc"

    global  mode_prec
    global  mode_bump
    global  mode_command

    extern  line_buf
    extern  match_word
    extern  sys_write_stdout
    extern  sys_write_stderr

MODE_NAME           equ 0               ; NUL-terminated, for matching
MODE_NLEN           equ CELL            ; the same text's length, for printing
MODE_ROW            equ CELL * 2
MODE_BUMP           equ CELL * 3
MODE_ENT            equ CELL * 4

W_MODE_LEN          equ 4               ; length of the word "mode"

    section .text

; rdi = token kind -> rax = binding strength under the active mode, 0 if it is
; not a binary operator. The parser asks this and nothing else about order.
mode_prec:
    xor     eax, eax
    sub     rdi, TK_OP_FIRST
    cmp     rdi, TK_OP_LAST - TK_OP_FIRST
    ja      .out
    mov     rcx, [mode_row]
    movzx   eax, byte [rcx + rdi]
.out:
    ret

; Handles "mode" and "mode <name>" the way is_quit handles "quit".
; -> rax = 1 if the line was a mode command and has been dealt with.
mode_command:
    push    rbx
    lea     rdi, [line_buf]
    call    skip_blanks
    lea     rsi, [w_mode]
    call    match_word
    test    rax, rax
    jz      .not_ours

    add     rdi, W_MODE_LEN
    call    skip_blanks
    cmp     byte [rdi], 0
    je      .show

    lea     rbx, [mode_table]
.try:
    lea     rcx, [mode_end]
    cmp     rbx, rcx
    jae     .unknown
    mov     rsi, [rbx + MODE_NAME]
    push    rbx
    call    match_word                  ; rdi survives, so we can keep trying
    pop     rbx
    test    rax, rax
    jnz     .found
    add     rbx, MODE_ENT
    jmp     .try

.found:
    mov     [mode_active], rbx
    mov     rax, [rbx + MODE_ROW]
    mov     [mode_row], rax
    mov     rax, [rbx + MODE_BUMP]
    mov     [mode_bump], rax
    call    print_current
    jmp     .handled

.show:
    call    print_current
    lea     rsi, [msg_list]
    mov     rdx, msg_list.len
    call    sys_write_stdout
    jmp     .handled

.unknown:
    lea     rsi, [msg_unknown]
    mov     rdx, msg_unknown.len
    call    sys_write_stderr

.handled:
    mov     eax, 1
    pop     rbx
    ret
.not_ours:
    xor     eax, eax
    pop     rbx
    ret

print_current:
    lea     rsi, [msg_mode]
    mov     rdx, msg_mode.len
    call    sys_write_stdout
    mov     rax, [mode_active]
    mov     rsi, [rax + MODE_NAME]
    mov     rdx, [rax + MODE_NLEN]
    call    sys_write_stdout
    lea     rsi, [msg_newline]
    mov     rdx, 1
    jmp     sys_write_stdout

; rdi = text -> rdi past any spaces and tabs
skip_blanks:
    movzx   eax, byte [rdi]
    cmp     al, ' '
    je      .step
    cmp     al, 9
    jne     .done
.step:
    inc     rdi
    jmp     skip_blanks
.done:
    ret

; ---------------------------------------------------------------------------
    section .data

w_mode:
    db      "mode", 0

n_bodmas:
    db      "bodmas", 0
.len                equ $ - n_bodmas - 1
n_ltr:
    db      "ltr", 0
.len                equ $ - n_ltr - 1
n_rtl:
    db      "rtl", 0
.len                equ $ - n_rtl - 1

; One row per mode, indexed by token kind minus TK_OP_FIRST.
r_bodmas:
    db      PREC_ADDITIVE               ; TK_PLUS
    db      PREC_ADDITIVE               ; TK_MINUS
    db      PREC_MULTIPLICATIVE         ; TK_STAR
    db      PREC_MULTIPLICATIVE         ; TK_SLASH
    db      PREC_MULTIPLICATIVE         ; TK_PERCENT
r_flat:
    times   5 db PREC_LOWEST

    align   8
mode_table:
    dq      n_bodmas, n_bodmas.len, r_bodmas, 1
    dq      n_ltr, n_ltr.len, r_flat, 1
    dq      n_rtl, n_rtl.len, r_flat, 0
mode_end:

    align   8
mode_active:
    dq      mode_table                  ; bodmas
mode_row:
    dq      r_bodmas
mode_bump:
    dq      1

msg_mode:
    db      "mode: "
.len                equ $ - msg_mode
msg_list:
    db      "  bodmas  brackets, then * / %, then + -", 10
    db      "  ltr     one flat level, folded left to right", 10
    db      "  rtl     one flat level, folded right to left", 10
.len                equ $ - msg_list
msg_newline:
    db      10
msg_unknown:
    db      "error: unknown mode; try bodmas, ltr or rtl", 10
.len                equ $ - msg_unknown
