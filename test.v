`include "global.inc"

//`define I2CTEST

// virtual receiver uart
module uartDump #(
     parameter CLKDIV = 8'd139
  ) (
    input  clk,
    input  resetn,
    input  ser_rx,
    input  [31:0] reg_div_di
);

reg [3:0] recv_state;
reg [7:0] recv_divcnt;
reg [7:0] recv_pattern;
reg	  done;

// receive logic
always @(posedge clk) begin
  if (!resetn) begin
    recv_state	 <= 0;
    recv_divcnt  <= 0;
    recv_pattern <= 0;
    done	 <= 0;
  end else begin
    recv_divcnt <= recv_divcnt + 1;
    case (recv_state)
      0: begin
	   if (!ser_rx)
	     recv_state <= 1;
	   recv_divcnt <= 0;
	 end
      1: begin
	   if (2*recv_divcnt > CLKDIV) begin
	     recv_state  <= 2;
	     recv_divcnt <= 0;
	   end
	 end
      10: begin
	   if (recv_divcnt > CLKDIV) begin
	     //recv_buf_data  <= recv_pattern;
	     recv_state     <= 0;
	     $write ("%s", recv_pattern);
	   end
	 end
      default: begin
	   if (recv_divcnt > CLKDIV) begin
	     recv_pattern <= {ser_rx, recv_pattern[7:1]};
	     recv_state   <= recv_state + 1;
	     recv_divcnt  <= 0;
	   end
	 end
    endcase
  end
end
endmodule

// virtual eeprom i2c slave
module Ic2Slave #(
    parameter SLAVE_ADDR = 7'h50,
    parameter READ_BYTES = 2
  ) (
  inout wire SDA,
  input wire SCL
  );

localparam READ_ADDRESS = 0;
localparam SKIP 	= 1;
localparam READ_WRITE	= 2;
localparam ADDRESS_ACK	= 3;
localparam ADDR_HI	= 4;
localparam ADDR_HI_ACK	= 5;
localparam ADDR_LO	= 6;
localparam ADDR_LO_ACK	= 7;
localparam READ_DATA	= 8;
localparam DATA_ACK	= 9;
localparam DATA_END0	= 10;

reg [3:0]  state = 0;
reg [6:0]  addr;
reg [3:0]  addressCounter;
reg [15:0] rom_addr = 0;

reg [7:0] data;
reg [2:0] dataCounter;
reg [7:0] readCounter;

reg readWrite;
reg start = 0;
reg write_ack = 0;

reg    vsda_out = 0;
wire   vsda_oe;
assign vsda_oe = state == READ_DATA || (state == DATA_ACK && SCL);

