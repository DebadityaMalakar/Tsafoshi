; SPDX-License-Identifier: MIT
;
; The function table. One record per function the session has defined, and the
; only thing that outlives a submission besides the text and the code itself.
;
; A record has to serve two engines that agree on nothing about how a call
; works. The VM wants an entry point -- an offset into the code arena -- and a
; frame size, so it can push a frame and jump. The tree walker wants the body's
; syntax tree, so it can walk it again. Both are kept, both are filled in by
; the same definition, and neither engine looks at the other's half.
;
; Names are registered *before* the body is parsed. That is not tidiness: it is
; the whole of what makes a function able to call itself, because the call
; inside the body has to resolve to something, and the something is this record
; with its entry point not yet known.

%include "tsafoshi.inc"

    global  func_init
    global  func_declare
    global  func_find
    global  func_arity
    global  func_frame
    global  func_entry
    global  func_body
    global  func_name
    global  func_set_frame
    global  func_set_entry
    global  func_set_body
    global  func_count
    global  func_type
    global  func_param
    global  func_set_param

    extern  err_toomanyfuncs
    extern  err_redefined

FN_NAME             equ 0               ; the interned identifier
FN_ARITY            equ CELL
FN_FRAME            equ CELL * 2        ; cells of locals, parameters included
FN_ENTRY            equ CELL * 3        ; offset into the code arena
FN_BODY             equ CELL * 4        ; the statement list, for the walker
FN_TYPE             equ CELL * 5        ; what it returns
FN_SIZE             equ CELL * 6

    section .text

func_init:
    mov     qword [func_count], 0
    ret

; rdi = index -> rax = the record
record:
    lea     rax, [func_tab]
    imul    rcx, rdi, FN_SIZE
    add     rax, rcx
    ret

; rdi = name slot, rsi = arity, rdx = position, rcx = return type
; -> rax = the function id, or -1.
;
; Redefinition is refused rather than allowed to shadow. At a prompt it is
; tempting to let the second definition win, but then a call compiled against
; the first would still be pointing at it, and "the function I just fixed did
; not change" is a worse experience than being told to pick another name.
func_declare:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     rdi, rbx
    call    func_find
    cmp     rax, -1
    jne     .already
    mov     rcx, [func_count]
    cmp     rcx, FUNC_CAP
    jae     .too_many
    mov     rdi, rcx
    call    record
    mov     [rax + FN_NAME], rbx
    mov     [rax + FN_ARITY], r12
    mov     qword [rax + FN_FRAME], 0
    mov     qword [rax + FN_ENTRY], 0
    mov     qword [rax + FN_BODY], 0
    mov     [rax + FN_TYPE], r14
    mov     rax, [func_count]
    inc     qword [func_count]
    jmp     .out

.already:
    mov     rdi, r13
    call    err_redefined
    jmp     .fail
.too_many:
    mov     rdi, r13
    call    err_toomanyfuncs
.fail:
    mov     rax, -1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; rdi = name slot -> rax = the function id, or -1
func_find:
    xor     ecx, ecx
    lea     r8, [func_tab]
.next:
    cmp     rcx, [func_count]
    jae     .missing
    imul    r9, rcx, FN_SIZE
    mov     rax, [r8 + r9 + FN_NAME]
    cmp     rax, rdi
    je      .found
    inc     rcx
    jmp     .next
.found:
    mov     rax, rcx
    ret
.missing:
    mov     rax, -1
    ret

; rdi = function id -> rax = the field asked for
func_name:
    call    record
    mov     rax, [rax + FN_NAME]
    ret
func_arity:
    call    record
    mov     rax, [rax + FN_ARITY]
    ret
func_frame:
    call    record
    mov     rax, [rax + FN_FRAME]
    ret
func_entry:
    call    record
    mov     rax, [rax + FN_ENTRY]
    ret
func_body:
    call    record
    mov     rax, [rax + FN_BODY]
    ret
func_type:
    call    record
    mov     rax, [rax + FN_TYPE]
    ret

; The parameter types, kept beside the table rather than in it: they are a
; short list per function, they are read only where a call is being built, and
; a record with a variable-length tail would be the one shape in this tree that
; is not a fixed number of cells.
;
; rdi = function id, rsi = which parameter -> rax = its type
func_param:
    lea     rax, [fn_ptypes]
    imul    rcx, rdi, PARAM_MAX
    add     rcx, rsi
    movzx   eax, byte [rax + rcx]
    ret

; rdi = function id, rsi = which parameter, rdx = its type
func_set_param:
    lea     rax, [fn_ptypes]
    imul    rcx, rdi, PARAM_MAX
    add     rcx, rsi
    mov     [rax + rcx], dl
    ret

; rdi = function id, rsi = the value to record
func_set_frame:
    call    record
    mov     [rax + FN_FRAME], rsi
    ret
func_set_entry:
    call    record
    mov     [rax + FN_ENTRY], rsi
    ret
func_set_body:
    call    record
    mov     [rax + FN_BODY], rsi
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
func_count:
    resq    1
func_tab:
    resb    FUNC_CAP * FN_SIZE
fn_ptypes:
    resb    FUNC_CAP * PARAM_MAX
