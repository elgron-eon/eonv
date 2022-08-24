//
// tinyfgpa bx eon soc
//
`include "global.inc"

// look in pins.pcf for all the pin names on the TinyFPGA BX board
module top (
  input  CLK,	      // 16MHz clock
  input  PIN_2,       // uart rx
  input  PIN_24,      // reset (active low)
  output USBPU,
  output LED,
  output PIN_23,      // led halt
  output PIN_1,       // uart tx
  output PIN_12,      // i2c SCL
  inout  PIN_13,      // i2c SDA
  output PIN_22,      // spi SS
  output PIN_21,      // spi SCK
  output PIN_20,      // spi MOSI
  input  PIN_19       // spi MISO
);

// Disable USB
assign USBPU = 0;

// instance soc
eonSoc #(
    .WIDTH	 (32),
    .EEPROM_PAGE (16),
    .UART_DIV	 (139)	   // 16Mhz / 115200
  ) soc (
    .clk    (CLK),
    .rstn   (PIN_24),
    .led_r  (LED),
    .led_h  (PIN_23),

    .rx     (PIN_2),
    .tx     (PIN_1),

    .scl    (PIN_12),
    .sda    (PIN_13),

    .ssn    (PIN_22),
    .sck    (PIN_21),
    .mosi   (PIN_20),
    .miso   (PIN_19)
  );

endmodule
