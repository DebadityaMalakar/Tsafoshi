; SPDX-License-Identifier: MIT
;
; File reading, Linux x86-64. Raw syscalls, no libc.
;
; The other half of the platform contract, and the half that actually differs
; between the two targets rather than merely being spelled differently. Here a
; file is an integer the kernel hands back and three syscalls; on Windows it is
; an opaque handle and three kernel32 calls with a different convention. Same
; three routines either way, which is the point of putting them behind a seam.
;
; Kernel ABI: args rdi rsi rdx r10 r8 r9, number in rax, result in rax
; (negative errno on failure). The syscall instruction clobbers rcx and r11.

%include "tsafoshi.inc"

    global  sys_args_init
    global  sys_argv
    global  sys_open_read
    global  sys_read_file
    global  sys_close

SYS_READ            equ 0
SYS_CLOSE           equ 3
SYS_OPENAT          equ 257
AT_FDCWD            equ -100
O_RDONLY            equ 0

    section .text

; rdi = the stack pointer as the kernel left it. Linux puts the command line
; there and nowhere else: argc first, then argc pointers, then a NULL. Nothing
; copies it, so remembering where it was is the whole of the work.
sys_args_init:
    mov     [os_stack], rdi
    ret

; rdi = index -> rax = that argument, or 0 if there is no such one
sys_argv:
    mov     rcx, [os_stack]
    test    rcx, rcx
    jz      .none
    mov     rax, [rcx]                  ; argc
    cmp     rdi, rax
    jae     .none
    lea     rax, [rcx + CELL]           ; argv
    mov     rax, [rax + rdi * CELL]
    ret
.none:
    xor     eax, eax
    ret

; rdi = NUL-terminated path -> rax = a file, or a negative number if it could
; not be opened.
;
; openat rather than open: open is not present on every architecture Linux
; supports any more, and openat with AT_FDCWD means exactly the same thing
; everywhere it is.
sys_open_read:
    mov     rsi, rdi
    mov     edi, AT_FDCWD
    xor     edx, edx                    ; O_RDONLY
    xor     r10d, r10d                  ; mode, unused without O_CREAT
    mov     eax, SYS_OPENAT
    syscall
    ret

; rdi = file, rsi = buf, rdx = cap -> rax = bytes, 0 at the end
sys_read_file:
    mov     eax, SYS_READ
    syscall
    ret

; rdi = file
sys_close:
    mov     eax, SYS_CLOSE
    syscall
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
os_stack:
    resq    1

    section .note.GNU-stack noalloc noexec nowrite progbits
