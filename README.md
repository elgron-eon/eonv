# eonv
32 bit [EON](https://github.com/elgron-eon/eon-cpu) cpu implemented on tinyfpga BX. The internal clock frequency is 16MHz,
I2C bus is about 400Khz and SPI bus is about 1MHz.

# hardware parts
I suggest you to consider first [eonduino](https://github.com/elgron-eon/eonduino). Easier to build and
same hardware. One important difference: tinyfpga BX is 3.3v (avr is 5v).

# implementation
The source has a SOC module, which implements: uart, i2c bus, spi bus, l2 memory cache, eeprom driver, sram driver and a debug module.

The core cpu is implemented in coreZ0. It's a pipelined, single issue, out of order execution, commit in order design.

# build
Prerequisites:
* eonrom.img from [eonrom](https://github.com/elgron-eon/eonrom)
* [iverilog/vvp](https://github.com/steveicarus/iverilog)
* [gtkwave](https://github.com/gtkwave/gtkwave) (optional)
* [yosys](https://github.com/YosysHQ/yosys)
* [nextpnr](https://github.com/YosysHQ/nextpnr)
* [icepack](https://github.com/YosysHQ/icestorm)
* [tinyprog](https://github.com/tinyfpga/TinyFPGA-Bootloader)
* a serial terminal emulator. I use [picocom](https://github.com/npat-efault/picocom), but any other will work.

to build emulator and wave file, just type `make`  
to build fpga image, type `make /tmp/hardware.bin`  
and finally type `make tinyfpga && make com` to enjoy your system !
