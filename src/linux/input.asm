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
    global  sys_isatty

SYS_READ            equ 0
SYS_WRITE           equ 1
SYS_IOCTL           equ 16
SYS_EXIT            equ 60
TCGETS              equ 0x5401          ; ask a terminal for its settings
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

; rdi = 0 for stdin, 1 for stdout -> rax = 1 if that is a terminal.
;
; There is no isatty syscall; isatty is a libc routine and what it does is ask
; the descriptor for terminal settings and see whether the kernel objects. A
; pipe or a file is not a terminal and answers ENOTTY, which is the whole test.
sys_isatty:
    mov     esi, TCGETS
    lea     rdx, [termios_buf]
    mov     eax, SYS_IOCTL
    syscall
    test    rax, rax
    jnz     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; edi = status
sys_exit:
    mov     eax, SYS_EXIT
    syscall
    hlt

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
termios_buf:
    resb    64                          ; struct termios is 60 of them

    section .note.GNU-stack noalloc noexec nowrite progbits
