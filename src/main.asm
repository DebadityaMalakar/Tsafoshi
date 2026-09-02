; SPDX-License-Identifier: MIT
;
; Process entry point, both platforms.
;
; The loader hands us a 16-byte aligned stack with no return address below it
; (Linux puts argc there, Windows nothing), so the only setup needed is to
; force that alignment and cut the frame chain. Everything platform-specific
; lives behind the sys_* routines in src/<platform>/input.asm.
;
; Linux ld picks _start up by default; the Windows linkers are told
; /entry:_start explicitly.

%include "tsafoshi.inc"

    global  _start

    extern  repl_main
    extern  sys_exit

    section .text

_start:
    and     rsp, -16
    xor     rbp, rbp
    call    repl_main                   ; normally exits from inside the loop
    xor     edi, edi
    jmp     sys_exit
