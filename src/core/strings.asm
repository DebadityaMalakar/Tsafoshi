; SPDX-License-Identifier: MIT
;
; String literals: escape decoding, and an arena that interns the result.
;
; Like names these are never released. A string's value is its address, and a
; variable can hold that address, so a literal has to outlive the line it was
; written on -- resetting this arena per line the way ast.asm resets nodes
; would hand out dangling pointers the moment anyone wrote s = "hi".
;
; Interning is what makes that affordable: a line retyped at the prompt, or a
; loop body seen again, costs nothing after the first time.

%include "tsafoshi.inc"

    global  str_intern
    global  str_addr
    global  str_base
    global  str_escape

    extern  err_strspace
    extern  err_badescape

    section .text

; rdi = first byte after the opening quote, rsi = raw length, rdx = position
; for errors -> rax = offset into the arena, or -1 with the error recorded.
; rbx = source, r12 = one past its end, r13 = write offset, r14 = where this
; string started, r15 = the position to blame
str_intern:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    lea     r12, [rdi + rsi]
    mov     r15, rdx
    mov     r13, [str_used]
    mov     r14, r13
    mov     qword [str_failed], 0

.scan:
    cmp     rbx, r12
    jae     .decoded
    movzx   eax, byte [rbx]
    inc     rbx
    cmp     al, '\'
    jne     .plain
    call    escape
    cmp     qword [str_failed], 0
    jne     .fail
.plain:
    call    emit
    cmp     qword [str_failed], 0
    jne     .fail
    jmp     .scan

.decoded:
    xor     eax, eax
    call    emit                        ; NUL, so %s and the C world agree
    cmp     qword [str_failed], 0
    jne     .fail
    mov     rax, r13
    sub     rax, r14
    dec     rax                         ; the terminator is not part of it
    mov     r12, rax                    ; r12 = decoded length, source is done

; A linear search over what we already have. There are at most STR_MAX of
; them and this runs once per literal per line, not once per character.
    xor     ecx, ecx
.match:
    cmp     rcx, [str_count]
    jae     .commit
    lea     rax, [str_lens]
    mov     rax, [rax + rcx * CELL]
    cmp     rax, r12
    jne     .no_match
    lea     rax, [str_offs]
    mov     rdi, [rax + rcx * CELL]
    lea     rax, [str_arena]
    lea     rsi, [rax + r14]
    add     rdi, rax
    mov     rdx, r12
.byte:
    test    rdx, rdx
    jz      .reuse
    dec     rdx
    movzx   eax, byte [rdi + rdx]
    cmp     al, [rsi + rdx]
    je      .byte
.no_match:
    inc     rcx
    jmp     .match

.reuse:
    lea     rax, [str_offs]             ; the copy we just decoded is dropped
    mov     rax, [rax + rcx * CELL]     ; simply by not advancing str_used
    jmp     .out

.commit:
    mov     rcx, [str_count]
    cmp     rcx, STR_MAX
    jae     .no_room
    lea     rax, [str_offs]
    mov     [rax + rcx * CELL], r14
    lea     rax, [str_lens]
    mov     [rax + rcx * CELL], r12
    inc     qword [str_count]
    mov     [str_used], r13
    mov     rax, r14
    jmp     .out

.no_room:
    mov     rdi, r15
    call    err_strspace
.fail:
    mov     qword [str_failed], 0
    mov     rax, -1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; al = byte, appended at r13. Both helpers work on str_intern's registers
; directly, which is why they live here and not behind an argument list.
emit:
    cmp     r13, STR_CAP - 1
    jae     .full
    lea     rcx, [str_arena]
    mov     [rcx + r13], al
    inc     r13
    ret
.full:
    mov     rdi, r15
    call    err_strspace
    mov     qword [str_failed], 1
    ret

; rdi = just past the backslash, rsi = one past the last byte that could
; belong to the escape, rdx = position -> al = the byte, rdx = where scanning
; continues.
;
; The same routine a string literal uses, because a character constant escapes
; exactly the same way a string does -- there is no second table and no second
; set of rules, which is the only way the two can be guaranteed to agree.
str_escape:
    push    rbx
    push    r12
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r15, rdx
    call    escape
    mov     rdx, rbx
    pop     r15
    pop     r12
    pop     rbx
    ret

; The backslash is already consumed; rbx points at what follows it.
; -> al = the byte it stands for
escape:
    cmp     rbx, r12
    jae     .unknown
    movzx   eax, byte [rbx]
    inc     rbx
    cmp     al, 'x'
    je      .hex
    cmp     al, '0'
    jb      .simple
    cmp     al, '7'
    jbe     .octal

; The two tables are parallel, so a hit in one indexes the other.
.simple:
    lea     rcx, [esc_from]
    lea     rdx, [esc_to]
.simple_next:
    movzx   r8d, byte [rcx]
    test    r8b, r8b
    jz      .unknown
    cmp     r8b, al
    je      .simple_hit
    inc     rcx
    inc     rdx
    jmp     .simple_next
.simple_hit:
    movzx   eax, byte [rdx]
    ret

; C99 allows one to three octal digits; the first one is already in al.
.octal:
    sub     eax, '0'
    mov     ecx, 2
.octal_next:
    cmp     rbx, r12
    jae     .octal_done
    movzx   edx, byte [rbx]
    cmp     dl, '0'
    jb      .octal_done
    cmp     dl, '7'
    ja      .octal_done
    shl     eax, 3
    sub     edx, '0'
    add     eax, edx
    inc     rbx
    dec     ecx
    jnz     .octal_next
.octal_done:
    movzx   eax, al
    ret

; and any number of hex digits, but at least one
.hex:
    xor     eax, eax
    xor     r9d, r9d
.hex_next:
    cmp     rbx, r12
    jae     .hex_done
    movzx   edi, byte [rbx]
    call    hex_digit
    test    ecx, ecx
    js      .hex_done
    shl     eax, 4
    add     eax, ecx
    inc     rbx
    inc     r9d
    jmp     .hex_next
.hex_done:
    test    r9d, r9d
    jz      .unknown
    movzx   eax, al
    ret

.unknown:
    mov     rdi, r15
    call    err_badescape
    mov     qword [str_failed], 1
    xor     eax, eax
    ret

; dil = character -> ecx = its value, or -1
hex_digit:
    mov     ecx, edi
    sub     ecx, '0'
    cmp     ecx, 9
    jbe     .out
    mov     ecx, edi
    or      ecx, 32                     ; one fold handles A-F and a-f
    sub     ecx, 'a' - 10
    cmp     ecx, 15
    jbe     .out
    mov     ecx, -1
.out:
    ret

; rdi = offset -> rax = address
str_addr:
    lea     rax, [str_arena]
    add     rax, rdi
    ret

; ---------------------------------------------------------------------------
    section .data

; The simple escapes, as two parallel rows. A backslash-zero is not here:
; it arrives through the octal path, along with the rest of that form.
esc_from:
    db      "abfnrtv", 92, 39, '"', "?", 0
esc_to:
    db      7, 8, 12, 10, 13, 9, 11, 92, 39, '"', "?"

; ---------------------------------------------------------------------------
    section .bss

    alignb  8
str_used:
    resq    1
str_count:
    resq    1
str_failed:
    resq    1
str_offs:
    resq    STR_MAX
str_lens:
    resq    STR_MAX
str_base:
str_arena:
    resb    STR_CAP
