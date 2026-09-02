; SPDX-License-Identifier: MIT
;
; Scanner. One token of lookahead lives in tok_kind / tok_val / tok_pos; the
; parser reads those directly and calls lex_next to consume.

%include "tsafoshi.inc"

    global  lex_init
    global  lex_next
    global  tok_kind
    global  tok_val
    global  tok_pos

    section .text

; rdi = NUL-terminated source. Loads the first token.
lex_init:
    mov     [lex_cur], rdi
    ; fall through

lex_next:
    mov     rdi, [lex_cur]
.space:
    movzx   eax, byte [rdi]
    cmp     al, ' '
    je      .skip
    cmp     al, 9
    je      .skip
    cmp     al, 13
    je      .skip
    jmp     .scan
.skip:
    inc     rdi
    jmp     .space

.scan:
    mov     [tok_pos], rdi
    movzx   eax, byte [rdi]
    test    al, al
    jz      .eof
    cmp     al, '0'
    jb      .punct
    cmp     al, '9'
    jbe     .number

.punct:
    inc     rdi
    mov     [lex_cur], rdi
    lea     rcx, [punct_map]
    movzx   eax, byte [rcx + rax]
    mov     [tok_kind], rax
    ret

.number:
    xor     eax, eax                    ; wraps silently on overflow for now
.digits:
    movzx   ecx, byte [rdi]
    cmp     cl, '0'
    jb      .number_done
    cmp     cl, '9'
    ja      .number_done
    sub     ecx, '0'
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .digits
.number_done:
    mov     [lex_cur], rdi
    mov     [tok_val], rax
    mov     qword [tok_kind], TK_NUM
    ret

.eof:
    mov     [lex_cur], rdi
    mov     qword [tok_kind], TK_EOF
    ret

; ---------------------------------------------------------------------------
    section .data

; byte -> token kind. Digits are handled before this is consulted.
punct_map:
    times   37 db TK_BAD                ; 0 .. 36
    db      TK_PERCENT                  ; 37 %
    times   2 db TK_BAD                 ; 38 &   39 '
    db      TK_LPAREN                   ; 40 (
    db      TK_RPAREN                   ; 41 )
    db      TK_STAR                     ; 42 *
    db      TK_PLUS                     ; 43 +
    db      TK_BAD                      ; 44 ,
    db      TK_MINUS                    ; 45 -
    db      TK_BAD                      ; 46 .
    db      TK_SLASH                    ; 47 /
    times   208 db TK_BAD               ; 48 .. 255

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
lex_cur:
    resq    1
tok_kind:
    resq    1
tok_val:
    resq    1
tok_pos:
    resq    1
