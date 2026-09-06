; SPDX-License-Identifier: MIT
;
; The command line.
;
; Until now there was one argument and it was a path. That was enough to run a
; file and nothing else, and it left the interpreter unable to answer the two
; questions every command-line tool is asked first -- what version is this, and
; how do I use it -- except by starting a session at someone who wanted neither.
;
; So: options, a source, and the program's own arguments after it. The shape is
; Python's, because Python's is the one people already have in their fingers:
; options first, then a file or -e or -, then everything else belongs to the
; program and is not read as an option however much it looks like one.
;
; Two rules hold the parsing up. The first non-option argument ends the options
; -- it is the source, and everything after it is the program's. And "--" ends
; them explicitly, for the file that is genuinely called "-e". Both mean the
; same thing: from here on, this is not ours to read.
;
; What this file does *not* do is decide anything. It records what was asked
; for; repl.asm does it. That split is what lets the same four source kinds be
; driven by a flag, by a pipe, or by nothing at all.

%include "tsafoshi.inc"

    global  cli_parse
    global  cli_argc
    global  cli_arg
    global  cli_kind
    global  cli_text
    global  cli_interactive
    global  cli_quiet
    global  cli_status

    extern  sys_argv
    extern  sys_write_stdout
    extern  sys_write_stderr
    extern  exec_select_engine
    extern  mode_select

    section .text

; -> rax = 1 to carry on, or 0 to stop with cli_status.
;
; rbx = which argument, r12 = that argument, r13 = whether "--" has been seen
cli_parse:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     qword [cli_kind], CLI_NONE
    mov     qword [cli_text], 0
    mov     qword [cli_interactive], 0
    mov     qword [cli_quiet], 0
    mov     qword [cli_status], 0
    mov     qword [cli_argc], 0
    mov     ebx, 1
    xor     r13, r13

.next:
    mov     rdi, rbx
    call    sys_argv
    test    rax, rax
    jz      .done
    mov     r12, rax
    test    r13, r13
    jnz     .source
    cmp     byte [r12], '-'
    jne     .source
    cmp     byte [r12 + 1], 0           ; a bare "-" is a source, not a flag
    je      .stdin

    mov     rdi, r12
    lea     rsi, [f_endopts]
    call    streq
    test    rax, rax
    jnz     .endopts
    mov     rdi, r12
    lea     rsi, [f_help_s]
    call    streq
    test    rax, rax
    jnz     .help
    mov     rdi, r12
    lea     rsi, [f_help_l]
    call    streq
    test    rax, rax
    jnz     .help
    mov     rdi, r12
    lea     rsi, [f_version_s]
    call    streq
    test    rax, rax
    jnz     .version
    mov     rdi, r12
    lea     rsi, [f_version_l]
    call    streq
    test    rax, rax
    jnz     .version
    mov     rdi, r12
    lea     rsi, [f_quiet_s]
    call    streq
    test    rax, rax
    jnz     .quiet
    mov     rdi, r12
    lea     rsi, [f_quiet_l]
    call    streq
    test    rax, rax
    jnz     .quiet
    mov     rdi, r12
    lea     rsi, [f_inter_s]
    call    streq
    test    rax, rax
    jnz     .inter
    mov     rdi, r12
    lea     rsi, [f_inter_l]
    call    streq
    test    rax, rax
    jnz     .inter
    mov     rdi, r12
    lea     rsi, [f_eval_s]
    call    streq
    test    rax, rax
    jnz     .eval
    mov     rdi, r12
    lea     rsi, [f_eval_l]
    call    streq
    test    rax, rax
    jnz     .eval
    mov     rdi, r12
    lea     rsi, [f_engine]
    call    streq
    test    rax, rax
    jnz     .engine
    mov     rdi, r12
    lea     rsi, [f_mode]
    call    streq
    test    rax, rax
    jnz     .mode
    jmp     .unknown

.endopts:
    mov     r13d, 1
    inc     rbx
    jmp     .next
.quiet:
    mov     qword [cli_quiet], 1
    inc     rbx
    jmp     .next
.inter:
    mov     qword [cli_interactive], 1
    inc     rbx
    jmp     .next

; -e takes the code as its own argument and then stops reading options, because
; everything left is the program's -- exactly as it would be after a filename.
.eval:
    call    value_of
    test    rax, rax
    jz      .needs_value
    mov     qword [cli_kind], CLI_EVAL
    mov     [cli_text], rax
    lea     rax, [n_eval]
    mov     rdi, rax
    call    record_arg
    jmp     .rest

.engine:
    call    value_of
    test    rax, rax
    jz      .needs_value
    mov     r12, rax                    ; the value is what a complaint is about
    mov     rdi, rax
    call    exec_select_engine
    test    rax, rax
    jz      .bad_value
    inc     rbx
    jmp     .next
.mode:
    call    value_of
    test    rax, rax
    jz      .needs_value
    mov     r12, rax
    mov     rdi, rax
    call    mode_select
    test    rax, rax
    jz      .bad_value
    inc     rbx
    jmp     .next

.stdin:
    mov     qword [cli_kind], CLI_STDIN
    jmp     .take_source
.source:
    mov     qword [cli_kind], CLI_FILE
    mov     [cli_text], r12
.take_source:
    mov     rdi, r12
    call    record_arg

