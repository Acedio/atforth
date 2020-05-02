; Need some way of having both SRAM words and PROGMEM words.
; If this is token-based, maybe signify in the LSB what kind of word the token
; is for?

#include <avr/io.h>

#include "macros.i"

#define CODEWORD_SIZE 2

; The interpreter pointer is r25:r24
#define IP_LREG 24
; The data stack pointer is Y (r28)
#define DS_LREG 28

#define RS0 0x100
#define DS0 0x180

; The dictionary address of the most recently defined word.
.set link,0

.text
; Interrupt vectors.
rjmp main ; RESET
rjmp main ; INT0
rjmp kb_clocked ; PCINT0
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop

.global DOCOL
DOCOL:
  PUSHRSP IP_LREG
  ; r23:22 contains the codeword's address.
  movw IP_LREG, r22
  ; Skip past the codeword to get to the first token.
  adiw IP_LREG, CODEWORD_SIZE
; Execute NEXT immediately.
.global NEXT
NEXT:
  ; Load the next token, which is an offset into the token table.
  movw ZL, IP_LREG ; load the address of the next token
  adiw IP_LREG, 1 ; increment the IP
  ; Load the token index into ZL. ZH is constant
  lpm ZL, Z
  ldi ZH, hi8(TOKEN_TABLE)

  ; Load the codeword's address from the token table. Keep it in r22 so DOCOL
  ; can read it later.
  lpm r22, Z+
  lpm r23, Z
  movw ZL, r22

  ; The codeword contains the address of the code to run for this word, so we
  ; need to jump to the address stored at the codeword.
  lpm r20, Z+
  lpm r21, Z
  movw ZL, r20
  ; Execute the codeword.
  ijmp

.global main
main:
  cli
  ; Intialize return stack
  ldi r16, lo8(RS0)
  out _SFR_IO_ADDR(SPL), r16
  ldi r16, hi8(RS0)
  out _SFR_IO_ADDR(SPH), r16

  ; Initialize data stack
  ldi DS_LREG, lo8(DS0)
  ldi DS_LREG+1, hi8(DS0)

  ; Initialize the interpreter pointer
  ldi IP_LREG, lo8(forth_main)
  ldi IP_LREG+1, hi8(forth_main)
  ; Call NEXT to kick things off.
  rjmp NEXT

; The default program!
forth_main:
  ; Wait because the keyboard is noisy on the busy line (TODO: I think?)
  lit 0x3FFF
  fw WAIT
  fw RAMINIT
  fw SERINIT
  fw LCDINIT
  fw KBINIT

  fw TRUE
  fw LEDSTORE

  fw QUIT ; Never returns.

defcode "RAMINIT",,RAMINIT
  ldi ZL, lo8(__data_load_start)
  ldi ZH, hi8(__data_load_start)
  ldi XL, lo8(__data_start)
  ldi XH, hi8(__data_start)
1:
  lpm r0, Z+
  st X+, r0
  ldi r16, lo8(__data_load_end)
  ldi r17, hi8(__data_load_end)
  sub r16, ZL
  sbc r17, ZH
  or r16, r17
  brne 1b
  rjmp NEXT

; == DEBUGGING TOOLS ==

; TICKS --
defword "WAIT",,WAIT
1:
  fw DECR ; D: T-1
  fw DUP  ; D: T-1 T-1
  fw ZEQU ; D: =0 T-1
  zbranch 1b ; D: T-1
  fw DROP ; D: empty
  fw EXIT

defword "LED!",,LEDSTORE
  fw LCD_RW_READ
  fw SWAP
  zbranch 1f
  fw LCD_LED
  fw OR
1:
  fw TOSER
  fw EXIT

; Blinks the LED if top of stack = 0, holds steady if != 0.
defword "TESTLED",,TESTLED
1:
  fw FALSE
  fw LEDSTORE

  lit 0x0FFF
  fw WAIT

  fw TRUE
  fw LEDSTORE

  lit 0x0FFF
  fw WAIT

  fw DUP
  zbranch 1b

1:
  fw FALSE
  zbranch 1b

