; SPDX-License-Identifier: MIT
;
; Diagnostics. Callers name an error and a position; the strings stay here.

%include "tsafoshi.inc"

    global  err_reset
    global  err_report
    global  err_expected
    global  err_unclosed
    global  err_divzero
    global  err_trailing
    global  err_code

    extern  line_buf
    extern  write_spaces
    extern  sys_write_stderr

    section .text

err_reset:
    mov     qword [err_code], 0
    ret

; rdi = position
err_expected:
    lea     rsi, [e_expected]
    mov     rdx, e_expected.len
    jmp     err_set
err_unclosed:
    lea     rsi, [e_unclosed]
    mov     rdx, e_unclosed.len
    jmp     err_set
err_divzero:
    lea     rsi, [e_divzero]
    mov     rdx, e_divzero.len
    jmp     err_set
err_trailing:
    lea     rsi, [e_trailing]
    mov     rdx, e_trailing.len
    ; fall through

; rsi = message, rdx = length, rdi = position. The first error on a line wins;
; everything after it is just unwinding noise.
err_set:
    cmp     qword [err_code], 0
    jne     .keep
    mov     qword [err_code], 1
    mov     [err_msg], rsi
    mov     [err_len], rdx
    mov     [err_pos], rdi
.keep:
    ret

; Caret under the offending column, then the message.
err_report:
    lea     rax, [line_buf]
    mov     rdi, [err_pos]
    sub     rdi, rax
    add     rdi, PROMPT_LEN
    call    write_spaces
    lea     rsi, [msg_caret]
    mov     rdx, msg_caret.len
    call    sys_write_stderr
    lea     rsi, [msg_error]
    mov     rdx, msg_error.len
    call    sys_write_stderr
    mov     rsi, [err_msg]
    mov     rdx, [err_len]
    call    sys_write_stderr
    lea     rsi, [msg_newline]
    mov     rdx, 1
    jmp     sys_write_stderr

; ---------------------------------------------------------------------------
    section .data

msg_caret:
    db      "^", 10
.len                equ $ - msg_caret
msg_error:
    db      "error: "
.len                equ $ - msg_error
msg_newline:
    db      10

e_expected:
    db      "expected a number or '('"
.len                equ $ - e_expected
e_unclosed:
    db      "expected ')'"
.len                equ $ - e_unclosed
e_divzero:
    db      "division by zero"
.len                equ $ - e_divzero
e_trailing:
    db      "unexpected trailing input"
.len                equ $ - e_trailing

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
err_code:
    resq    1
err_msg:
    resq    1
err_len:
    resq    1
err_pos:
    resq    1
