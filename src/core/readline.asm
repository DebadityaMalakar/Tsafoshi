; SPDX-License-Identifier: MIT
;
; Line input on top of the platform's sys_read_stdin, and the buffer that
; collects several of those into one submission.
;
; A block does not fit on a line, so the REPL had to stop being line-oriented.
; It still reads one line at a time -- that is what a terminal gives you -- but
; what it hands the lexer is src_buf, which is however many lines it took to
; balance the braces. Everything above here works in offsets into that buffer,
; including the positions the compiler freezes into the bytecode.

%include "tsafoshi.inc"

    global  read_line
    global  line_is_blank
    global  is_quit
    global  match_word
    global  skip_blanks
    global  line_buf
    global  src_begin
    global  src_append
    global  src_open_braces
    global  src_line_start
    global  src_buf

    extern  sys_read_stdin
    extern  err_srcfull

    section .text

; One NUL-terminated line into line_buf, CR/LF stripped. Buffered, so a pipe
; behaves like a console. -> rax = 1, or 0 at EOF with nothing left.
read_line:
    push    rbx
    push    r12
    push    r13
    xor     r12, r12
    lea     r13, [line_buf]

.next_byte:
    mov     rax, [rd_pos]
    cmp     rax, [rd_len]
    jb      .have_byte
    lea     rsi, [rd_buf]
    mov     rdx, RD_CAP
    call    sys_read_stdin
    test    rax, rax
    jle     .eof
    mov     [rd_len], rax
    mov     qword [rd_pos], 0

.have_byte:
    lea     rbx, [rd_buf]
    mov     rax, [rd_pos]
    movzx   ecx, byte [rbx + rax]
    inc     rax
    mov     [rd_pos], rax
    cmp     cl, 10
    je      .end_of_line
    cmp     r12, LINE_CAP - 1
    jae     .next_byte                  ; over-long line: drop the excess
    mov     [r13 + r12], cl
    inc     r12
    jmp     .next_byte

.eof:
    test    r12, r12
    jz      .nothing
.end_of_line:
    test    r12, r12
    jz      .terminate
    cmp     byte [r13 + r12 - 1], 13
    jne     .terminate
    dec     r12
.terminate:
    mov     byte [r13 + r12], 0
    mov     eax, 1
    jmp     .out
.nothing:
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; --- the submission buffer

src_begin:
    mov     qword [src_len], 0
    lea     rax, [src_buf]
    mov     byte [rax], 0
    ret

; Appends whatever read_line just left in line_buf, with a newline in front of
; it if there is already something there.
;
; A separator rather than a terminator, and the difference matters: an error
; reported at the very end of the input would otherwise be measured from the
; start of an empty line that follows it, and the caret would jump back to
; column zero. The submission ends where the last character does.
src_append:
    push    rbx
    push    r12
    lea     rbx, [src_buf]
    mov     r12, [src_len]
    test    r12, r12
    jz      .copy_setup
    cmp     r12, SRC_CAP - 2
    jae     .full
    mov     byte [rbx + r12], 10
    inc     r12
.copy_setup:
    lea     rcx, [line_buf]
    xor     edx, edx
.copy:
    movzx   eax, byte [rcx + rdx]
    test    al, al
    jz      .done
    cmp     r12, SRC_CAP - 2
    jae     .full
    mov     [rbx + r12], al
    inc     r12
    inc     rdx
    jmp     .copy
.done:
    mov     byte [rbx + r12], 0
    mov     [src_len], r12
    mov     eax, 1
    jmp     .out
.full:
    mov     byte [rbx + r12], 0
    mov     [src_len], r12
    lea     rdi, [src_buf]
    call    err_srcfull
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; -> rax = how many braces are open in the submission so far, which is how the
; REPL knows to keep reading. Quotes and comments are skipped, because a brace
; inside either of them closes nothing.
;
; Only braces are counted. An unbalanced parenthesis is a typo and should be
; reported, not waited on; an unclosed brace is nearly always a block still
; being typed.
src_open_braces:
    push    rbx
    lea     rbx, [src_buf]
    xor     eax, eax                    ; the depth
    xor     ecx, ecx                    ; the offset