; Blink indefinitely.
defword "BLINK",,BLINK
1:
  fw LCD_LED
  fw LCD_RW_READ
  fw OR
  fw TOSER
  lit 0x0FFF
  fw WAIT

  fw LCD_RW_READ
  fw TOSER
  lit 0x0FFF
  fw WAIT

  fw FALSE
  zbranch 1b

; == STACK MANIPULATION ==

defcode "DROP",,DROP
  adiw Y, 2
  rjmp NEXT

defcode "SWAP",,SWAP
  POPDSP 0
  POPDSP 2
  PUSHDSP 0
  PUSHDSP 2
  rjmp NEXT

defcode "DUP",,DUP
  ; MSB is top of stack, LSB is next
  ldd r0, Y+1
  ld r1, Y
  PUSHDSP 0
  rjmp NEXT

defcode "OVER",,OVER
  ldd r0, Y+3
  ldd r1, Y+2
  PUSHDSP 0
  rjmp NEXT

defcode "ROT",,ROT
  ; Bring the third item to the top.
  POPDSP 0
  POPDSP 2
  POPDSP 4
  PUSHDSP 2
  PUSHDSP 0
  PUSHDSP 4
  rjmp NEXT

defword "-ROT",,NROT
  fw ROT
  fw ROT
  fw EXIT

defword "2DROP",,TWODROP
  fw DROP
  fw DROP
  fw EXIT

defword "2DUP",,TWODUP
  fw OVER
  fw OVER
  fw EXIT

; == RETURN STACK MANIPULATION ==

defcode ">R",,TOR
  POPDSP 0
  PUSHRSP 0
  rjmp NEXT

defcode "R>",,FROMR
  POPRSP 0
  PUSHDSP 0
  rjmp NEXT

defcode "RSP@",,RSPFETCH
  in r0, _SFR_IO_ADDR(SPL)
  in r1, _SFR_IO_ADDR(SPH)
  PUSHDSP 0
  rjmp NEXT

defcode "RSP!",,RSPSTORE
  POPDSP 0
  out _SFR_IO_ADDR(SPL), r0
  out _SFR_IO_ADDR(SPH), r1
  rjmp NEXT

defcode "RDROP",,RDROP
  POPRSP 0
  rjmp NEXT

defcode "DSP@",,DSPFETCH
  ; PUSHDSP isn't atomic, so need to buffer it via a different register.
  movw r0, DS_LREG
  PUSHDSP 0
  rjmp NEXT

defcode "DSP!",,DSPSTORE
  ; POPDSP isn't atomic, so need to buffer it via a different register.
  POPDSP 0
  movw DS_LREG, r0
  rjmp NEXT

; Relative branch.
defcode "0BRANCH",,ZBRANCH
  ; Push the next word onto the data stack.
  movw ZL, IP_LREG
  ; TODO: This could just be a byte, but would require extending the byte into a
  ; word.
  lpm r0, Z+
  lpm r1, Z+
  POPDSP 2
  or r2, r3
  brne 1f  ; If top of stack is 0, we'll modify Z to branch.
  add ZL, r0
  adc ZH, r1
1:
  movw IP_LREG, ZL
  rjmp NEXT

; == ARITHMETIC ==

defcode "+",,ADD
  POPDSP 0
  POPDSP 2
  add r0, r2
  adc r1, r3
  PUSHDSP 0
  rjmp NEXT

defcode "-",,SUB
  POPDSP 0
  POPDSP 2
  sub r0, r2
  sbc r1, r3
  PUSHDSP 0
  rjmp NEXT

defword "1+",,INCR
  lit 1
  fw ADD
  fw EXIT

defword "1-",,DECR
  lit -1
  fw ADD
  fw EXIT

defcode "2*",,ASL
  POPDSP 0
  lsl r0 ; shift into carry
  rol r1 ; shifts carry into low bit
  PUSHDSP 0
  rjmp NEXT

defcode "2/",,ASR
  POPDSP 0
  asr r1 ; leave high bit, shift rest, shift into carry
  ror r0 ; shifts carry into high bit
  PUSHDSP 0
  rjmp NEXT

