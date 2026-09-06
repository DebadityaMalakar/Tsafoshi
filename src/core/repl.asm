; SPDX-License-Identifier: MIT
;
; The read-eval-print loop, and the decision about whether to have one at all.
;
; Every command lives behind a colon. Until stage 2.1 the language had no
; identifiers, so "mode" could safely be a whole line that meant something;
; with variables it could not, because "mode" is also a perfectly good name for
; one. Rather than keep a list of words the user may not use, the colon takes
; the commands out of the language's namespace entirely -- there is no valid
; expression that begins with one, so the two can never be confused again.
;
; A submission is no longer a line. Blocks arrived at stage 2.2 and they do not
; fit on one, so the loop keeps reading while braces are open, with a
; continuation prompt of exactly the same width -- which is what lets the caret
; land in the right column on the fourth line of a block as easily as the
; first. Everything downstream is handed the whole submission and works in
; offsets into it.
;
; What is new at 3.1 is that the loop is no longer the default and no longer
; the only thing here. cli.asm says what was asked for; this file does it, and
; the session is one of four answers rather than the answer. The rule for the
; case where nothing was asked for is the one every other language settled on:
; a terminal gets a conversation, a pipe gets a program. Prompting a pipe is
; writing to somebody who is not there, and it is worth one syscall to find
; out.

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
    extern  src_text
    extern  names_init
    extern  scope_init
    extern  func_init
    extern  ast_init
    extern  code_init
    extern  scope_unwind
    extern  lex_init
    extern  tok_kind
    extern  tok_pos
    extern  ast_reset
    extern  parse_line
    extern  parse_silent
    extern  parse_value
    extern  exec_run
    extern  exec_define
    extern  print_result
    extern  err_code
    extern  err_reset
    extern  err_report
    extern  err_trailing
    extern  err_at_prompt
    extern  err_reading_file
    extern  cli_parse
    extern  cli_kind
    extern  cli_text
    extern  cli_interactive
    extern  cli_quiet
    extern  cli_status
    extern  script_run
    extern  script_eval
    extern  script_stdin
    extern  sys_isatty
    extern  sys_write_stdout
    extern  sys_write_stderr
    extern  sys_exit

    section .text

; Every session, interactive or not, starts the same way. What differs is only
; where the source comes from after that.
repl_main:
    call    names_init
    call    scope_init
    call    func_init
    call    ast_init
    call    code_init

    call    cli_parse
    test    rax, rax
    jz      .leave_cli

    mov     rax, [cli_kind]
    cmp     rax, CLI_FILE
    je      .file
    cmp     rax, CLI_EVAL
    je      .eval
    cmp     rax, CLI_STDIN
    je      .stdin

; Nothing was named. "-i" is an answer on its own -- it asks for a session in
; so many words, and asking is enough. Otherwise the terminal decides.
    cmp     qword [cli_interactive], 0
    jne     .interactive
    xor     edi, edi
    call    sys_isatty
    test    rax, rax
    jz      .stdin
.interactive:
    call    session
    xor     eax, eax
    jmp     .leave_run

.file:
    mov     rdi, [cli_text]
    call    script_run
    jmp     .ran
.eval:
    mov     rdi, [cli_text]
    call    script_eval
    jmp     .ran
.stdin:
    call    script_stdin

; "-i" is the one case where a program and a session happen in the same run,
; and it works only because everything the program defined is still there: the
; names, the globals, the functions and their code all outlive the submission
; that made them. Exiting the session afterwards is not a failure, so the
; program's status is not what the process leaves with.
.ran:
    mov     [run_status], rax
    cmp     qword [cli_interactive], 0
    je      .leave_program
    call    session
    xor     eax, eax
    jmp     .leave_run
.leave_program:
    mov     rax, [run_status]
    jmp     .leave_run

.leave_cli:
    mov     rax, [cli_status]
.leave_run:
    mov     edi, eax
    call    sys_exit
    hlt

; The interactive loop. Returns when the input ends or a command says to stop,
; rather than exiting, because "-i" needs there to be something after it.
;
; Whether this is a terminal is asked once and remembered: it decides the
; banner, the prompts, and how an error draws its caret -- all three being the
; same question about whether anybody is watching the screen.
session:
    push    rbx
    xor     edi, edi
    call    sys_isatty
    mov     [at_terminal], rax
    test    rax, rax
    jz      .not_watched
    call    err_at_prompt
    cmp     qword [cli_quiet], 0
    jne     .loop
    lea     rsi, [msg_banner]
    mov     rdx, msg_banner.len
    call    sys_write_stdout
    jmp     .loop

; A session down a pipe is still a session -- "-i" asked for one -- but nothing
; echoed the line, so an error has to print it the way a file's errors are
; printed rather than pointing at an echo that never happened.
.not_watched:
    call    err_reading_file

.loop:
    lea     rsi, [msg_prompt]
    mov     rdx, msg_prompt.len
    call    prompt

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
    call    prompt
    call    read_line
    test    rax, rax
    jz      .ready                      ; end of input closes what it can
    jmp     .gather

.ready:
    call    ast_reset
    call    src_text
    mov     rdi, rax
    call    lex_init
    call    parse_line
    cmp     qword [err_code], 0
    jne     .error

    cmp     qword [tok_kind], TK_EOF    ; the whole submission must be consumed
    jne     .trailing

    push    rax
    call    exec_define                 ; keep whatever functions were defined
    pop     rax
    cmp     qword [err_code], 0
    jne     .error

    mov     rdi, rax                    ; the statements, then the value
    mov     rsi, [parse_value]
    call    exec_run
    cmp     qword [err_code], 0
    jne     .error

    cmp     qword [parse_silent], 0     ; a trailing ";" makes it a statement
    jne     .loop
    mov     rdi, [parse_value]
    mov     rdi, [rdi + NODE_TYPE]
    cmp     rdi, TY_VOID                ; a void expression has no answer, and
    je      .loop                       ; printing "= 0" would invent one
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
    call    prompt
    pop     rbx
    ret

; rsi = text, rdx = length. Written only if somebody is looking at it. A
; prompt down a pipe is not a prompt, it is the first thing the reader on the
; other end has to learn to ignore.
prompt:
    cmp     qword [at_terminal], 0
    je      .silent
    jmp     sys_write_stdout
.silent:
    ret

; ---------------------------------------------------------------------------
    section .data

w_help:
    db      "help", 0

msg_banner:
    db      "Tsafoshi 0.8 -- stage 3.2: types", 10
    db      "commands start with a colon; ':help' lists them, ':quit' leaves", 10
    db      "everything else is C: int sq(int n) { return n * n; } sq(7)", 10, 10
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

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
at_terminal:
    resq    1
run_status:
    resq    1
