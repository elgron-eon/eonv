`include "global.inc"

module eonSoc #(
     parameter WIDTH	     = 32,
     parameter UART_DIV      = 139,
     parameter RSTWIDTH      = 8,
     parameter I2CDIV	     = 16'd37,
     parameter EEPROM_DEVICE = 7'h50,
     parameter EEPROM_PAGE   = 8'd32,
     parameter SPI_DIV	     = 8
  ) (
    input  clk, 	// hardware clock
    input  rstn,	// reset button, active low
    output led_r,	// running led
    output led_h,	// halt led

    // uart
    input  rx,
    output tx,

    // i2c bus
    output scl,
    inout  sda,

    // spi bus
    output sck,
    output ssn,
    output mosi,
    input  miso
);

// debug support
wire [15:0] dbg_payload, dbg_module;
wire	    dbg_ready;

// reset signal
reg [RSTWIDTH - 1:0] reset_cnt = 0;
wire resetn = &reset_cnt;
wire reset  = ~resetn;

always @(posedge clk) begin
  if (resetn && !rstn) begin
    reset_cnt <= 0;
  end else begin
    reset_cnt <= reset_cnt + !resetn;
  end
end

// uart
reg  [7:0] reg_dat_di;	// byte to write
wire [7:0] reg_dat_do;	// byte to read
reg  reg_dat_re, reg_dat_we;
wire reg_dat_wait;

uart #(
    .CLKDIV (UART_DIV)
  ) uart (
    .clk	 (clk),
    .resetn	 (resetn),

    .ser_tx	 (tx),
    .ser_rx	 (rx),

    .reg_div_we  (1'b0),
    .reg_div_di  (UART_DIV),

    .reg_dat_we  (reg_dat_we),
    .reg_dat_re  (reg_dat_re),
    .reg_dat_di  (reg_dat_di),
    .reg_dat_do  (reg_dat_do),
    .reg_dat_wait(reg_dat_wait)
);

// i2c bus
wire i2c_enable, i2c_rw;
wire i2c_busy, i2c_send_ready, i2c_recv_ready;
wire [6:0] i2c_addr;
wire [7:0] i2c_nbytes;
wire [7:0] i2c_readed;
wire [7:0] i2c_to_write;

i2c_master #(
    .DIVIDER (I2CDIV)
  ) i2c (
    .dbg_data	   (dbg_module),
    .i_clk	   (clk),
    .i_rst	   (reset),
    .i_enable	   (i2c_enable),
    .i_rw	   (i2c_rw),
    .i_device_addr (i2c_addr),
    .i_nbytes	   (i2c_nbytes),
    .i_mosi_data   (i2c_to_write),
    .o_miso_data   (i2c_readed),
    .o_need_data   (i2c_send_ready),
    .o_data_ready  (i2c_recv_ready),
    .o_busy	   (i2c_busy),
    .io_sda	   (sda),
    .io_scl	   (scl)
);

// eeprom
wire eeprom_start;
wire eeprom_ready, eeprom_busy;
wire [ 7:0] eeprom_data;
wire [15:0] eeprom_page;

read_eeprom #(
    .PAGE_BYTES (EEPROM_PAGE)
  ) eeprom (
    .clk	       (clk),
    .reset	       (reset),
    .slave_addr_w      (EEPROM_DEVICE),
    .page_addr_w       (eeprom_page),
    .read_nbytes_w     (EEPROM_PAGE[7:0]),
    .start	       (eeprom_start),
    .data_out	       (eeprom_data),
    .byte_ready        (eeprom_ready),
    .busy	       (eeprom_busy),

    .i2c_start	       (i2c_enable),
    .i2c_busy	       (i2c_busy),
    .i2c_rw	       (i2c_rw),
    .i2c_slave_addr    (i2c_addr),
    .i2c_nbytes        (i2c_nbytes),
    .i2c_write_data    (i2c_to_write),
    .i2c_read_data     (i2c_readed),
    .i2c_tx_data_req   (i2c_send_ready),
    .i2c_rx_data_ready (i2c_recv_ready)
);

// spi bus
wire	   spi_tx_ready, spi_tx_valid, spi_rx_valid;
wire [7:0] spi_tx_byte,  spi_rx_byte;
wire [6:0] spi_tx_count, spi_rx_count;

spi_bus #(
    .CLKS_PER_HALF_BIT (SPI_DIV)
  ) spi (
    .i_Clk    (clk),
    .i_Rst_L  (resetn),

   .i_TX_Count	(spi_tx_count),
   .i_TX_Byte	(spi_tx_byte),
   .i_TX_DV	(spi_tx_valid),
   .o_TX_Ready	(spi_tx_ready),

   .o_RX_Count	(spi_rx_count),
   .o_RX_DV	(spi_rx_valid),
   .o_RX_Byte	(spi_rx_byte),

   .o_SPI_Clk  (sck),
   .o_SPI_CS_n (ssn),
   .i_SPI_MISO (miso),
   .o_SPI_MOSI (mosi)
);

// sram
wire sram_busy, sram_ready, sram_start;
wire [ 7:0] sram_o_byte, sram_i_byte;
wire [15:0] sram_pageno;

sram #(
    .PAGE_BITS ($clog2 (EEPROM_PAGE))
  ) sram (
    .clk	       (clk),
    .reset	       (reset),
    .page_no	       (sram_pageno),
    .nbytes	       (EEPROM_PAGE[7:0]),
    .start	       (sram_start),
    .o_byte	       (sram_o_byte),
    .i_byte	       (sram_i_byte),
    .io_ready	       (sram_ready),
    .busy	       (sram_busy),

    .spi_tx_ready      (spi_tx_ready),
    .spi_tx_valid      (spi_tx_valid),
    .spi_tx_byte       (spi_tx_byte),
    .spi_tx_count      (spi_tx_count),

    .spi_rx_valid      (spi_rx_valid),
    .spi_rx_byte       (spi_rx_byte),
    .spi_rx_count      (spi_rx_count)
);

// level2 cache
wire l2_startI, l2_startD, l2_write, l2_launchI, l2_launchD, l2_busy, l2_ready;
wire [WIDTH - 1:0] l2_pageI, l2_pageD;
wire [15:0] l2_data;

mcache #(
    .MEM_PAGE	(EEPROM_PAGE),
    .ADDR_WIDTH (WIDTH),
    .BYTES	(512)
  ) l2 (
    .clk	(clk),
    .rst	(reset),
    .pageI	(l2_pageI),
    .pageD	(l2_pageD),
    .startI	(l2_startI),
    .startD	(l2_startD),
    .writeReq	(l2_write),
    .launchI	(l2_launchI),
    .launchD	(l2_launchD),
    .busy	(l2_busy),
    .ready	(l2_ready),
    .data	(l2_data),

    .ram_start	(sram_start),
    .ram_busy	(sram_busy),
    .ram_ready	(sram_ready),
    .ram_page	(sram_pageno),
    .ram_o_byte (sram_o_byte),
    .ram_i_byte (sram_i_byte),

    .rom_start	(eeprom_start),
    .rom_busy	(eeprom_busy),
    .rom_ready	(eeprom_ready),
    .rom_page	(eeprom_page),
    .rom_data	(eeprom_data)
);

// cpu
coreZ0 #(
    .WIDTH    (WIDTH),
    .ROM_PAGE (EEPROM_PAGE)
  ) cpu0 (
    .dbg_data	(dbg_payload),
    .dbg_empty	(dbg_ready),
    .clk	(clk),
    .rst	(reset),
    .led_r	(led_r),
    .led_h	(led_h),

    // l2
    .l2_startI	(l2_startI),
    .l2_startD	(l2_startD),
    .l2_write	(l2_write),
    .l2_pageI	(l2_pageI),
    .l2_pageD	(l2_pageD),
    .l2_launchI (l2_launchI),
    .l2_launchD (l2_launchD),
    .l2_busy	(l2_busy),
    .l2_ready	(l2_ready),
    .l2_data	(l2_data)
);

// debug function to dump hexadecimal
function [7:0] hdigit (input [3:0] nib);
    case (nib)
	4'h0: hdigit = "0";
	4'h1: hdigit = "1";
	4'h2: hdigit = "2";
	4'h3: hdigit = "3";
	4'h4: hdigit = "4";
	4'h5: hdigit = "5";
	4'h6: hdigit = "6";
	4'h7: hdigit = "7";
	4'h8: hdigit = "8";
	4'h9: hdigit = "9";
	4'ha: hdigit = "a";
	4'hb: hdigit = "b";
	4'hc: hdigit = "c";
	4'hd: hdigit = "d";
	4'he: hdigit = "e";
	4'hf: hdigit = "f";
    endcase
endfunction

// debug buffer
localparam BUFSIZE = 32;
localparam BUFBITS = $clog2 (BUFSIZE);

reg  [15:0] dbg_buf [0:BUFSIZE - 1];

reg  [BUFBITS - 1:0] dbg_read;
reg  [BUFBITS - 1:0] dbg_write;
reg		     dbg_wait_for_send;
wire		     dbg_empty = dbg_read == dbg_write;
assign		     dbg_ready = dbg_empty & !dbg_wait_for_send;

wire [BUFBITS - 1:0] dbg_plus1 = dbg_write + 1'b1;
wire		     dbg_full  = dbg_plus1 == dbg_read;

// send uart state
reg [1:0] sst;
localparam S_ZERO = 0;
localparam S_NIB0 = 1;
localparam S_NIB1 = 2;

always @(posedge clk) begin
  if (reset) begin
    dbg_read	      <= 0;
    dbg_write	      <= 0;
    dbg_wait_for_send <= 0;
    sst 	      <= S_ZERO;
  end else begin
    // new data
    if (|dbg_payload | |dbg_module) begin
      if (!dbg_full) begin
	dbg_buf[dbg_write] <= |dbg_payload ? dbg_payload : dbg_module;
	dbg_write	   <= dbg_plus1;
`ifdef TEST
	//$display ("DEBUG+\t%x %x %x (%x %x) empty=%x full=%x", cpu0.cycle, dbg_payload, dbg_module, dbg_read, dbg_write, dbg_empty, dbg_full);
      end else begin
	$display ("DEBUG!\t%x drop %x %x (%x %x) empty=%x full=%x", cpu0.cycle, dbg_payload, dbg_module, dbg_read, dbg_write, dbg_empty, dbg_full);
