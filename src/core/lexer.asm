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
    global  tok_type

    extern  name_intern
    extern  str_intern
    extern  str_escape
    extern  err_unterminated
    extern  err_unterminatedcomment
    extern  err_badchar
    extern  utf8_decode
    extern  shortcode_of

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
    cmp     al, 39                      ; a single quote
    je      .charconst
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

;
; Three bases, because C has three and a header full of 0x1f is not an exotic
; case. The leading zero does double duty exactly as it does in C: on its own
; it is the number zero, and in front of digits it is octal.
.number:
    xor     eax, eax                    ; wraps silently on overflow for now
    cmp     byte [rdi], '0'
    jne     .digits
    movzx   ecx, byte [rdi + 1]
    or      ecx, 32
    cmp     cl, 'x'
    je      .hex
    jmp     .octal

.digits:
    movzx   ecx, byte [rdi]
    cmp     cl, '0'
    jb      .suffix
    cmp     cl, '9'
    ja      .suffix
    sub     ecx, '0'
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .digits

.octal:
    movzx   ecx, byte [rdi]
    cmp     cl, '0'
    jb      .suffix
    cmp     cl, '7'
    ja      .suffix
    sub     ecx, '0'
    shl     rax, 3
    add     rax, rcx
    inc     rdi
    jmp     .octal

.hex:
    add     rdi, 2
.hex_more:
    movzx   ecx, byte [rdi]
    call    hex_digit
    cmp     ecx, -1
    je      .suffix
    shl     rax, 4
    add     rax, rcx
    inc     rdi
    jmp     .hex_more

; The suffixes, and then the one rule that decides a literal's type: it is the
; narrowest of the types its suffix allows that can actually hold it. Which is
; why 2147483648 is a long without anyone writing an L, and 42 is not.
;
; r9 = "u" was written, r10 = how many "l"s were
.suffix:
    xor     r9d, r9d
    xor     r10d, r10d
.suffix_more:
    movzx   ecx, byte [rdi]
    or      ecx, 32
    cmp     cl, 'u'
    je      .suffix_u
    cmp     cl, 'l'
    je      .suffix_l
    jmp     .suffix_done
.suffix_u:
    mov     r9d, 1
    inc     rdi
    jmp     .suffix_more
.suffix_l:
    inc     r10d
    inc     rdi
    jmp     .suffix_more

.suffix_done:
    mov     rcx, rax
    test    r9d, r9d
    jnz     .lit_unsigned
    test    r10d, r10d
    jnz     .lit_long
    movsxd  rdx, ecx
    cmp     rdx, rcx
    jne     .lit_long
    mov     edx, TY_INT
    jmp     .number_done
.lit_long:
    mov     edx, TY_LONG
    jmp     .number_done
.lit_unsigned:
    test    r10d, r10d
    jnz     .lit_ulong
    mov     edx, ecx
    cmp     rdx, rcx
    jne     .lit_ulong
    mov     edx, TY_UINT
    jmp     .number_done
.lit_ulong:
    mov     edx, TY_ULONG

.number_done:
    mov     [lex_cur], rdi
    mov     [tok_val], rax
    mov     [tok_type], rdx
    mov     qword [tok_kind], TK_NUM
    ret

; A character constant is a number token and nothing else -- C99 gives it type
; int, not char, and the interpreter has no reason to disagree. The closing
; quote is found first so the escape decoder can be told where to stop, which
; is what lets it be the same decoder a string literal uses.
;
; rsi = the first byte of the constant, rcx = the closing quote
.charconst:
    lea     rsi, [rdi + 1]
    mov     rcx, rsi
.char_find:
    movzx   eax, byte [rcx]
    test    al, al
    jz      .bad_char
    cmp     al, 39
    je      .char_end
    cmp     al, 92
    jne     .char_step
    inc     rcx
    cmp     byte [rcx], 0
    je      .bad_char
.char_step:
    inc     rcx
    jmp     .char_find

