; SPDX-License-Identifier: MIT
;
; Recursive descent with precedence climbing, over the lexer's one-token
; lookahead. The parser produces a tree and never a value:
;
; line       := ( definition | statement )*
; definition := "int" IDENT "(" params ")" block
; params     := "void" | <nothing> | "int" IDENT ( "," "int" IDENT )*
; statement  := ";"
; | "{" statement* "}"
; | "int" declarator ( "," declarator )* ";"
; | "if" "(" expression ")" statement ( "else" statement )?
; | "while" "(" expression ")" statement
; | "do" statement "while" "(" expression ")" ";"
; | "for" "(" for-init ";" expression? ";" expression? ")" statement
; | "break" ";"
; | "continue" ";"
; | expression ";"
; declarator := IDENT ( "=" expression )?
; for-init   := "int" declarator ( "," declarator )* | expression | <nothing>
; expression := binary(PREC_LOWEST) ( "=" expression )?
; binary(p)  := unary ( binop(q >= p) binary(q + bump) )*
; unary      := ( "-" | "+" | "!" | "~" )* primary
; primary    := NUM | STRING | IDENT | call | "(" expression ")"
; call       := IDENT "(" ( expression ( "," expression )* )? ")"
;
; One loop covers every binary level. Adding a level means adding tokens and
; widening the row in mode.asm; nothing here changes. The "q + bump" on the
; recursive call is what decides associativity: with the bump at 1 an operator
; of equal strength does not bind into the right operand, so it falls out to
; the loop and folds leftward. mode.asm supplies both the table and the bump,
; so switching convention changes no code here.
;
; Two operators are not in that table's gift. Assignment is below everything
; else, folds rightward, and needs its left side to be a variable rather than
; merely a value -- so it is a rule of its own, and the check happens after the
; left side is parsed rather than by looking ahead. And "&&" and "||" do carry
; a precedence, but they may not become NT_BINARY: a binary node evaluates both
; operands, which is the one thing short-circuiting forbids.
;
; This is also where a name stops being a name. scope.asm turns an identifier
; into the storage slot it currently denotes, once, here -- so the tree carries
; slots, both engines index them, and shadowing is entirely a parse-time fact.
; Since stage 2.3 that answer has two halves, because a slot inside a function
; is a frame offset and outside one is a global cell, and the node carries
; which.
;
; A function is registered in func.asm before its body is parsed, which is what
; lets the body call it. The definition itself compiles to nothing at all: it
; leaves an empty statement behind, and the real work -- turning the body into
; code -- is done afterwards by whoever asked for the parse, because the parser
; still does not know what a code buffer is.
;
; Each rule returns a node in rax; on failure it records an error and returns
; zero, and callers re-check err_code and unwind the same way.

%include "tsafoshi.inc"

    global  parse_line
    global  parse_expression
    global  parse_silent
    global  parse_value
    global  parse_defined
    global  parse_defined_count
    global  parse_type

    extern  lex_next
    extern  tok_kind
    extern  tok_val
    extern  tok_pos
    extern  tok_type
    extern  mode_prec
    extern  mode_bump
    extern  ast_num
    extern  ast_unary
    extern  ast_binary
    extern  ast_logical
    extern  ast_var
    extern  ast_assign
    extern  ast_str
    extern  ast_call
    extern  ast_arg
    extern  ast_seq
    extern  ast_expr
    extern  ast_decl
    extern  ast_if
    extern  ast_loop
    extern  ast_leaf
    extern  ast_return
    extern  ast_invoke
    extern  ast_conv
    extern  ast_typed
    extern  type_build
    extern  type_size
    extern  type_promote
    extern  type_common
    extern  func_type
    extern  func_param
    extern  func_set_param
    extern  builtin_type
    extern  builtin_param
    extern  func_declare
    extern  func_find
    extern  func_arity
    extern  builtin_arity
    extern  func_set_body
    extern  func_set_frame
    extern  scope_enter_function
    extern  scope_leave_function
    extern  scope_in_function
    extern  scope_push
    extern  scope_pop
    extern  scope_declare
    extern  scope_lookup
    extern  err_code
    extern  err_expected
    extern  err_unclosed
    extern  err_notlvalue
    extern  err_builtin
    extern  err_unknownfn
    extern  err_toomanyargs
    extern  err_needargs
    extern  err_expectedsemi
    extern  err_expectedparen
    extern  err_expectedname
    extern  err_expectedwhile
    extern  err_undeclared
    extern  err_declbody
    extern  err_notinloop
    extern  err_notinfunction
    extern  err_nestedfunction
    extern  err_expectedbrace
    extern  err_expectedtype
    extern  err_argcount
    extern  err_toomanyfuncs
    extern  err_badtype
    extern  err_voidvalue
    extern  src_buf

; What a statement is allowed to be, where it appears.
ST_TAIL             equ 1               ; a bare final expression may end it
ST_DECL             equ 2               ; a declaration is allowed here
ST_TOP              equ 4               ; and so is a function definition

; A bit set on the callee while a call is being gathered, to remember that it
; resolved to a user function rather than a builtin. It is above every function
; id there can be, so it cannot collide with one.
FN_TAG              equ 1 << 20

    section .text

; The whole submission -> rax = the statement list, which every engine runs for
; effect only. If the last thing on the line was an expression with no
; semicolon after it, that expression is left in parse_value instead and
; parse_silent is cleared: the prompt has something to echo.
;
; Which is exactly the C distinction between a statement and the expression
; inside it, and the reason "n = n + 1;" prints nothing while "n" prints "= 2".
;
; rbx = the head of the list, r12 = its last link
parse_line:
    push    rbx
    push    r12
    mov     qword [parse_silent], 1
    mov     qword [parse_value], 0
    mov     qword [loop_depth], 0
    mov     qword [func_depth], 0
    mov     qword [parse_defined_count], 0
    xor     rbx, rbx
    xor     r12, r12