defcode "AND",,AND
  POPDSP 0
  POPDSP 2
  and r0, r2
  and r1, r3
  PUSHDSP 0
  rjmp NEXT

defcode "OR",,OR
  POPDSP 0
  POPDSP 2
  or r0, r2
  or r1, r3
  PUSHDSP 0
  rjmp NEXT

defcode "XOR",,XOR
  POPDSP 0
  POPDSP 2
  eor r0, r2
  eor r1, r3
  PUSHDSP 0
  rjmp NEXT

defcode "INVERT",,INVERT
  POPDSP 0
  com r0
  com r1
  PUSHDSP 0
  rjmp NEXT

; Switch the high and low bytes.
defcode "SWIZZLE",,SWIZZLE
  POPDSP 0
  mov r2, r0
  mov r0, r1
  mov r1, r2
  PUSHDSP 0
  rjmp NEXT

defcode "0=",,ZEQU
  POPDSP 30
  ser r16
  adiw r30, 0
  breq 1f 
  clr r16 ; Clear all bits in r16 if the Z flag is cleared.
1:
  mov r17, r16 ; Mirror into r16
  PUSHDSP 16
  rjmp NEXT

defcode "0<",,ZLT
  POPDSP 30
  ser r16
  adiw r30, 0
  brlt 1f 
  clr r16 ; Clear all bits in r16 if the Z flag is cleared.
1:
  mov r17, r16 ; Mirror into r16
  PUSHDSP 16
  rjmp NEXT

defword "0>",,ZGT
  fw DUP
  fw ZEQU
  fw ZEQU
  fw SWAP
  fw ZLT
  fw ZEQU
  fw AND
  fw EXIT

defword "=",,EQU
  fw SUB
  fw ZEQU
  fw EXIT

defword "<>",,NEQU
  fw EQU
  fw ZEQU
  fw EXIT

defword ">",,GT
  fw SUB
  fw ZGT
  fw EXIT

defword "<",,LT
  fw SUB
  fw ZLT
  fw EXIT

; == MEMORY COMMANDS ==

defcode "C!",,STOREBYTE
  POPDSP 30 ; address
  POPDSP 0 ; data
  st Z, r0
  rjmp NEXT

defcode "C@",,FETCHBYTE
  POPDSP 30 ; address
  ld r16, Z
  ldi r17, 0
  PUSHDSP 16
  rjmp NEXT

; (addr data -- )
defword "!",,STORE
  ; Store high byte.
  fw OVER
  fw SWIZZLE
  fw OVER
  fw INCR
  fw STOREBYTE
  ; Store low byte.
  fw STOREBYTE
  fw EXIT

; (addr -- data)
defword "@",,FETCH
  fw DUP
  ; Low byte
  fw FETCHBYTE
  fw SWAP
  ; High byte
  fw INCR
  fw FETCHBYTE
  fw SWIZZLE
  ; Combine
  fw OR
  fw EXIT

defcode "ROMC@",,ROMFETCHBYTE
  POPDSP 30
  lpm r16, Z
  ldi r17, 0
  PUSHDSP 16
  rjmp NEXT

defword "ROM@",,ROMFETCH
  fw DUP
  fw ROMFETCHBYTE
  fw SWAP
  fw INCR
  fw ROMFETCHBYTE
  fw SWIZZLE
  fw OR
  fw EXIT

; == FLAGS ==

; FLAGSVAR FLAG --
defword "SETFLAG",,SETFLAG
  fw SWAP
  fw OVER
  fw FETCH
  fw OR
  fw SWAP
  fw STORE
  fw EXIT

; FLAGSVAR FLAG --
defword "CLRFLAG",,CLRFLAG
  fw SWAP
  fw INVERT
  fw OVER
  fw FETCH
  fw AND
  fw SWAP
  fw STORE
  fw EXIT

; FLAGSVAR FLAG -- IS_SET
defword "CHECKFLAG",,CHECKFLAG
  fw FETCH
  fw AND
  fw ZEQU
  fw ZEQU
  fw EXIT

