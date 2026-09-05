; SPDX-License-Identifier: MIT
;
; Lexical scope: which name means which storage slot, right here.
;
; Until this stage a variable *was* its name -- vars.asm indexed the cell array
; by the interned name slot, so there was exactly one x for the whole session
; and no way to have a second. That is what a block is for, so it had to go.
;
; A binding is a pair: the name slot the source wrote, and the storage slot the
; engines index. Bindings live on a stack; entering a block records a mark and
; leaving one truncates back to it, which frees both the bindings and the
; storage they were using. Lookup scans backwards, so the innermost declaration
; of a name is the one found -- that is all shadowing is.
;
; The whole thing is resolved during parsing and gone by the time anything
; runs. The tree carries storage slots, both engines index them, and neither
; has any idea a scope ever existed. That is the point: at stage 2.3 a slot
; becomes an offset into a call frame, and only this file has to notice.

%include "tsafoshi.inc"

    global  scope_init
    global  scope_push
    global  scope_pop
    global  scope_unwind
    global  scope_declare
    global  scope_lookup
    global  scope_global_count
    global  scope_global_name
    global  scope_global_slot
    global  scope_name_of

    extern  err_toomanyvars
    extern  err_toomanyscopes
    extern  err_redeclared

BIND_NAME           equ 0               ; the interned identifier
BIND_SLOT           equ 4               ; the storage cell it stands for
BIND_SIZE           equ 8

MARK_COUNT          equ 0               ; bindings live when the block opened
MARK_NEXT           equ 4               ; storage in use when it opened
MARK_SIZE           equ 8

    section .text

; The global scope is depth zero and is never popped: it is the session, and a
; variable declared at the prompt has to outlive the line that declared it.
scope_init:
    mov     qword [bind_count], 0
    mov     qword [next_slot], 0
    mov     qword [depth], 0
    ret

; rdi = position for errors -> rax = 0 on failure, with the error recorded
scope_push:
    mov     rax, [depth]
    cmp     rax, SCOPE_DEPTH
    jae     .full
    lea     rcx, [marks]
    imul    rdx, rax, MARK_SIZE
    add     rcx, rdx
    mov     edx, [bind_count]
    mov     [rcx + MARK_COUNT], edx
    mov     edx, [next_slot]
    mov     [rcx + MARK_NEXT], edx
    inc     qword [depth]
    mov     eax, 1
    ret
.full:
    call    err_toomanyscopes
    xor     eax, eax
    ret

; Storage is reclaimed as well as the names, so a hundred sequential blocks
; each declaring a variable cost one slot between them rather than a hundred.
scope_pop:
    mov     rax, [depth]
    test    rax, rax
    jz      .none
    dec     rax
    mov     [depth], rax
    lea     rcx, [marks]
    imul    rdx, rax, MARK_SIZE
    add     rcx, rdx
    mov     eax, [rcx + MARK_COUNT]
    mov     [bind_count], rax
    mov     eax, [rcx + MARK_NEXT]
    mov     [next_slot], rax
.none:
    ret

; Back to the global scope. A parse that fails inside a block never reaches the
; closing brace, so the REPL calls this instead of the pops that did not run.
scope_unwind:
    cmp     qword [depth], 0
    je      .done
    call    scope_pop
    jmp     scope_unwind
.done:
    ret

; rdi = name slot, rsi = position -> rax = storage slot, or -1.
; Redeclaration is an error in the same scope and shadowing in an inner one,
; which is the same rule read from two sides: the search stops at the mark.
scope_declare:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     rcx, [bind_count]
    mov     rdx, 0                      ; where the current scope starts
    cmp     qword [depth], 0
    je      .have_floor
    mov     rax, [depth]
    dec     rax
    lea     r8, [marks]
    imul    r9, rax, MARK_SIZE
    mov     edx, [r8 + r9 + MARK_COUNT]
.have_floor:
    lea     r8, [binds]
.search:
    cmp     rcx, rdx
    jbe     .fresh
    dec     rcx
    imul    r9, rcx, BIND_SIZE
    mov     eax, [r8 + r9 + BIND_NAME]
    cmp     rax, rbx
    je      .already
    jmp     .search

.fresh:
    mov     rcx, [bind_count]
    cmp     rcx, SCOPE_CAP
    jae     .too_many
    mov     rax, [next_slot]
    cmp     rax, VAR_CAP
    jae     .too_many
    lea     r8, [binds]
    imul    r9, rcx, BIND_SIZE
    mov     [r8 + r9 + BIND_NAME], ebx
    mov     [r8 + r9 + BIND_SLOT], eax
    inc     qword [bind_count]
    inc     qword [next_slot]
    jmp     .out

.already:
    mov     rdi, r12
    call    err_redeclared
    jmp     .fail
.too_many:
    mov     rdi, r12
    call    err_toomanyvars
.fail:
    mov     rax, -1
.out:
    pop     r12
    pop     rbx
    ret

; rdi = name slot -> rax = storage slot, or -1 if nothing declared it.
; Backwards, so the innermost binding wins.
scope_lookup:
    mov     rcx, [bind_count]
    lea     r8, [binds]
.search:
    test    rcx, rcx
    jz      .missing
    dec     rcx
    imul    r9, rcx, BIND_SIZE
    mov     eax, [r8 + r9 + BIND_NAME]
    cmp     rax, rdi
    je      .found
    jmp     .search
.found:
    mov     eax, [r8 + r9 + BIND_SLOT]
    ret
.missing:
    mov     rax, -1
    ret

; rdi = storage slot -> rax = the name currently bound to it, or -1.
;
; The disassembler's one question, and it is asked after the parse has finished
; -- so every scope a block opened is closed again and only the globals are
; still bound. A local's name is genuinely gone by then, which is the seam
; working rather than failing, and the listing says so by printing the slot.
scope_name_of:
    mov     rcx, [bind_count]
    lea     r8, [binds]
.search:
    test    rcx, rcx
    jz      .missing
    dec     rcx
    imul    r9, rcx, BIND_SIZE
    mov     eax, [r8 + r9 + BIND_SLOT]
    cmp     rax, rdi
    je      .found
    jmp     .search
.found:
    mov     eax, [r8 + r9 + BIND_NAME]
    ret
.missing:
    mov     rax, -1
    ret

; The global scope, for ":vars". Between lines the depth is zero, so every
; live binding is a global one and the count is the whole array.
scope_global_count:
    mov     rax, [bind_count]
    ret

; rdi = index -> rax = the name slot it binds
scope_global_name:
    lea     r8, [binds]
    imul    r9, rdi, BIND_SIZE
    mov     eax, [r8 + r9 + BIND_NAME]
    ret

; rdi = index -> rax = the storage slot it binds
scope_global_slot:
    lea     r8, [binds]
    imul    r9, rdi, BIND_SIZE
    mov     eax, [r8 + r9 + BIND_SLOT]
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
bind_count:
    resq    1
next_slot:
    resq    1
depth:
    resq    1
binds:
    resb    SCOPE_CAP * BIND_SIZE
marks:
    resb    SCOPE_DEPTH * MARK_SIZE
