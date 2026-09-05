; SPDX-License-Identifier: MIT
;
; Scanner. One token of lookahead lives in tok_kind / tok_val / tok_pos; the
; parser reads those directly and calls lex_next to consume.
;
; A lexeme is resolved to a value here rather than passed on as text: a number
; becomes its value, an identifier its name slot, a string literal its offset
; in the string arena. The parser therefore never sees characters at all.
;
; A keyword is not a separate lexical class. It is an identifier whose interned
; slot happens to be one of the first few, because names_init reserves those
; before any input is read -- so recognising one is a compare and an add, and
; the keyword list lives in exactly one place, which is names.asm.

%include "tsafoshi.inc"

    global  lex_init
    global  lex_next
    global  tok_kind
    global  tok_val
    global  tok_pos

    extern  name_intern
    extern  str_intern
    extern  err_unterminated
    extern  err_unterminatedcomment

    section .text

; rdi = NUL-terminated source. Loads the first token.
lex_init:
    mov     [lex_cur], rdi
    ; fall through

; Whitespace and comments are the same thing to everything downstream, so they
; are skipped by the same loop. A newline is whitespace: a submission may span
; several lines, and nothing above here cares where they end.
lex_next:
    mov     rdi, [lex_cur]
.space:
    movzx   eax, byte [rdi]
    cmp     al, ' '
    je      .skip
    cmp     al, 9
    je      .skip
    cmp     al, 10
    je      .skip
    cmp     al, 13
    je      .skip
    cmp     al, '/'
    je      .maybe_comment
    jmp     .scan
.skip:
    inc     rdi
    jmp     .space

; Only "//" and "/*" are comments; a lone slash is division, and has to fall
; through with rdi still pointing at it.
.maybe_comment:
    movzx   eax, byte [rdi + 1]
    cmp     al, '/'
    je      .line_comment
    cmp     al, '*'
    je      .block_comment
    jmp     .scan

.line_comment:
    add     rdi, 2
.line_more:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .space                      ; end of input ends the comment
    cmp     al, 10
    je      .space
    inc     rdi
    jmp     .line_more

.block_comment:
    mov     rsi, rdi                    ; where it opened, for the caret
    add     rdi, 2
.block_more:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .unterminated_comment
    cmp     al, '*'
    jne     .block_step
    cmp     byte [rdi + 1], '/'
    je      .block_end
.block_step:
    inc     rdi
    jmp     .block_more
.block_end:
    add     rdi, 2
    jmp     .space
.unterminated_comment:
    mov     [lex_cur], rdi
    mov     [tok_pos], rsi
    mov     rdi, rsi
    call    err_unterminatedcomment
    mov     qword [tok_kind], TK_BAD
    ret

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
;
; Two-character operators are tried before the single-character map, because
; the map cannot tell "<" from the "<" of "<=". The table is short enough that
; a scan costs less than a second indexed table would.
.punct:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rdi + 1]         ; the NUL terminator matches no pair
    lea     r8, [digraphs]
.digraph:
    movzx   edx, byte [r8]
    test    dl, dl
    jz      .single
    cmp     dl, al
    jne     .digraph_step
    movzx   edx, byte [r8 + 1]
    cmp     dl, cl
    jne     .digraph_step
    movzx   eax, byte [r8 + 2]
    add     rdi, 2
    jmp     .punct_done
.digraph_step:
    add     r8, 3
    jmp     .digraph
.single:
    lea     rcx, [punct_map]
    movzx   eax, byte [rcx + rax]
    inc     rdi
.punct_done:
    mov     [lex_cur], rdi
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
    cmp     rax, KW_COUNT               ; the reserved slots are the keywords
    jb      .keyword
    mov     [tok_val], rax
    mov     qword [tok_kind], TK_IDENT
    ret
.keyword:
    add     rax, TK_KW_FIRST
    mov     [tok_kind], rax
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

; first byte, second byte, token kind. Terminated by a zero first byte. Order
; matters only in that no pair here is a prefix of another.
digraphs:
    db      '<', '<', TK_SHL
    db      '>', '>', TK_SHR
    db      '<', '=', TK_LE
    db      '>', '=', TK_GE
    db      '=', '=', TK_EQ
    db      '!', '=', TK_NE
    db      '&', '&', TK_ANDAND
    db      '|', '|', TK_OROR
    db      0, 0, 0

; byte -> token kind. Digits, quotes and the two-character operators are all
; handled before this is consulted.
punct_map:
    times   33 db TK_BAD                ; 0 .. 32
    db      TK_BANG                     ; 33 !
    times   3 db TK_BAD                 ; 34 "   35 #   36 $
    db      TK_PERCENT                  ; 37 %
    db      TK_AMP                      ; 38 &
    db      TK_BAD                      ; 39 '
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
    db      TK_LT                       ; 60 <
    db      TK_ASSIGN                   ; 61 =
    db      TK_GT                       ; 62 >
    times   31 db TK_BAD                ; 63 .. 93
    db      TK_CARET                    ; 94 ^
    times   28 db TK_BAD                ; 95 .. 122
    db      TK_LBRACE                   ; 123 {
    db      TK_PIPE                     ; 124 |
    db      TK_RBRACE                   ; 125 }
    db      TK_TILDE                    ; 126 ~
    times   129 db TK_BAD               ; 127 .. 255

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
