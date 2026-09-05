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
; has any idea a scope ever existed. That was the point, and stage 2.3 is where
; it pays: a slot inside a function is now an offset into a call frame rather
; than an index into one flat array, and this is the only file that had to
; notice. A binding therefore carries one extra thing -- which of the two kinds
; of storage it names -- and that single bit is all the parser passes on.
;
; Frame offsets are handed out per function and reclaimed by blocks exactly as
; global slots are, but the *high-water mark* is what the function's frame has
; to be big enough for, so that is tracked separately and never rewound.

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
    global  scope_enter_function
    global  scope_leave_function
    global  scope_in_function

    extern  err_toomanyvars
    extern  err_toomanyscopes
    extern  err_redeclared

BIND_NAME           equ 0               ; the interned identifier
BIND_SLOT           equ 4               ; the storage it stands for
BIND_KIND           equ 8               ; VAR_GLOBAL or VAR_LOCAL
BIND_SIZE           equ 12

MARK_COUNT          equ 0               ; bindings live when the block opened
MARK_NEXT           equ 4               ; global storage in use when it opened
MARK_LOCAL          equ 8               ; frame storage in use when it opened
MARK_SIZE           equ 12

    section .text

; The global scope is depth zero and is never popped: it is the session, and a
; variable declared at the prompt has to outlive the line that declared it.
scope_init:
    mov     qword [bind_count], 0
    mov     qword [next_slot], 0
    mov     qword [depth], 0
    mov     qword [local_next], 0
    mov     qword [local_high], 0
    mov     qword [scope_in_function], 0
    ret

; A function body is a scope like any other, plus the fact that declarations
; inside it are frame offsets. Parameters are declared first and so land at
; offsets 0, 1, 2 ... which is exactly where the caller puts them.
; rdi = position -> rax = 0 on failure
scope_enter_function:
    mov     qword [local_next], 0
    mov     qword [local_high], 0
    mov     qword [scope_in_function], 1
    jmp     scope_push

; -> rax = how many cells the frame needs. The high-water mark, not the count
; still live: two sibling blocks reuse each other's offsets, and the frame has
; to be big enough for whichever of them is running.
scope_leave_function:
    call    scope_pop
    mov     qword [scope_in_function], 0
    mov     rax, [local_high]
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
    mov     edx, [local_next]
    mov     [rcx + MARK_LOCAL], edx
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
    mov     eax, [rcx + MARK_LOCAL]
    mov     [local_next], rax
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

; rdi = name slot, rsi = position -> rax = storage slot, rdx = VAR_GLOBAL or
; VAR_LOCAL; rax is -1 on failure.
;
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
    cmp     qword [scope_in_function], 0
    jne     .local
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
    mov     dword [r8 + r9 + BIND_KIND], VAR_GLOBAL
    inc     qword [bind_count]
    inc     qword [next_slot]
    xor     edx, edx
    jmp     .out

.local:
    mov     rcx, [bind_count]
    cmp     rcx, SCOPE_CAP
    jae     .too_many
    mov     rax, [local_next]
    cmp     rax, PARAM_MAX + SCOPE_CAP
    jae     .too_many
    lea     r8, [binds]
    imul    r9, rcx, BIND_SIZE
    mov     [r8 + r9 + BIND_NAME], ebx
    mov     [r8 + r9 + BIND_SLOT], eax
    mov     dword [r8 + r9 + BIND_KIND], VAR_LOCAL
    inc     qword [bind_count]
    inc     rax
    mov     [local_next], rax
    cmp     rax, [local_high]           ; the frame must fit the deepest block
    jbe     .no_new_high
    mov     [local_high], rax
.no_new_high:
    dec     rax
    mov     edx, VAR_LOCAL
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

; rdi = name slot -> rax = storage slot and rdx = its kind, or rax = -1 if
; nothing declared it. Backwards, so the innermost binding wins.
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
    mov     edx, [r8 + r9 + BIND_KIND]
    mov     eax, [r8 + r9 + BIND_SLOT]
    ret
.missing:
    mov     rax, -1
    ret

; rdi = storage slot, rsi = its kind -> rax = the name bound to it, or -1.
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
    mov     eax, [r8 + r9 + BIND_KIND]
    cmp     rax, rsi
    jne     .search
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
local_next:
    resq    1
local_high:
    resq    1
scope_in_function:
    resq    1
binds:
    resb    SCOPE_CAP * BIND_SIZE
marks:
    resb    SCOPE_DEPTH * MARK_SIZE
