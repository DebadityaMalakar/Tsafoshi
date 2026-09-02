; SPDX-License-Identifier: MIT
;
; Platform layer, Linux x86-64. Raw syscalls, no libc.
; Kernel ABI: args rdi rsi rdx r10 r8 r9, number in rax, result in rax
; (negative errno on failure). The syscall instruction clobbers rcx and r11.

%include "tsafoshi.inc"

    global  sys_write_stdout
    global  sys_write_stderr
    global  sys_read_stdin
    global  sys_exit

SYS_READ            equ 0
SYS_WRITE           equ 1
SYS_EXIT            equ 60
STDIN               equ 0
STDOUT              equ 1
STDERR              equ 2

    section .text

; rsi = buf, rdx = len
sys_write_stdout:
    mov     edi, STDOUT
    mov     eax, SYS_WRITE
    syscall
    ret

sys_write_stderr:
    mov     edi, STDERR
    mov     eax, SYS_WRITE
    syscall
    ret

; rsi = buf, rdx = cap -> rax = bytes, <= 0 at EOF or error
sys_read_stdin:
    mov     edi, STDIN
    mov     eax, SYS_READ
    syscall
    ret

; edi = status
sys_exit:
    mov     eax, SYS_EXIT
    syscall
    hlt

    section .note.GNU-stack noalloc noexec nowrite progbits
