; SPDX-License-Identifier: MIT
;
; File reading, Windows x86-64.
;
; The other half of the platform contract. Linux gets a small integer from the
; kernel and reads it with the same call it reads a pipe with; here a file is
; an opaque HANDLE from CreateFileA, and INVALID_HANDLE_VALUE rather than a
; negative errno is how failure arrives. Both are hidden behind the same three
; routines, which is the entire reason the seam exists.
;
; Calling convention as in input.asm: args rcx rdx r8 r9 then the stack at
; [rsp+32], a mandatory 32-byte shadow area, and rsp 16-byte aligned at the
; call. CreateFileA takes seven arguments, so three of them go on the stack.

%include "tsafoshi.inc"

    global  sys_args_init
    global  sys_argv
    global  sys_open_read
    global  sys_read_file
    global  sys_close

    extern  GetCommandLineA
    extern  CreateFileA
    extern  ReadFile
    extern  CloseHandle

GENERIC_READ        equ 0x80000000
FILE_SHARE_READ     equ 1
OPEN_EXISTING       equ 3
FILE_ATTR_NORMAL    equ 0x80
ARGV_MAX            equ 16
CMD_CAP             equ 4096

    section .text

; Windows does not put the command line on the stack, so the argument main.asm
; passes is ignored and the OS is asked instead -- which is the whole reason
; this is a platform routine and not shared code.
;
; GetCommandLineA hands back one string, so it is split here rather than by
; CommandLineToArgvW: that lives in shell32, wants wide characters, and would
; drag a second import library in for a job that is a loop over bytes. Quoting
; is honoured so a path with a space in it survives; the backslash rules MSVCRT
; applies inside quotes are not, because they only matter for arguments this
; stage does not have.
;
; The string is copied before it is split, because splitting is done by writing
; terminators into it and the one the OS hands back is not ours to write on.
;
; rbx = where we are in the string, r12 = how many arguments are split so far
sys_args_init:
    push    rbx
    push    r12
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    and     rsp, -16
    call    GetCommandLineA
    mov     rsp, rbp
    pop     rbp
    test    rax, rax
    jz      .done_empty
    lea     rbx, [cmd_buf]
    xor     ecx, ecx
.copy:
    cmp     rcx, CMD_CAP - 1
    jae     .copied
    movzx   edx, byte [rax + rcx]
    mov     [rbx + rcx], dl
    test    dl, dl
    jz      .copied
    inc     rcx
    jmp     .copy
.copied:
    mov     byte [rbx + rcx], 0
    xor     r12, r12

.next:
    movzx   eax, byte [rbx]             ; skip the gaps between arguments
    test    al, al
    jz      .done
    cmp     al, ' '
    je      .skip
    cmp     al, 9
    jne     .word
.skip:
    inc     rbx
    jmp     .next

.word:
    cmp     r12, ARGV_MAX
    jae     .done
    xor     r8d, r8d                    ; inside quotes?
    cmp     al, '"'
    jne     .record
    mov     r8d, 1
    inc     rbx
.record:
    lea     rcx, [argv_tab]
    mov     [rcx + r12 * CELL], rbx
    inc     r12
.scan:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .done
    cmp     al, '"'
    je      .quote
    test    r8d, r8d
    jnz     .step
    cmp     al, ' '
    je      .cut
    cmp     al, 9
    je      .cut
.step:
    inc     rbx
    jmp     .scan
.quote:
    xor     r8d, 1
    jmp     .cut_keep
.cut:
    mov     byte [rbx], 0               ; terminate in place
    inc     rbx
    jmp     .next
.cut_keep:
    mov     byte [rbx], 0
    inc     rbx
    jmp     .next

.done:
    mov     [argv_count], r12
    pop     r12
    pop     rbx
    ret
.done_empty:
    mov     qword [argv_count], 0
    pop     r12
    pop     rbx
    ret

; rdi = index -> rax = that argument, or 0 if there is no such one
sys_argv:
    cmp     rdi, [argv_count]
    jae     .none
    lea     rax, [argv_tab]
    mov     rax, [rax + rdi * CELL]
    ret
.none:
    xor     eax, eax
    ret

; rdi = NUL-terminated path -> rax = a handle, or -1 if it could not be opened.
;
; ANSI rather than wide, deliberately: the interpreter deals in bytes from top
; to bottom, and a path is one more thing that arrived as bytes. It costs
; non-ASCII filenames outside the active code page, which is a limitation worth
; naming rather than a wide-character layer worth carrying at this stage.
sys_open_read:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96
    and     rsp, -16
    mov     rcx, rdi                    ; lpFileName
    mov     edx, GENERIC_READ
    mov     r8d, FILE_SHARE_READ
    xor     r9d, r9d                    ; lpSecurityAttributes
    mov     qword [rsp+32], OPEN_EXISTING
    mov     qword [rsp+40], FILE_ATTR_NORMAL
    mov     qword [rsp+48], 0           ; hTemplateFile
    call    CreateFileA
    mov     rsp, rbp
    pop     rbp
    ret

; rdi = handle, rsi = buf, rdx = cap -> rax = bytes, 0 at the end
sys_read_file:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 96
    and     rsp, -16
    mov     [rbp-8], rsi
    mov     [rbp-16], rdx
    mov     qword [rbp-24], 0
    mov     rcx, rdi
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

; rdi = handle
sys_close:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 64
    and     rsp, -16
    mov     rcx, rdi
    call    CloseHandle
    mov     rsp, rbp
    pop     rbp
    ret

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
argv_count:
    resq    1
argv_tab:
    resq    ARGV_MAX
cmd_buf:
    resb    CMD_CAP