assign SDA = write_ack == 1 ? 0 : (vsda_oe ? vsda_out : 1'bz);
//assign SDA = (write_ack == 1) ? 0 : 1'bz;

// memory
reg [7:0] rommem [0:8191];
initial begin
  $display  ("Loading ROM ...");
  $readmemh ("/tmp/zrom.hex", rommem);
end

always @(negedge SCL) begin
  write_ack <= 0;
end

always @(negedge SDA) begin
  if ((start == 0) && (SCL == 1)) begin
    // start condition detection
    start	   <= 1;
    addressCounter <= 0;
    addr	   <= 7'h00;
    vsda_out	   <= 0;
    state	   <= READ_ADDRESS;
`ifdef I2CTEST
    $display ("i2cslv start %t", $time);
`endif
  end
end

always @(posedge SDA) begin
  if (SCL == 1 && state == SKIP) begin
    start <= 0;
    state <= READ_ADDRESS;
`ifdef I2CTEST
    $display ("i2cslv stop  %t", $time);
`endif
  end
end

always @(posedge SCL) begin
  if (start == 1) begin
    case (state)

      READ_ADDRESS: begin
	addr	       <= {addr[5:0], SDA};
	addressCounter <= addressCounter + 1;
	//$display ("i2cslv addr! %t bit %d", $time, SDA);
	if (addressCounter == 6) begin
	  state <= READ_WRITE;
	end
      end

      SKIP: begin
	// wait for stop condition
	write_ack <= 0;
	//$display ("i2cslv skip! %t", $time);
      end

      READ_WRITE: begin
	readWrite   <= SDA;
	readCounter <= READ_BYTES;
	state	    <= addr == SLAVE_ADDR ? ADDRESS_ACK : SKIP;
`ifdef I2CTEST
	$display ("i2cslv r/w-- %t = %d addr %x", $time, SDA, addr);
`endif
      end

      ADDRESS_ACK: begin
	write_ack   <= 1;
	state	    <= ADDR_HI;
	dataCounter <= 0;
	if (readWrite) begin
	  state    <= READ_DATA;
	  data	   <= rommem[rom_addr[12:0]];
	  rom_addr <= rom_addr + 1'b1;
	end
`ifdef I2CTEST
	$display ("i2cslv addrC %t read/write= %d addr=%x rom_addr=%x", $time, readWrite, addr, rom_addr);
`endif
      end

      ADDR_HI: begin
	write_ack	  <= 0;
	rom_addr	  <= {rom_addr[14:0], SDA};
	dataCounter	  <= dataCounter + 1;
`ifdef I2CTEST
	$display ("i2cslv addrH %t bit %d = %d", $time, 7 - dataCounter, SDA);
`endif
	if (dataCounter == 7) begin
	  state       <= ADDR_HI_ACK;
	end
      end

      ADDR_HI_ACK: begin
	write_ack   <= 1;
	dataCounter <= 0;
	state	    <= ADDR_LO;
`ifdef I2CTEST
	$display ("i2cslv addrH %t = %x", $time, rom_addr);
`endif
      end

      ADDR_LO: begin
	write_ack   <= 0;
	rom_addr    <= {rom_addr[14:0], SDA};
	dataCounter <= dataCounter + 1;
`ifdef I2CTEST
	$display ("i2cslv addrL %t bit %d = %d", $time, 7 - dataCounter, SDA);
`endif
	if (dataCounter == 7) begin
	  state     <= ADDR_LO_ACK;
	end
      end

      ADDR_LO_ACK: begin
	write_ack <= 1;
	state	  <= SKIP;
`ifdef I2CTEST
	$display ("i2cslv addrL %t = %x", $time, rom_addr);
`endif
      end

      READ_DATA: begin
	write_ack   <= 0;
	vsda_out    <= data[7 - dataCounter];
	dataCounter <= dataCounter + 1;
	//$display ("i2cslv sendb %t bit %d of %x = %d", $time, 7 - dataCounter, data, data[7 - dataCounter]);
	if (dataCounter == 7) begin
	  // ignore ack or nack and try next byte
	  state       <= DATA_ACK;
	  dataCounter <= 0;
	  data	      <= rommem[rom_addr[12:0]];
	  rom_addr    <= rom_addr + 1'b1;
	  readCounter <= readCounter - 1'b1;
	  //$display ("i2cslv+\t\tbyte %x at %x", data, rom_addr);
	end
      end

      DATA_ACK: begin
	state <= |readCounter ? READ_DATA : DATA_END0;
	//$display ("i2cslv dack! %t next %x readCounter %d", $time, data, readCounter);
      end

      DATA_END0: begin
`ifdef I2CTEST
	$display ("i2cslv dend0 %t", $time);
`endif
	state <= SKIP;
      end

    endcase
  end
end
endmodule

// virtual SPI SRAM slave
module spi_ram #(
    parameter MEMORY_BITS = 17	// 128KB
  ) (
    input      clk,
    input      mosi,
    input      ss_n,
    output reg miso
);

// memory cmds
localparam CMD_MODE  = 8'h01;
localparam CMD_WRITE = 8'h02;
localparam CMD_READ  = 8'h03;

// states
localparam S_IDLE    = 3'd0;
localparam S_MODE    = 3'd1;
localparam S_ADDR_H  = 3'd2;
localparam S_ADDR_M  = 3'd3;
localparam S_ADDR_L  = 3'd4;
localparam S_DATA    = 3'd5;

// receiver states
localparam rb7 = 3'd0;
localparam rb6 = 3'd1;
localparam rb5 = 3'd2;
localparam rb4 = 3'd3;
localparam rb3 = 3'd4;
localparam rb2 = 3'd5;
localparam rb1 = 3'd6;
localparam rb0 = 3'd7;

// sender states
localparam sb7 = 3'd0;
localparam sb6 = 3'd1;
localparam sb5 = 3'd2;
localparam sb4 = 3'd3;
localparam sb3 = 3'd4;
localparam sb2 = 3'd5;
localparam sb1 = 3'd6;
localparam sb0 = 3'd7;

reg [2:0] cs;
reg [2:0] st_recv;
reg [2:0] st_send;
reg read, send_now;

reg [7:0] rx_data, send_data;

// emulated ram
integer ii;
localparam MEM_BYTES = $pow (2, MEMORY_BITS);
reg [23:0] sram_addr;
reg [ 7:0] sram [MEM_BYTES - 1:0];

initial begin
  for (ii = 0; ii < MEM_BYTES; ii++)
    sram[ii] = ii[7:0];
  st_send   = sb7;
  send_now  = 0;
  st_recv   = rb7;
  st_send   = sb7;
  cs	    = S_IDLE;
  sram_addr = 0;
end