.next:
    cmp     qword [tok_kind], TK_EOF
    je      .done
    mov     edi, ST_TAIL | ST_DECL | ST_TOP
    call    parse_statement
    cmp     qword [err_code], 0
    jne     .fail
    test    rax, rax
    jz      .done                       ; the tail expression ended the line

    mov     rdi, rax
    mov     rsi, rbx
    mov     rdx, r12
    call    list_append
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax
    mov     r12, rdx
    jmp     .next

.done:
    mov     rax, rbx
    jmp     .out
.fail:
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; rdi = the statement, rsi = the head so far, rdx = the last link so far
; -> rax = the head, rdx = the new last link. One NT_SEQ per statement, chained
; through NODE_RHS, so a list costs a node a statement and nothing to walk.
list_append:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rsi
    mov     r12, rdx
    mov     r13, [rdi + NODE_POS]
    mov     rsi, 0
    mov     rdx, r13
    call    ast_seq
    test    rax, rax
    jz      .out
    test    r12, r12
    jz      .first
    mov     [r12 + NODE_RHS], rax
    mov     rdx, rax
    mov     rax, rbx
    jmp     .out
.first:
    mov     rdx, rax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = ST_ flags -> rax = a statement node, or zero. Zero means either that
; an error was recorded, or -- with ST_TAIL, and only then -- that the line
; ended in a bare expression, which is now in parse_value.
parse_statement:
    push    rbx
    mov     rbx, rdi
    mov     rax, [tok_kind]

    cmp     rax, TK_SEMI
    je      .empty
    cmp     rax, TK_LBRACE
    je      .block
    cmp     rax, TK_SPEC_FIRST          ; every declaration begins with one
    jb      .not_declaration
    cmp     rax, TK_SPEC_LAST
    jbe     .declaration
.not_declaration:
    cmp     rax, TK_IF
    je      .if
    cmp     rax, TK_WHILE
    je      .while
    cmp     rax, TK_DO
    je      .do
    cmp     rax, TK_FOR
    je      .for
    cmp     rax, TK_BREAK
    je      .break
    cmp     rax, TK_CONTINUE
    je      .continue
    cmp     rax, TK_RETURN
    je      .return

; An expression, then either a semicolon -- in which case it is a statement and
; its value is thrown away -- or the end of the line, which is the one place a
; value survives.
    push    qword [tok_pos]
    call    parse_expression
    pop     rsi
    cmp     qword [err_code], 0
    jne     .fail
    cmp     qword [tok_kind], TK_SEMI
    je      .terminated
    test    rbx, ST_TAIL
    jz      .want_semi
    cmp     qword [tok_kind], TK_EOF
    jne     .want_semi
    mov     [parse_value], rax
    mov     qword [parse_silent], 0
    xor     eax, eax
    jmp     .out
.terminated:
    push    rax
    push    rsi
    call    lex_next
    pop     rsi
    pop     rdi
    call    ast_expr
    jmp     .out

.empty:
    mov     rsi, [tok_pos]
    push    rsi
    call    lex_next
    pop     rsi
    mov     edi, NT_EMPTY
    call    ast_leaf
    jmp     .out

.block:
    call    parse_block
    jmp     .out

.declaration:
    test    rbx, ST_DECL
    jz      .decl_body
    mov     rdi, rbx
    call    parse_declaration
    jmp     .out

.if:
    call    parse_if
    jmp     .out
.while:
    call    parse_while
    jmp     .out
.do:
    call    parse_do
    jmp     .out
.for:
    call    parse_for
    jmp     .out

.break:
    mov     edi, NT_BREAK
    jmp     .jump
.continue:
    mov     edi, NT_CONTINUE
.jump:
    cmp     qword [loop_depth], 0
    je      .not_in_loop
    mov     rsi, [tok_pos]
    push    rdi
    push    rsi
    call    lex_next
    call    expect_semi
    pop     rsi
    pop     rdi
    cmp     qword [err_code], 0
    jne     .fail
    call    ast_leaf
    jmp     .out

; "return" with no expression is "return 0", which is what falling off the end
; of a function already means. With one, the value becomes the function's
; return type here rather than at the call site, because this is the last place
; that knows what the function was declared to give back.
.return:
    cmp     qword [func_depth], 0
    je      .not_in_function
    mov     r8, [tok_pos]
    push    r8
    call    lex_next
    xor     eax, eax
    cmp     qword [tok_kind], TK_SEMI
    je      .return_build
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .return_failed
    mov     rdi, rax
    mov     rsi, [parse_ret_type]
    call    coerce
    cmp     qword [err_code], 0
    jne     .return_failed
.return_build:
    push    rax
    mov     rdi, rbx
    call    expect_end
    pop     rdi
    pop     rsi
    cmp     qword [err_code], 0
    jne     .fail
    call    ast_return
    jmp     .out
.return_failed:
    pop     r8
    jmp     .fail

.not_in_function:
    mov     rdi, [tok_pos]
    call    err_notinfunction
    jmp     .fail
; A declaration is not a statement in C's grammar wherever a body is expected,
; and for a good reason: there would be no block for it to be scoped to, so it
; would leak into the enclosing one.
.not_in_loop:
    mov     rdi, [tok_pos]
    call    err_notinloop
    jmp     .fail
.decl_body:
    mov     rdi, [tok_pos]
    call    err_declbody
    jmp     .fail
.want_semi:
    mov     rdi, [tok_pos]
    call    err_expectedsemi
.fail:
    xor     eax, eax
.out:
    pop     rbx
    ret

; "{" statement* "}", with a scope around it. That scope is the entire meaning
; of a block: the braces are otherwise just a list.
; rbx = the head, r12 = the last link, r13 = the opening brace
parse_block:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r13, [tok_pos]
    mov     rdi, r13
    call    scope_push
    test    rax, rax
    jz      .fail_nopop
    call    lex_next
    xor     rbx, rbx
    xor     r12, r12

