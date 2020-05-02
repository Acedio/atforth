MCU_TARGET     = attiny85
OPTIMIZE       = -Os
CC             = avr-gcc

override AFLAGS        = -nostdlib -Wall -mmcu=$(MCU_TARGET)
override LDFLAGS       = -Wl,-Tdata,0x800180

all: forth.hex

forth.o: token_table.i

# forth.S must be last in order to ensure LATEST is last.
token_table.S: token_table.i kb.S lcd.S forth.S
	cp token_table.i $@
	cat kb.S lcd.S forth.S \
	| grep -E "^def(code|word|var|const|string)" \
	| sed "s/^[^,]*,[^,]*,// ; s/[^A-Z_].*// ; s/\(.*\)/.global T_\1\n.set T_\1,.-TOKEN_TABLE\n.word \1/" >> $@

%.o: %.S
	$(CC) -c $(AFLAGS) -o $@ $<

forth.elf: forth.o kb.o lcd.o token_table.o
	$(CC) $(LDFLAGS) -o $@ $^

%.hex: %.elf
	avr-objcopy -j .text -j .data -O ihex $< $@

upload: forth.hex
	avrdude -p t85 -c ftdifriend -b 19200 -u -U flash:w:$<

clean:
	rm -rf *.o
	rm -rf *.hex
	rm -rf *.elf
	rm token_table.S
