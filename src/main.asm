; SPDX-License-Identifier: MIT
;
; Process entry point, both platforms.
;
; The loader hands us a 16-byte aligned stack with no return address below it
; (Linux puts argc there, Windows nothing), so the only setup needed is to
; force that alignment and cut the frame chain. Everything platform-specific
; lives behind the sys_* routines in src/<platform>/.
;
; The one thing that has to happen before the alignment is handing the initial
; stack pointer to sys_args_init, because on Linux the command line is on that
; stack and nowhere else. Windows ignores the argument and asks the OS instead.
; This file still names no platform: it passes rsp on and lets each target
; decide whether that was useful.
;
; Linux ld picks _start up by default; the Windows linkers are told
; /entry:_start explicitly.

%include "tsafoshi.inc"

    global  _start

    extern  repl_main
    extern  sys_args_init
    extern  sys_exit

    section .text

_start:
    mov     rdi, rsp
    and     rsp, -16
    xor     rbp, rbp
    call    sys_args_init
    call    repl_main                   ; normally exits from inside the loop
    xor     edi, edi
    jmp     sys_exit