.next:
    mov     rax, [tok_kind]
    cmp     rax, TK_RBRACE
    je      .close
    cmp     rax, TK_EOF
    je      .unclosed
    mov     edi, ST_DECL
    call    parse_statement
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, rax
    mov     rsi, rbx
    mov     rdx, r12
    call    list_append
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax
    mov     r12, rdx
    jmp     .next

.close:
    call    lex_next
    call    scope_pop
    test    rbx, rbx
    jz      .empty
    mov     rax, rbx
    jmp     .out
.empty:
    mov     edi, NT_EMPTY
    mov     rsi, r13
    call    ast_leaf
    jmp     .out

.unclosed:
    mov     rdi, r13
    call    err_unclosed
.fail:
    call    scope_pop
.fail_nopop:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = ST_ flags. Either a declarator list or, if a "(" follows the first
; name, a function definition -- which is the only place in the grammar that
; needs to see two tokens past a keyword, and it sees them by consuming the
; name it would have wanted anyway.
;
; rbx = the head, r12 = the last link, r13 = the flags, r14 = the first name,
; r15 = where it was written
parse_declaration:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13, rdi
    call    parse_type
    cmp     rax, -1
    je      .fail
    mov     [decl_type], rax
    cmp     qword [tok_kind], TK_IDENT
    jne     .want_name
    mov     r14, [tok_val]
    mov     r15, [tok_pos]
    call    lex_next
    cmp     qword [tok_kind], TK_LPAREN
    je      .definition

    xor     rbx, rbx
    xor     r12, r12
    mov     rdi, r14
    mov     rsi, r15
.declarator:
    mov     rdx, [decl_type]
    call    parse_declarator
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, rax
    mov     rsi, rbx
    mov     rdx, r12
    call    list_append
    cmp     qword [err_code], 0
    jne     .fail
    mov     rbx, rax
    mov     r12, rdx
    cmp     qword [tok_kind], TK_COMMA
    jne     .end
    call    lex_next
    cmp     qword [tok_kind], TK_IDENT
    jne     .want_name
    mov     rdi, [tok_val]
    mov     rsi, [tok_pos]
    push    rdi
    push    rsi
    call    lex_next
    pop     rsi
    pop     rdi
    jmp     .declarator
.end:
    mov     rdi, r13
    call    expect_end
    cmp     qword [err_code], 0
    jne     .fail
    mov     rax, rbx
    jmp     .out

.definition:
    test    r13, ST_TOP
    jz      .nested
    mov     rdi, r14
    mov     rsi, r15
    mov     rdx, [decl_type]
    call    parse_function
    jmp     .out

.want_name:
    mov     rdi, [tok_pos]
    call    err_expectedname
    jmp     .fail
.nested:
    mov     rdi, r15
    call    err_nestedfunction
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

; rdi = name slot, rsi = its position, rdx = the declared type, with the name
; already consumed. -> rax = NT_DECL.
;
; The name is declared before the initialiser is parsed, which is C99's rule
; and not an accident of order: in "int x = x;" the x on the right is the new
; one, and the standard says so.
;
; The initialiser becomes the variable's type here, which is where narrowing
; happens: "char c = 300" stores 44 because the conversion is in the tree, not
; because anything at run time noticed how wide a char is.
;
; rbx = the storage slot, r12 = the position, r13 = which storage it is,
; r14 = the declared type
parse_declarator:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r14, rdx
    cmp     r14, TY_VOID
    je      .void_variable
    call    scope_declare
    cmp     rax, -1
    je      .fail
    mov     rbx, rax
    mov     r13, rdx

    xor     esi, esi                    ; no initialiser reads as zero
    cmp     qword [tok_kind], TK_ASSIGN
    jne     .build
    call    lex_next
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, rax
    mov     rsi, r14
    call    coerce
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
.build:
    mov     rdi, rbx
    mov     rdx, r13
    mov     rcx, r12
    call    ast_decl
    mov     rdi, rax
    mov     rsi, r14
    call    ast_typed
    jmp     .out
.void_variable:
    mov     rdi, r12
    call    err_voidvalue
.fail:
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = name slot, rsi = its position, rdx = the return type, and the current
; token is "(". -> rax = NT_EMPTY: a definition does nothing when the line runs.
;
; The order here is the whole trick. Parameters are declared into the
; function's own scope first, so they land at frame offsets 0, 1, 2 ... which
; is exactly where a caller will put them and means the calling convention
; needs no table. Then the function is registered -- before the body is parsed,
; so a call inside the body finds it and recursion works. Only then is the body
; read.
;
; rbx = the position, r12 = the name, r13 = the arity, r14 = the function id,
; r15 = the return type
parse_function:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rsi
    mov     r12, rdi
    mov     r15, rdx
    xor     r13, r13
    mov     rdi, rbx
    call    scope_enter_function
    test    rax, rax
    jz      .fail_noleave
    call    lex_next

    cmp     qword [tok_kind], TK_RPAREN
    je      .params_done
    cmp     qword [tok_kind], TK_VOID   ; "(void)" is the empty list, and the
    jne     .parameter                  ; one place a lone void is a parameter
    call    lex_next
    cmp     qword [tok_kind], TK_RPAREN
    je      .params_done
    mov     rdi, [tok_pos]
    call    err_expectedname
    jmp     .fail

