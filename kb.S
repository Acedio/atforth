#include <avr/io.h>

#include "macros.i"

#define KB_BUS_PIN 0
#define KB_CLK_PIN 4

#define PS2_STATE_REG 8
#define PS2_DATA_REG 9

#define PS2_ERROR 0
#define PS2_START 1
; 2-9 are data bits
#define PS2_PARITY 10
#define PS2_STOP 11

#define KBUF_SIZE 0x08
#define KBUF_MASK 0x07

; Interrupt called whenever the PS2 clock pin changes.
.global kb_clocked
kb_clocked:
  ; We read the data pin when the clock falls, so return if it's high.
  sbic _SFR_IO_ADDR(PINB), KB_CLK_PIN
  reti

  push r30
  push r31
  in r30, _SFR_IO_ADDR(SREG)
  push r30

  rcall kb_clk_fall

  pop r30
  out _SFR_IO_ADDR(SREG), r30
  pop r31
  pop r30
  reti

kb_clk_fall:
  ; Wait ~25us because we should read the data line in between clock pulses.
  ; TODO: Waiting is necessary but should probably let other processes continue.
  ldi r30, 67
1:
  dec r30  ; 1 clk
  brne 1b ; 2 clk on loop

  ; Read bus pin
  in r31, _SFR_IO_ADDR(PINB)

  mov r30, PS2_STATE_REG

  ; <= 0 is Error
  tst r30
  brlt ps2_error
  breq ps2_error
  cpi r30, PS2_START
  breq ps2_start
  cpi r30, PS2_PARITY
  ; If > START and < PARITY, this is a data bit.
  brlt ps2_data
  breq ps2_parity
  cpi r30, PS2_STOP
  breq ps2_stop
  ; Fall through to ps2_error if >PS2_STOP
  
ps2_error:
  ; hold clk low for ~100us
  sbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  cbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN
  clr r30
1:
  dec r30  ; 1 clk
  brne 1b ; 2 clk on loop
  ; release clk, enable pullup
  cbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  sbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN

  ; reset status register
  ldi r30, PS2_START
  mov PS2_STATE_REG, r30
  ret
ps2_start:
  ; Start bit is low.
  andi r31, _BV(KB_BUS_PIN)
  brne ps2_error ; nz = error
  clr PS2_DATA_REG
  inc PS2_STATE_REG
  ret
ps2_data: ; low bit first
  ; Put bit into carry
  clc
  sbrc r31, KB_BUS_PIN
  sec
  ror PS2_DATA_REG ; rotate carry into high bit of data register
  inc PS2_STATE_REG
  ret
ps2_parity:
  andi r31, _BV(KB_BUS_PIN)
  ; This could probably be more efficient.
  ; Basically, if we EOR all bits together we should get a 1 (odd parity).
  eor r31, PS2_DATA_REG ; Combine the parity bit into the data register.
  mov r30, r31
  swap r30     ; swap nibbles
  eor r31, r30 ; eor high nibble into low nibble
  mov r30, r31
  lsr r30
  lsr r30
  eor r31, r30 ; eor bits 2-3 into bits 0-1
  mov r30, r31
  lsr r30
  eor r31, r30 ; eor bit 1 into bit 0
  sbrs r31, 0  ; Lowest bit should be 1 now (with the parity bit parity is odd)
  rjmp ps2_error
  inc PS2_STATE_REG
  ret
ps2_stop:
  ; Stop bit is high.
  andi r31, _BV(KB_BUS_PIN)
  breq ps2_error ; zero = error

  ; KBIN is an index and only uses the lo8.
  ; Using PS2_STATE_REG as temporary storage here since it will be reset later.
  lds PS2_STATE_REG, var_KBIN
  ldi r30, lo8(var_KBUF)
  ldi r31, hi8(var_KBUF)
  add r30, PS2_STATE_REG
  st Z+, PS2_DATA_REG ; KBUF[KBIN] = PS2_DATA_REG

  ; Now determine the new KBIN. It's .balign 8'd, so just mask the bottom 3 bits
  andi r30, KBUF_MASK
  mov PS2_STATE_REG, r30
  ldi r30, lo8(var_KBIN)
  ldi r31, hi8(var_KBIN)
  st Z, PS2_STATE_REG
  
  ldi r30, PS2_START
  mov PS2_STATE_REG, r30
  ret

; KBUF is a ring buffer that stores keyboard input. KBIN and KBOUT are indices
; into the buffer. KBIN is where the next byte will be written, KBOUT is where
; the next byte should be read. The buffer is empty when KBIN = KBOUT.
; TODO: Could store these together in the same word.
defvar "KBIN",,KBIN,0
defvar "KBOUT",,KBOUT,0

defcode "KBUF",,KBUF
  ldi r16, lo8(var_KBUF)
  ldi r17, hi8(var_KBUF)
  PUSHDSP 16
  rjmp NEXT
.data
.balign KBUF_SIZE
var_KBUF:
.fill KBUF_SIZE, 1, 0
.text

defcode "KBINIT",,KBINIT
  ; Set bus pin as input and enable pull-up.
  cbi _SFR_IO_ADDR(DDRB), KB_BUS_PIN
  sbi _SFR_IO_ADDR(PORTB), KB_BUS_PIN
  ; Initialize the state machine.
  ldi r16, PS2_START
  mov PS2_STATE_REG, r16
  rjmp KBDISABLE

; Keyboard must be disabled (keyboard clock held low) during LCD operations.
defcode "KBDISABLE",,KBDISABLE
  cli
  clr r16
  out _SFR_IO_ADDR(GIMSK), r16
  out _SFR_IO_ADDR(PCMSK), r16
  ; Clear the interrupt flag by writing one to it.
  ldi r16, _BV(PCIF)
  out _SFR_IO_ADDR(GIFR), r16
  ; Holding the clock low disables the keyboard.
  sbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  cbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN
  ; Wait ~100us to ensure the keyboard isn't sending other commands
  ; (1/8000000 seconds * 256 loops * 3 clocks per loop = 96us)
  ldi r16, 0
