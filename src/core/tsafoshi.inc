; SPDX-License-Identifier: MIT
;
; Shared constants. Included by every core module.

%ifndef TSAFOSHI_INC
%define TSAFOSHI_INC

    bits    64
    default rel                         ; win64 images load above 4 GiB

; One evaluation-stack slot. Every value on the VM stack occupies exactly this
; much, whatever its C type -- see "The 64-bit cell rule" in the README. Note
; this is the width of a *slot*, not of a C object: sizeof(int) stays 4.
CELL                equ 8

LINE_CAP            equ 1024            ; one physical line of input
SRC_CAP             equ 65536           ; every submission of the session
RD_CAP              equ 4096
NUM_CAP             equ 24
PROMPT_LEN          equ 10              ; width of both prompts, for the caret

; Token kinds. The operators are contiguous and in C99 precedence order, which
; buys two things: mode.asm indexes one row by (kind - TK_OP_FIRST), and the
; compiler turns an operator token into its opcode with a subtract and an add.
;
; The two short-circuiting operators sit at the end of that range. They carry a
; precedence like every other operator, but they are not values op.asm can
; produce -- both operands would have to be evaluated first, which is exactly
; what they forbid -- so the range op_apply covers stops short, at TK_VAL_LAST.
TK_EOF              equ 0
TK_NUM              equ 1

TK_STAR             equ 2
TK_SLASH            equ 3
TK_PERCENT          equ 4
TK_PLUS             equ 5
TK_MINUS            equ 6
TK_SHL              equ 7
TK_SHR              equ 8
TK_LT               equ 9
TK_GT               equ 10
TK_LE               equ 11
TK_GE               equ 12
TK_EQ               equ 13
TK_NE               equ 14
TK_AMP              equ 15
TK_CARET            equ 16
TK_PIPE             equ 17
TK_ANDAND           equ 18
TK_OROR             equ 19

TK_LPAREN           equ 20
TK_RPAREN           equ 21
TK_LBRACE           equ 22
TK_RBRACE           equ 23
TK_BANG             equ 24
TK_TILDE            equ 25
TK_ASSIGN           equ 26
TK_COMMA            equ 27
TK_SEMI             equ 28
TK_IDENT            equ 29
TK_STR              equ 30
TK_BAD              equ 31

; Keywords. A keyword is an identifier the lexer recognises by its interned
; slot: names_init puts them in the first slots, so the test is one compare
; against a constant and the token kind is that slot plus a base.
; The type specifiers are last and contiguous, so "does a declaration start
; here" is one range check rather than a list of compares -- which matters
; because that question is asked at the top of every statement.
TK_KW_FIRST         equ 32
TK_IF               equ 32
TK_ELSE             equ 33
TK_WHILE            equ 34
TK_DO               equ 35
TK_FOR              equ 36
TK_BREAK            equ 37
TK_CONTINUE         equ 38
TK_RETURN           equ 39
TK_SIZEOF           equ 40
TK_VOID             equ 41
TK_BOOL             equ 42
TK_CHAR             equ 43
TK_SHORT            equ 44
TK_INT              equ 45
TK_LONG             equ 46
TK_SIGNED           equ 47
TK_UNSIGNED         equ 48

TK_SPEC_FIRST       equ TK_VOID
TK_SPEC_LAST        equ TK_UNSIGNED

TK_OP_FIRST         equ TK_STAR         ; the whole precedence-carrying class
TK_OP_LAST          equ TK_OROR
TK_VAL_LAST         equ TK_PIPE         ; the part of it op.asm can evaluate

; Binding strength, higher binds tighter. These are the C99 levels; assignment
; sits below all of them and is a rule of its own in the parser.
PREC_LOGOR          equ 1
PREC_LOGAND         equ 2
PREC_BITOR          equ 3
PREC_BITXOR         equ 4
PREC_BITAND         equ 5
PREC_EQUALITY       equ 6
PREC_RELATIONAL     equ 7
PREC_SHIFT          equ 8
PREC_ADDITIVE       equ 9
PREC_MULTIPLICATIVE equ 10

PREC_LOWEST         equ PREC_LOGOR

; AST node kinds. The first nine produce a value; the rest are statements, and
; a statement leaves the operand stack exactly as it found it.
NT_NUM              equ 0
NT_UNARY            equ 1
NT_BINARY           equ 2
NT_VAR              equ 3
NT_ASSIGN           equ 4
NT_STR              equ 5
NT_CALL             equ 6
NT_ARG              equ 7
NT_LOGICAL          equ 8

NT_SEQ              equ 9
NT_EXPR             equ 10
NT_DECL             equ 11
NT_IF               equ 12
NT_WHILE            equ 13
NT_DO               equ 14
NT_FOR              equ 15
NT_BREAK            equ 16
NT_CONTINUE         equ 17
NT_EMPTY            equ 18
NT_RETURN           equ 19
NT_INVOKE           equ 20
NT_CONV             equ 21
NT_COUNT            equ 22

