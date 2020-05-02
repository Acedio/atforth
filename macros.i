#ifndef MACROS_I
#define MACROS_I

; == ASM STACK INTERACTION ==

; Must use the register number (e.g. 24 instead of r24)
.macro PUSHRSP reg
  push \reg
  push \reg + 1
.endm

.macro POPRSP reg
  pop \reg + 1
  pop \reg
.endm

.macro PUSHDSP reg
  st -Y, \reg
  st -Y, \reg + 1
.endm

.macro POPDSP reg
  ld \reg + 1, Y+
  ld \reg, Y+
.endm

; == WORD DEFINITIONS ==

.macro defword name, flags=0, label
  .text
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  ; TODO: ORing defconst flags together doesn't seem to work.
  .byte \flags|(nameend_\label - . - 1) ; flags + length of the name
  .ascii "\name" ; the name
nameend_\label :
  .balign 2
  .global \label
\label :
  .word pm(DOCOL) ; Codeword
  ; list of word tokens follow
.endm

.macro defcode name, flags=0, label
  .text
  .balign 2
  .global name_\label
name_\label :
  .word link ; link to the previously defined word
  .set link,name_\label
  .byte \flags|(nameend_\label - . - 1) ; flags + length of the name
  .ascii "\name" ; the name
nameend_\label :
  .balign 2
  .global \label
\label :
  .word pm(code_\label) ; Codeword
  .balign 2
  .global code_\label
code_\label :
  ; list of word tokens follow
.endm

.macro defvar name, flags=0, label, initial=0
  defcode \name,\flags,\label
  ldi r16, lo8(var_\label)
  ldi r17, hi8(var_\label)
  PUSHDSP 16
  rjmp NEXT
  .data
var_\label:
  .word \initial
  .text
.endm

.macro defconst name, flags=0, label, value
  .set value_\name, value
  defcode \name,\flags,\label
  ldi r16, lo8(\value)
  ldi r17, hi8(\value)
  PUSHDSP 16
  rjmp NEXT
.endm

; TODO: Make this push the length on as well.
.macro defstring name, flags=0, label, value
  defconst "\name",\flags,\label,string_\label
string_\label :
  .string "\value"
.endm

; == WORD TOKENS ==

.macro fw name
  .byte T_\name
.endm

.macro lit word
  fw LIT
  .word \word
.endm

.macro zbranch rel
  fw ZBRANCH
  .word \rel - . - 2
.endm

#endif
