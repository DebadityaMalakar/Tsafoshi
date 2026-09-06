; SPDX-License-Identifier: MIT
;
; Running something that is not a prompt: a file, a pipe, or one submission
; spelled out on the command line.
;
; "tsafoshi hello.c" is a C program in the ordinary sense: the whole file is
; one submission, execution begins at main, and main's return value is the
; process's exit status. The REPL is the *interactive* mode and a convenience;
; this is the one that has to look like C.
;
; Almost nothing here is new. The source becomes one very long submission,
; which the same lexer, parser and engines then handle exactly as they handle a
; line -- and that works only because a submission stopped being a line at
; stage 2.2. Reaching main afterwards is a call node built by hand, handed to
; exec_run as if the user had typed "main()", so every route runs a program the
; same way it runs anything else.
;
; The three entry points differ in two small ways and no more, which is why
; they are three labels in front of one routine rather than three routines:
; whether a trailing expression is answered, and whether a missing main is a
; complaint or simply the end of the program.

%include "tsafoshi.inc"

    global  script_run
    global  script_eval
    global  script_stdin

    extern  sys_open_read
    extern  sys_read_file
    extern  sys_close
    extern  sys_write_stdout
    extern  sys_write_stderr
    extern  read_line
    extern  src_begin
    extern  src_add
    extern  src_append
    extern  src_text
    extern  lex_init
    extern  tok_kind
    extern  tok_pos
    extern  ast_reset
    extern  ast_invoke
    extern  parse_line
    extern  parse_value
    extern  parse_silent
    extern  print_result
    extern  exec_define
    extern  exec_run
    extern  func_find
    extern  func_arity
    extern  name_intern
    extern  err_code
    extern  err_reset
    extern  err_report
    extern  err_trailing
    extern  err_nomain
    extern  err_argcount
    extern  err_reading_file
    extern  err_quiet_caret

; What the caller wants done with the submission once it has run.
RUN_PRINT           equ 1               ; answer a trailing expression
RUN_NEEDMAIN        equ 2               ; a missing main is an error

    section .text

; rdi = the path -> rax = the exit status.
;
; rbx = the file, r12 = how much of it has been read
script_run:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    err_reading_file
    call    sys_open_read
    cmp     rax, 0
    jl      .cannot_open
    cmp     rax, -1                     ; Windows says INVALID_HANDLE_VALUE
    je      .cannot_open
    mov     rbx, rax

    xor     r12, r12
.read:
    lea     rsi, [file_buf]
    add     rsi, r12
    mov     rdx, SRC_CAP
    sub     rdx, r12
    sub     rdx, 1
    jle     .too_big
    mov     rdi, rbx
    call    sys_read_file
    test    rax, rax
    jle     .read_done
    add     r12, rax
    jmp     .read
.read_done:
    mov     rdi, rbx
    call    sys_close
    lea     rcx, [file_buf]
    mov     byte [rcx + r12], 0

    mov     rdi, r12
    call    blank_directives
    call    err_reset
    call    src_begin
    lea     rdi, [file_buf]
    mov     rsi, r12
    call    src_add
    test    rax, rax
    jz      .failed
    mov     edi, RUN_NEEDMAIN
    call    run_submission
    jmp     .out

.too_big:
    mov     rdi, rbx
    call    sys_close
    lea     rsi, [m_toobig]
    mov     rdx, m_toobig.len
    call    sys_write_stderr
    mov     eax, 1
    jmp     .out
.cannot_open:
    lea     rsi, [m_noopen]
    mov     rdx, m_noopen.len
    call    sys_write_stderr
    mov     eax, 1
    jmp     .out
.failed:
    call    err_report
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = NUL-terminated code -> rax = the exit status.
;
; "-e" is one submission typed somewhere other than the prompt, so it behaves
; like one: a trailing expression is answered, a trailing semicolon silences
; it, and main is called only if the code bothered to define one. Anything
; else would make the flag a different language from the prompt it imitates.
script_eval:
    push    rbx
    mov     rbx, rdi
    call    err_reading_file
    call    err_reset
    call    src_begin
    mov     rdi, rbx
    call    length_of
    mov     rsi, rax
    mov     rdi, rbx
    call    src_add
    test    rax, rax
    jz      .failed
    mov     edi, RUN_PRINT
    call    run_submission
    pop     rbx
    ret
.failed:
    call    err_report
    mov     eax, 1
    pop     rbx
    ret

; -> rax = the exit status. The whole of standard input is one submission.
;
; A pipe is a program, not a conversation: nothing is prompted for, nothing is
; answered back, and the lines are gathered one at a time only because that is
; what puts the newline separators in and keeps every error's line number
; counting from the right place.
script_stdin:
    call    err_reading_file
    call    err_reset
    call    src_begin
.line:
    call    read_line
    test    rax, rax
    jz      .gathered
    call    src_append
    test    rax, rax
    jz      .failed
    jmp     .line
.gathered:
    xor     edi, edi
    jmp     run_submission
