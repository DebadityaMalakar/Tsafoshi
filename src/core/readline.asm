; SPDX-License-Identifier: MIT
;
; Line input on top of the platform's sys_read_stdin.

%include "tsafoshi.inc"

    global  read_line
    global  line_is_blank
    global  is_quit
    global  line_buf

    extern  sys_read_stdin

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

is_quit:
    lea     rdi, [line_buf]
.skip:
    movzx   eax, byte [rdi]
    cmp     al, ' '
    je      .advance
    cmp     al, 9
    jne     .try
.advance:
    inc     rdi
    jmp     .skip
.try:
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
line_buf:
    resb    LINE_CAP
rd_buf:
    resb    RD_CAP
