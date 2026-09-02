; SPDX-License-Identifier: MIT
;
; Identifier interning. Text goes in, a slot number comes out, and the same
; text always comes back to the same slot -- for the whole session, not just
; the line, which is what lets a variable outlive the statement that made it.
;
; This file knows nothing about values. vars.asm holds those, indexed by the
; slots handed out here, so the compiler deals only in slots and the VM only
; in cells.

%include "tsafoshi.inc"

    global  names_init
    global  name_intern
    global  name_text
    global  name_count

    extern  err_toomanynames
    extern  err_longname

    section .text

; Interns the builtin names before any input is read, so BI_PRINTF and the
; rest are the constants they claim to be.
names_init:
    mov     qword [name_count], 0
    lea     rdi, [b_printf]
    mov     esi, b_printf.len
    xor     edx, edx
    jmp     name_intern

; rdi = text, rsi = length, rdx = position for errors -> rax = slot, or -1
name_intern:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    cmp     r12, NAME_LEN - 1           ; the terminator needs the last byte
    ja      .too_long

    xor     r14, r14
.search:
    cmp     r14, [name_count]
    jae     .fresh
    lea     rcx, [name_lens]
    movzx   eax, byte [rcx + r14]
    cmp     rax, r12
    jne     .step                       ; different length, cannot match
    mov     rdi, r14
    call    slot_text
    mov     r15, rax
    mov     rcx, r12
.byte:
    test    rcx, rcx
    jz      .found
    dec     rcx
    movzx   eax, byte [r15 + rcx]
    cmp     al, [rbx + rcx]
    je      .byte
.step:
    inc     r14
    jmp     .search

.found:
    mov     rax, r14
    jmp     .out

.fresh:
    cmp     r14, NAME_CAP
    jae     .too_many
    lea     rcx, [name_lens]
    mov     [rcx + r14], r12b
    mov     rdi, r14
    call    slot_text
    xor     ecx, ecx
.copy:
    cmp     rcx, r12
    jae     .terminate
    movzx   edx, byte [rbx + rcx]
    mov     [rax + rcx], dl
    inc     rcx
    jmp     .copy
.terminate:
    mov     byte [rax + rcx], 0
    inc     qword [name_count]
    mov     rax, r14
    jmp     .out

.too_long:
    mov     rdi, r13
    call    err_longname
    jmp     .fail
.too_many:
    mov     rdi, r13
    call    err_toomanynames
.fail:
    mov     rax, -1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = slot -> rax = NUL-terminated text, rdx = length
name_text:
    lea     rcx, [name_lens]
    movzx   edx, byte [rcx + rdi]
    ; fall through

; rdi = slot -> rax = the record's text
slot_text:
    lea     rax, [name_txt]
    imul    rcx, rdi, NAME_LEN
    add     rax, rcx
    ret

; ---------------------------------------------------------------------------
    section .data

b_printf:
    db      "printf"
.len                equ $ - b_printf

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
name_count:
    resq    1
name_lens:
    resb    NAME_CAP
name_txt:
    resb    NAME_CAP * NAME_LEN
