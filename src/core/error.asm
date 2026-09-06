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
    global  err_toobig
    global  err_unterminated
    global  err_unterminatedcomment
    global  err_longname
    global  err_toomanynames
    global  err_strspace
    global  err_badescape
    global  err_badconv
    global  err_missingarg
    global  err_notlvalue
    global  err_builtin
    global  err_unknownfn
    global  err_toomanyargs
    global  err_needargs
    global  err_expectedsemi
    global  err_expectedparen
    global  err_expectedname
    global  err_expectedwhile
    global  err_undeclared
    global  err_redeclared
    global  err_declbody
    global  err_notinloop
    global  err_toomanyvars
    global  err_toomanyscopes
    global  err_toodeep
    global  err_srcfull
    global  err_notinfunction
    global  err_nestedfunction
    global  err_expectedbrace
    global  err_expectedtype
    global  err_argcount
    global  err_redefined
    global  err_toomanyfuncs
    global  err_stackfull
    global  err_nomain
    global  err_codefull
    global  err_deep
    global  err_code
    global  err_quiet_caret
    global  err_reading_file
    global  err_at_prompt

    extern  src_buf
    extern  src_line_start
    extern  src_line_end
    extern  src_line_number
    extern  fmt_i64
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
    jmp     err_set
err_toobig:
    lea     rsi, [e_toobig]
    mov     rdx, e_toobig.len
    jmp     err_set
err_unterminated:
    lea     rsi, [e_unterminated]
    mov     rdx, e_unterminated.len
    jmp     err_set
err_unterminatedcomment:
    lea     rsi, [e_unterminatedcomment]
    mov     rdx, e_unterminatedcomment.len
    jmp     err_set
err_longname:
    lea     rsi, [e_longname]
    mov     rdx, e_longname.len
    jmp     err_set
err_toomanynames:
    lea     rsi, [e_toomanynames]
    mov     rdx, e_toomanynames.len
    jmp     err_set
err_strspace:
    lea     rsi, [e_strspace]
    mov     rdx, e_strspace.len
    jmp     err_set
err_badescape:
    lea     rsi, [e_badescape]
    mov     rdx, e_badescape.len
    jmp     err_set
err_badconv:
    lea     rsi, [e_badconv]
    mov     rdx, e_badconv.len
    jmp     err_set
err_missingarg:
    lea     rsi, [e_missingarg]
    mov     rdx, e_missingarg.len
    jmp     err_set
err_notlvalue:
    lea     rsi, [e_notlvalue]
    mov     rdx, e_notlvalue.len
    jmp     err_set
err_builtin:
    lea     rsi, [e_builtin]
    mov     rdx, e_builtin.len
    jmp     err_set
err_unknownfn:
    lea     rsi, [e_unknownfn]
    mov     rdx, e_unknownfn.len
    jmp     err_set
err_toomanyargs:
    lea     rsi, [e_toomanyargs]
    mov     rdx, e_toomanyargs.len
    jmp     err_set
err_needargs:
    lea     rsi, [e_needargs]
    mov     rdx, e_needargs.len
    jmp     err_set
err_expectedsemi:
    lea     rsi, [e_expectedsemi]
    mov     rdx, e_expectedsemi.len
    jmp     err_set
err_expectedparen:
    lea     rsi, [e_expectedparen]
    mov     rdx, e_expectedparen.len
    jmp     err_set
err_expectedname:
    lea     rsi, [e_expectedname]
    mov     rdx, e_expectedname.len
    jmp     err_set
err_expectedwhile:
    lea     rsi, [e_expectedwhile]
    mov     rdx, e_expectedwhile.len
    jmp     err_set
err_undeclared:
    lea     rsi, [e_undeclared]
    mov     rdx, e_undeclared.len
    jmp     err_set
err_redeclared:
    lea     rsi, [e_redeclared]
    mov     rdx, e_redeclared.len
    jmp     err_set
err_declbody:
    lea     rsi, [e_declbody]
    mov     rdx, e_declbody.len
    jmp     err_set
err_notinloop:
    lea     rsi, [e_notinloop]
    mov     rdx, e_notinloop.len
    jmp     err_set
err_toomanyvars:
    lea     rsi, [e_toomanyvars]
    mov     rdx, e_toomanyvars.len
    jmp     err_set
