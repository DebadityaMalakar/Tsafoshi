; SPDX-License-Identifier: MIT
;
; Bytecode listing. A second decoder over the same stream vm.asm executes,
; which is the cheapest way to keep the compiler honest: if the listing reads
; wrong, the encoding is wrong.
;
; Which is also why the operand shapes live in a table here rather than being
; inferred: this decoder is meant to be an independent statement of the
; format, not a paraphrase of the one in vm.asm.

%include "tsafoshi.inc"

    global  disasm_all

    extern  code_buf
    extern  code_len
    extern  fmt_i64
    extern  name_text
    extern  scope_name_of
    extern  sys_write_stdout

MNEMONIC_LEN        equ 7               ; padded, so operands line up
OFF_DIGITS          equ 4

    section .text

; rbx = offset into the stream, r12 = the opcode, r13 = its operand shape
disasm_all:
    push    rbx
    push    r12
    push    r13
    xor     ebx, ebx

.next:
    cmp     rbx, [code_len]
    jae     .done

    mov     rdi, rbx
    call    put_offset
    lea     rcx, [code_buf]
    movzx   eax, byte [rcx + rbx]
    inc     rbx
    cmp     rax, OP_COUNT               ; a stream we cannot read is a bug
    jae     .done
    mov     r12, rax
    lea     rcx, [operands]
    movzx   r13d, byte [rcx + rax]

    lea     rsi, [mnemonics]
    imul    rcx, r12, MNEMONIC_LEN
    add     rsi, rcx
    mov     rdx, MNEMONIC_LEN
    test    r13d, r13d
    jnz     .name                       ; an operand follows, so keep the pad
.trim:
    cmp     byte [rsi + rdx - 1], ' '
    jne     .name
    dec     rdx
    jmp     .trim
.name:
    call    sys_write_stdout
    lea     rcx, [operand_table]
    jmp     [rcx + r13 * 8]

.endline:
    lea     rsi, [t_newline]
    mov     rdx, 1
    call    sys_write_stdout
    jmp     .next

.immediate:
    lea     rcx, [code_buf]
    mov     rax, [rcx + rbx]
    add     rbx, 8
    call    fmt_i64
    call    sys_write_stdout
    jmp     .endline

; "@n" is a column in the source; "+n" an offset into the string arena; ">n"
; an offset into this very listing. Three different spaces, so three sigils.
.column:
    lea     rsi, [t_at]
    mov     rdx, 1
    call    sys_write_stdout
    call    take_u32
    call    fmt_i64
    call    sys_write_stdout
    jmp     .endline

.offset:
    lea     rsi, [t_plus]
    mov     rdx, 1
    call    sys_write_stdout
    call    take_u32
    call    fmt_i64
    call    sys_write_stdout
    jmp     .endline

; A jump prints its target the same width the offset column does, so the eye
; can find the line it lands on without counting.
.target:
    lea     rsi, [t_arrow]
    mov     rdx, t_arrow.len
    call    sys_write_stdout
    call    take_u32
    mov     rdi, rax
    call    put_digits
    jmp     .endline

; A slot number would be correct and unreadable, so the name is printed where
; there still is one. After a block closes there is not: the binding is gone,
; the storage is somebody else's now, and "$3" is the honest thing to say.
.slot:
    call    take_u32
    push    rax
    mov     rdi, rax
    call    scope_name_of
    pop     rcx
    cmp     rax, -1
    je      .anonymous
    mov     rdi, rax
    call    name_text
    mov     rsi, rax
    call    sys_write_stdout
    jmp     .endline
.anonymous:
    lea     rsi, [t_dollar]
    mov     rdx, 1
    push    rcx
    call    sys_write_stdout
    pop     rax
    call    fmt_i64
    call    sys_write_stdout
    jmp     .endline

.count:
    call    take_u32
    call    fmt_i64
    call    sys_write_stdout
    lea     rsi, [t_space]
    mov     rdx, 1
    call    sys_write_stdout
    jmp     .column

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -> rax = the next four bytes, rbx advanced past them
take_u32:
    lea     rcx, [code_buf]
    mov     eax, dword [rcx + rbx]
    add     rbx, 4
    ret

