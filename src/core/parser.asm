; SPDX-License-Identifier: MIT
;
; Recursive descent over the lexer's one-token lookahead.
;
; expression := unary ( binop unary )*     folded left, no precedence
; unary      := ("-" | "+")* primary
; primary    := NUM | "(" expression ")"
;
; Structure only: every value is produced by op.asm. Each rule returns its
; result in rax; on failure it records an error and returns, and callers
; re-check err_code and unwind the same way.

%include "tsafoshi.inc"

    global  parse_expression

    extern  lex_next
    extern  tok_kind
    extern  tok_val
    extern  tok_pos
    extern  op_apply
    extern  op_neg
    extern  err_code
    extern  err_expected
    extern  err_unclosed

    section .text

; -> rax.  rbx = accumulator, r12 = operator kind, r13 = its column
parse_expression:
    push    rbx
    push    r12
    push    r13
    call    parse_unary
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax

.next:
    mov     rax, [tok_kind]
    cmp     rax, TK_OP_FIRST
    jb      .done
    cmp     rax, TK_OP_LAST
    ja      .done

    mov     r12, rax
    mov     r13, [tok_pos]
    call    lex_next
    call    parse_unary
    cmp     qword [err_code], 0
    jne     .fail

    mov     rsi, rax
    mov     rdi, rbx
    mov     rdx, r12
    mov     rcx, r13
    call    op_apply
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax
    jmp     .next

.fail:
    xor     eax, eax
    jmp     .out
.done:
    mov     rax, rbx
.out:
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
    call    lex_next
    jmp     parse_unary
.negate:
    call    lex_next
    call    parse_unary
    mov     rdi, rax
    jmp     op_neg                      ; harmless if an error already fired

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
    push    qword [tok_val]
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