; A parameter is declared into the function's scope with its type, and the
; type is also recorded against the function, because a call site three lines
; later has to convert its arguments to something and this is the only record
; of what.
.parameter:
    mov     rax, [tok_kind]
    cmp     rax, TK_SPEC_FIRST
    jb      .want_type
    cmp     rax, TK_SPEC_LAST
    ja      .want_type
    call    parse_type
    cmp     rax, -1
    je      .fail
    cmp     rax, TY_VOID
    je      .want_type
    mov     [param_type], rax
    cmp     qword [tok_kind], TK_IDENT
    jne     .want_name
    mov     rdi, [tok_val]
    mov     rsi, [tok_pos]
    mov     rdx, [param_type]
    call    scope_declare
    cmp     rax, -1
    je      .fail
    cmp     r13, PARAM_MAX
    jae     .too_many
    lea     rcx, [param_types]
    mov     rdx, [param_type]
    mov     [rcx + r13 * CELL], rdx
    inc     r13
    call    lex_next
    cmp     qword [tok_kind], TK_COMMA
    jne     .params_done
    call    lex_next
    jmp     .parameter

.params_done:
    cmp     qword [tok_kind], TK_RPAREN
    jne     .want_close
    call    lex_next
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, rbx
    mov     rcx, r15
    call    func_declare
    cmp     rax, -1
    je      .fail
    mov     r14, rax
    call    record_params

    cmp     qword [tok_kind], TK_LBRACE
    jne     .want_brace
    inc     qword [func_depth]
    push    qword [parse_ret_type]
    mov     [parse_ret_type], r15
    call    parse_block
    pop     qword [parse_ret_type]
    dec     qword [func_depth]
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, r14
    mov     rsi, rax
    call    func_set_body

; The frame size is known only now, because it is the deepest the body ever
; got and not the number of names still in scope at the end of it.
    call    scope_leave_function
    mov     rdi, r14
    mov     rsi, rax
    call    func_frame_size
    mov     rdi, r14
    call    remember_defined
    cmp     qword [err_code], 0
    jne     .fail_noleave
    mov     edi, NT_EMPTY
    mov     rsi, rbx
    call    ast_leaf
    jmp     .out

.want_type:
    mov     rdi, [tok_pos]
    call    err_expectedtype
    jmp     .fail
.want_name:
    mov     rdi, [tok_pos]
    call    err_expectedname
    jmp     .fail
.want_close:
    mov     rdi, [tok_pos]
    call    err_unclosed
    jmp     .fail
.want_brace:
    mov     rdi, [tok_pos]
    call    err_expectedbrace
    jmp     .fail
.too_many:
    mov     rdi, rbx
    call    err_toomanyargs
.fail:
    call    scope_leave_function
.fail_noleave:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; The parameters are the first r13 bindings of the function's scope, in order,
; because they were declared first and into an empty one. So their types are
; read back from where they already are rather than collected a second time.
;
; rcx = which parameter
record_params:
    push    rbx
    xor     ebx, ebx
.next:
    cmp     rbx, r13
    jae     .done
    mov     rdi, r14
    mov     rsi, rbx
    lea     rcx, [param_types]
    mov     rdx, [rcx + rbx * CELL]
    call    func_set_param
    inc     rbx
    jmp     .next
.done:
    pop     rbx
    ret

; rdi = function id, rsi = frame size. A thin wrapper so parse_function reads
; as one sequence rather than as register shuffling.
func_frame_size:
    jmp     func_set_frame

; rdi = function id. The submission's list of new definitions, which is what
; the caller compiles once the parse has succeeded -- the parser itself still
; has no idea there is such a thing as a code buffer.
remember_defined:
    mov     rax, [parse_defined_count]
    cmp     rax, FUNC_CAP
    jae     .full
    lea     rcx, [parse_defined]
    mov     [rcx + rax * CELL], rdi
    inc     qword [parse_defined_count]
    ret
.full:
    lea     rdi, [src_buf]
    jmp     err_toomanyfuncs

; "if" "(" expression ")" statement ( "else" statement )?
; rbx = the position, r12 = the condition, r13 = the then branch
parse_if:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, [tok_pos]
    call    lex_next
    call    parse_paren_test
    cmp     qword [err_code], 0
    jne     .fail
    mov     r12, rax
    xor     edi, edi
    call    parse_statement
    cmp     qword [err_code], 0
    jne     .fail
    mov     r13, rax

    xor     edx, edx                    ; the else branch, if there is one
    cmp     qword [tok_kind], TK_ELSE
    jne     .build
    call    lex_next
    xor     edi, edi
    call    parse_statement
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdx, rax
.build:
    mov     rdi, r12
    mov     rsi, r13
    mov     rcx, rbx
    call    ast_if
    jmp     .out
.fail:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; "while" "(" expression ")" statement
; rbx = the position, r12 = the condition
parse_while:
    push    rbx
    push    r12
    mov     rbx, [tok_pos]
    call    lex_next
    call    parse_paren_test
    cmp     qword [err_code], 0
    jne     .fail
    mov     r12, rax
    xor     edi, edi
    call    parse_body
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdx, rax
    mov     edi, NT_WHILE
    mov     rsi, r12
    xor     ecx, ecx
    mov     r8, rbx
    call    ast_loop
    jmp     .out
.fail:
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; "do" statement "while" "(" expression ")" ";"
; rbx = the position, r12 = the body
parse_do:
    push    rbx
    push    r12
    mov     rbx, [tok_pos]
    call    lex_next
    xor     edi, edi
    call    parse_body
    cmp     qword [err_code], 0
    jne     .fail
    mov     r12, rax
    cmp     qword [tok_kind], TK_WHILE
    jne     .want_while
    call    lex_next
    call    parse_paren_test
    cmp     qword [err_code], 0
    jne     .fail
    push    rax
    call    expect_semi
    pop     rsi
    cmp     qword [err_code], 0
    jne     .fail
    mov     edi, NT_DO
    mov     rdx, r12
    xor     ecx, ecx
    mov     r8, rbx
    call    ast_loop
    jmp     .out
.want_while:
    mov     rdi, [tok_pos]
    call    err_expectedwhile