; rdi = offset, printed as four digits with the indent in front of it
put_offset:
    push    rdi
    lea     rsi, [t_indent]
    mov     rdx, t_indent.len
    call    sys_write_stdout
    pop     rdi
    call    put_digits
    lea     rsi, [t_gap]
    mov     rdx, t_gap.len
    jmp     sys_write_stdout

; rdi = value, written as exactly OFF_DIGITS decimal digits
put_digits:
    mov     rax, rdi
    lea     r8, [off_buf]
    mov     r9d, 10
    mov     rcx, OFF_DIGITS
.digit:
    xor     edx, edx
    div     r9
    add     dl, '0'
    dec     rcx
    mov     [r8 + rcx], dl
    test    rcx, rcx
    jnz     .digit
    lea     rsi, [off_buf]
    mov     rdx, OFF_DIGITS
    jmp     sys_write_stdout

; ---------------------------------------------------------------------------
    section .data

; Padded to a fixed width so the operand column lines up without a table of
; lengths, and so indexing is one multiply. The pad is trimmed again for the
; opcodes that have no operand, which would otherwise print trailing spaces.
mnemonics:
    db      "halt   "                   ; OP_HALT
    db      "push   "                   ; OP_PUSH
    db      "mul    "                   ; OP_MUL
    db      "div    "                   ; OP_DIV
    db      "mod    "                   ; OP_MOD
    db      "add    "                   ; OP_ADD
    db      "sub    "                   ; OP_SUB
    db      "shl    "                   ; OP_SHL
    db      "shr    "                   ; OP_SHR
    db      "lt     "                   ; OP_LT
    db      "gt     "                   ; OP_GT
    db      "le     "                   ; OP_LE
    db      "ge     "                   ; OP_GE
    db      "eq     "                   ; OP_EQ
    db      "ne     "                   ; OP_NE
    db      "and    "                   ; OP_AND
    db      "xor    "                   ; OP_XOR
    db      "or     "                   ; OP_OR
    db      "neg    "                   ; OP_NEG
    db      "not    "                   ; OP_NOT
    db      "bnot   "                   ; OP_BNOT
    db      "pop    "                   ; OP_POP
    db      "load   "                   ; OP_LOAD
    db      "store  "                   ; OP_STORE
    db      "str    "                   ; OP_STR
    db      "printf "                   ; OP_PRINTF
    db      "jmp    "                   ; OP_JMP
    db      "jz     "                   ; OP_JZ
    db      "jnz    "                   ; OP_JNZ

; opcode -> what follows it, as an index into operand_table
operands:
    db      0                           ; OP_HALT
    db      1                           ; OP_PUSH     8-byte immediate
    db      0                           ; OP_MUL
    db      2, 2                        ; OP_DIV OP_MOD    source column
    db      0, 0                        ; OP_ADD OP_SUB
    db      0, 0                        ; OP_SHL OP_SHR
    db      0, 0, 0, 0                  ; OP_LT OP_GT OP_LE OP_GE
    db      0, 0                        ; OP_EQ OP_NE
    db      0, 0, 0                     ; OP_AND OP_XOR OP_OR
    db      0, 0, 0                     ; OP_NEG OP_NOT OP_BNOT
    db      0                           ; OP_POP
    db      3, 3                        ; OP_LOAD OP_STORE storage slot
    db      4                           ; OP_STR      arena offset
    db      5                           ; OP_PRINTF   count, then a column
    db      6, 6, 6                     ; OP_JMP OP_JZ OP_JNZ  a target

    align   8
operand_table:
    dq      disasm_all.endline
    dq      disasm_all.immediate
    dq      disasm_all.column
    dq      disasm_all.slot
    dq      disasm_all.offset
    dq      disasm_all.count
    dq      disasm_all.target

t_indent:
    db      "    "
.len                equ $ - t_indent
t_gap:
    db      "  "
.len                equ $ - t_gap
t_at:
    db      "@"
t_plus:
    db      "+"
t_dollar:
    db      "$"
t_arrow:
    db      "->"
.len                equ $ - t_arrow
t_space:
    db      " "
t_newline:
    db      10

; ---------------------------------------------------------------------------
    section .bss

off_buf:
    resb    OFF_DIGITS