.scan:
    movzx   edx, byte [rbx + rcx]
    test    dl, dl
    jz      .done
    cmp     dl, '"'
    je      .string
    cmp     dl, 39                      ; a single quote
    je      .string
    cmp     dl, '/'
    je      .maybe_comment
    cmp     dl, '{'
    je      .open
    cmp     dl, '}'
    je      .close
.step:
    inc     rcx
    jmp     .scan
.open:
    inc     rax
    jmp     .step
.close:
    test    rax, rax
    jz      .step                       ; a stray brace waits for nothing
    dec     rax
    jmp     .step

.string:
    mov     r8, rdx                     ; which quote opened it
    inc     rcx
.string_more:
    movzx   edx, byte [rbx + rcx]
    test    dl, dl
    jz      .done
    cmp     dl, 92                      ; a backslash
    jne     .string_test
    inc     rcx
    cmp     byte [rbx + rcx], 0
    je      .done
    inc     rcx
    jmp     .string_more
.string_test:
    inc     rcx
    cmp     dl, r8b
    jne     .string_more
    jmp     .scan

.maybe_comment:
    movzx   edx, byte [rbx + rcx + 1]
    cmp     dl, '/'
    je      .line_comment
    cmp     dl, '*'
    je      .block_comment
    jmp     .step
.line_comment:
    add     rcx, 2
.line_more:
    movzx   edx, byte [rbx + rcx]
    test    dl, dl
    jz      .done
    inc     rcx
    cmp     dl, 10
    jne     .line_more
    jmp     .scan
.block_comment:
    add     rcx, 2
.block_more:
    movzx   edx, byte [rbx + rcx]
    test    dl, dl
    jz      .done
    inc     rcx
    cmp     dl, '*'
    jne     .block_more
    cmp     byte [rbx + rcx], '/'
    jne     .block_more
    inc     rcx
    jmp     .scan

.done:
    pop     rbx
    ret

; rdi = a position inside src_buf -> rax = the start of the line it is on.
; The caret needs a column, not an offset, and both prompts are the same width
; -- so a position on the fourth line of a submission still lands under the
; character the terminal is showing it beside.
src_line_start:
    lea     rcx, [src_buf]
    mov     rax, rdi
.back:
    cmp     rax, rcx
    jbe     .start
    cmp     byte [rax - 1], 10
    je      .start
    dec     rax
    jmp     .back
.start:
    ret

line_is_blank:
    lea     rdi, [line_buf]
.scan:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .blank
    cmp     al, ' '
    je      .step
    cmp     al, 9
    jne     .no
.step:
    inc     rdi
    jmp     .scan
.blank:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; rdi = the command text, already past the colon
is_quit:
    lea     rsi, [w_quit]
    call    match_word
    test    rax, rax
    jnz     .yes
    lea     rsi, [w_exit]
    call    match_word
    test    rax, rax
    jnz     .yes
    lea     rsi, [w_q]
    call    match_word
    ret
.yes:
    mov     eax, 1
    ret

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

; rdi = line, rsi = NUL-terminated word. Must be followed by space or EOL.
; -> rax = 1/0, rdi preserved so callers can try several words.
match_word:
    push    rdi
    push    rsi
.compare:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .word_done
    movzx   ecx, byte [rdi]
    cmp     al, cl
    jne     .no
    inc     rdi
    inc     rsi
    jmp     .compare
.word_done:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .yes
    cmp     al, ' '
    je      .yes
    cmp     al, 9
    je      .yes
.no:
    xor     eax, eax
    jmp     .out
.yes:
    mov     eax, 1
.out:
    pop     rsi
    pop     rdi
    ret

; ---------------------------------------------------------------------------
    section .data

w_quit:
    db      "quit", 0
w_exit:
    db      "exit", 0
w_q:
    db      "q", 0

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
rd_pos:
    resq    1
rd_len:
    resq    1
src_len:
    resq    1
line_buf:
    resb    LINE_CAP
src_buf:
    resb    SRC_CAP
rd_buf:
    resb    RD_CAP