.fail:
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; "for" "(" for-init ";" condition? ";" step? ")" statement
;
; The whole loop gets a scope of its own, because C99 puts the init clause's
; declaration in one: the i of "for (int i = 0; ...)" is gone afterwards. The
; init clause then becomes an ordinary statement in front of the loop, and the
; result is a two-element list -- so "for" needs no fourth slot in a node.
;
; rbx = the position, r12 = the init statement, r13 = the condition,
; r14 = the step
parse_for:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [tok_pos]
    mov     rdi, rbx
    call    scope_push
    test    rax, rax
    jz      .fail_nopop
    call    lex_next
    cmp     qword [tok_kind], TK_LPAREN
    jne     .want_paren
    call    lex_next

    xor     r12, r12                    ; the init clause
    cmp     qword [tok_kind], TK_SEMI
    je      .init_empty
    cmp     qword [tok_kind], TK_INT
    je      .init_decl
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, rax
    mov     rsi, rbx
    call    ast_expr
    mov     r12, rax
    call    expect_semi
    cmp     qword [err_code], 0
    jne     .fail
    jmp     .condition
.init_decl:
    xor     edi, edi                    ; here a ";" really is required
    call    parse_declaration           ; which it eats itself
    cmp     qword [err_code], 0
    jne     .fail
    mov     r12, rax
    jmp     .condition
.init_empty:
    call    lex_next

.condition:
    xor     r13, r13                    ; an absent condition is always true
    cmp     qword [tok_kind], TK_SEMI
    je      .cond_done
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     r13, rax
.cond_done:
    call    expect_semi
    cmp     qword [err_code], 0
    jne     .fail

    xor     r14, r14                    ; the step
    cmp     qword [tok_kind], TK_RPAREN
    je      .step_done
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, rax
    mov     rsi, rbx
    call    ast_expr
    mov     r14, rax
.step_done:
    cmp     qword [tok_kind], TK_RPAREN
    jne     .want_close
    call    lex_next

    xor     edi, edi
    call    parse_body
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdx, rax
    mov     edi, NT_FOR
    mov     rsi, r13
    mov     rcx, r14
    mov     r8, rbx
    call    ast_loop
    test    rax, rax
    jz      .fail
    test    r12, r12
    jz      .no_init

; init first, then the loop: an ordinary two-statement list, inside the scope
; this rule pushed and is about to pop.
    mov     rdi, rax
    xor     esi, esi
    mov     rdx, rbx
    call    ast_seq
    test    rax, rax
    jz      .fail
    mov     rsi, rax
    mov     rdi, r12
    mov     rdx, rbx
    call    ast_seq
    test    rax, rax
    jz      .fail
.no_init:
    push    rax
    call    scope_pop
    pop     rax
    jmp     .out

.want_paren:
    mov     rdi, [tok_pos]
    call    err_expectedparen
    jmp     .fail
.want_close:
    mov     rdi, [tok_pos]
    call    err_unclosed
.fail:
    call    scope_pop
.fail_nopop:
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; A loop body, which is an ordinary statement parsed with the loop counter
; raised. That counter is the whole of what makes "break" legal: the parser is
; the only pass that knows which statements are inside a loop, so it is the one
; that can put the caret on the offending word.
parse_body:
    inc     qword [loop_depth]
    call    parse_statement
    dec     qword [loop_depth]
    ret

; "(" expression ")" -> rax, for the three rules whose test is parenthesised.
parse_paren_test:
    cmp     qword [tok_kind], TK_LPAREN
    jne     .want_paren
    call    lex_next
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    cmp     qword [tok_kind], TK_RPAREN
    jne     .want_close
    push    rax
    call    lex_next
    pop     rax
    ret
.want_paren:
    mov     rdi, [tok_pos]
    call    err_expectedparen
    jmp     .fail
.want_close:
    mov     rdi, [tok_pos]
    call    err_unclosed
.fail:
    xor     eax, eax
    ret

; Consumes a ";" or records that one was wanted.
expect_semi:
    xor     edi, edi
    ; fall through

; rdi = ST_ flags. A ";" ends a statement, and so does the end of a submission
; -- but only where a bare expression would also have been allowed to end it,
; which is to say at the prompt. Inside a block the semicolon is the grammar;
; on the last line typed at a prompt it is a formality, and "int n = 5" means
; what it obviously means.
expect_end:
    cmp     qword [tok_kind], TK_SEMI
    je      .semi
    test    rdi, ST_TAIL
    jz      .missing
    cmp     qword [tok_kind], TK_EOF
    je      .done
.missing:
    mov     rdi, [tok_pos]
    jmp     err_expectedsemi
.semi:
    jmp     lex_next
.done:
    ret

; -> rax.  rbx = the left side, r12 = its storage slot
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
    call    lex_next
    call    parse_expression            ; right-associative for free
    cmp     qword [err_code], 0
    jne     .fail

; An assignment's value is the value stored, not the value written -- so with
; "char c" the expression "c = 300" is 44, and the conversion that makes that
; true is one node in front of the store rather than a rule at run time.
    mov     rdi, rax
    mov     rsi, [rbx + NODE_TYPE]
    call    coerce
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    mov     rdi, r12
    mov     rdx, [rbx + NODE_RHS]       ; global cell or frame offset
    mov     rcx, [rbx + NODE_POS]
    call    ast_assign
    mov     rdi, rax
    mov     rsi, [rbx + NODE_TYPE]
    call    ast_typed
    jmp     .out

.not_lvalue:
    mov     rdi, [rbx + NODE_POS]
    call    err_notlvalue
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

    mov     rsi, rax
    mov     rdi, rbx
    mov     rdx, r13
    mov     rcx, r14
    cmp     r13, TK_ANDAND              ; these two must not evaluate both
    jae     .short_circuit
    call    build_binary
    jmp     .built
.short_circuit:
    call    build_logical
.built:
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