`endif
      end
    end

    // send uart logic
    if (!dbg_wait_for_send) begin
      case (sst)
	S_ZERO: begin
	  if (!dbg_empty) begin
	    dbg_wait_for_send <= 1'b1;
	    reg_dat_we	      <= 1'b1;
	    reg_dat_di	      <= dbg_buf[dbg_read][15:8];
	    sst 	      <= S_NIB0;
	  end
	end

	S_NIB0: begin
	  dbg_wait_for_send <= 1'b1;
	  reg_dat_we	    <= 1'b1;
	  reg_dat_di	    <= hdigit (dbg_buf[dbg_read][7:4]);
	  sst		    <= S_NIB1;
	end

	S_NIB1: begin
	  dbg_wait_for_send <= 1'b1;
	  reg_dat_we	    <= 1'b1;
	  reg_dat_di	    <= hdigit (dbg_buf[dbg_read][3:0]);
	  dbg_read	    <= dbg_read + 1'b1;
	  sst		    <= S_ZERO;
	  //$display ("DEBUG-\t%x (%x %x) empty=%x full=%x", cpu0.cycle, dbg_read, dbg_write, dbg_empty, dbg_full);
	end

      endcase
    end else if (!reg_dat_wait) begin
      reg_dat_we	<= 0;
      dbg_wait_for_send <= 0;
    end
  end
end

endmodule
