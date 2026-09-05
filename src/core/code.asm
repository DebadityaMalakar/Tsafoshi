; SPDX-License-Identifier: MIT
;
; The code buffer: storage for one compiled line, the writes that fill it, and
; the two routines that let a jump be emitted before anyone knows where it
; goes. Like the AST arena this is reset per line and never freed.
;
; compile.asm writes here; vm.asm and disasm.asm read. None of them owns the
; memory, so adding a fourth reader costs nothing.

%include "tsafoshi.inc"

    global  code_reset
    global  code_op
    global  code_i64
    global  code_u32
    global  code_here
    global  code_jump
    global  code_patch
    global  code_buf
    global  code_len

    extern  err_codefull

    section .text

code_reset:
    mov     qword [code_len], 0
    ret

; Each writer refuses rather than runs past the end; the first refusal records
; the error and the rest are harmless repeats of it.

; rdi = opcode byte
code_op:
    mov     rax, [code_len]
    cmp     rax, CODE_CAP - 1
    ja      err_codefull
    lea     rcx, [code_buf]
    mov     [rcx + rax], dil
    inc     qword [code_len]
    ret

; rdi = 64-bit immediate
code_i64:
    mov     rax, [code_len]
    cmp     rax, CODE_CAP - 8
    ja      err_codefull
    lea     rcx, [code_buf]
    mov     [rcx + rax], rdi
    add     qword [code_len], 8
    ret

; rdi = 32-bit operand
code_u32:
    mov     rax, [code_len]
    cmp     rax, CODE_CAP - 4
    ja      err_codefull
    lea     rcx, [code_buf]
    mov     [rcx + rax], edi
    add     qword [code_len], 4
    ret

; -> rax = where the next instruction will land. A label is nothing more than
; this number written down.
code_here:
    mov     rax, [code_len]
    ret

; rdi = jump opcode -> rax = the offset of its target field, for code_patch.
;
; A forward jump has to be emitted before its destination is known, so it goes
; out with a hole in it and the hole's address comes back. Zero is never a
; valid one -- the first byte of the stream is an opcode, never an operand --
; so zero is free to mean "no jump", which is what lets the compiler thread a
; chain of unpatched breaks through the holes themselves.
code_jump:
    call    code_op
    mov     rax, [code_len]
    push    rax
    xor     edi, edi
    call    code_u32
    pop     rax
    ret

; rdi = the offset code_jump returned, rsi = where the jump should go
code_patch:
    cmp     rdi, CODE_CAP - 4
    ja      .out
    lea     rcx, [code_buf]
    mov     [rcx + rdi], esi
.out:
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
code_len:
    resq    1
code_buf:
    resb    CODE_CAP