; Unary plus produces no node at all; the other three do, and all of them
; nest, so "!!x" and "- -x" both parse.
;
; "-" and "~" promote their operand and answer that type; "!" answers int
; whatever it was given, because a truth value is an int and nothing else.
parse_unary:
    mov     rax, [tok_kind]
    cmp     rax, TK_MINUS
    je      .prefix
    cmp     rax, TK_BANG
    je      .prefix
    cmp     rax, TK_TILDE
    je      .prefix
    cmp     rax, TK_PLUS
    je      .plus
    jmp     parse_primary
.plus:
    call    lex_next                    ; unary plus has no effect, and no node
    jmp     parse_unary
.prefix:
    push    rax
    push    qword [tok_pos]
    call    lex_next
    call    parse_unary
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    pop     rdx
    pop     rdi
    jmp     build_unary
.fail:
    pop     rdx
    pop     rdi
    xor     eax, eax
    ret

parse_primary:
    mov     rax, [tok_kind]
    cmp     rax, TK_NUM
    je      .number
    cmp     rax, TK_SIZEOF
    je      .sizeof
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
    mov     rdi, rax
    mov     rsi, [tok_type]             ; the suffix, or the width it needed
    call    ast_typed
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
    mov     rdi, rax
    mov     esi, TY_LONG                ; an address, until pointers exist
    call    ast_typed
    test    rax, rax
    jz      .zero
    push    rax
    call    lex_next
    pop     rax
    ret

; A name is a variable unless a "(" follows it, which is the only lookahead
; past one token anywhere in the parser -- and it is one token of it.
;
; This is where an identifier stops being one. Whatever scope says it means
; right now is baked into the node; nothing downstream can ask again.
.ident:
    push    qword [tok_val]
    push    qword [tok_pos]
    call    lex_next
    cmp     qword [tok_kind], TK_LPAREN
    je      .call
    pop     rsi
    pop     rdi
    cmp     rdi, BI_COUNT               ; printf is a name, not a variable
    jb      .builtin
    push    rsi
    call    scope_lookup                ; slot, storage kind, declared type
    pop     rsi
    cmp     rax, -1
    je      .undeclared
    push    rcx
    mov     rdi, rax
    xchg    rsi, rdx                    ; rsi = the kind, rdx = the position
    call    ast_var
    pop     rsi
    mov     rdi, rax
    jmp     ast_typed
.call:
    pop     rsi
    pop     rdi
    jmp     parse_call
.builtin:
    mov     rdi, rsi
    call    err_builtin
    xor     eax, eax
    ret
.undeclared:
    mov     rdi, rsi
    call    err_undeclared
    xor     eax, eax
    ret

; A "(" is either a grouping or a cast, and the token after it says which --
; the second and last place the parser needs to see past one token, and like
; the first it sees it by consuming a token it would have wanted anyway.
.paren:
    call    lex_next
    mov     rax, [tok_kind]
    cmp     rax, TK_SPEC_FIRST
    jb      .grouping
    cmp     rax, TK_SPEC_LAST
    ja      .grouping

.cast:
    push    qword [tok_pos]
    call    parse_type
    cmp     rax, -1
    je      .cast_failed
    push    rax
    cmp     qword [tok_kind], TK_RPAREN
    jne     .cast_unclosed
    call    lex_next
    call    parse_unary                 ; binds tighter than any binary operator
    cmp     qword [err_code], 0
    jne     .cast_dropped
    pop     rsi
    pop     rdx
    mov     rdi, rax
    jmp     coerce
.cast_unclosed:
    pop     rax
.cast_failed:
    pop     rdi
    call    err_unclosed
    xor     eax, eax
    ret
.cast_dropped:
    pop     rsi
    pop     rdx
    xor     eax, eax
    ret

.grouping:
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .zero
    cmp     qword [tok_kind], TK_RPAREN
    jne     .unclosed
    push    rax
    call    lex_next
    pop     rax
    ret

; "sizeof (type)", "sizeof (expression)" and "sizeof expression", all folded
; here into a constant. The operand of the last two is parsed and then dropped:
; only its type was ever wanted, and C99 says it is not evaluated.
.sizeof:
    push    qword [tok_pos]
    call    lex_next
    cmp     qword [tok_kind], TK_LPAREN
    jne     .sizeof_bare
    call    lex_next
    mov     rax, [tok_kind]
    cmp     rax, TK_SPEC_FIRST
    jb      .sizeof_paren
    cmp     rax, TK_SPEC_LAST
    ja      .sizeof_paren
    call    parse_type
    cmp     rax, -1
    je      .sizeof_failed
    push    rax
    cmp     qword [tok_kind], TK_RPAREN
    jne     .sizeof_unclosed
    call    lex_next
    pop     rdi
    jmp     .sizeof_done
.sizeof_paren:
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .sizeof_failed
    push    qword [rax + NODE_TYPE]
    cmp     qword [tok_kind], TK_RPAREN
    jne     .sizeof_unclosed
    call    lex_next
    pop     rdi
    jmp     .sizeof_done
.sizeof_bare:
    call    parse_unary
    cmp     qword [err_code], 0
    jne     .sizeof_failed
    mov     rdi, [rax + NODE_TYPE]
.sizeof_done:
    call    type_size
    pop     rsi
    mov     rdi, rax
    call    ast_num
    mov     rdi, rax
    mov     esi, TY_ULONG               ; which is what size_t is here
    jmp     ast_typed
.sizeof_unclosed:
    pop     rax
.sizeof_failed:
    pop     rdi
    call    err_unclosed
    xor     eax, eax
    ret

.unclosed:
    mov     rdi, [tok_pos]
    call    err_unclosed
.zero:
    xor     eax, eax
    ret

; rdi = name slot, rsi = its position, and the current token is "(".
;
; Both kinds of call are gathered the same way and differ only in what they
; become: a builtin is a routine inside this binary, a user function is a frame
; and a jump. The arguments are collected before either is decided, because the
; argument list is the part of a call that has nothing to do with the callee.
;
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
    cmp     r12, BI_COUNT               ; a keyword is not callable
    jb      .not_builtin
    mov     rdi, r12
    call    func_find
    cmp     rax, -1
    je      .unknown
    mov     r12, rax
    or      r12, FN_TAG                 ; remember which kind this became