.failed:
    call    err_report
    mov     eax, 1
    ret

; rdi = the RUN_ flags -> rax = the exit status.
;
; rbx = those flags, r12 = the function id of main
run_submission:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    ast_reset
    call    src_text
    mov     rdi, rax
    call    lex_init
    call    parse_line
    cmp     qword [err_code], 0
    jne     .failed
    cmp     qword [tok_kind], TK_EOF
    jne     .trailing

    push    rax
    call    exec_define
    pop     rax
    cmp     qword [err_code], 0
    jne     .failed

; A program's top-level statements run first -- there should not be any in real
; C, but this interpreter has no separate translation unit to forbid them in,
; and running them is friendlier than pretending the lines are not there.
    mov     rdi, rax
    mov     rsi, [parse_value]
    call    exec_run
    cmp     qword [err_code], 0
    jne     .failed

    test    rbx, RUN_PRINT
    jz      .to_main
    cmp     qword [parse_value], 0
    je      .to_main
    cmp     qword [parse_silent], 0
    jne     .to_main
    mov     rdi, [parse_value]
    mov     rdi, [rdi + NODE_TYPE]
    cmp     rdi, TY_VOID                ; a void expression has no answer
    je      .to_main
    call    print_result

.to_main:
    call    find_main
    cmp     rax, -1
    je      .no_main
    mov     r12, rax
    mov     rdi, r12
    call    func_arity
    test    rax, rax
    jnz     .main_args

    call    src_text                    ; a call node built by hand: "main()"
    mov     rcx, rax
    mov     rdi, r12
    xor     esi, esi
    xor     edx, edx
    call    ast_invoke
    test    rax, rax
    jz      .failed
    xor     edi, edi
    mov     rsi, rax
    call    exec_run
    cmp     qword [err_code], 0
    jne     .failed
    jmp     .out

; No main is only a problem when something claimed to be a translation unit.
; A pipe or a -e is a submission, and a submission that ran is finished.
.no_main:
    test    rbx, RUN_NEEDMAIN
    jz      .nothing_more
    mov     qword [err_quiet_caret], 1
    call    src_text
    mov     rdi, rax
    call    err_nomain
    jmp     .failed
.nothing_more:
    xor     eax, eax
    jmp     .out

.trailing:
    mov     rdi, [tok_pos]
    call    err_trailing
    jmp     .failed
; Not about a place in the source, so no caret pointing at one.
.main_args:
    mov     qword [err_quiet_caret], 1
    call    src_text
    mov     rdi, rax
    call    err_argcount                ; main(int, char**) needs stage 3.3
.failed:
    call    err_report
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
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

; rdi = how many bytes were read. Blanks out every preprocessor line.
;
; "#include <stdio.h>" is accepted and ignored, because the standard library is
; already here -- there is no translation unit to declare printf into and no
; linker to resolve it afterwards, so the line has nothing left to do. Real C
; source has it at the top and must keep working unchanged, which is the whole
; requirement.
;
; The line is overwritten with spaces rather than removed, so every byte after
; it stays at the offset it had in the file and a caret still lands under the
; right column. Doing this here rather than in the lexer keeps it honest about
; what it is: not a preprocessor, which is stage 5, but a way of not tripping
; over the one directive that would otherwise stop a real file from loading.
;
; rbx = the text, r12 = where we are, r13 = the length
blank_directives:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rbx, [file_buf]
    mov     r13, rdi
    xor     r12, r12
.line:
    cmp     r12, r13
    jae     .done
    mov     rcx, r12                    ; the first non-blank of the line
.blank:
    cmp     rcx, r13
    jae     .advance
    movzx   eax, byte [rbx + rcx]
    cmp     al, ' '
    je      .blank_step
    cmp     al, 9
    jne     .test
.blank_step:
    inc     rcx
    jmp     .blank
.test:
    cmp     al, '#'
    jne     .advance
.erase:
    cmp     r12, r13
    jae     .done
    movzx   eax, byte [rbx + r12]
    cmp     al, 10
    je      .advance
    mov     byte [rbx + r12], ' '
    inc     r12
    jmp     .erase

.advance:
    cmp     r12, r13
    jae     .done
    movzx   eax, byte [rbx + r12]
    inc     r12
    cmp     al, 10
    jne     .advance
    jmp     .line
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; -> rax = the function id of main, or -1
find_main:
    lea     rdi, [w_main]
    mov     esi, w_main.len
    xor     edx, edx
    call    name_intern
    cmp     rax, -1
    je      .none
    mov     rdi, rax
    jmp     func_find
.none:
    ret

; ---------------------------------------------------------------------------
    section .data

w_main:
    db      "main"
.len                equ $ - w_main

m_noopen:
    db      "tsafoshi: cannot open that file", 10
.len                equ $ - m_noopen
m_toobig:
    db      "tsafoshi: that file is too large", 10
.len                equ $ - m_toobig

; ---------------------------------------------------------------------------
    section .bss

file_buf:
    resb    SRC_CAP