; DUPs the return address so that a copy of the LOOP point still exists even
; after EXITing from this word.
defword "LOOP",,LOOP
  fw FROMR
  fw DUP
  fw TOR
  fw TOR
  fw EXIT

; pred a b -- pred ? a : b
defword "TERN",,TERN
  fw DUP ; pred pred a b
  fw ROT ; a pred pred b
  fw AND ; a? pred b
  fw NROT ; pred b a?
  fw INVERT ; !pred b a?
  fw AND ; b? a?
  fw OR
  fw EXIT

; Branches to the top of RSP if COND, else exits normally. Caller needs to RDROP
; the loop point after the loop terminates.
defword "WHILE",,WHILE
  ; D: COND R: NORMAL IFTRUE
  fw FROMR ; NORMAL COND
  fw FROMR ; IFTRUE NORMAL COND
  fw DUP
  fw TOR   ; D: IFTRUE NORMAL COND R: IFTRUE
  fw ROT   ; D: COND IFTRUE NORMAL R: IFTRUE
  fw TERN  ; D: next R: IFTRUE
  fw TOR
  ; Maybe conditionally RDROP so the caller doesn't have to?
  fw EXIT

; Calculate the Nth triangle number with some awful stack manipulation.
; n -- the nth triangle number
defword "TRI",,TRI
  lit 0 ; running sum
  fw LOOP ; D: SUM N -- R: LOOP

  fw OVER ; N SUM N
  fw ADD  ; NSUM N
  fw SWAP ; N NSUM
  fw DECR ; N-1 NSUM
  fw SWAP ; NSUM N-1
  fw OVER ; N-1 NSUM N-1
  fw ZEQU  ; ISZERO NSUM N-1
  fw INVERT ; !ISZERO NSUM N-1
  fw WHILE
  fw RDROP

  fw ADD ; Drop the arg (which is 0 now)
  fw EXIT

; == I/O ==

#define SBUF_SIZE 0x20

defcode "SBUF",,SBUF
  ldi r16, lo8(var_SBUF)
  ldi r17, hi8(var_SBUF)
  PUSHDSP 16
  rjmp NEXT
.data
.balign SBUF_SIZE
var_SBUF:
.fill SBUF_SIZE, 1, 0
.text

defstring "GREETING",,GREETING,"Hello, world!"

defword "WORD",,WORD
1:
  fw KEY

  fw DUP
  lit ' '
  fw EQU
  zbranch 2f
  fw DROP ; drop the space
  fw FALSE
  zbranch 1b
2:
  
  fw SBUF ; Cursor.
  fw SWAP
1: ; CHAR CURSOR --
  fw OVER
  fw STOREBYTE

  fw INCR
  fw KEY

  fw DUP
  lit ' '
  fw EQU
  zbranch 1b

  fw DROP
  fw SBUF
  fw SWAP
  fw SUB
  fw SBUF
  fw SWAP ; length on top
  fw EXIT

defword "EMIT",,EMIT
  fw SWIZZLE   ; Put char in high byte.
  fw LCD_RS_DR ; Data register.
  fw OR
  fw LCDCMD
  fw EXIT

defword "WRITEWORD",,WRITEWORD
  lit 4
1:
  fw SWAP
  fw DUP
  ; Move to bottom nibble
  fw SWIZZLE
  fw ASR
  fw ASR
  fw ASR
  fw ASR
  fw TOHEX
  fw EMIT
  ; Shift left 4 bits to move to the next digit.
  fw ASL
  fw ASL
  fw ASL
  fw ASL
  fw SWAP
  fw DECR
  fw DUP
  fw ZEQU
  zbranch 1b
  fw DROP
  fw DROP
  fw EXIT

; LEN ADDR --
defword "TELL",,TELL
1:
  fw DUP
  zbranch 2f
  fw DECR
  fw SWAP
  fw DUP
  fw FETCHBYTE
  fw EMIT
  fw INCR
  fw SWAP
  fw FALSE
  zbranch 1b
