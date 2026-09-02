; SPDX-License-Identifier: MIT
;
; Which engine runs an expression, and the commands that switch it.
;
; Two engines walk the same tree. The tree walker came first and is kept, not
; as a fallback but as an oracle: both engines must agree on every input, and
; the day they disagree one of them has a bug worth finding.

%include "tsafoshi.inc"

    global  exec_run
    global  exec_command

    extern  ast_eval
    extern  code_compile
    extern  vm_run
    extern  disasm_all
    extern  err_code
    extern  match_word
    extern  skip_blanks
    extern  sys_write_stdout
    extern  sys_write_stderr

W_ENGINE_LEN        equ 6               ; length of the word "engine"

    section .text

; rdi = root node -> rax
exec_run:
    cmp     qword [engine_bytecode], 0
    je      ast_eval

    call    code_compile
    cmp     qword [err_code], 0
    jne     .zero
    cmp     qword [dis_listing], 0
    je      vm_run
    call    disasm_all
    jmp     vm_run
.zero:
    xor     eax, eax
    ret

; rdi = the command text, already past the colon. Handles "engine",
; "engine <name>" and "dis". -> rax = 1 if it was ours.
exec_command:
    lea     rsi, [w_engine]
    call    match_word
    test    rax, rax
    jnz     .engine
    lea     rsi, [w_dis]
    call    match_word
    test    rax, rax
    jnz     .dis
    xor     eax, eax
    ret

.dis:
    xor     qword [dis_listing], 1
    lea     rsi, [m_listing]
    mov     rdx, m_listing.len
    call    sys_write_stdout
    cmp     qword [dis_listing], 0
    je      .off
    lea     rsi, [m_on]
    mov     rdx, m_on.len
    jmp     .say
.off:
    lea     rsi, [m_off]
    mov     rdx, m_off.len
.say:
    call    sys_write_stdout
    mov     eax, 1
    ret

.engine:
    add     rdi, W_ENGINE_LEN
    call    skip_blanks
    cmp     byte [rdi], 0
    je      .show
    lea     rsi, [w_tree]
    call    match_word
    test    rax, rax
    jnz     .use_tree
    lea     rsi, [w_bytecode]
    call    match_word
    test    rax, rax
    jnz     .use_bytecode
    lea     rsi, [m_unknown]
    mov     rdx, m_unknown.len
    call    sys_write_stderr
    mov     eax, 1
    ret
.use_tree:
    mov     qword [engine_bytecode], 0
    jmp     .show
.use_bytecode:
    mov     qword [engine_bytecode], 1

.show:
    lea     rsi, [m_engine]
    mov     rdx, m_engine.len
    call    sys_write_stdout
    cmp     qword [engine_bytecode], 0
    je      .name_tree
    lea     rsi, [w_bytecode]
    mov     rdx, w_bytecode.len
    jmp     .name
.name_tree:
    lea     rsi, [w_tree]
    mov     rdx, w_tree.len
.name:
    call    sys_write_stdout
    lea     rsi, [m_newline]
    mov     rdx, 1
    call    sys_write_stdout
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
    section .data

w_engine:
    db      "engine", 0
w_dis:
    db      "dis", 0
w_tree:
    db      "tree", 0
.len                equ $ - w_tree - 1
w_bytecode:
    db      "bytecode", 0
.len                equ $ - w_bytecode - 1

m_engine:
    db      "engine: "
.len                equ $ - m_engine
m_listing:
    db      "disassembly: "
.len                equ $ - m_listing
m_on:
    db      "on", 10
.len                equ $ - m_on
m_off:
    db      "off", 10
.len                equ $ - m_off
m_newline:
    db      10
m_unknown:
    db      "error: unknown engine; try tree or bytecode", 10
.len                equ $ - m_unknown

    align   8
engine_bytecode:
    dq      1                           ; the tree walker is now the fallback
dis_listing:
    dq      0
