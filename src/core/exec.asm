; SPDX-License-Identifier: MIT
;
; Which engine runs an expression, and the commands that switch it.
;
; Two engines walk the same tree. The tree walker came first and is kept, not
; as a fallback but as an oracle: both engines must agree on every input, and
; the day they disagree one of them has a bug worth finding.

%include "tsafoshi.inc"

    global  exec_run
    global  exec_define
    global  exec_command
    global  exec_select_engine

    extern  eval_program
    extern  code_compile
    extern  code_compile_function
    extern  ast_commit
    extern  parse_defined
    extern  parse_defined_count
    extern  disasm_range
    extern  vm_run
    extern  func_name
    extern  func_entry
    extern  name_text
    extern  code_base
    extern  code_len
    extern  err_code
    extern  match_word
    extern  skip_blanks
    extern  sys_write_stdout
    extern  sys_write_stderr

W_ENGINE_LEN        equ 6               ; length of the word "engine"

    section .text

; Compiles and keeps whatever functions the submission just defined, and makes
; their bodies permanent in the tree arena.
;
; This happens whichever engine is running, and that is deliberate. The tree
; walker needs the body kept; the VM needs it compiled; and the engine can be
; switched at any prompt, so a function that was only half-defined because of
; which engine happened to be active would be a trap. Definition is a fact
; about the session, not about an engine.
;
; rbx = which definition
exec_define:
    cmp     qword [parse_defined_count], 0
    je      .none
    push    rbx
    xor     ebx, ebx
.next:
    cmp     rbx, [parse_defined_count]
    jae     .done
    lea     rcx, [parse_defined]
    mov     rdi, [rcx + rbx * CELL]
    push    rdi
    call    code_compile_function
    pop     rdi
    cmp     qword [dis_listing], 0
    je      .quiet
    call    disasm_function
.quiet:
    inc     rbx
    jmp     .next
.done:
    pop     rbx
    call    ast_commit
.none:
    ret

; rdi = function id. Lists the code just compiled for it, which is the range
; between where it starts and where the arena now ends.
disasm_function:
    push    rbx
    mov     rbx, rdi
    lea     rsi, [m_function]
    mov     rdx, m_function.len
    call    sys_write_stdout
    mov     rdi, rbx
    call    func_name
    mov     rdi, rax
    call    name_text
    mov     rsi, rax
    call    sys_write_stdout
    lea     rsi, [m_colon]
    mov     rdx, m_colon.len
    call    sys_write_stdout
    mov     rdi, rbx
    call    func_entry
    mov     rdi, rax
    mov     rsi, [code_base]
    call    disasm_range
    pop     rbx
    ret

; rdi = the statement list, rsi = the trailing expression or zero -> rax.
;
; Both engines take the same pair, because the split is the language's and not
; an engine's: statements run for effect, and a line answers with the last
; expression on it if there was one.
exec_run:
    cmp     qword [engine_bytecode], 0
    je      eval_program

    call    code_compile                ; rax = where the line's code starts
    cmp     qword [err_code], 0
    jne     .zero
    push    rax
    cmp     qword [dis_listing], 0
    je      .quiet
    mov     rdi, rax
    mov     rsi, [code_len]
    call    disasm_range
.quiet:
    pop     rdi
    jmp     vm_run
.zero:
    xor     eax, eax
    ret

; rdi = a name -> rax = 1 if it named an engine, which is now the one running.
;
; The command and the --engine flag both come here, because they are the same
; act; only the command reports what it did afterwards.
exec_select_engine:
    lea     rsi, [w_tree]
    call    match_word
    test    rax, rax
    jnz     .tree
    lea     rsi, [w_bytecode]
    call    match_word
    test    rax, rax
    jnz     .bytecode
    xor     eax, eax
    ret
.tree:
    mov     qword [engine_bytecode], 0
    mov     eax, 1
    ret
.bytecode:
    mov     qword [engine_bytecode], 1
    mov     eax, 1
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
    call    exec_select_engine
    test    rax, rax
    jnz     .show
    lea     rsi, [m_unknown]
    mov     rdx, m_unknown.len
    call    sys_write_stderr
    mov     eax, 1
    ret

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
m_function:
    db      "function "
.len                equ $ - m_function
m_colon:
    db      ":", 10
.len                equ $ - m_colon
m_unknown:
    db      "error: unknown engine; try tree or bytecode", 10
.len                equ $ - m_unknown

    align   8
engine_bytecode:
    dq      1                           ; the tree walker is now the fallback
dis_listing:
    dq      0
