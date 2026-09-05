; SPDX-License-Identifier: MIT
;
; The read-eval-print loop. Entry point for the platform layer.
;
; Every command lives behind a colon. Until stage 2.1 the language had no
; identifiers, so "mode" could safely be a whole line that meant something;
; with variables it could not, because "mode" is also a perfectly good name for
; one. Rather than keep a list of words the user may not use, the colon takes
; the commands out of the language's namespace entirely -- there is no valid
; expression that begins with one, so the two can never be confused again.
;
; A submission is no longer a line. Blocks arrived at this stage and they do
; not fit on one, so the loop keeps reading while braces are open, with a
; continuation prompt of exactly the same width -- which is what lets the caret
; land in the right column on the fourth line of a block as easily as the
; first. Everything downstream is handed the whole submission and works in
; offsets into it.

%include "tsafoshi.inc"

    global  repl_main

    extern  read_line
    extern  line_is_blank
    extern  is_quit
    extern  skip_blanks
    extern  match_word
    extern  mode_command
    extern  exec_command
    extern  vars_command
    extern  line_buf
    extern  src_begin
    extern  src_append
    extern  src_open_braces
    extern  src_buf
    extern  names_init
    extern  scope_init
    extern  scope_unwind
    extern  lex_init
    extern  tok_kind
    extern  tok_pos
    extern  ast_reset
    extern  parse_line
    extern  parse_silent
    extern  parse_value
    extern  exec_run
    extern  print_result
    extern  err_code
    extern  err_reset
    extern  err_report
    extern  err_trailing
    extern  sys_write_stdout
    extern  sys_write_stderr
    extern  sys_exit

    section .text

repl_main:
    call    names_init
    call    scope_init
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
    call    line_is_blank
    test    rax, rax
    jnz     .loop

; A command is a whole submission and never continues onto another line, so it
; is recognised before the braces are counted.
    lea     rdi, [line_buf]
    call    skip_blanks
    cmp     byte [rdi], ':'
    je      .command

    call    err_reset
    call    src_begin
.gather:
    call    src_append
    test    rax, rax
    jz      .error                      ; the submission outgrew the buffer
    call    src_open_braces
    test    rax, rax
    jz      .ready

    lea     rsi, [msg_more]
    mov     rdx, msg_more.len
    call    sys_write_stdout
    call    read_line
    test    rax, rax
    jz      .ready                      ; end of input closes what it can
    jmp     .gather

.ready:
    call    ast_reset
    lea     rdi, [src_buf]
    call    lex_init
    call    parse_line
    cmp     qword [err_code], 0
    jne     .error

    cmp     qword [tok_kind], TK_EOF    ; the whole submission must be consumed
    jne     .trailing

    mov     rdi, rax                    ; the statements, then the value
    mov     rsi, [parse_value]
    call    exec_run
    cmp     qword [err_code], 0
    jne     .error

    cmp     qword [parse_silent], 0     ; a trailing ";" makes it a statement
    jne     .loop
    call    print_result
    jmp     .loop

; Each module owns its own commands and says whether the line was one of them,
; which is why adding a command means touching one file and this list.
.command:
    inc     rdi
    call    skip_blanks
    call    is_quit
    test    rax, rax
    jnz     .bye
    call    mode_command
    test    rax, rax
    jnz     .loop
    call    exec_command
    test    rax, rax
    jnz     .loop
    call    vars_command
    test    rax, rax
    jnz     .loop
    lea     rsi, [w_help]
    call    match_word
    test    rax, rax
    jnz     .help
    lea     rsi, [msg_nocommand]
    mov     rdx, msg_nocommand.len
    call    sys_write_stderr
    jmp     .loop

.help:
    lea     rsi, [msg_help]
    mov     rdx, msg_help.len
    call    sys_write_stdout
    jmp     .loop

.trailing:
    mov     rdi, [tok_pos]
    call    err_trailing

; A parse that failed inside a block never reached the closing brace, so the
; scopes it opened are still open. Nothing else in the session would notice
; until the next stray shadow, which is exactly the kind of bug worth not
; having.
.error:
    call    scope_unwind
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

w_help:
    db      "help", 0

msg_banner:
    db      "Tsafoshi 0.5 -- stage 2.2: if, while, for, blocks and scope", 10
    db      "commands start with a colon; ':help' lists them, ':quit' leaves", 10
    db      "everything else is C: int n = 5; while (n > 0) n = n - 1;", 10, 10
.len                equ $ - msg_banner
msg_prompt:
    db      "tsafoshi> "
.len                equ $ - msg_prompt

; The same width as the prompt above, and that is load-bearing: err_report
; counts a column from the start of a line and adds PROMPT_LEN, which is only
; right if every line was offered at the same indent.
msg_more:
    db      "     ...> "
.len                equ $ - msg_more
msg_help:
    db      "  :mode [name]      evaluation order: bodmas, ltr, rtl", 10
    db      "  :engine [name]    which engine runs a line: bytecode, tree", 10
    db      "  :dis              toggle the bytecode listing", 10
    db      "  :vars             every variable and its value", 10
    db      "  :quit             leave, as do :exit, :q and end of input", 10
.len                equ $ - msg_help
msg_nocommand:
    db      "error: no such command; try :help", 10
.len                equ $ - msg_nocommand
msg_bye:
    db      10, "north star out.", 10
.len                equ $ - msg_bye