err_toomanyscopes:
    lea     rsi, [e_toomanyscopes]
    mov     rdx, e_toomanyscopes.len
    jmp     err_set
err_toodeep:
    lea     rsi, [e_toodeep]
    mov     rdx, e_toodeep.len
    jmp     err_set
err_srcfull:
    lea     rsi, [e_srcfull]
    mov     rdx, e_srcfull.len
    jmp     err_set
err_notinfunction:
    lea     rsi, [e_notinfunction]
    mov     rdx, e_notinfunction.len
    jmp     err_set
err_nestedfunction:
    lea     rsi, [e_nestedfunction]
    mov     rdx, e_nestedfunction.len
    jmp     err_set
err_expectedbrace:
    lea     rsi, [e_expectedbrace]
    mov     rdx, e_expectedbrace.len
    jmp     err_set
err_expectedtype:
    lea     rsi, [e_expectedtype]
    mov     rdx, e_expectedtype.len
    jmp     err_set
err_argcount:
    lea     rsi, [e_argcount]
    mov     rdx, e_argcount.len
    jmp     err_set
err_redefined:
    lea     rsi, [e_redefined]
    mov     rdx, e_redefined.len
    jmp     err_set
err_toomanyfuncs:
    lea     rsi, [e_toomanyfuncs]
    mov     rdx, e_toomanyfuncs.len
    jmp     err_set
err_stackfull:
    lea     rsi, [e_stackfull]
    mov     rdx, e_stackfull.len
    jmp     err_set
err_nomain:
    lea     rsi, [e_nomain]
    mov     rdx, e_nomain.len
    jmp     err_set

; These two are raised from inside the compiler and the VM, which are past the
; point of knowing which column is to blame, so they point at the source
; itself.
err_codefull:
    lea     rsi, [e_codefull]
    mov     rdx, e_codefull.len
    lea     rdi, [src_buf]
    jmp     err_set
err_deep:
    lea     rsi, [e_deep]
    mov     rdx, e_deep.len
    lea     rdi, [src_buf]
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
;
; At a prompt the line is already on the screen, put there by the terminal when
; it was typed, so the caret only has to be indented past the prompt to line up
; underneath it -- which is why both prompts are the same width. Reading a file
; there is no such echo and no prompt, so the line has to be printed first, and
; a line number with it because there are more than a few of them.
;
; Two presentations of one fact, and the fact is the same either way: a column
; measured from the start of the line the position is on.
err_report:
    cmp     qword [err_code], 0
    je      .none
    cmp     qword [err_quiet_caret], 0
    jne     .message
    cmp     qword [err_interactive], 0
    je      .in_file

    mov     rdi, [err_pos]
    call    src_line_start
    mov     rdi, [err_pos]
    sub     rdi, rax
    add     rdi, PROMPT_LEN
    call    write_spaces
    jmp     .caret

; rbx is not available here without saving it, so the line start is recomputed
; rather than kept -- three cheap scans on a path that only runs once, and only
; when something has already gone wrong.
.in_file:
    mov     rdi, [err_pos]
    call    src_line_number
    call    fmt_i64
    call    sys_write_stderr
    lea     rsi, [msg_bar]
    mov     rdx, msg_bar.len
    call    sys_write_stderr

    mov     rdi, [err_pos]
    call    src_line_start
    push    rax
    mov     rdi, rax
    call    src_line_end
    pop     rsi
    mov     rdx, rax
    sub     rdx, rsi
    push    rsi
    call    sys_write_stderr
    lea     rsi, [msg_newline]
    mov     rdx, 1
    call    sys_write_stderr

    pop     rcx
    mov     rdi, [err_pos]
    sub     rdi, rcx
    add     rdi, msg_bar.len + 1        ; past the number and the separator
    call    write_spaces

.caret:
    lea     rsi, [msg_caret]
    mov     rdx, msg_caret.len
    call    sys_write_stderr
.message:
    lea     rsi, [msg_error]
    mov     rdx, msg_error.len
    call    sys_write_stderr
    mov     rsi, [err_msg]
    mov     rdx, [err_len]
    call    sys_write_stderr
    lea     rsi, [msg_newline]
    mov     rdx, 1
    jmp     sys_write_stderr
.none:
    ret

