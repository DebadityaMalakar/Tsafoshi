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

%endif
