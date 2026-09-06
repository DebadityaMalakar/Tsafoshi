; SPDX-License-Identifier: MIT
;
; Platform layer, Windows x86-64.
;
; Not raw syscalls: NT service numbers are private and get renumbered between
; builds. kernel32 is the stable boundary. What differs from the Linux file is
; the calling convention -- args rcx rdx r8 r9 then the stack at [rsp+32], a
; mandatory 32-byte shadow area, and rsp 16-byte aligned at every call.

%include "tsafoshi.inc"

    global  sys_write_stdout
    global  sys_write_stderr
    global  sys_read_stdin
    global  sys_exit
    global  sys_isatty

    extern  GetStdHandle
    extern  ReadFile
    extern  WriteFile
    extern  ExitProcess
    extern  GetConsoleMode

STD_INPUT_HANDLE    equ -10
STD_OUTPUT_HANDLE   equ -11
STD_ERROR_HANDLE    equ -12

    section .text

; rsi = buf, rdx = len
sys_write_stdout:
    mov     r11d, STD_OUTPUT_HANDLE
    jmp     win_write

sys_write_stderr:
    mov     r11d, STD_ERROR_HANDLE
    ; fall through

; r11d = std handle id, rsi = buf, rdx = len
win_write:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96
    and     rsp, -16
    mov     [rbp-8], rsi
    mov     [rbp-16], rdx
    mov     ecx, r11d
    call    GetStdHandle
    mov     rcx, rax
    mov     rdx, [rbp-8]
    mov     r8d, dword [rbp-16]
    lea     r9, [rbp-24]                ; lpNumberOfBytesWritten
    mov     qword [rsp+32], 0           ; lpOverlapped
    call    WriteFile
    mov     rsp, rbp
    pop     rbp
    ret

; rsi = buf, rdx = cap -> rax = bytes, 0 at EOF.
; ReadFile returns FALSE at a console Ctrl+Z and TRUE with 0 bytes at a piped
; EOF; both collapse to 0.
sys_read_stdin:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96
    and     rsp, -16
    mov     [rbp-8], rsi
    mov     [rbp-16], rdx
    mov     qword [rbp-24], 0
    mov     ecx, STD_INPUT_HANDLE
    call    GetStdHandle
    mov     rcx, rax
    mov     rdx, [rbp-8]
    mov     r8d, dword [rbp-16]
    lea     r9, [rbp-24]                ; lpNumberOfBytesRead
    mov     qword [rsp+32], 0           ; lpOverlapped
    call    ReadFile
    test    eax, eax
    jz      .failed
    mov     eax, dword [rbp-24]
    jmp     .out
.failed:
    xor     eax, eax
.out:
    mov     rsp, rbp
    pop     rbp
    ret

; rdi = 0 for stdin, 1 for stdout -> rax = 1 if that is a console.
;
; The same question the Linux side asks, and answered the same way: try the one
; call only a terminal will accept and see whether it does. GetConsoleMode
; fails on a pipe, a file and a redirected handle, which between them are every
; case where prompting somebody would be prompting nobody.
sys_isatty:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96
    and     rsp, -16
    mov     ecx, STD_INPUT_HANDLE
    test    rdi, rdi
    jz      .ask
    mov     ecx, STD_OUTPUT_HANDLE
.ask:
    call    GetStdHandle
    mov     rcx, rax
    lea     rdx, [rbp-8]                ; lpMode, wanted and then thrown away
    call    GetConsoleMode
    test    eax, eax
    jz      .no
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    mov     rsp, rbp
    pop     rbp
    ret

; edi = status
sys_exit:
    and     rsp, -16
    sub     rsp, 32
    mov     ecx, edi
    call    ExitProcess
    hlt