; Reading a file rather than a prompt: no echo to point at, so print the line.
err_reading_file:
    mov     qword [err_interactive], 0
    ret

; And back again, for "-i": the program is over, the prompt is up, and the
; terminal is echoing what gets typed at it once more.
err_at_prompt:
    mov     qword [err_interactive], 1
    ret

; ---------------------------------------------------------------------------
    section .data

msg_caret:
    db      "^", 10
.len                equ $ - msg_caret

    align   8
err_interactive:
    dq      1
msg_error:
    db      "error: "
.len                equ $ - msg_error
msg_newline:
    db      10
msg_bar:
    db      " | "
.len                equ $ - msg_bar

e_expected:
    db      "expected an expression"
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
e_toobig:
    db      "expression too complex"
.len                equ $ - e_toobig
e_unterminated:
    db      "unterminated string"
.len                equ $ - e_unterminated
e_unterminatedcomment:
    db      "unterminated comment"
.len                equ $ - e_unterminatedcomment
e_longname:
    db      "identifier too long"
.len                equ $ - e_longname
e_toomanynames:
    db      "too many identifiers"
.len                equ $ - e_toomanynames
e_strspace:
    db      "out of string space"
.len                equ $ - e_strspace
e_badescape:
    db      "unknown escape sequence"
.len                equ $ - e_badescape
e_badconv:
    db      "unknown conversion in format string"
.len                equ $ - e_badconv
e_missingarg:
    db      "not enough arguments for format string"
.len                equ $ - e_missingarg
e_notlvalue:
    db      "left of '=' is not a variable"
.len                equ $ - e_notlvalue
e_builtin:
    db      "a builtin function is not a variable"
.len                equ $ - e_builtin
e_unknownfn:
    db      "unknown function"
.len                equ $ - e_unknownfn
e_toomanyargs:
    db      "too many arguments"
.len                equ $ - e_toomanyargs
e_needargs:
    db      "printf needs a format string"
.len                equ $ - e_needargs
e_expectedsemi:
    db      "expected ';'"
.len                equ $ - e_expectedsemi
e_expectedparen:
    db      "expected '('"
.len                equ $ - e_expectedparen
e_expectedname:
    db      "expected a variable name"
.len                equ $ - e_expectedname
e_expectedwhile:
    db      "expected 'while' after the body of 'do'"
.len                equ $ - e_expectedwhile
e_undeclared:
    db      "undeclared identifier"
.len                equ $ - e_undeclared
e_redeclared:
    db      "already declared in this scope"
.len                equ $ - e_redeclared
e_declbody:
    db      "a declaration needs a block of its own"
.len                equ $ - e_declbody
e_notinloop:
    db      "not inside a loop"
.len                equ $ - e_notinloop
e_toomanyvars:
    db      "too many variables"
.len                equ $ - e_toomanyvars
e_toomanyscopes:
    db      "blocks nest too deeply"
.len                equ $ - e_toomanyscopes
e_toodeep:
    db      "loops nest too deeply"
.len                equ $ - e_toodeep
e_srcfull:
    db      "input too long"
.len                equ $ - e_srcfull
e_notinfunction:
    db      "'return' outside a function"
.len                equ $ - e_notinfunction
e_nestedfunction:
    db      "a function cannot be defined in here"
.len                equ $ - e_nestedfunction
e_expectedbrace:
    db      "expected '{'"
.len                equ $ - e_expectedbrace
e_expectedtype:
    db      "expected 'int'"
.len                equ $ - e_expectedtype
e_argcount:
    db      "wrong number of arguments"
.len                equ $ - e_argcount
e_redefined:
    db      "that function is already defined"
.len                equ $ - e_redefined
e_toomanyfuncs:
    db      "too many functions"
.len                equ $ - e_toomanyfuncs
e_stackfull:
    db      "too much recursion"
.len                equ $ - e_stackfull
e_nomain:
    db      "no main() to run"
.len                equ $ - e_nomain
e_codefull:
    db      "compiled code too large"
.len                equ $ - e_codefull
e_deep:
    db      "expression nests too deeply"
.len                equ $ - e_deep

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
err_code:
    resq    1
err_quiet_caret:
    resq    1
err_msg:
    resq    1
err_len:
    resq    1
err_pos:
    resq    1
