# eonv
[EON](https://github.com/elgron-eon/eon-cpu) fpga system with tinyfpga BX. Implement a 16 or 32 bit EON system.
The internal clock frequency is 16MHz, I2C bus is about 400Khz and SPI bus is about 1MHz.

# hardware parts
I suggest you to consider first [eonduino](https://github.com/elgron-eon/eonduino). It's more easy to build and
the hardware is the same. One important difference: tinyfpga BX is 3.3v (avr is 5v).

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
