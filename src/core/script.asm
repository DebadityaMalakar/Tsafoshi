; SPDX-License-Identifier: MIT
;
; Running a .c file, as against typing at the prompt.
;
; "tsafoshi hello.c" is a C program in the ordinary sense: the whole file is
; one submission, execution begins at main, and main's return value is the
; process's exit status. The REPL is the *interactive* mode and a convenience;
; this is the one that has to look like C.
;
; Almost nothing here is new. The file becomes one very long submission, which
; the same lexer, parser and engines then handle exactly as they handle a line
; -- and that works only because a submission stopped being a line at stage
; 2.2. Reaching main afterwards is a call node built by hand, handed to
; exec_run as if the user had typed "main()", so both engines run a file by the
; same route they run anything else.

%include "tsafoshi.inc"

    global  script_run

    extern  sys_open_read
    extern  sys_read_file
    extern  sys_close
    extern  sys_write_stdout
    extern  sys_write_stderr
    extern  src_begin
    extern  src_add
    extern  src_text
    extern  lex_init
    extern  tok_kind
    extern  tok_pos
    extern  ast_reset
    extern  ast_invoke
    extern  parse_line
    extern  parse_value
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

; A file's top-level statements run first -- there should not be any in real C,
; but this interpreter has no separate translation unit to forbid them in, and
; running them is friendlier than pretending the lines are not there.
    mov     rdi, rax
    mov     rsi, [parse_value]
    call    exec_run
    cmp     qword [err_code], 0
    jne     .failed

    call    find_main
    cmp     rax, -1
    je      .no_main
    mov     r13, rax
    mov     rdi, r13
    call    func_arity
    test    rax, rax
    jnz     .main_args

    call    src_text                    ; a call node built by hand: "main()"
    mov     rcx, rax
    mov     rdi, r13
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

.trailing:
    mov     rdi, [tok_pos]
    call    err_trailing
    jmp     .failed
; Neither of these is about a place in the file, so neither gets a caret
; pointing at one.
.no_main:
    mov     qword [err_quiet_caret], 1
    call    src_text
    mov     rdi, rax
    call    err_nomain
    jmp     .failed
.main_args:
    mov     qword [err_quiet_caret], 1
    call    src_text
    mov     rdi, rax
    call    err_argcount                ; main(int, char**) needs stage 3
    jmp     .failed
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
