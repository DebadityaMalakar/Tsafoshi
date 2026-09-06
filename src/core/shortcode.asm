; SPDX-License-Identifier: MIT
;
; One codepoint -> one ASCII shortcode, Discord-style.
;
; Sooner or later somebody types an emoji into a variable name, on purpose, to
; see what happens. This is what happens: the lexer transliterates it before
; anything else sees it, so 💀 becomes `:skull` and the name table stays what
; it has always been -- short, fixed-width, ASCII, comparable with one loop
; over bytes. Nothing downstream of the lexer learns that Unicode exists.
;
; That is the whole trick, and it is deliberately the cheap half of the job.
; The alternative is a name table that stores UTF-8, which means every compare
; and every listing and every error message grows a notion of what a character
; is; this way exactly one file has one, and it is the file next door.
;
; The table is the common emoji rather than all of them. There are several
; thousand, they are added to every year, and shipping the register would be a
; large fraction of this binary for a feature that is mostly a joke. What is
; not a joke is that an unlisted one still has to work, so anything missing
; falls back to its codepoint in hex -- `:u1f4a9` -- which is unique, stable,
; and still ASCII. The same applies to every non-emoji script: an identifier
; in Greek or Cyrillic or CJK is transliterated the same way and works for the
; same reason.
;
; Zero-width joiners and skin tones get names of their own rather than being
; dropped, because 👍🏽 and 👍 are two different identifiers and a language that
; quietly conflated them would be worse than one that refused both.

%include "tsafoshi.inc"

    global  shortcode_of

SHORTCODE_MAX       equ 24              ; the longest thing this can write

    section .text

; rdi = codepoint, rsi = where to write -> rax = how many bytes it wrote.
;
; Zero for the presentational codepoints: a variation selector says how to draw
; the character before it and is not part of the name of anything, so ❤️ and ❤
; are the same identifier -- which they are, and which is what somebody pasting
; from a chat window will expect.
;
; rbx = the destination, r12 = the codepoint
shortcode_of:
    push    rbx
    push    r12
    mov     rbx, rsi
    mov     r12, rdi

    cmp     r12, 0xFE00                 ; the variation selectors
    jb      .not_selector
    cmp     r12, 0xFE0F
    jbe     .nothing
.not_selector:

    lea     rcx, [codes]
.search:
    mov     rax, [rcx]
    test    rax, rax
    jz      .hex
    cmp     rax, r12
    je      .found
    add     rcx, CELL * 2
    jmp     .search

.found:
    mov     rsi, [rcx + CELL]
    mov     byte [rbx], ':'
    mov     rax, 1
.copy:
    movzx   ecx, byte [rsi]
    test    cl, cl
    jz      .done
    mov     [rbx + rax], cl
    inc     rax
    inc     rsi
    jmp     .copy

; Not in the table, so it becomes what it unambiguously is. Four hex digits
; minimum, so no short one can be a prefix of a longer one the way ":u1f4" and
; ":u1f48" would be.
;
; r8 = which nibble, counting down from the top
.hex:
    mov     word [rbx], ':' | ('u' << 8)
    mov     rax, 2
    mov     r8, 4
    mov     rdx, r12
    shr     rdx, 16
    jz      .emit
    mov     r8, 5
    mov     rdx, r12
    shr     rdx, 20
    jz      .emit
    mov     r8, 6
.emit:
    dec     r8
.digit:
    mov     rcx, r8
    shl     rcx, 2
    mov     rdx, r12
    shr     rdx, cl
    and     rdx, 0x0F
    lea     r9, [hex_digits]
    movzx   edx, byte [r9 + rdx]
    mov     [rbx + rax], dl
    inc     rax
    test    r8, r8
    jz      .done
    dec     r8
    jmp     .digit

.nothing:
    xor     eax, eax
.done:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
    section .data

hex_digits:
    db      "0123456789abcdef"

n_skull:
    db      "skull", 0
n_sob:
    db      "sob", 0
n_joy:
    db      "joy", 0
n_rofl:
    db      "rofl", 0
n_sweat_smile:
    db      "sweat_smile", 0
n_blush:
    db      "blush", 0
n_sunglasses:
    db      "sunglasses", 0
n_thinking:
    db      "thinking", 0
n_scream:
    db      "scream", 0
n_upside_down:
    db      "upside_down", 0
n_triumph:
    db      "triumph", 0
n_pleading:
    db      "pleading", 0
n_flushed:
    db      "flushed", 0
n_exploding_head:
    db      "exploding_head", 0
n_cold_face:
    db      "cold_face", 0
n_melting_face:
    db      "melting_face", 0
n_salute:
    db      "salute", 0
n_fire:
    db      "fire", 0
n_sparkles:
    db      "sparkles", 0
n_hundred:
    db      "100", 0
n_tada:
    db      "tada", 0
n_rocket:
    db      "rocket", 0
n_zap:
    db      "zap", 0
n_star2:
    db      "star2", 0
n_star:
    db      "star", 0
n_heart:
    db      "heart", 0
n_broken_heart:
    db      "broken_heart", 0
n_thumbsup:
    db      "thumbsup", 0
n_thumbsdown:
    db      "thumbsdown", 0
n_eyes:
    db      "eyes", 0
n_point_up:
    db      "point_up", 0
n_point_right:
    db      "point_right", 0
n_pray:
    db      "pray", 0
n_clap:
    db      "clap", 0
n_handshake:
    db      "handshake", 0
n_muscle:
    db      "muscle", 0
n_brain:
    db      "brain", 0
n_poop:
    db      "poop", 0
