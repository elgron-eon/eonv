`include "global.inc"

`ifndef SYNTH
`define SRAM_TEST
`endif

module sram #(
    parameter PAGE_BITS = 5
  ) (
    // inputs
    input wire clk,
    input wire reset,
    input wire [15:0] page_no,
    input wire [ 7:0] nbytes,
    input wire start,

    // outputs
    input  wire [7:0] i_byte,
    output reg	[7:0] o_byte,
    output reg	io_ready,
    output reg	busy,

    // spi lines
    input  wire       spi_tx_ready,
    output reg	      spi_tx_valid,
    output reg	[7:0] spi_tx_byte,
    output reg	[6:0] spi_tx_count,

    input wire	     spi_rx_valid,
    input wire [7:0] spi_rx_byte,
    input wire [6:0] spi_rx_count
);

localparam PAGE_BYTES = $pow (2, PAGE_BITS);

localparam RAM_WRMR  = 8'h01;
localparam RAM_WRITE = 8'h02;
localparam RAM_READ  = 8'h03;

localparam MODE_SEQUENTIAL = 8'h40;

//state params
localparam STATE_IDLE	    = 0;
localparam STATE_START	    = 1;
localparam STATE_INIT_0     = 2;
localparam STATE_INIT_DONE  = 3;
localparam STATE_ADDR_H     = 4;
localparam STATE_ADDR_M     = 5;
localparam STATE_ADDR_L     = 6;
localparam STATE_READ	    = 7;

// locals
reg	   sram_init, drop;
reg [ 3:0] state;
reg [23:0] mem_addr;
reg [ 7:0] read_nbytes;

//output register definitions
reg waiting_for_tx;
reg read_prev_data;
reg [7:0] byte_count;

always @(posedge clk) begin
  if (reset == 1) begin
    spi_tx_valid <= 0;
    spi_tx_count <= 0;

    sram_init	 <= 0;
    o_byte	 <= 0;
    io_ready	 <= 0;

    mem_addr	   <= 0;
    read_nbytes    <= 0;
    byte_count	   <= 0;
    waiting_for_tx <= 0;

    busy	   <= 0;
    state	   <= STATE_IDLE;
  end else begin
    case(state)

      STATE_IDLE: begin
	busy <= 0;
	if (start) begin
	  state        <= STATE_START;
	  mem_addr     <= {page_no[15 - PAGE_BITS:0], {PAGE_BITS {1'b0}}};
	  read_nbytes  <= nbytes + 3'b100; // 4 bytes more: CMD + ADDR(3)
	  busy	       <= 1'b1;
`ifdef SRAM_TEST
	    $display ("sram   begin %t page %x nbytes %d pagebits %d", $time, page_no, nbytes, PAGE_BITS);
`endif
	end
      end

      STATE_START: begin
	if (spi_tx_ready) begin
	  if (!sram_init) begin
	    state	 <= STATE_INIT_0;
	    spi_tx_count <= 2;
	    spi_tx_byte  <= RAM_WRMR;
	    sram_init	 <= 1'b1;
	  end else begin
	    state	 <= STATE_ADDR_H;
	    spi_tx_count <= 3;
	    spi_tx_byte  <= RAM_READ;
	  end
	  spi_tx_valid <= 1'b1;
`ifdef SRAM_TEST
	  $display ("sram   start %t addr %x init %d", $time, mem_addr, sram_init);
`endif
	end
      end

      STATE_INIT_0: begin
	 spi_tx_valid <= 1'b0;
	 if (spi_tx_ready) begin
	   spi_tx_byte	<= MODE_SEQUENTIAL;
	   spi_tx_valid <= 1'b1;
	   state	<= STATE_INIT_DONE;
`ifdef SRAM_TEST
	   $display ("sram   init0 %t", $time);
`endif
	 end
      end

      STATE_INIT_DONE: begin
	 spi_tx_valid <= 1'b0;
	 if (spi_tx_ready) begin
	    state	 <= STATE_ADDR_H;
	    spi_tx_count <= read_nbytes;
	    spi_tx_byte  <= RAM_READ;
	    spi_tx_valid <= 1'b1;
`ifdef SRAM_TEST
	 $display ("sram   idone %t", $time);
`endif
	 end
      end

      STATE_ADDR_H: begin
	 spi_tx_valid <= 1'b0;
	 if (spi_tx_ready) begin
	   spi_tx_byte	<= mem_addr[23:16];
	   spi_tx_valid <= 1'b1;
	   state	<= STATE_ADDR_M;
`ifdef SRAM_TEST
	   $display ("sram   addrH %t = %x", $time, mem_addr[23:16]);
`endif
	 end
      end

      STATE_ADDR_M: begin
	 spi_tx_valid <= 1'b0;
	 if (spi_tx_ready) begin
	   spi_tx_byte	<= mem_addr[15:8];
	   spi_tx_valid <= 1'b1;
	   state	<= STATE_ADDR_L;
`ifdef SRAM_TEST
	   $display ("sram   addrM %t = %x", $time, mem_addr[15:8]);
`endif
	 end
      end

      STATE_ADDR_L: begin
	 spi_tx_valid <= 1'b0;
	 if (spi_tx_ready) begin
	   spi_tx_byte	<= mem_addr[7:0];
	   spi_tx_valid <= 1'b1;
	   state	<= STATE_READ;
	   drop 	<= 1'b1;
`ifdef SRAM_TEST
	   $display ("sram   addrL %t = %x", $time, mem_addr[7:0]);
`endif
	 end
      end

      STATE_READ: begin
	 io_ready <= 1'b0;
	 spi_tx_valid <= 1'b0;
	 if (spi_tx_ready) begin
	   spi_tx_byte	<= 0;
	   spi_tx_valid <= 1'b1;
	   state	<= STATE_READ;
`ifdef SRAM_TEST
	   $display ("sram   nextb %t", $time);
`endif
	 end
	 if (spi_rx_valid) begin
	   if (drop)
	     drop <= 1'b0;
	   else begin
	     io_ready <= 1'b1;
	     o_byte   <= spi_rx_byte;
`ifdef SRAM_TEST
	     $display ("sram-- readb %t %x (%x)", $time, spi_rx_byte, spi_rx_count);
`endif
	     if (|spi_rx_count == 1'b0) begin
	       state <= STATE_IDLE;
	       busy  <= 1'b0;
`ifdef SRAM_TEST
	       $display ("sram-- done  %t", $time);
`endif
	     end
	   end
	 end
      end

    endcase
  end
end

endmodule