2:
  fw DROP
  fw DROP
  fw EXIT

; == STRINGS ==

; Parses an ASCII value as a hex digit.
; DIGIT -- SUCCESS NUMBER
defword "DIGIT",,DIGIT
  fw DUP
  lit 'a'-1
  fw LT
  fw OVER
  lit 'f'+1
  fw GT
  fw AND
  zbranch 1f
  lit 'a'-10
  fw SWAP
  fw SUB
  fw TRUE
  fw EXIT
1:
  fw DUP
  lit 'A'-1
  fw LT
  fw OVER
  lit 'F'+1
  fw GT
  fw AND
  zbranch 1f
  lit 'A'-10
  fw SWAP
  fw SUB
  fw TRUE
  fw EXIT
1:
  fw DUP
  lit '0'-1
  fw LT
  fw OVER
  lit '9'+1
  fw GT
  fw AND
  zbranch 1f
  lit '0'
  fw SWAP
  fw SUB
  fw TRUE
  fw EXIT
1:
  fw FALSE
  fw EXIT

; Parses a hex number. TODO: negatives, decimal+other bases
; LEN ADDR -- SUCCESS NUMBER
defword "NUMBER",,NUMBER
  ; Check for zero.
  fw DUP
  fw ZEQU
  zbranch 1f
  fw DROP
  fw FALSE
  fw EXIT
1: ; LEN INDEX
  lit 0
  fw TOR
2: ; LEN INDEX R: TOTAL
  fw DECR
  fw SWAP
  fw DUP ; INDEX INDEX LEN
  fw FETCHBYTE ; CHAR INDEX LEN
  fw DIGIT ; SUCCESS NUMBER INDEX LEN
  fw ZEQU ; NOTSUCCESS NUMBER INDEX LEN
  zbranch 1f ; NUMBER INDEX LEN
  fw RDROP
  fw DROP ; INDEX GARBAGE
  fw DROP ; GARBAGE
  fw FALSE ; FALSE GARBAGE
  fw EXIT
1: ; NUMBER INDEX LEN

  fw FROMR
  fw ASL
  fw ASL
  fw ASL
  fw ASL
  fw ADD
  fw TOR

  fw INCR
  fw SWAP
  fw DUP
  fw ZEQU
  zbranch 2b
  fw DROP
  fw DROP
  fw FROMR
  fw TRUE
  fw EXIT

; Lowest 4 bits to hex digit
defword "TOHEX",,TOHEX
  lit 0x000F
  fw AND
  fw DUP
  lit 10
  fw GT
  zbranch 1f
  lit '0'
  fw ADD
  fw EXIT
1:
  lit 'A' - 10
  fw ADD
  fw EXIT

; TODO: Right now, ADDR1 must be in progmem. Maybe copy it into RAM?
; LEN1 ADDR1 LEN2 ADDR2 -- EQUAL
defword "STREQU",,STREQU
  fw ROT
  fw OVER ; LEN1 LEN2 LEN1 ADDR1 ADDR2
  fw NEQU
  zbranch 1f
  ; Not equal lengths.
  fw DROP
  fw DROP
  fw DROP
  fw FALSE
  fw EXIT
1: ; LEN ADDR1 ADDR2

  fw DUP
  fw ZEQU
  zbranch 2f
  fw DROP
  fw DROP
  fw DROP
  fw TRUE
  fw EXIT
2:

  fw DECR
  fw NROT ; ADDR1 ADDR2 LEN-1
  fw OVER
  fw FETCHBYTE ; *ADDR2
  fw OVER
  fw ROMFETCHBYTE ; *ADDR1
  fw NEQU ; NEQU ADDR1 ADDR2 LEN-1
  zbranch 2f
  fw DROP
  fw DROP
  fw DROP
  fw FALSE
  fw EXIT
2:

  fw INCR
  fw NROT
  fw INCR
  fw NROT
  fw FALSE
  zbranch 1b

; == INTERPRETING ==

defvar "STATE",,STATE
defvar "HERE",,HERE
defvar "S0",,SZ,DS0