.not_builtin:
    call    lex_next
    cmp     qword [tok_kind], TK_RPAREN
    je      .close

.argument:
    call    parse_expression
    cmp     qword [err_code], 0
    jne     .fail
    mov     [arg_node], rax
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r15
    call    arg_type
    mov     rsi, rax
    mov     rdi, [arg_node]
    call    coerce
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
    test    r12, FN_TAG
    jnz     .invoke

; A builtin knows its own arity, so a call that disagrees is caught here too.
; printf is the one that cannot: it takes a format and then whatever the format
; asks for, so all that can be insisted on is that the format is there.
    mov     rdi, r12
    call    builtin_arity
    cmp     rax, BI_VARIADIC
    je      .variadic
    cmp     rax, r15
    jne     .wrong_count
    jmp     .builtin_go
.variadic:
    test    r15, r15
    jz      .no_format
.builtin_go:
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r15
    mov     rcx, rbx
    call    ast_call
    push    rax
    mov     rdi, r12
    call    builtin_type
    mov     rsi, rax
    pop     rdi
    call    ast_typed
    jmp     .out

; A user function knows how many arguments it takes, so a call that disagrees
; is caught here rather than by the frame being the wrong shape at run time.
.invoke:
    and     r12, ~FN_TAG
    mov     rdi, r12
    call    func_arity
    cmp     rax, r15
    jne     .wrong_count
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r15
    mov     rcx, rbx
    call    ast_invoke
    push    rax
    mov     rdi, r12
    call    func_type
    mov     rsi, rax
    pop     rdi
    call    ast_typed
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
.wrong_count:
    mov     rdi, rbx
    call    err_argcount
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
; Types, and the four places the parser has to think about them.
;
; All of it happens here and none of it happens later. By the time a tree
; leaves this file every conversion C99 asks for is a node in it and every
; operator has been told whether it is the signed one, so both engines can run
; the tree without knowing what a type is. That is the same trick scope.asm
; plays with names, for the same reason.

; -> rax = the type the specifier keywords spell, or -1 with the error already
; recorded. The current token is the first of them and they are all consumed.
;
; The words may come in any order, so they are gathered into a set and judged
; once at the end -- which is specifier.asm's whole job and not this file's.
;
; rbx = the set so far, r12 = how many "long"s, r13 = where it started
parse_type:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r13, [tok_pos]
    xor     ebx, ebx
    xor     r12d, r12d
.more:
    mov     rax, [tok_kind]
    cmp     rax, TK_SPEC_FIRST
    jb      .end
    cmp     rax, TK_SPEC_LAST
    ja      .end
    sub     rax, TK_SPEC_FIRST
    lea     rcx, [spec_bits]
    movzx   edx, byte [rcx + rax]
    cmp     edx, SP_LONG                ; "long long" is two of them, not one
    jne     .set
    inc     r12
.set:
    or      rbx, rdx
    call    lex_next
    jmp     .more

.end:
    test    rbx, rbx
    jz      .none
    mov     rdi, rbx
    mov     rsi, r12
    call    type_build
    cmp     rax, -1
    je      .bad
    jmp     .out
.none:
    mov     rdi, r13
    call    err_expectedtype
    mov     rax, -1
    jmp     .out
.bad:
    mov     rdi, r13
    call    err_badtype
    mov     rax, -1
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = an expression node, rsi = the type it has to have -> rax = the node,
; wrapped in a conversion if it is not already of that type.
;
; The one door every conversion goes through -- an initialiser, an assignment,
; an argument, a return value, a cast, and both operands of every arithmetic
; operator. It is also therefore the one place that can notice a void being
; used as a value, so that is where the complaint lives.
coerce:
    test    rdi, rdi
    jz      .none
    mov     rax, [rdi + NODE_TYPE]
    cmp     rax, rsi
    je      .already
    cmp     rax, TY_VOID
    je      .void
    mov     rdx, [rdi + NODE_POS]
    jmp     ast_conv
.already:
    mov     rax, rdi
    ret
.void:
    mov     rdi, [rdi + NODE_POS]
    call    err_voidvalue
.none:
    xor     eax, eax
    ret

; rdi = a node that has just produced an arithmetic result, rsi = its type
; -> rax = the node, narrowed if that type is narrower than a cell.
;
; int arithmetic wraps at 32 bits, because that is what an int does. The cell
; is 64 bits wide either way; this is what keeps the value in it honest about
; which type it is.
;
; rbx = the node, r12 = the type
wrap_result:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    test    rbx, rbx
    jz      .as_is
    mov     rdi, r12
    call    type_size
    cmp     rax, CELL
    jae     .as_is
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [rbx + NODE_POS]
    call    ast_conv
    jmp     .out
.as_is:
    mov     rax, rbx
.out:
    pop     r12
    pop     rbx
    ret

; rdi = lhs, rsi = rhs, rdx = operator token, rcx = position -> rax.
;
; The usual arithmetic conversions, applied where they belong: both operands
; become the common type, the operator is built, and the answer is that type --
; except for a comparison, which answers int whatever it compared.
;
; rbx = lhs, r12 = rhs, r13 = the operator, r14 = the position, r15 = the type
; both operands ended up with
build_binary:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    test    rbx, rbx
    jz      .fail
    test    r12, r12
    jz      .fail

    cmp     r13, TK_SHL
    je      .shift
    cmp     r13, TK_SHR
    je      .shift

    mov     rdi, [rbx + NODE_TYPE]
    mov     rsi, [r12 + NODE_TYPE]
    call    type_common
    mov     r15, rax
    mov     rdi, rbx
    mov     rsi, r15
    call    coerce
    mov     rbx, rax
    mov     rdi, r12
    mov     rsi, r15
    call    coerce
    mov     r12, rax
    jmp     .assemble