n_snake:
    db      "snake", 0
n_crab:
    db      "crab", 0
n_bug:
    db      "bug", 0
n_penguin:
    db      "penguin", 0
n_lobster:
    db      "lobster", 0
n_coffee:
    db      "coffee", 0
n_pizza:
    db      "pizza", 0
n_video_game:
    db      "video_game", 0
n_joystick:
    db      "joystick", 0
n_computer:
    db      "computer", 0
n_keyboard:
    db      "keyboard", 0
n_desktop:
    db      "desktop", 0
n_package:
    db      "package", 0
n_file_folder:
    db      "file_folder", 0
n_memo:
    db      "memo", 0
n_wrench:
    db      "wrench", 0
n_hammer:
    db      "hammer", 0
n_gear:
    db      "gear", 0
n_puzzle:
    db      "puzzle", 0
n_dart:
    db      "dart", 0
n_trophy:
    db      "trophy", 0
n_lock:
    db      "lock", 0
n_key:
    db      "key", 0
n_warning:
    db      "warning", 0
n_x:
    db      "x", 0
n_check:
    db      "white_check_mark", 0
n_heavy_check:
    db      "heavy_check_mark", 0
n_question:
    db      "question", 0
n_exclamation:
    db      "exclamation", 0
n_recycle:
    db      "recycle", 0
n_rainbow:
    db      "rainbow", 0
n_moon:
    db      "moon", 0
n_sun:
    db      "sun", 0
n_earth:
    db      "earth", 0
n_musical_note:
    db      "musical_note", 0
n_bell:
    db      "bell", 0
n_pushpin:
    db      "pushpin", 0
n_moyai:
    db      "moyai", 0
n_speaking_head:
    db      "speaking_head", 0
n_zwj:
    db      "zwj", 0
n_tone1:
    db      "tone1", 0
n_tone2:
    db      "tone2", 0
n_tone3:
    db      "tone3", 0
n_tone4:
    db      "tone4", 0
n_tone5:
    db      "tone5", 0

; codepoint, name. A zero codepoint ends it. Names are Discord's where Discord
; has one, because that is the set people already have in their fingers.
    align   8
codes:
    dq      0x1F480, n_skull
    dq      0x1F62D, n_sob
    dq      0x1F602, n_joy
    dq      0x1F923, n_rofl
    dq      0x1F605, n_sweat_smile
    dq      0x1F60A, n_blush
    dq      0x1F60E, n_sunglasses
    dq      0x1F914, n_thinking
    dq      0x1F631, n_scream
    dq      0x1F643, n_upside_down
    dq      0x1F624, n_triumph
    dq      0x1F97A, n_pleading
    dq      0x1F633, n_flushed
    dq      0x1F92F, n_exploding_head
    dq      0x1F976, n_cold_face
    dq      0x1FAE0, n_melting_face
    dq      0x1FAE1, n_salute
    dq      0x1F525, n_fire
    dq      0x2728, n_sparkles
    dq      0x1F4AF, n_hundred
    dq      0x1F389, n_tada
    dq      0x1F680, n_rocket
    dq      0x26A1, n_zap
    dq      0x1F31F, n_star2
    dq      0x2B50, n_star
    dq      0x2764, n_heart
    dq      0x1F494, n_broken_heart
    dq      0x1F44D, n_thumbsup
    dq      0x1F44E, n_thumbsdown
    dq      0x1F440, n_eyes
    dq      0x261D, n_point_up
    dq      0x1F449, n_point_right
    dq      0x1F64F, n_pray
    dq      0x1F44F, n_clap
    dq      0x1F91D, n_handshake
    dq      0x1F4AA, n_muscle
    dq      0x1F9E0, n_brain
    dq      0x1F4A9, n_poop
    dq      0x1F40D, n_snake
    dq      0x1F980, n_crab
    dq      0x1F41B, n_bug
    dq      0x1F427, n_penguin
    dq      0x1F99E, n_lobster
    dq      0x2615, n_coffee
    dq      0x1F355, n_pizza
    dq      0x1F3AE, n_video_game
    dq      0x1F579, n_joystick
    dq      0x1F4BB, n_computer
    dq      0x2328, n_keyboard
    dq      0x1F5A5, n_desktop
    dq      0x1F4E6, n_package
    dq      0x1F4C1, n_file_folder
    dq      0x1F4DD, n_memo
    dq      0x1F527, n_wrench
    dq      0x1F528, n_hammer
    dq      0x2699, n_gear
    dq      0x1F9E9, n_puzzle
    dq      0x1F3AF, n_dart
    dq      0x1F3C6, n_trophy
    dq      0x1F512, n_lock
    dq      0x1F511, n_key
    dq      0x26A0, n_warning
    dq      0x274C, n_x
    dq      0x2705, n_check
    dq      0x2714, n_heavy_check
    dq      0x2753, n_question
    dq      0x2757, n_exclamation
    dq      0x267B, n_recycle
    dq      0x1F308, n_rainbow
    dq      0x1F319, n_moon
    dq      0x2600, n_sun
    dq      0x1F30D, n_earth
    dq      0x1F3B5, n_musical_note
    dq      0x1F514, n_bell
    dq      0x1F4CC, n_pushpin
    dq      0x1F5FF, n_moyai
    dq      0x1F5E3, n_speaking_head
    dq      0x200D, n_zwj
    dq      0x1F3FB, n_tone1
    dq      0x1F3FC, n_tone2
    dq      0x1F3FD, n_tone3
    dq      0x1F3FE, n_tone4
    dq      0x1F3FF, n_tone5
    dq      0, 0
