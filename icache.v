`include "global.inc"

`ifndef SYNTH
//`define ICACHE_TEST
`endif

module icache #(
     parameter ADDR_WIDTH = 16,
     parameter PAGE_BYTES = 32,
     parameter BYTES	  = 1024
  ) (
    input clk,
    input rst,
    input [ADDR_WIDTH - 1:0] addr,
    output reg busy,
    output reg ready,
    output [15:0] out,

    // l2 api
    input  wire       l2_busy,
    input  wire       l2_ready,
    input  wire       l2_launch,
    output reg	      l2_start,
    output reg [ADDR_WIDTH - 1:0] l2_page,
    input  wire[15:0] l2_data
);

// cache dimensions
localparam PAGE_WORDS  = PAGE_BYTES / 2;
localparam WORDS       = BYTES / 2;
localparam CACHE_LINES = BYTES / PAGE_BYTES;
localparam COMP_LINES  = CACHE_LINES / 2;	// two way cache
localparam CACHE_BITS  = $clog2 (COMP_LINES);
localparam OFFSET_BITS = $clog2 (PAGE_BYTES);

//state
reg [2:0] state;
localparam S_IDLE	 = 0;
localparam S_POLL	 = 1;
localparam S_CHECK_BEGIN = 2;
localparam S_CHECK	 = 3;
localparam S_LOAD	 = 4;
localparam S_LOOP	 = 5;

// cache memory
reg [15:0] vdata [0:WORDS - 1];
reg [ADDR_WIDTH - CACHE_BITS - 1:0] vtag [0:CACHE_LINES - 1];
reg vvalid [0:CACHE_LINES - 1];
reg vlru   [0:COMP_LINES - 1];

// internal helpers
reg  [$clog2 (WORDS) - 1:0] at;
assign out = vdata[at];

wire [OFFSET_BITS - 2:0]	       offset = addr[OFFSET_BITS - 1:1];
wire [ADDR_WIDTH  - OFFSET_BITS - 1:0] tag    = addr[ADDR_WIDTH - 1:OFFSET_BITS];
wire [CACHE_BITS  - 1:0]	       index  = tag [CACHE_BITS - 1:0];
wire [CACHE_BITS     :0]	       slot0  = {index, 1'b0};
wire [CACHE_BITS     :0]	       slot1  = {index, 1'b1};

reg [$clog2 (PAGE_WORDS) - 1:0] count;
reg [$clog2 (WORDS) - 1:0]	l2_load;

integer i;

always @(posedge clk)
begin
  if (rst) begin
    ready      <= 1'b0;
    busy       <= 1'b0;
    at	       <= 0;
    state      <= S_IDLE;
    for (i = 0; i < CACHE_LINES; i = i + 1) begin
      vvalid[i] <= 1'b0;
    end
    //$display ("ICACHE %d bytes %d lines(%d) addr %d bits offset %d bits", BYTES, CACHE_LINES, COMP_LINES, CACHE_BITS, OFFSET_BITS);
    // 32 ICACHE	1024 bytes	   32 lines(	    16) addr	       4 bits offset	       5 bits
    // 16 ICACHE	1024 bytes	   64 lines(	    32) addr	       5 bits offset	       4 bits
    //	4 ICACHE	1024 bytes	  256 lines(	   128) addr	       7 bits offset	       2 bits
  end else begin
    case (state)
      S_IDLE: begin
	busy  <= 1'b0;
	ready <= 1'b1;
	if (vvalid[slot0] && (vtag[slot0] == tag)) begin
	  at	      <= slot0 * PAGE_WORDS + offset;
	  vlru[index] <= 1'b1;
`ifdef ICACHE_TEST
	  $display ("icache0\t%x addr %x slot0 %x offset %x", coreZ0.cycle, addr, slot0, offset);
`endif
	end else if (vvalid[slot1] && (vtag[slot1] == tag)) begin
	  at	      <= slot1 * PAGE_WORDS + offset;
	  vlru[index] <= 1'b0;
`ifdef ICACHE_TEST
	  $display ("icache1\t%x addr %x slot1 %x offset %x", coreZ0.cycle, addr, slot1, offset);
`endif
	end else begin
	  busy		<= 1'b1;
	  ready 	<= 1'b0;

	  if (!vvalid[slot0] | (vvalid[slot1] & !vlru[index])) begin
	    at		  <= slot0 * PAGE_WORDS + offset;
	    l2_load	  <= slot0 * PAGE_WORDS;
	    vvalid[slot0] <= 1'b1;
	    vtag[slot0]   <= tag;
	    vlru[index]   <= 1'b1;
	  end else begin
	    at		  <= slot1 * PAGE_WORDS + offset;
	    l2_load	  <= slot1 * PAGE_WORDS;
	    vvalid[slot1] <= 1'b1;
	    vtag[slot1]   <= tag;
	    vlru[index]   <= 1'b0;
	  end

	  l2_page <= tag;
	  if (l2_busy) begin
	    state    <= S_POLL;
	  end else begin
	    state    <= S_CHECK_BEGIN;
	    l2_start <= 1'b1;
	  end
`ifdef ICACHE_TEST
	  $display ("icache\t%x addr %x tag %x offset %x index %d (%d %d)",
	    coreZ0.cycle, addr, tag, offset, index, slot0, slot1
	    );
`endif
	end
      end

      S_POLL: begin
	if (!l2_busy) begin
	  state    <= S_CHECK_BEGIN;
	  l2_start <= 1'b1;
	end
      end

      S_CHECK_BEGIN: begin
	state <= S_CHECK;
      end

      S_CHECK: begin
	if (!l2_launch) begin
	  // collision with more priority module
	  state <= S_POLL;
	end else begin
	  state <= S_LOAD;
	  count <= PAGE_WORDS - 1;
	end
      end

      S_LOAD: begin
	if (l2_ready) begin
	  state 	 <= S_LOOP;
	  vdata[l2_load] <= l2_data;
	  l2_load	 <= l2_load + 1'b1;
`ifdef ICACHE_TEST
	  $display ("icache+\t%x at %x = %x", coreZ0.cycle, l2_load, l2_data);
`endif
	end
      end

      S_LOOP: begin
	l2_start <= 0;
	count	 <= count - 1'b1;
	if (|count) begin
	  state <= S_LOAD;
	end else begin
	  state <= S_IDLE;
	  busy	<= 1'b0;
	  ready <= 1'b1;
`ifdef ICACHE_TEST
	  $display ("icache\t%x done", coreZ0.cycle);
`endif
	end
      end

    endcase
  end
end

endmodule
