; SPDX-License-Identifier: MIT
;
; Recursive descent with precedence climbing, over the lexer's one-token
; lookahead. The parser produces a tree and never a value:
;
; expression := binary(PREC_LOWEST)
; binary(p)  := unary ( binop(q >= p) binary(q + 1) )*
; unary      := ("-" | "+")* primary
; primary    := NUM | "(" expression ")"
;
; One loop covers every binary level. Adding a level means adding tokens and a
; row to the table in op.asm; nothing here changes. The "q + 1" on the
; recursive call is what makes operators left-associative: an operator of equal
; strength does not bind into the right operand, so it falls out to the loop
; and folds leftward instead. mode.asm supplies both the table and that bump,
; so switching convention changes no code here.
;
; Each rule returns a node in rax; on failure it records an error and returns
; zero, and callers re-check err_code and unwind the same way.

%include "tsafoshi.inc"

    global  parse_expression

    extern  lex_next
    extern  tok_kind
    extern  tok_val
    extern  tok_pos
    extern  mode_prec
    extern  mode_bump
    extern  ast_num
    extern  ast_unary
    extern  ast_binary
    extern  err_code
    extern  err_expected
    extern  err_unclosed

    section .text

; -> rax
parse_expression:
    mov     edi, PREC_LOWEST
    ; fall through

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