; AST node layout. Five cells; see "The 64-bit cell rule". The three pointer
; slots are reused rather than widened, so every node stays the same size:
;
; NT_NUM      VAL = the literal
; NT_UNARY    VAL = operator token, LHS = operand
; NT_BINARY   VAL = operator token, LHS/RHS = operands
; NT_VAR      VAL = storage slot
; NT_ASSIGN   VAL = storage slot, LHS = the value expression
; NT_STR      VAL = offset into the string arena
; NT_CALL     VAL = builtin id, LHS = argument chain, RHS = argument count
; NT_ARG      LHS = one argument, RHS = the next NT_ARG or zero
; NT_LOGICAL  VAL = the "&&" or "||" token, LHS/RHS = operands
;
; NT_SEQ      LHS = one statement, RHS = the rest of the list
; NT_EXPR     LHS = an expression run for its effect, its value discarded
; NT_DECL     VAL = storage slot, LHS = the initialiser or zero
; NT_IF       LHS = condition, RHS = the then branch, VAL = the else branch
; NT_WHILE    LHS = condition, RHS = body
; NT_DO       LHS = condition, RHS = body
; NT_FOR      LHS = condition or zero, RHS = body, VAL = the step or zero
; NT_BREAK  NT_CONTINUE  NT_EMPTY   carry nothing but a position
; NT_RETURN   LHS = the value expression or zero
; NT_INVOKE   VAL = function id, LHS = argument chain, RHS = argument count
; NT_CONV     VAL = the type to convert to, LHS = the value
;
; NT_VAR, NT_ASSIGN and NT_DECL keep one more thing in RHS: whether the slot
; in VAL is a global cell or an offset into the current call frame. It is the
; one bit of a variable's identity that survives the parser, because it is the
; one the engines cannot work out for themselves.
; And every expression node carries its type, because C decides what an
; operator means from the types of its operands and the parser is the only
; pass that still knows them. A statement's type slot is never read.
NODE_KIND           equ 0
NODE_VAL            equ CELL
NODE_LHS            equ CELL * 2
NODE_RHS            equ CELL * 3
NODE_POS            equ CELL * 4
NODE_TYPE           equ CELL * 5
NODE_SIZE           equ CELL * 6

AST_CAP             equ 16384           ; nodes at once, then "too complex"

; Identifiers. Names are interned once and never released, so a slot is stable
; for the whole session and a variable survives the line that created it.
NAME_CAP            equ 256             ; distinct identifiers per session
NAME_LEN            equ 32              ; bytes per name, NUL included

; Keywords and builtin functions occupy the first name slots, interned before
; any input is read, so recognising either is a compare against a constant.
KW_COUNT            equ 17              ; TK_IF .. TK_UNSIGNED

; The builtins. Each is a name the session cannot rebind and a routine inside
; this binary, and the table in builtin.asm gives every one of them the same
; shape -- an argument block, a count, a position -- so the two engines call
; all of them through one door. printf is the variadic one; the rest take a
; fixed number of arguments and the parser checks it.
BI_PRINTF           equ KW_COUNT
BI_ARGC             equ KW_COUNT + 1
BI_ARGV             equ KW_COUNT + 2
BI_EXIT             equ KW_COUNT + 3
BI_COUNT            equ KW_COUNT + 4    ; the first slot a user name can have

BI_FIRST            equ BI_PRINTF
BI_VARIADIC         equ -1              ; an arity that means "at least one"

ARG_MAX             equ 16              ; arguments in one call

; Variables. A storage slot is handed out by scope.asm at declaration and is
; what every engine indexes; the name behind it stops mattering after parsing.
VAR_CAP             equ 512             ; cells of global storage
SCOPE_CAP           equ 256             ; bindings visible at once
SCOPE_DEPTH         equ 32              ; nested blocks

; Where a variable lives. Globals are cells in one flat array and outlive
; everything; a local is an offset into the frame of the call that is running,
; so the same offset means a different cell on every recursion.
VAR_GLOBAL          equ 0
VAR_LOCAL           equ 1

; Where a session's source comes from. The command line decides this once,
; before anything is read, and the rest of the interpreter never asks again.
CLI_NONE            equ 0               ; nothing was named: a session
CLI_FILE            equ 1               ; a path
CLI_EVAL            equ 2               ; -e, one submission spelled inline
CLI_STDIN           equ 3               ; "-", or a pipe with no terminal

ARGV_PROG           equ 32              ; arguments a program can be given

