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

LINE_CAP            equ 1024
RD_CAP              equ 4096
NUM_CAP             equ 24
PROMPT_LEN          equ 10              ; width of "tsafoshi> ", for the caret

; Token kinds. The binary operators are contiguous so the parser can test the
; whole class with one range compare.
TK_EOF              equ 0
TK_NUM              equ 1
TK_PLUS             equ 2
TK_MINUS            equ 3
TK_STAR             equ 4
TK_SLASH            equ 5
TK_PERCENT          equ 6
TK_LPAREN           equ 7
TK_RPAREN           equ 8
TK_BAD              equ 9
TK_IDENT            equ 10
TK_STR              equ 11
TK_ASSIGN           equ 12
TK_COMMA            equ 13
TK_SEMI             equ 14

TK_OP_FIRST         equ TK_PLUS
TK_OP_LAST          equ TK_PERCENT

; Binding strength, higher binds tighter. The gaps are deliberate: these are
; the C99 levels, so shifts, comparisons and the bitwise operators drop into
; 5 .. 8 later without renumbering anything that already exists.
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

; AST node kinds.
NT_NUM              equ 0
NT_UNARY            equ 1
NT_BINARY           equ 2
NT_VAR              equ 3
NT_ASSIGN           equ 4
NT_STR              equ 5
NT_CALL             equ 6
NT_ARG              equ 7
NT_SEQ              equ 8

; AST node layout. Five cells; see "The 64-bit cell rule". The three pointer
; slots are reused rather than widened, so every node stays the same size:
;
; NT_NUM     VAL = the literal
; NT_UNARY   VAL = operator token, LHS = operand
; NT_BINARY  VAL = operator token, LHS/RHS = operands
; NT_VAR     VAL = name slot
; NT_ASSIGN  VAL = name slot, LHS = the value expression
; NT_STR     VAL = offset into the string arena
; NT_CALL    VAL = builtin id, LHS = argument chain, RHS = argument count
; NT_ARG     LHS = one argument, RHS = the next NT_ARG or zero
; NT_SEQ     LHS = one statement, RHS = the rest of the line
NODE_KIND           equ 0
NODE_VAL            equ CELL
NODE_LHS            equ CELL * 2
NODE_RHS            equ CELL * 3
NODE_POS            equ CELL * 4
NODE_SIZE           equ CELL * 5

AST_CAP             equ 4096            ; nodes per line, then "too complex"

; Identifiers. Names are interned once and never released, so a slot is stable
; for the whole session and a variable survives the line that created it.
NAME_CAP            equ 256             ; distinct identifiers per session
NAME_LEN            equ 32              ; bytes per name, NUL included

; Builtin functions occupy the first name slots, interned before any input is
; read, so recognising a call is a compare against a constant.
BI_PRINTF           equ 0
BI_COUNT            equ 1

ARG_MAX             equ 16              ; arguments in one call

; String literals. Interned like names and, like names, never released: a
; string's address has to outlive the line, because a variable can hold it.
STR_CAP             equ 8192            ; bytes of decoded text per session
STR_MAX             equ 256             ; distinct literals per session

; Bytecode. One byte of opcode, then whatever operand that opcode carries:
; PUSH an 8-byte immediate, DIV and MOD a 4-byte offset into the line so a
; division by zero can still put the caret in the right column.
;
; The binary opcodes are laid out in token order, so the compiler turns an
; operator token into its opcode with one subtract and one add rather than a
; table lookup.
OP_HALT             equ 0
OP_PUSH             equ 1
OP_ADD              equ 2
OP_SUB              equ 3
OP_MUL              equ 4
OP_DIV              equ 5
OP_MOD              equ 6
OP_NEG              equ 7
OP_POP              equ 8
OP_LOAD             equ 9               ; 4-byte name slot
OP_STORE            equ 10              ; 4-byte name slot, value stays on top
OP_STR              equ 11              ; 4-byte offset into the string arena
OP_PRINTF           equ 12              ; 4-byte count, then a 4-byte column
OP_COUNT            equ 13

CODE_CAP            equ 65536           ; bytes of bytecode per line
VM_STACK_CAP        equ 1024            ; cells on the operand stack

%endif