defconst "R0",,RZ,RS0
defconst "DOCOL",,__DOCOL,DOCOL
defconst "F_IMMED",,F_IMMED,0x80
defconst "F_HIDDEN",,F_HIDDEN,0x20
defconst "F_LENMASK",,F_LENMASK,0x1f
defconst "TRUE",,TRUE,0xFFFF
defconst "FALSE",,FALSE,0x0

; Returns from current word and starts executing the top of the return stack.
defcode "EXIT",,EXIT
  POPRSP IP_LREG
  rjmp NEXT

defcode "LIT",,LIT
  ; Push the next word onto the data stack.
  movw ZL, IP_LREG
  adiw IP_LREG, 2
  lpm r0, Z+
  lpm r1, Z
  PUSHDSP 0
  rjmp NEXT

; LEN ADDR -- NAMEPTR
defword "FIND",,FIND
  fw LATEST
  fw FETCH ; *LATEST LEN ADDR
  fw TOR
1: ; =LEN =ADDR R: THIS
  fw TWODUP
  fw FROMR
  fw DUP
  fw TOR ; THIS =LEN =ADDR =LEN =ADDR R: THIS
  fw INCR
  fw INCR
  fw DUP
  fw INCR ; ADDR &FLAGS =LEN =ADDR =LEN =ADDR
  fw SWAP
  fw ROMFETCHBYTE ; FLAGS ADDR =LEN =ADDR =LEN =ADDR
  fw F_LENMASK
  fw F_HIDDEN
  fw OR
  fw AND ; LEN|HIDDEN ADDR =LEN =ADDR =LEN =ADDR
  fw STREQU

  zbranch 2f
  fw DROP
  fw DROP
  fw FROMR ; Found it!
  fw EXIT
2:
  
  fw FROMR
  fw ROMFETCH ; NEXT =LEN =ADDR

  fw DUP
  fw ZEQU
  zbranch 2f
  fw NROT ; save the zero
  fw DROP
  fw DROP
  fw EXIT
2:
  
  fw TOR ; =LEN =ADDR R: NEXT
  fw FALSE
  zbranch 1b

defword ">CFA",,TOCFA
  fw INCR
  fw INCR
  fw DUP
  fw ROMFETCHBYTE
  fw F_LENMASK
  fw AND
  fw INCR ; + 1 to also skip the FLAGS
  fw ADD
  fw INCR ; + 1 and AND to round to next word boundary
  fw TRUE
  fw DECR ; 0xFFFE
  fw AND
  fw EXIT

defword ">DFA",,TODFA
  fw TOCFA
  fw INCR
  fw EXIT

defword "QUIT",,QUIT
  fw RZ
  fw RSPSTORE
1:
  fw INTERPRET
  fw FALSE
  zbranch 1b

defcode "__EXE",,__EXE
  POPDSP 30

  ; Move codeword address into r22:23 so it's accessible by DOCOL.
  movw r22, Z

  ; Load the codeword.
  lpm r20, Z+
  lpm r21, Z

  ; Execute (jump to) the codeword. Eventually NEXT will be called and we'll
  ; return to EXECUTE, below.
  movw ZL, r20
  ijmp

; xt -- R: codeword
defword "EXECUTE",,EXECUTE
  fw TOCFA
  fw __EXE
  fw EXIT

defword "INTERPRET",,INTERPRET
  fw LCDDISABLE
  fw KBENABLE
  fw WORD
  fw KBDISABLE
  fw LCDCLEAR
  fw TWODUP
  fw TELL

  fw TWODUP
  fw FIND
  fw DUP
  zbranch 1f
  ; found word, execute it
  fw NROT
  fw TWODROP ; drop name
  fw EXECUTE
  fw EXIT
1:
  fw DROP ; drop zero

  fw TWODUP
  fw NUMBER
  zbranch 1f
  fw NROT ; Leave number on stack
  fw TWODROP
  fw EXIT
1:
  ; error, name not found and not a literal.
  fw EXIT

; The last word in the dictionary
defvar "LATEST",,LATEST,name_LATEST
