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

; AST node layout. Five cells; see "The 64-bit cell rule". NODE_VAL holds the
; literal for NT_NUM and the operator's token kind otherwise, and NT_UNARY
; keeps its single operand in NODE_LHS.
NODE_KIND           equ 0
NODE_VAL            equ CELL
NODE_LHS            equ CELL * 2
NODE_RHS            equ CELL * 3
NODE_POS            equ CELL * 4
NODE_SIZE           equ CELL * 5

AST_CAP             equ 4096            ; nodes per line, then "too complex"

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
OP_COUNT            equ 8

CODE_CAP            equ 65536           ; bytes of bytecode per line
VM_STACK_CAP        equ 1024            ; cells on the operand stack

%endif
