SRCS  = coreZ0.v decode.v alu.v fetch.v icache.v mcache.v regfile.v uart.v
SRCS += i2c.v eeprom.v soc.v spi.v spi-bus.v sram.v commit.v issue.v
SRCS += balu.v memory.v

all: /tmp/eonsoc.lxt

com:
	picocom -b 115200 -r -l -f n --imap lfcrlf /dev/ttyUSB0

clean:
	rm -f /tmp/zrom.* /tmp/eonsoc* /tmp/hardware.*

wave:
	gtkwave /tmp/eonsoc.lxt &

/tmp/eonsoc: $(SRCS) test.v /tmp/zrom.hex
	iverilog -Wimplicit -Wportbind -Wselect-range -s test -DTEST -o $@ $(SRCS) test.v

/tmp/eonsoc.lxt: /tmp/eonsoc
	vvp $^ -lxt2

/tmp/zrom.hex: eonrom.bin
	@od -v -A n -t x1 $^ > $@

#
# tinyfpga BX synth
#
stats-tinyfgpa: $(SRCS) top.tinyfpga-bx.v
	@yosys -f "verilog -DICE40 -DSYNTH" -p "synth_ice40 -top top" $^ > /tmp/eon-report && tail -30 /tmp/eon-report

luts-tinyfgpa: $(SRCS) top.tinyfpga-bx.v
	@yosys -f "verilog -DICE40 -DSYNTH" -p "synth_ice40 -top top -abc9 -noflatten" $^ > /tmp/luts-report

/tmp/hardware.json: $(SRCS) top.tinyfpga-bx.v
	@echo yosys $@
	@yosys -f "verilog -DICE40 -DSYNTH" -p "synth_ice40 -json $@" -q $^

/tmp/hardware.asc: /tmp/hardware.json
	@echo nextpnr-ice40 $@
	@rm -f /tmp/hardware.fail
	@-nextpnr-ice40 --lp8k --package cm81 --json $^ --asc $@ --pcf pins.tinyfpga-bx.pcf --force -q --log /tmp/hardware.log || touch /tmp/hardware.fail
	@head -`expr 6 "+" $$(grep -n "^Info: Device utilisation:" /tmp/hardware.log | cut -d: -f1)` /tmp/hardware.log | tail -7
	@if [ -f /tmp/hardware.fail ] ; then exit 1; fi

stats-time: /tmp/hardware.asc
	@icetime -d lp8k -i $^

/tmp/hardware.bin: /tmp/hardware.asc
	@echo icepack $@
	@icepack $^ $@

tinyfpga: /tmp/hardware.bin
	tinyprog --pyserial -c /dev/ttyACM0 --program $^