// receiver
always @(posedge clk) begin
  if (ss_n) begin
    st_recv  <= rb7;
    cs	     <= S_IDLE;
    send_now <= 0;
  end else begin
    //$display ("spislv step  %t state %d bit %d", $time, st_recv, mosi);

    case (st_recv)
      rb7: begin st_recv <= rb6; rx_data[7] <= mosi; end
      rb6: begin st_recv <= rb5; rx_data[6] <= mosi; end
      rb5: begin st_recv <= rb4; rx_data[5] <= mosi; end
      rb4: begin st_recv <= rb3; rx_data[4] <= mosi; end
      rb3: begin st_recv <= rb2; rx_data[3] <= mosi; end
      rb2: begin st_recv <= rb1; rx_data[2] <= mosi; end
      rb1: begin st_recv <= rb0; rx_data[1] <= mosi; end
      rb0: begin
	rx_data[0] = mosi;
	st_recv   <= rb7;
	//$display ("spislv recvb %t = %x state %d", $time, rx_data, cs);

	// state machine
	case (cs)
	  S_IDLE: begin
	    // new cmd
	    case (rx_data)
	      CMD_MODE: begin
		cs <= S_MODE;
	      end
	      CMD_READ: begin
		read <= 1'b1;
		cs   <= S_ADDR_H;
	      end
	      CMD_WRITE: begin
		read <= 1'b0;
		cs   <= S_ADDR_H;
	      end
	      default: begin
		$display ("spislv cmd?? %t = %x", $time, rx_data);
	      end
	    endcase
	  end

	  S_MODE: begin
	    // ignore mode set byte
	    //$display ("spislv stmod %t mode %x", $time, rx_data);
	    cs <= S_IDLE;
	  end

	  S_ADDR_H: begin
	    sram_addr[23:16] <= rx_data;
	    cs		     <= S_ADDR_M;
	  end

	  S_ADDR_M: begin
	    sram_addr[15:8] <= rx_data;
	    cs		    <= S_ADDR_L;
	  end

	  S_ADDR_L: begin
	    sram_addr[7:0] <= rx_data;
	    cs		   <= S_DATA;
	    send_now	   <= read;
	    st_send	   <= sb6;
	    send_data	   <= sram[{sram_addr[MEMORY_BITS - 1: 8], rx_data}];
	    miso	   <= sram[{sram_addr[MEMORY_BITS - 1: 8], rx_data}][7];
	    //$strobe ("spislv addr= %t %x data %x", $time, sram_addr, send_data);
	  end

	  S_DATA: begin
	    // ignore for read
	  end

	endcase
      end
    endcase
  end
end

always @(posedge clk) begin
  if (send_now) begin
    case (st_send)
      sb7: begin st_send = sb6; miso = send_data[7]; end
      sb6: begin st_send = sb5; miso = send_data[6]; end
      sb5: begin st_send = sb4; miso = send_data[5]; end
      sb4: begin st_send = sb3; miso = send_data[4]; end
      sb3: begin st_send = sb2; miso = send_data[3]; end
      sb2: begin st_send = sb1; miso = send_data[2]; end
      sb1: begin st_send = sb0; miso = send_data[1]; sram_addr <= sram_addr + 1'b1; end
      sb0: begin
	st_send   <= sb7;
	miso	  <= send_data[0];
	send_data <= sram[sram_addr];
	//$display ("spislv sendb %t = %x new %x", $time, send_data, sram[sram_addr]);
      end
    endcase
  end
end
endmodule

/*
 * test module
 */
module test;

localparam EEPROM_PAGE = 8'd16;
localparam UART_DIV    = 139; //3;

// clock & rst
reg clk, rst;
wire rstn = ~rst;

// terminate signal
wire terminate;

// wires
wire tx, scl, sda, led_r, led_h, ssn, sck, miso, mosi, uart_rx;

// instance soc
eonSoc #(
    .WIDTH	 (32),
    .RSTWIDTH	 (3),
    .I2CDIV	 (16'd3),
    .UART_DIV	 (UART_DIV),
    .EEPROM_PAGE (EEPROM_PAGE),
    .SPI_DIV	 (2)
  ) soc (
    .clk    (clk),
    .rstn   (rstn),
    .led_r  (led_r),
    .led_h  (led_h),

    .rx     (1'b0),
    .tx     (uart_rx),

    .scl    (scl),
    .sda    (sda),

    .ssn    (ssn),
    .sck    (sck),
    .mosi   (mosi),
    .miso   (miso)
  );

// instance uart receiver emulator
uartDump #(
    .CLKDIV (UART_DIV)
  ) uartd (
    .clk	 (clk),
    .resetn	 (rstn),
    .ser_rx	 (uart_rx),
    .reg_div_di  (UART_DIV)
);

// instance EEPROM device
Ic2Slave #(
    .READ_BYTES (EEPROM_PAGE)
  ) eeprom (
    .SDA (sda),
    .SCL (scl)
);

// instance SRAM device
spi_ram sram (
    .clk     (sck),
    .mosi    (mosi),
    .ss_n    (ssn),
    .miso    (miso)
);

// clock generation
always begin
  #32;			// half cycle time units (ns) = 16MHz
  clk = 1'b0;
  #32;
  clk = 1'b1;
end

initial begin
  // dump file
  $dumpfile ("/tmp/eonsoc.lxt");
  $dumpvars (0, test);

  // set time format dump
  $timeformat (-6, 3, "us", 12);

  // initial reset pulse
  clk	= 1'b1;
  rst	= 1'b1;
  #128;
  rst	= 1'b0;

  // reset pulse oscilation (simulate switch)
  if (0) repeat (4) begin
    #200;
    rst = 1'b1;
    #100;
    rst = 1'b0;
  end

  // n cycles
  while (!led_h && soc.cpu0.cycle < 20'h20000) begin
    # 64;
  end

  // done
  $display ("\n\t%x %t", soc.cpu0.cycle, $time);
  $finish;
end

endmodule
