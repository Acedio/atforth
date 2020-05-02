# @forth: A Forth for the ATtiny85.

## Simplified Schematic

```
  ________________       ________________       ___________________
 |                |     |                |     |                   |
 | ATTiny85 (MCU) |-----| 74HC595 (FLAG) |-----| 74HC595 (ADDRESS) |
 |________________|     |________________|     |___________________|
                         |  |  |                 |    |
                         |  |  |           +-/7/-+    +--- TO MCU
                         |__|__|___________|________  |
                        |E  RW RS        A0-A6    A7|-*
                        | HD44780U (LCD controller) |
                        |___________________________|
```

## ATTiny85 Port Assignment

PB0 - LCD busy pin and the MSB of the LCD bus.
PB1 - Serial out to the shift registers.
PB2 - Clock for serial input on the shift registers.
PB3 - Clock for the outputs on the shift registers.
PB4 - PS/2 clock.
PB5 - Reset pin, left open for programming.