.char_end:
    cmp     rsi, rcx
    je      .bad_char                   ; "''" stands for nothing
    lea     rdx, [rcx + 1]
    mov     [lex_cur], rdx
    movzx   eax, byte [rsi]
    cmp     al, 92
    je      .char_escape
    movsx   rax, al
    jmp     .char_done
.char_escape:
    lea     rdi, [rsi + 1]
    mov     rsi, rcx
    mov     rdx, [tok_pos]
    call    str_escape
    movsx   rax, al
.char_done:
    mov     [tok_val], rax
    mov     qword [tok_type], TY_INT
    mov     qword [tok_kind], TK_NUM
    ret
.bad_char:
    mov     [lex_cur], rcx
    mov     rdi, [tok_pos]
    call    err_badchar
    mov     qword [tok_kind], TK_BAD
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
    sub     rdi, rsi                    ; rdi = how long it is
    mov     rdx, rsi
    mov     rsi, rdi
    mov     rdi, rdx
    call    ident_ascii                 ; -> rax = text, rdx = length
    mov     rdi, rax
    mov     rsi, rdx
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
    mov     qword [tok_type], TY_LONG   ; an address, until pointers exist
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

; rdi = the identifier's bytes, rsi = how many -> rax = the text to intern,
; rdx = its length.
;
; The same pointer straight back when it was already ASCII, which is every
; identifier anybody has ever written and therefore the path worth keeping
; free. Only when a byte turns up with its top bit set does anything get
; copied, and then the whole identifier is rebuilt a codepoint at a time.
;
; What comes out is still an identifier and still ASCII, so names.asm, the
; parser, the disassembler and every error message carry on knowing nothing
; about any of this.
ident_ascii:
    xor     ecx, ecx
.look:
    cmp     rcx, rsi
    jae     .plain
    cmp     byte [rdi + rcx], 0x80
    jae     translate
    inc     rcx
    jmp     .look
.plain:
    mov     rax, rdi
    mov     rdx, rsi
    ret

; rbx = the source, r12 = its length, r13 = where we are in it, r14 = how much
; has been written
translate:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13, r13
    xor     r14, r14

.next:
    cmp     r13, r12
    jae     .done
    cmp     r14, NAME_LEN               ; past the limit, and names.asm will
    ja      .done                       ; say so; stop before the buffer ends
    lea     rdi, [rbx + r13]
    movzx   eax, byte [rdi]
    cmp     al, 0x80
    jb      .plain_byte

    call    utf8_decode
    add     r13, rdx
    mov     rdi, rax
    lea     rsi, [ident_buf]
    add     rsi, r14
    call    shortcode_of
    add     r14, rax
    jmp     .next

.plain_byte:
    lea     rcx, [ident_buf]
    mov     [rcx + r14], al
    inc     r14
    inc     r13
    jmp     .next

.done:
    lea     rax, [ident_buf]
    mov     rdx, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; cl = character -> ecx = its value as a hexadecimal digit, or -1
hex_digit:
    cmp     cl, '0'
    jb      .no
    cmp     cl, '9'
    jbe     .decimal
    or      ecx, 32
    cmp     cl, 'a'
    jb      .no
    cmp     cl, 'f'
    ja      .no
    sub     ecx, 'a' - 10
    ret
.decimal:
    sub     ecx, '0'
    ret
.no:
    mov     ecx, -1
    ret

; al = character -> eax = 1 if it may begin an identifier. Underscore sits
; between the two letter ranges, so it is tested on its own.
; Anything with its top bit set counts, which is every byte of every UTF-8
; sequence. C99 leaves it to the implementation which "other characters" may
; appear in an identifier, and this implementation's answer is all of them --
; the transliteration happens afterwards, so the scanner only has to agree on
; where the name ends.
ident_start:
    cmp     al, 0x80
    jae     .yes
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
tok_type:
    resq    1
ident_buf:
    resb    IDENT_CAP
