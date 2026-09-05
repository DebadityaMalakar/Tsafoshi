; SPDX-License-Identifier: MIT
;
; Line input on top of the platform's sys_read_stdin, and the buffer that
; collects several of those into one submission.
;
; A block does not fit on a line, so the REPL had to stop being line-oriented.
; It still reads one line at a time -- that is what a terminal gives you -- but
; what it hands the lexer is a submission, which is however many lines it took
; to balance the braces. Everything above here works in offsets into src_buf,
; including the positions the compiler freezes into the bytecode.
;
; And src_buf is the whole session, not one submission. Functions arrived at
; stage 2.3 and they outlive the line that defined them, so a division by zero
; three functions deep still has to be able to name the column it was written
; at -- which it cannot do if the text has been overwritten since. Keeping
; every line costs 64 KiB and makes the answer trivially correct.

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
    global  src_line_end
    global  src_line_number
    global  src_text
    global  src_add
    global  src_mark
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

; Opens a new submission at the end of what is already there, with a newline
; between it and the last one.
src_begin:
    cmp     qword [src_len], 0
    je      .mark
    mov     edi, 10
    call    src_putc
.mark:
    mov     rax, [src_len]
    mov     [src_mark], rax
    ret

; -> rax = where the current submission starts, which is what the lexer is
; given. Everything before it is older text nobody is parsing any more.
src_text:
    lea     rax, [src_buf]
    add     rax, [src_mark]
    ret

; rdi = text, rsi = length. Appends it to the arena exactly as it is, which is
; what a file wants: it arrived with its own line breaks and every offset in it
; has to keep meaning the same column.
src_add:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13, r13
.next:
    cmp     r13, r12
    jae     .done
    movzx   edi, byte [rbx + r13]
    call    src_putc
    test    rax, rax
    jz      .out
    inc     r13
    jmp     .next
.done:
    mov     eax, 1
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = one byte -> rax = 1, or 0 with the error recorded
src_putc:
    mov     rax, [src_len]
    cmp     rax, SRC_CAP - 2
    jae     .full
    lea     rcx, [src_buf]
    mov     [rcx + rax], dil
    inc     rax
    mov     [src_len], rax
    mov     byte [rcx + rax], 0
    mov     eax, 1
    ret
.full:
    lea     rdi, [src_buf]
    add     rdi, rax
    call    err_srcfull
    xor     eax, eax
    ret

; Appends whatever read_line just left in line_buf, with a newline in front of
; it if this submission already has a line.
;
; A separator rather than a terminator, and the difference matters: an error
; reported at the very end of the input would otherwise be measured from the
; start of an empty line that follows it, and the caret would jump back to
; column zero. A submission ends where its last character does.
src_append:
    push    rbx
    push    r12
    mov     rax, [src_len]
    cmp     rax, [src_mark]
    jbe     .copy_setup
    mov     edi, 10
    call    src_putc
    test    rax, rax
    jz      .out
.copy_setup:
    lea     rbx, [line_buf]
    xor     r12, r12
.copy:
    movzx   edi, byte [rbx + r12]
    test    dil, dil
    jz      .done
    call    src_putc
    test    rax, rax
    jz      .out
    inc     r12
    jmp     .copy
.done:
    mov     eax, 1
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
    mov     rcx, [src_mark]             ; only this submission's own braces
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

; rdi = a position -> rax = one past the last character of its line
src_line_end:
    mov     rax, rdi
.scan:
    movzx   ecx, byte [rax]
    test    cl, cl
    jz      .done
    cmp     cl, 10
    je      .done
    inc     rax
    jmp     .scan
.done:
    ret

; rdi = a position -> rax = which line of the current submission it is on,
; counting from one. Only the submission, not the session: a file is one
; submission, so this is the line number the user's editor would show.
src_line_number:
    lea     rcx, [src_buf]
    add     rcx, [src_mark]
    mov     eax, 1
.scan:
    cmp     rcx, rdi
    jae     .done
    cmp     byte [rcx], 10
    jne     .step
    inc     rax
.step:
    inc     rcx
    jmp     .scan
.done:
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
src_mark:
    resq    1
line_buf:
    resb    LINE_CAP
src_buf:
    resb    SRC_CAP
rd_buf:
    resb    RD_CAP