; From here every argument is the program's, whatever it looks like.
.rest:
    inc     rbx
    mov     rdi, rbx
    call    sys_argv
    test    rax, rax
    jz      .done
    mov     rdi, rax
    call    record_arg
    jmp     .rest

.done:
    mov     eax, 1
    jmp     .out

.help:
    lea     rsi, [m_usage]
    mov     rdx, m_usage.len
    call    sys_write_stdout
    jmp     .leave_ok
.version:
    lea     rsi, [m_version]
    mov     rdx, m_version.len
    call    sys_write_stdout
.leave_ok:
    xor     eax, eax
    jmp     .out

.unknown:
    lea     rsi, [m_unknown]
    mov     rdx, m_unknown.len
    call    complain
    jmp     .usage_error
.needs_value:
    lea     rsi, [m_needs]
    mov     rdx, m_needs.len
    call    complain
    jmp     .usage_error
.bad_value:
    lea     rsi, [m_badvalue]
    mov     rdx, m_badvalue.len
    call    complain

; Two, not one: a usage error is the command line being wrong, which is a
; different thing from the program being wrong, and a shell script wants to be
; able to tell them apart.
.usage_error:
    mov     qword [cli_status], 2
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; rsi = message, rdx = its length, r12 = the argument at fault. Prints the
; complaint, then the argument, then where to look.
complain:
    call    sys_write_stderr
    mov     rdi, r12
    call    length_of
    mov     rdx, rax
    mov     rsi, r12
    call    sys_write_stderr
    lea     rsi, [m_tryhelp]
    mov     rdx, m_tryhelp.len
    jmp     sys_write_stderr

; -> rax = the argument after the flag, or zero if the flag was the last one.
; Advances rbx onto it, so the caller's "inc rbx" steps past both.
value_of:
    inc     rbx
    mov     rdi, rbx
    jmp     sys_argv

; rdi = one of the program's arguments. Silently drops the excess: a program
; given more than thirty arguments at this stage is not the case worth failing
; the whole run over.
record_arg:
    mov     rax, [cli_argc]
    cmp     rax, ARGV_PROG
    jae     .full
    lea     rcx, [argv_prog]
    mov     [rcx + rax * CELL], rdi
    inc     qword [cli_argc]
.full:
    ret

; rdi = index -> rax = that argument, or zero past the end
cli_arg:
    cmp     rdi, [cli_argc]
    jae     .none
    lea     rax, [argv_prog]
    mov     rax, [rax + rdi * CELL]
    ret
.none:
    xor     eax, eax
    ret

; rdi, rsi = NUL-terminated -> rax = 1 if they are the same text
streq:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     al, cl
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     streq
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; rdi = NUL-terminated -> rax = its length
length_of:
    xor     eax, eax
.step:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .step
.done:
    ret

; ---------------------------------------------------------------------------
    section .data

f_endopts:
    db      "--", 0
f_help_s:
    db      "-h", 0
f_help_l:
    db      "--help", 0
f_version_s:
    db      "-v", 0
f_version_l:
    db      "--version", 0
f_quiet_s:
    db      "-q", 0
f_quiet_l:
    db      "--quiet", 0
f_inter_s:
    db      "-i", 0
f_inter_l:
    db      "--interactive", 0
f_eval_s:
    db      "-e", 0
f_eval_l:
    db      "--eval", 0
f_engine:
    db      "--engine", 0
f_mode:
    db      "--mode", 0

; What argv(0) is when there is no file to name. Python calls it "-c"; the
; flag here is -e, and the principle is the same: the program should be able
; to say where it came from.
n_eval:
    db      "-e", 0

m_version:
    db      "tsafoshi 0.8", 10
.len                equ $ - m_version

m_usage:
    db      "usage: tsafoshi [options] [file] [arguments...]", 10
    db      "       tsafoshi [options] -e code [arguments...]", 10
    db      "       tsafoshi [options] -    [arguments...]", 10, 10
    db      "  -e, --eval code    run code as one submission, then leave", 10
    db      "  -i, --interactive  stay at the prompt afterwards", 10
    db      "  -q, --quiet        no banner", 10
    db      "      --engine name  bytecode or tree", 10
    db      "      --mode name    bodmas, ltr or rtl", 10
    db      "  -v, --version      print the version and leave", 10
    db      "  -h, --help         print this and leave", 10
    db      "  --                 end of options; the rest is the program's", 10, 10
    db      "With no file, a terminal gets a session and a pipe gets a", 10
    db      "program. The exit status is what main returned, 1 if something", 10
    db      "went wrong, and 2 if this command line did.", 10
.len                equ $ - m_usage

m_unknown:
    db      "tsafoshi: no such option: "
.len                equ $ - m_unknown
m_needs:
    db      "tsafoshi: this option needs a value: "
.len                equ $ - m_needs
m_badvalue:
    db      "tsafoshi: not a name that option knows: "
.len                equ $ - m_badvalue
m_tryhelp:
    db      10, "try 'tsafoshi --help'", 10
.len                equ $ - m_tryhelp

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
cli_kind:
    resq    1
cli_text:
    resq    1
cli_interactive:
    resq    1
cli_quiet:
    resq    1
cli_status:
    resq    1
cli_argc:
    resq    1
argv_prog:
    resq    ARGV_PROG
