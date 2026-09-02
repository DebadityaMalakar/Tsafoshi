; SPDX-License-Identifier: MIT
;
; Scanner. One token of lookahead lives in tok_kind / tok_val / tok_pos; the
; parser reads those directly and calls lex_next to consume.
;
; A lexeme is resolved to a value here rather than passed on as text: a number
; becomes its value, an identifier its name slot, a string literal its offset
; in the string arena. The parser therefore never sees characters at all.

%include "tsafoshi.inc"

    global  lex_init
    global  lex_next
    global  tok_kind
    global  tok_val
    global  tok_pos

    extern  name_intern
    extern  str_intern
    extern  err_unterminated

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
    cmp     al, '"'
    je      .string
    cmp     al, '0'
    jb      .punct
    cmp     al, '9'
    jbe     .number
    call    ident_start
    test    eax, eax
    jnz     .ident

; Re-read rather than trust eax: the identifier test above is a call, and a
; call is allowed to have clobbered it.
.punct:
    movzx   eax, byte [rdi]
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

; rsi = where the name starts; the interning is names.asm's problem.
.ident:
    mov     rsi, rdi
.ident_more:
    inc     rdi
    movzx   eax, byte [rdi]
    call    ident_part
    test    eax, eax
    jnz     .ident_more
    mov     [lex_cur], rdi
    sub     rdi, rsi
    mov     rdx, rsi
    mov     rsi, rdi
    mov     rdi, rdx
    mov     rdx, [tok_pos]
    call    name_intern
    mov     [tok_val], rax
    mov     qword [tok_kind], TK_IDENT
    ret

; The raw extent only; strings.asm decodes the escapes. The one thing that
; has to be understood twice is the backslash, because without it the scanner
; cannot tell which quote ends the literal.
.string:
    inc     rdi
    mov     rsi, rdi
.string_more:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .unterminated
    cmp     al, '"'
    je      .string_end
    cmp     al, 92                      ; a backslash
    jne     .string_step
    inc     rdi
    cmp     byte [rdi], 0
    je      .unterminated
.string_step:
    inc     rdi
    jmp     .string_more
.string_end:
    mov     rcx, rdi
    sub     rcx, rsi
    inc     rdi                         ; past the closing quote
    mov     [lex_cur], rdi
    mov     rdi, rsi
    mov     rsi, rcx
    mov     rdx, [tok_pos]
    call    str_intern
    mov     [tok_val], rax
    mov     qword [tok_kind], TK_STR
    ret
.unterminated:
    mov     [lex_cur], rdi
    mov     rdi, [tok_pos]
    call    err_unterminated
    mov     qword [tok_kind], TK_BAD
    ret

.eof:
    mov     [lex_cur], rdi
    mov     qword [tok_kind], TK_EOF
    ret

; al = character -> eax = 1 if it may begin an identifier. Underscore sits
; between the two letter ranges, so it is tested on its own.
ident_start:
    cmp     al, '_'
    je      .yes
    mov     ecx, eax
    or      ecx, 32                     ; one fold covers both cases
    cmp     ecx, 'a'
    jb      .no
    cmp     ecx, 'z'
    jbe     .yes
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; al = character -> eax = 1 if it may continue one
ident_part:
    cmp     al, '0'
    jb      ident_start
    cmp     al, '9'
    jbe     ident_start.yes
    jmp     ident_start

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
    db      TK_COMMA                    ; 44 ,
    db      TK_MINUS                    ; 45 -
    db      TK_BAD                      ; 46 .
    db      TK_SLASH                    ; 47 /
    times   11 db TK_BAD                ; 48 .. 58
    db      TK_SEMI                     ; 59 ;
    db      TK_BAD                      ; 60 <
    db      TK_ASSIGN                   ; 61 =
    times   194 db TK_BAD               ; 62 .. 255

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
