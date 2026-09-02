; SPDX-License-Identifier: MIT
;
; The read-eval-print loop. Entry point for the platform layer.

%include "tsafoshi.inc"

    global  repl_main

    extern  read_line
    extern  line_is_blank
    extern  is_quit
    extern  line_buf
    extern  lex_init
    extern  tok_kind
    extern  tok_pos
    extern  parse_expression
    extern  print_result
    extern  err_code
    extern  err_reset
    extern  err_report
    extern  err_trailing
    extern  sys_write_stdout
    extern  sys_exit

    section .text

repl_main:
    lea     rsi, [msg_banner]
    mov     rdx, msg_banner.len
    call    sys_write_stdout

.loop:
    lea     rsi, [msg_prompt]
    mov     rdx, msg_prompt.len
    call    sys_write_stdout

    call    read_line
    test    rax, rax
    jz      .bye
    call    is_quit
    test    rax, rax
    jnz     .bye
    call    line_is_blank
    test    rax, rax
    jnz     .loop

    call    err_reset
    lea     rdi, [line_buf]
    call    lex_init
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .error

    cmp     qword [tok_kind], TK_EOF    ; the whole line must be consumed
    jne     .trailing

    call    print_result
    jmp     .loop

.trailing:
    mov     rdi, [tok_pos]
    call    err_trailing
.error:
    call    err_report
    jmp     .loop

.bye:
    lea     rsi, [msg_bye]
    mov     rdx, msg_bye.len
    call    sys_write_stdout
    xor     edi, edi
    call    sys_exit
    hlt

; ---------------------------------------------------------------------------
    section .data

msg_banner:
    db      "Tsafoshi 0.1 -- stage 0: left-to-right calculator", 10
    db      "no operator precedence yet: 2 + 3 * 4 is 20", 10
    db      "type an expression, or 'quit' to leave", 10, 10
.len                equ $ - msg_banner
msg_prompt:
    db      "tsafoshi> "
.len                equ $ - msg_prompt
msg_bye:
    db      10, "north star out.", 10
.len                equ $ - msg_bye
