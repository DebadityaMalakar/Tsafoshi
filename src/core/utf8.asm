; SPDX-License-Identifier: MIT
;
; UTF-8: one sequence in, one codepoint out, and how wide it looks.
;
; The interpreter deals in bytes from top to bottom and that is not changing.
; Source is bytes, string literals are bytes, printf writes bytes, and a file
; is read into a byte buffer at the offsets it had on disk. This file exists
; because two places need to know where one *character* ends and the next
; begins, and neither of them is the one you would guess:
;
; - an identifier containing an emoji has to be turned into an ASCII name,
; which means walking it a codepoint at a time (see shortcode.asm);
; - an error caret has to land under the right column, and a column is a
; thing on a screen rather than a byte in a buffer.
;
; Nothing else in the tree decodes UTF-8, and nothing else should have to.
;
; Invalid input never stalls the scan. A malformed lead byte, a truncated
; sequence or a bad continuation byte all come back as the single byte that
; was there, so the caller always advances and a corrupt file is a stream of
; strange identifiers rather than an infinite loop. That is the property worth
; having when somebody is deliberately trying to break the thing.

%include "tsafoshi.inc"

    global  utf8_decode
    global  utf8_width

    section .text

; rdi = bytes -> rax = the codepoint, rdx = how many bytes it took.
;
; Overlong encodings are decoded rather than rejected. They cannot occur in an
; identifier that means anything, they cannot escape into a string (strings do
; not come through here), and rejecting them would need a fourth rule for a
; case that only ever arrives on purpose.
utf8_decode:
    movzx   eax, byte [rdi]
    cmp     al, 0x80
    jb      .one

    mov     ecx, eax
    and     ecx, 0xE0
    cmp     ecx, 0xC0
    je      .two
    mov     ecx, eax
    and     ecx, 0xF0
    cmp     ecx, 0xE0
    je      .three
    mov     ecx, eax
    and     ecx, 0xF8
    cmp     ecx, 0xF0
    je      .four

; A continuation byte with nothing in front of it, or 0xFE / 0xFF, which are
; not UTF-8 at all.
.one:
    mov     edx, 1
    ret

.two:
    movzx   ecx, byte [rdi + 1]
    call    continuation
    jz      .one
    and     eax, 0x1F
    shl     eax, 6
    or      eax, ecx
    mov     edx, 2
    ret

.three:
    movzx   ecx, byte [rdi + 1]
    call    continuation
    jz      .one
    and     eax, 0x0F
    shl     eax, 12
    shl     ecx, 6
    or      eax, ecx
    movzx   ecx, byte [rdi + 2]
    call    continuation
    jz      .one_undo3
    or      eax, ecx
    mov     edx, 3
    ret
.one_undo3:
    movzx   eax, byte [rdi]
    mov     edx, 1
    ret

.four:
    movzx   ecx, byte [rdi + 1]
    call    continuation
    jz      .one
    and     eax, 0x07
    shl     eax, 18
    shl     ecx, 12
    or      eax, ecx
    movzx   ecx, byte [rdi + 2]
    call    continuation
    jz      .one_undo4
    shl     ecx, 6
    or      eax, ecx
    movzx   ecx, byte [rdi + 3]
    call    continuation
    jz      .one_undo4
    or      eax, ecx
    mov     edx, 4
    ret
.one_undo4:
    movzx   eax, byte [rdi]
    mov     edx, 1
    ret

; ecx = a byte -> ZF clear and ecx = its six payload bits if it is a
; continuation byte, ZF set if it is not. eax is left alone, because every
; caller is part way through building a codepoint in it.
continuation:
    mov     r8d, ecx
    and     r8d, 0xC0
    cmp     r8d, 0x80
    jne     .no
    and     ecx, 0x3F
    or      r8d, r8d                    ; 0x80, so not zero: ZF clear
    ret
.no:
    xor     r8d, r8d
    ret

; rdi = codepoint -> rax = how many terminal columns it occupies.
;
; Not a full wcwidth: that is a table of hundreds of ranges maintained by
; people whose job it is, and the caret only has to be right rather than
; provably right. What is here covers the two cases that actually appear in
; source somebody typed -- emoji and CJK are two columns wide, and joiners and
; variation selectors are none -- and everything else is one, which is true of
; every character this project has any business seeing.
utf8_width:
    cmp     rdi, 0x200B                 ; zero width space .. ZWJ
    jb      .not_zero
    cmp     rdi, 0x200F
    jbe     .zero
.not_zero:
    cmp     rdi, 0xFE00                 ; the variation selectors
    jb      .not_vs
    cmp     rdi, 0xFE0F
    jbe     .zero
.not_vs:
    cmp     rdi, 0x0300                 ; combining diacritics
    jb      .not_combining
    cmp     rdi, 0x036F
    jbe     .zero
.not_combining:

    lea     rcx, [wide_ranges]
.next:
    mov     eax, [rcx]
    test    eax, eax
    jz      .single
    cmp     rdi, rax
    jb      .step
    mov     eax, [rcx + 4]
    cmp     rdi, rax
    jbe     .double
.step:
    add     rcx, 8
    jmp     .next

.zero:
    xor     eax, eax
    ret
.single:
    mov     eax, 1
    ret
.double:
    mov     eax, 2
    ret

; ---------------------------------------------------------------------------
    section .data

; first, last. A zero first ends the list. Hangul, the CJK blocks, the
; fullwidth forms, and the emoji planes.
    align   8
wide_ranges:
    dd      0x1100, 0x115F
    dd      0x2E80, 0x303E
    dd      0x3041, 0x33FF
    dd      0x3400, 0x4DBF
    dd      0x4E00, 0x9FFF
    dd      0xA000, 0xA4CF
    dd      0xAC00, 0xD7A3
    dd      0xF900, 0xFAFF
    dd      0xFE30, 0xFE6F
    dd      0xFF00, 0xFF60
    dd      0xFFE0, 0xFFE6
    dd      0x1F300, 0x1F64F
    dd      0x1F680, 0x1F6FF
    dd      0x1F900, 0x1F9FF
    dd      0x1FA70, 0x1FAFF
    dd      0x20000, 0x3FFFD
    dd      0, 0
