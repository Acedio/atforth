#include <avr/io.h>

#include "macros.i"

; Two shift registers control inputs to the LCD:
;  - The first is the flag register. See the flag constants below.
;  - The second is the address register. The MSB is the only LCD pin that is
;    readable by the MCU, and is available on PB0.

#define LCD_BUSY_PIN 0
#define SER_DATA_PIN 1
#define SER_CLK_PIN 2
#define SER_LATCH_PIN 3

; == LCD FLAG REGISTER FLAGS ==
; LCD_E is the enable bit for sending data to the LCD. Reads are triggered by a
; rising edge, writes are triggered by a falling edge.
defconst "LCD_E",,LCD_E,0x80
; When LCD_RW_READ is set, puts the LCD into a read state. Unset = write.
; Setting the LCD_RW_READ bit also turns off the address register outputs so
; the pins are in a high impedence state and don't short :P
defconst "LCD_RW_READ",,LCD_RW_READ,0x40
; When LCD_RS_DR is set, selects the data register (DR). When unset, selects
; the instruction register (IR).
defconst "LCD_RS_DR",,LCD_RS_DR,0x20
; Drives an LED when set.
defconst "LCD_LED",,LCD_LED,0x10

; Must be called before any LCD operations.
defcode "SERINIT",,SERINIT
  cbi _SFR_IO_ADDR(DDRB), LCD_BUSY_PIN
  sbi _SFR_IO_ADDR(PORTB), LCD_BUSY_PIN

  ; CLK, LATCH, and OUT are always outputs.
  sbi _SFR_IO_ADDR(DDRB), SER_CLK_PIN
  sbi _SFR_IO_ADDR(DDRB), SER_LATCH_PIN
  sbi _SFR_IO_ADDR(DDRB), SER_DATA_PIN
  ; Init all to low.
  cbi _SFR_IO_ADDR(PORTB), SER_CLK_PIN
  cbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  cbi _SFR_IO_ADDR(PORTB), SER_DATA_PIN
  rjmp NEXT

defcode "SERLATCH",,SERLATCH
  cbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  sbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  rjmp NEXT

; Blink latch pin indefinitely.
; Useful to call from ASM when the kernel might be dead.
defcode "LATCHBLINK",,LATCHBLINK
  ldi r26, 0
  ldi r27, 0
  ldi r18, 0
1:
  adiw r26, 1
  brne 1b ; loop if not 0
  inc r18
  sbrs r18, 3
  rjmp 2f
  sbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  rjmp 1b
2:
  cbi _SFR_IO_ADDR(PORTB), SER_LATCH_PIN
  rjmp 1b

; Must set the LCD to LCD_RW_READ first.
defcode "LCDBUSY",,LCDBUSY
  ldi r16, 0
  sbic _SFR_IO_ADDR(PINB), LCD_BUSY_PIN
  ldi r16, 0xFF ; port is busy
  mov r17, r16
  PUSHDSP 16
  rjmp NEXT

defcode "B>SER",,BYTETOSER
  POPDSP 0
  ; Load the byte into the data register.
  out _SFR_IO_ADDR(USIDR), r0
  ; Reset the clock counter.
  ldi r16, _BV(USIOIF)
  out _SFR_IO_ADDR(USISR), r16

  ; Pulse clock until sent.
  ldi r16, _BV(USIWM0) | _BV(USICS1) | _BV(USICLK) | _BV(USITC)
1:
  out _SFR_IO_ADDR(USICR), r16
  sbis _SFR_IO_ADDR(USISR), USIOIF
  rjmp 1b

  ; Turn off USI.
  ldi r16, 0
  out _SFR_IO_ADDR(USICR), r16
  rjmp NEXT

; Writes a word to the shift registers.
defword ">SER",,TOSER
  ; High byte first.
  fw DUP
  fw SWIZZLE
  fw BYTETOSER

  ; Then the low byte.
  fw BYTETOSER

  fw SERLATCH
  fw EXIT

defword "LCDWAIT",,LCDWAIT
1:
  fw LCD_RW_READ
  fw TOSER
  fw LCD_RW_READ
  fw LCD_E
  fw OR
  fw TOSER
  fw LCDBUSY
  fw ZEQU
  zbranch 1b

  ; Bring LCD_E low so it's in a consistent state.
  fw LCD_RW_READ
  fw TOSER
  fw EXIT

; Writes an LCD command to the shift register and handles the clocking of E.
defword "LCDCMD",,LCDCMD
  fw LCDWAIT ; Wait for free.

  fw DUP
  fw LCD_E
  fw OR
  fw TOSER ; Clock E high first (should already be low).

  fw LCD_E
  fw INVERT
  fw AND
  fw TOSER ; Then low.

  fw EXIT

defword "LCDINIT",,LCDINIT
  ; 8 bits, 2 lines, 5x8
  lit 0x3800
  fw LCDCMD
  ; clear the screen
  lit 0x0100
  fw LCDCMD
  ; Enable screen, cursor, and blinking
  lit 0x0F00
  fw LCDCMD
  fw LCDDISABLE
  fw EXIT

; Hold the address lines high so the busy pin can be used by other devices.
defword "LCDDISABLE",,LCDDISABLE
  lit 0xFF00
  fw TOSER
  fw EXIT

defword "LCDCLEAR",,LCDCLEAR
  lit 0x0100
  fw LCDCMD
  fw EXIT