; A shift is the one binary operator with no common type. C99 promotes each
; operand on its own and the result is the left one's type -- shifting is not
; symmetric, and pretending it were would make "1L << n" depend on what n
; happens to be declared as.
.shift:
    mov     rdi, [rbx + NODE_TYPE]
    call    type_promote
    mov     r15, rax
    mov     rdi, rbx
    mov     rsi, r15
    call    coerce
    mov     rbx, rax
    mov     rdi, [r12 + NODE_TYPE]
    call    type_promote
    mov     rsi, rax
    mov     rdi, r12
    call    coerce
    mov     r12, rax

.assemble:
    cmp     qword [err_code], 0
    jne     .fail
    mov     rdi, r13
    mov     rsi, rbx
    mov     rdx, r12
    mov     rcx, r14
    call    ast_binary
    test    rax, rax
    jz      .fail

    cmp     r13, TK_LT                  ; the six comparisons answer int
    jb      .arithmetic
    cmp     r13, TK_NE
    ja      .arithmetic
    mov     rdi, rax
    mov     esi, TY_INT
    call    ast_typed
    jmp     .out

.arithmetic:
    mov     rdi, rax
    mov     rsi, r15
    call    ast_typed
    mov     rdi, rax
    mov     rsi, r15
    call    wrap_result
    jmp     .out
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

; rdi = lhs, rsi = rhs, rdx = the "&&" or "||", rcx = position -> rax.
;
; No conversions and no common type: both operands are tested against zero and
; nothing else is done to them, so the only question worth asking is whether
; either of them is a void, and the answer is always int.
build_logical:
    test    rdi, rdi
    jz      .fail
    test    rsi, rsi
    jz      .fail
    cmp     qword [rdi + NODE_TYPE], TY_VOID
    je      .void
    cmp     qword [rsi + NODE_TYPE], TY_VOID
    je      .void
    mov     r8, rdi
    mov     rdi, rdx                    ; ast_logical wants the operator first
    mov     rdx, rsi
    mov     rsi, r8
    call    ast_logical
    test    rax, rax
    jz      .fail
    mov     rdi, rax
    mov     esi, TY_INT
    jmp     ast_typed
.void:
    mov     rdi, rcx
    call    err_voidvalue
.fail:
    xor     eax, eax
    ret

; rdi = operator token, rsi = operand, rdx = position -> rax
;
; rbx = the operand, r12 = the operator, r13 = the position, r14 = the type
build_unary:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rsi
    mov     r12, rdi
    mov     r13, rdx
    test    rbx, rbx
    jz      .fail

    cmp     r12, TK_BANG
    je      .logical
    mov     rdi, [rbx + NODE_TYPE]
    call    type_promote
    mov     r14, rax
    mov     rdi, rbx
    mov     rsi, r14
    call    coerce
    cmp     qword [err_code], 0
    jne     .fail
    mov     rsi, rax
    mov     rdi, r12
    mov     rdx, r13
    call    ast_unary
    mov     rdi, rax
    mov     rsi, r14
    call    ast_typed
    mov     rdi, rax
    mov     rsi, r14
    call    wrap_result
    jmp     .out

; "!" is a test, so its operand keeps whatever type it had and its answer is
; an int -- the one unary operator that converts nothing at all.
.logical:
    mov     rdi, [rbx + NODE_TYPE]
    cmp     rdi, TY_VOID
    je      .void
    mov     rsi, rbx
    mov     rdi, r12
    mov     rdx, r13
    call    ast_unary
    mov     rdi, rax
    mov     esi, TY_INT
    call    ast_typed
    jmp     .out
.void:
    mov     rdi, r13
    call    err_voidvalue
.fail:
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = the argument node, rsi = the callee, rdx = which argument
; -> rax = the type that argument has to be converted to.
;
; A user function and a fixed-arity builtin both declared what they take. The
; variadic one cannot, so everything past its format gets the default argument
; promotions instead -- which is exactly what C does, and the reason printf can
; be handed a char and still find an int.
arg_type:
    cmp     rdx, PARAM_MAX
    jae     .anything
    test    rsi, FN_TAG
    jnz     .user
    cmp     rsi, BI_PRINTF
    jne     .fixed
    test    rdx, rdx
    jz      .fixed                      ; argument zero is the format
    mov     rdi, [rdi + NODE_TYPE]
    jmp     type_promote
.fixed:
    mov     rdi, rsi
    jmp     builtin_param
.user:
    mov     rdi, rsi
    and     rdi, ~FN_TAG
    mov     rsi, rdx
    jmp     func_param
.anything:
    mov     eax, TY_INT
    ret

; ---------------------------------------------------------------------------
    section .data

; Token kind minus TK_SPEC_FIRST -> the bit it contributes. The order is the
; one tsafoshi.inc numbers them in, and this table is what keeps the two lists
; from drifting apart.
spec_bits:
    db      SP_VOID                     ; TK_VOID
    db      SP_BOOL                     ; TK_BOOL
    db      SP_CHAR                     ; TK_CHAR
    db      SP_SHORT                    ; TK_SHORT
    db      SP_INT                      ; TK_INT
    db      SP_LONG                     ; TK_LONG
    db      SP_SIGNED                   ; TK_SIGNED
    db      SP_UNSIGNED                 ; TK_UNSIGNED

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
arg_node:
    resq    1
parse_silent:
    resq    1
parse_value:
    resq    1
parse_defined_count:
    resq    1
parse_defined:
    resq    FUNC_CAP
loop_depth:
    resq    1
func_depth:
    resq    1
parse_ret_type:
    resq    1
decl_type:
    resq    1
param_type:
    resq    1
param_types:
    resq    PARAM_MAX