; The integer types. A type is a small number and everything else about it --
; its width, whether it is signed, the name it prints under -- is a row in a
; table in types.asm. They are ordered by conversion rank, which is what makes
; "which of these two wins" a comparison rather than a matrix.
;
; The cell rule is unchanged and this is what makes it work: a cell is always
; 64 bits, and a value in one is always the value of its type extended to that
; width -- sign-extended if the type is signed, zero-extended if it is not. So
; the type says how to narrow on the way in, and nothing has to ask again on
; the way out.
TY_VOID             equ 0
TY_BOOL             equ 1
TY_CHAR             equ 2               ; plain char, signed on both targets
TY_SCHAR            equ 3
TY_UCHAR            equ 4
TY_SHORT            equ 5
TY_USHORT           equ 6
TY_INT              equ 7
TY_UINT             equ 8
TY_LONG             equ 9
TY_ULONG            equ 10
TY_COUNT            equ 11

; The type specifier keywords, as a set, so "unsigned long int" can be seen in
; any order and judged once at the end.
SP_VOID             equ 1
SP_BOOL             equ 2
SP_CHAR             equ 4
SP_SHORT            equ 8
SP_INT              equ 16
SP_LONG             equ 32
SP_SIGNED           equ 64
SP_UNSIGNED         equ 128

; Functions, and the managed C stack their locals live on.
FUNC_CAP            equ 128             ; functions per session
PARAM_MAX           equ ARG_MAX         ; a call cannot pass more than it takes
FRAME_CAP           equ 4096            ; cells of local storage, all frames
CALL_DEPTH          equ 256             ; nested calls, then "too much recursion"

; String literals. Interned like names and, like names, never released: a
; string's address has to outlive the line, because a variable can hold it.
STR_CAP             equ 8192            ; bytes of decoded text per session
STR_MAX             equ 256             ; distinct literals per session

; Bytecode. One byte of opcode, then whatever operand that opcode carries:
; PUSH an 8-byte immediate, a jump a 4-byte absolute offset into the stream,
; DIV and MOD a 4-byte offset into the source so a division by zero can still
; put the caret in the right column.
;
; OP_MUL .. OP_OR are laid out in token order, so the compiler turns an
; operator token into its opcode with one subtract and one add rather than a
; table lookup. The short-circuiting operators have no opcode: they are jumps.
OP_HALT             equ 0
OP_PUSH             equ 1               ; 8-byte immediate

OP_MUL              equ 2
OP_DIV              equ 3               ; 4-byte source column
OP_MOD              equ 4               ; 4-byte source column
OP_ADD              equ 5
OP_SUB              equ 6
OP_SHL              equ 7
OP_SHR              equ 8
OP_LT               equ 9
OP_GT               equ 10
OP_LE               equ 11
OP_GE               equ 12
OP_EQ               equ 13
OP_NE               equ 14
OP_AND              equ 15
OP_XOR              equ 16
OP_OR               equ 17

; Seven of the sixteen mean something different when their operands are
; unsigned, and only seven: addition, multiplication and the bitwise operators
; produce the same bits either way, and so does a left shift. These are the
; ones that do not, and they sit immediately after the signed block so that
; one contiguous range still covers every binary opcode.
OP_UDIV             equ 18              ; 4-byte source column
OP_UMOD             equ 19              ; 4-byte source column
OP_USHR             equ 20
OP_ULT              equ 21
OP_UGT              equ 22
OP_ULE              equ 23
OP_UGE              equ 24

OP_NEG              equ 25
OP_NOT              equ 26
OP_BNOT             equ 27
OP_POP              equ 28
OP_LOAD             equ 29              ; 4-byte storage slot
OP_STORE            equ 30              ; 4-byte storage slot, value stays
OP_STR              equ 31              ; 4-byte offset into the string arena
OP_BI               equ 32              ; 4-byte builtin, count, column
OP_JMP              equ 33              ; 4-byte target
OP_JZ               equ 34              ; pops, jumps if it was zero
OP_JNZ              equ 35              ; pops, jumps if it was not
OP_LOADL            equ 36              ; 4-byte frame offset
OP_STOREL           equ 37              ; 4-byte frame offset, value stays
OP_CALL             equ 38              ; 4-byte function id
OP_RET              equ 39              ; the value is on top of the stack
OP_CONV             equ 40              ; 4-byte type: narrow, then re-extend
OP_COUNT            equ 41

OP_BIN_FIRST        equ OP_MUL          ; mirrors TK_OP_FIRST .. TK_VAL_LAST
OP_BIN_LAST         equ OP_UGE          ; and then the unsigned seven

CODE_CAP            equ 65536           ; bytes of bytecode per line
VM_STACK_CAP        equ 1024            ; cells on the operand stack
LOOP_DEPTH          equ 32              ; nested loops the compiler tracks

; Non-local exit, for the tree walker. The VM does this with jumps; a
; recursive evaluator has to unwind instead, so ast_eval sets one of these and
; every statement rule tests it on the way back out.
FLOW_NORMAL         equ 0
FLOW_BREAK          equ 1
FLOW_CONTINUE       equ 2
FLOW_RETURN         equ 3

%endif
