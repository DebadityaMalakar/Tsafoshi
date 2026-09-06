; SPDX-License-Identifier: MIT
;
; The conversion rules: which type wins, and what happens to a value that
; crosses into another one.
;
; This is C99 6.3.1, and none of it is negotiable -- the rules are strange in
; places and they are still the rules, so they are written out rather than
; approximated. What *is* negotiable is where they run, and they run entirely
; in the parser. By the time either engine sees a tree, every conversion the
; standard demands is already an explicit node in it and every operator has
; already been told whether it is the signed one or the unsigned one. Neither
; engine knows what a type is.
;
; type.asm owns the table these rules are phrased in terms of; this file owns
; the rules. Splitting them is not ceremony: the table is data that grows when
; a type is added, and the rules are logic that does not.

%include "tsafoshi.inc"

    global  type_promote
    global  type_common
    global  type_convert

    extern  type_rank
    extern  type_unsigned

RANK_INT            equ 4               ; where the promotions stop

    section .text

; rdi = type -> rax = it after the integer promotions.
;
; "Anything narrower than int is an int." That one rule is why char + char is
; not a char, why a short overflows into an int rather than wrapping, and why
; there is no arithmetic opcode narrower than 32 bits anywhere in this
; interpreter. Every narrow type here fits in an int, so the promotion is
; always to signed int and never to unsigned int.
type_promote:
    push    rdi
    call    type_rank
    pop     rdi
    cmp     rax, RANK_INT
    jae     .keep
    mov     eax, TY_INT
    ret
.keep:
    mov     rax, rdi
    ret

; rdi, rsi = two types -> rax = the one both operands are converted to.
;
; The usual arithmetic conversions, after promotion. What is left is int, uint,
; long and ulong, and between those the rule collapses to two lines: at equal
; rank the unsigned one wins, and otherwise the wider one does -- because long
; is genuinely wide enough to hold every unsigned int, which is the condition
; the standard actually states rather than a shortcut past it.
;
; rbx = the promoted left, r12 = the promoted right
type_common:
    push    rbx
    push    r12
    call    type_promote
    mov     rbx, rax
    mov     rdi, rsi
    call    type_promote
    mov     r12, rax
    cmp     rbx, r12
    je      .same

    mov     rdi, rbx
    call    type_rank
    mov     rsi, rax
    mov     rdi, r12
    call    type_rank
    cmp     rsi, rax
    jb      .right_wider
    ja      .same

; Same rank, different types: exactly one of them is unsigned, and it wins.
    mov     rdi, rbx
    call    type_unsigned
    test    rax, rax
    jnz     .same
.right_wider:
    mov     rbx, r12
.same:
    mov     rax, rbx
    pop     r12
    pop     rbx
    ret

; rdi = value, rsi = type -> rax = that value as that type, extended back out
; to a full cell.
;
; Narrowing is a truncation, and C99 says so outright for the unsigned types;
; for the signed ones it is implementation-defined, and the definition chosen
; here is the one every compiler on this hardware chose, because it is what the
; hardware does.
;
; _Bool is the exception and is not a truncation at all: it is a test. Assigning
; 256 to a _Bool gives 1, not 0, which is the one place where "narrow it and
; see" would be quietly and specifically wrong.
type_convert:
    lea     rax, [conv_table]
    mov     rax, [rax + rsi * CELL]
    jmp     rax

conv_void:
    xor     eax, eax
    ret
conv_bool:
    xor     eax, eax
    test    rdi, rdi
    setne   al
    ret
conv_s8:
    movsx   rax, dil
    ret
conv_u8:
    movzx   eax, dil
    ret
conv_s16:
    movsx   rax, di
    ret
conv_u16:
    movzx   eax, di
    ret
conv_s32:
    movsxd  rax, edi
    ret
conv_u32:
    mov     eax, edi                    ; writing eax clears the top half
    ret
conv_s64:
    mov     rax, rdi
    ret

; ---------------------------------------------------------------------------
    section .data

; One row per type, in the same order type.asm lists them. A jump table rather
; than a width-and-signedness calculation, because the machine has a single
; instruction for every one of these and picking it is the whole job.
    align   8
conv_table:
    dq      conv_void                   ; TY_VOID
    dq      conv_bool                   ; TY_BOOL
    dq      conv_s8                     ; TY_CHAR
    dq      conv_s8                     ; TY_SCHAR
    dq      conv_u8                     ; TY_UCHAR
    dq      conv_s16                    ; TY_SHORT
    dq      conv_u16                    ; TY_USHORT
    dq      conv_s32                    ; TY_INT
    dq      conv_u32                    ; TY_UINT
    dq      conv_s64                    ; TY_LONG
    dq      conv_s64                    ; TY_ULONG
