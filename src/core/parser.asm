; SPDX-License-Identifier: MIT
;
; Recursive descent with precedence climbing, over the lexer's one-token
; lookahead. The parser produces a tree and never a value:
;
; line       := statement ( ";" statement )* ";"?
; statement  := expression
; expression := binary(PREC_LOWEST) ( "=" expression )?
; binary(p)  := unary ( binop(q >= p) binary(q + bump) )*
; unary      := ("-" | "+")* primary
; primary    := NUM | STRING | IDENT | call | "(" expression ")"
; call       := IDENT "(" ( expression ( "," expression )* )? ")"
;
; One loop covers every binary level. Adding a level means adding tokens and a
; row to the table in mode.asm; nothing here changes. The "q + bump" on the
; recursive call is what decides associativity: with the bump at 1 an operator
; of equal strength does not bind into the right operand, so it falls out to
; the loop and folds leftward. mode.asm supplies both the table and the bump,
; so switching convention changes no code here.
;
; Assignment is the one operator that is not in that table. C99 puts it below
; everything else and folds it rightward, and it needs its left side to be a
; variable rather than merely a value -- so it is a rule of its own, and the
; check happens after the left side is parsed rather than by looking ahead.
;
; Each rule returns a node in rax; on failure it records an error and returns
; zero, and callers re-check err_code and unwind the same way.

%include "tsafoshi.inc"

    global  parse_line
    global  parse_expression
    global  parse_silent

    extern  lex_next
    extern  tok_kind
    extern  tok_val
    extern  tok_pos
    extern  mode_prec
    extern  mode_bump
    extern  ast_num
    extern  ast_unary
    extern  ast_binary
    extern  ast_var
    extern  ast_assign
    extern  ast_str
    extern  ast_call
    extern  ast_arg
    extern  ast_seq
    extern  err_code
    extern  err_expected
    extern  err_unclosed
    extern  err_notlvalue
    extern  err_builtin
    extern  err_unknownfn
    extern  err_toomanyargs
    extern  err_needargs

    section .text

; The whole line -> rax. A trailing semicolon sets parse_silent, which is how
; the REPL knows to run the line without echoing its value: exactly the C
; distinction between a statement and the expression inside it.
parse_line:
    mov     qword [parse_silent], 0
    ; fall through

; rbx = the statement just parsed, r12 = the semicolon that followed it
parse_statements:
    push    rbx
    push    r12
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax
    cmp     qword [tok_kind], TK_SEMI
    jne     .done

    mov     r12, [tok_pos]
    call    lex_next
    cmp     qword [tok_kind], TK_EOF
    je      .last
    call    parse_statements
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    mov     rdi, rbx
    mov     rdx, r12
    call    ast_seq
    jmp     .out

.last:
    mov     qword [parse_silent], 1
.done:
    mov     rax, rbx
    jmp     .out
.fail:
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; -> rax.  rbx = the left side, r12 = its name slot
parse_expression:
    push    rbx
    push    r12
    mov     edi, PREC_LOWEST
    call    parse_binary
    cmp     qword [err_code], 0
    jne     .fail
    cmp     qword [tok_kind], TK_ASSIGN
    jne     .out
    test    rax, rax
    jz      .fail

    mov     rbx, rax
    cmp     qword [rbx + NODE_KIND], NT_VAR
    jne     .not_lvalue
    mov     r12, [rbx + NODE_VAL]
    cmp     r12, BI_COUNT               ; printf is a name, not a variable
    jb      .builtin
    call    lex_next
    call    parse_expression            ; right-associative for free
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    mov     rdi, r12
    mov     rdx, [rbx + NODE_POS]
    call    ast_assign
    jmp     .out

.not_lvalue:
    mov     rdi, [rbx + NODE_POS]
    call    err_notlvalue
    jmp     .fail
.builtin:
    mov     rdi, [rbx + NODE_POS]
    call    err_builtin
.fail:
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; rdi = lowest precedence this call may absorb -> rax
; rbx = left node, r12 = that floor, r13 = operator kind, r14 = its column
parse_binary:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    call    parse_unary
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax

.next:
    mov     rdi, [tok_kind]
    call    mode_prec
    test    rax, rax                    ; not a binary operator: we are done
    jz      .done
    cmp     rax, r12
    jb      .done                       ; binds looser than our caller allows

    mov     r13, [tok_kind]
    mov     r14, [tok_pos]
    add     rax, [mode_bump]            ; +1 folds left, +0 folds right
    push    rax                         ; the right operand's floor
    call    lex_next
    pop     rdi
    call    parse_binary
    cmp     qword [err_code], 0
    jne     .fail

    mov     rdx, rax
    mov     rdi, r13
    mov     rsi, rbx
    mov     rcx, r14
    call    ast_binary
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    jmp     .next

.done:
    mov     rax, rbx
    jmp     .out
.fail:
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

parse_unary:
    mov     rax, [tok_kind]
    cmp     rax, TK_MINUS
    je      .negate
    cmp     rax, TK_PLUS
    je      .plus
    jmp     parse_primary
.plus:
    call    lex_next                    ; unary plus has no effect, and no node
    jmp     parse_unary
.negate:
    push    qword [tok_pos]
    call    lex_next
    call    parse_unary
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    pop     rdx
    mov     edi, TK_MINUS
    jmp     ast_unary
.fail:
    pop     rdx
    xor     eax, eax
    ret

parse_primary:
    mov     rax, [tok_kind]
    cmp     rax, TK_NUM
    je      .number
    cmp     rax, TK_IDENT
    je      .ident
    cmp     rax, TK_STR
    je      .string
    cmp     rax, TK_LPAREN
    je      .paren
    mov     rdi, [tok_pos]
    call    err_expected
    xor     eax, eax
    ret

.number:
    mov     rdi, [tok_val]
    mov     rsi, [tok_pos]
    call    ast_num
    test    rax, rax
    jz      .zero
    push    rax
    call    lex_next
    pop     rax
    ret

.string:
    mov     rdi, [tok_val]
    mov     rsi, [tok_pos]
    call    ast_str
    test    rax, rax
    jz      .zero
    push    rax
    call    lex_next
    pop     rax
    ret

; A name is a variable unless a "(" follows it, which is the only lookahead
; past one token anywhere in the parser -- and it is one token of it.
.ident:
    push    qword [tok_val]
    push    qword [tok_pos]
    call    lex_next
    cmp     qword [tok_kind], TK_LPAREN
    je      .call
    pop     rsi
    pop     rdi
    jmp     ast_var
.call:
    pop     rsi
    pop     rdi
    jmp     parse_call

.paren:
    call    lex_next
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .zero
    cmp     qword [tok_kind], TK_RPAREN
    jne     .unclosed
    push    rax
    call    lex_next
    pop     rax
    ret
.unclosed:
    mov     rdi, [tok_pos]
    call    err_unclosed
.zero:
    xor     eax, eax
    ret

; rdi = name slot, rsi = its position, and the current token is "(".
; rbx = that position, r12 = the slot, r13 = the argument chain, r14 = its
; last link, r15 = how many links there are
parse_call:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rsi
    mov     r12, rdi
    xor     r13, r13
    xor     r14, r14
    xor     r15, r15
    cmp     r12, BI_COUNT               ; only builtins are callable so far
    jae     .unknown
    call    lex_next
    cmp     qword [tok_kind], TK_RPAREN
    je      .close

.argument:
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, rax
    mov     rsi, rbx
    call    ast_arg
    test    rax, rax
    jz      .fail
    test    r14, r14
    jz      .first
    mov     [r14 + NODE_RHS], rax
    jmp     .linked
.first:
    mov     r13, rax
.linked:
    mov     r14, rax
    inc     r15
    cmp     r15, ARG_MAX
    ja      .too_many
    cmp     qword [tok_kind], TK_COMMA
    jne     .close
    call    lex_next
    jmp     .argument

.close:
    cmp     qword [tok_kind], TK_RPAREN
    jne     .unclosed
    call    lex_next
    test    r15, r15                    ; printf's format is not optional
    jz      .no_format
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r15
    mov     rcx, rbx
    call    ast_call
    jmp     .out

.unclosed:
    mov     rdi, [tok_pos]
    call    err_unclosed
    jmp     .fail
.too_many:
    mov     rdi, rbx
    call    err_toomanyargs
    jmp     .fail
.no_format:
    mov     rdi, rbx
    call    err_needargs
    jmp     .fail
.unknown:
    mov     rdi, rbx
    call    err_unknownfn
.fail:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
parse_silent:
    resq    1