1:
  dec r16 ; 1 clk
  brne 1b ; 2 clk on loop
  rjmp NEXT

defcode "KBENABLE",,KBENABLE
  ; Set CLK as input and enable pullups.
  cbi _SFR_IO_ADDR(DDRB), KB_CLK_PIN
  sbi _SFR_IO_ADDR(PORTB), KB_CLK_PIN
  ; Clear any pending interrupts.
  ldi r16, _BV(PCIF)
  out _SFR_IO_ADDR(GIFR), r16
  ; Enable pin change interrupts on CLK pin.
  sbi _SFR_IO_ADDR(PCMSK), KB_CLK_PIN
  ldi r16, _BV(PCIE)
  out _SFR_IO_ADDR(GIMSK), r16
  sei
  rjmp NEXT

defword "KB@",,KBFETCH
  fw KBOUT
  fw FETCH
1:
  fw DUP
  fw KBIN
  fw FETCH
  fw SUB
  zbranch 1b

  ; Increment KBOUT
  fw DUP
  fw INCR
  lit KBUF_MASK
  fw AND
  fw KBOUT
  fw STORE

  ; Read the input
  fw KBUF
  fw ADD
  fw FETCHBYTE

  fw EXIT

KB_MAP:
.ascii \
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0`\0",\
  "\0\0\0\0\0q1\0\0\0zsaw2\0",\
  "\0cxde43\0\0 vftr5\0",\
  "\0nbhgy6\0\0\0mju78\0",\
  "\0,kio09\0\0./l;p-\0",\
  "\0\0'\0[=\0\0\0\0\0]\0\\\0\0"
.set KB_MAP_LEN, . - KB_MAP

KB_MAP_SHIFT:
.ascii \
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0~\0",\
  "\0\0\0\0\0Q!\0\0\0ZSAW@\0",\
  "\0CXDE$#\0\0 VFTR%\0",\
  "\0NBHGY^\0\0\0MJU&*\0",\
  "\0<KIO)(\0\0>?L:P_\0",\
  "\0\0\"\0{+\0\0\0\0\0}\0|\0\0"

defvar "KBSTATUS",,KBSTATUS,0
defconst "KBS_BREAK",,KBS_BREAK,0x0001
defconst "KBS_EXTENDED",,KBS_EXTENDED,0x0002
defconst "KBS_LSHIFT",,KBS_LSHIFT,0x0004
defconst "KBS_RSHIFT",,KBS_RSHIFT,0x0008

; MODFLAG --
; If KBS_BREAK is set, clear MODFLAG. Otherwise, set it.
defword "HANDLEMOD",,HANDLEMOD
  fw KBSTATUS

  fw KBS_BREAK
  fw KBSTATUS
  fw CHECKFLAG
  zbranch 1f
  fw CLRFLAG
  fw FALSE
  zbranch 2f
1:

  fw SETFLAG
2:

  fw RESETKB
  fw EXIT

defword "RESETKB",,RESETKB
  ; Reset the scancode prefixes.
  fw KBS_BREAK
  fw KBS_EXTENDED
  fw OR
  fw KBSTATUS
  fw CLRFLAG
  fw EXIT

defword "KEY",,KEY
key_top:
  fw KBFETCH

  fw DUP
  lit 0xF0 ; break codes
  fw EQU
  zbranch 1f
  fw DROP
  fw KBS_BREAK
  fw KBSTATUS
  fw SETFLAG
  fw FALSE
  zbranch key_top
1:

  fw DUP
  lit 0xE0 ; extended keys
  fw EQU
  zbranch 1f
  fw DROP
  fw KBS_EXTENDED
  fw KBSTATUS
  fw SETFLAG
  fw FALSE
  zbranch key_top
1:

  fw DUP
  lit 0x12 ; left shift
  fw EQU
  zbranch 1f
  fw DROP

  fw KBS_LSHIFT
  fw HANDLEMOD
  fw RESETKB

  fw FALSE
  zbranch key_top
1:

  fw DUP
  lit 0x59 ; right shift
  fw EQU
  zbranch 1f
  fw DROP

  fw KBS_RSHIFT
  fw HANDLEMOD
  fw RESETKB

  fw FALSE
  zbranch key_top
1:

  ; Past this point, we're always matching a real key and not a modifier key
  ; (even though we might not handle it).
  fw KBS_BREAK
  fw KBS_EXTENDED
  fw OR
  fw KBSTATUS
  fw CHECKFLAG
  zbranch 1f
  fw DROP ; Throw out the break and extended codes.
  fw RESETKB
  fw FALSE
  zbranch key_top
1:
  ; Past this point, BREAK and EXTENDED are not set.

  ; Verify it's within the map size.
  fw DUP
  lit KB_MAP_LEN
  fw GT
  fw ZEQU
  zbranch 1f ; if KB_MAP_LEN <= keycode
  fw DROP
  fw FALSE
  zbranch key_top
1:

  ; Determine which map to use.
  lit KB_MAP
  fw KBS_LSHIFT
  fw KBS_RSHIFT
  fw OR
  fw KBSTATUS
  fw CHECKFLAG
  zbranch 1f
  fw DROP
  lit KB_MAP_SHIFT
1:

  fw ADD
  fw ROMFETCHBYTE ; KB_MAP[keycode]
  fw DUP
  fw ZEQU
  zbranch 1f
  ; Char is zero in the map and isn't handled.
  zbranch key_top
1:
  fw EXIT

