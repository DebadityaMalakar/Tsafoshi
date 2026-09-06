; SPDX-License-Identifier: MIT
;
; The builtin functions, and the one door both engines call them through.
;
; A builtin is a name the session cannot rebind and a routine that already
; exists in this binary. Until now there was exactly one of them and the VM
; had an opcode with its name on it; that stops scaling the moment there are
; four, so they are a table instead: an id, an arity, and a routine.
;
; Every routine has the same signature -- an argument block, a count, and a
; position for errors -- which is the shape printf_run already wanted, because
; it is the shape the arguments are already in on the VM's operand stack. So
; the VM hands over a pointer into its own stack and the tree walker hands over
; a block it built on the machine stack, and neither of them knows or cares
; which builtin is on the other end.
;
; Arity is checked by the parser, not here, so a wrong call is a parse error
; with a caret under it rather than something discovered halfway through
; running. printf is the exception and says so: BI_VARIADIC means "at least
; one", because the format string is not optional and nothing after it is
; countable in advance.

%include "tsafoshi.inc"

    global  builtin_arity
    global  builtin_run
    global  builtin_type
    global  builtin_param

    extern  printf_run
    extern  cli_argc                    ; a count, not a routine
    extern  cli_arg
    extern  sys_exit

BF_ARITY            equ 0
BF_ROUTINE          equ CELL
BF_TYPE             equ CELL * 2        ; what it gives back
BF_PARAM            equ CELL * 3        ; what its argument is, where it has one
BF_SIZE             equ CELL * 4

    section .text

; rdi = builtin id -> rax = the field asked for
entry:
    sub     rdi, BI_FIRST
    lea     rax, [builtins]
    imul    rcx, rdi, BF_SIZE
    add     rax, rcx
    ret

; -> rax = how many arguments it takes, or BI_VARIADIC
builtin_arity:
    call    entry
    mov     rax, [rax + BF_ARITY]
    ret

; -> rax = the type of the value it produces
builtin_type:
    call    entry
    mov     rax, [rax + BF_TYPE]
    ret

; -> rax = the type its argument is converted to. printf's is the type of its
; format; everything after that gets the default argument promotions instead,
; because a variadic call has nothing else to go on.
builtin_param:
    call    entry
    mov     rax, [rax + BF_PARAM]
    ret

; rdi = builtin id, rsi = the arguments, rdx = how many, rcx = position -> rax
builtin_run:
    sub     rdi, BI_FIRST
    lea     rax, [builtins]
    imul    r8, rdi, BF_SIZE
    mov     rax, [rax + r8 + BF_ROUTINE]
    mov     rdi, rsi
    mov     rsi, rdx
    mov     rdx, rcx
    jmp     rax

; rdi = the arguments, rsi = how many, rdx = position. The three below take
; their arguments in the same block printf does, and ignore the position
; because none of them can fail in a way that points at a column.

; -> rax = how many arguments the program was given, argv(0) included
bi_argc:
    mov     rax, [cli_argc]
    ret

; -> rax = one of them as a NUL-terminated string, or zero past the end.
;
; This is how a program reads its command line at this stage. It is not
; main(int argc, char **argv), which needs a pointer type to even be spelled
; and therefore waits for 3.3; it is the same information through a door the
; language already has, because a string literal has been an address in a cell
; since 2.1 and argv's strings are addresses of exactly the same kind.
;
; Out of range is zero, so argv(argc()) is a null pointer for the same reason
; it is in C.
bi_argv:
    mov     rdi, [rdi]
    jmp     cli_arg

; Leaves immediately with that status, from wherever it was called -- inside a
; loop, inside a function, ten frames down. There is nothing to unwind: the
; frames are ours, the arenas are ours, and the process is about to stop being.
bi_exit:
    mov     rdi, [rdi]
    and     edi, 0xff                   ; a status is eight bits on both targets
    jmp     sys_exit

; ---------------------------------------------------------------------------
    section .data

; Indexed by builtin id minus BI_FIRST, in the same order names.asm interns
; them and tsafoshi.inc numbers them.
    align   8
builtins:
    dq      BI_VARIADIC, printf_run, TY_INT, TY_LONG ; BI_PRINTF
    dq      0, bi_argc, TY_INT, TY_VOID ; BI_ARGC
    dq      1, bi_argv, TY_LONG, TY_INT ; BI_ARGV
    dq      1, bi_exit, TY_VOID, TY_INT ; BI_EXIT
