`include "global.inc"

`ifndef SYNTH
`define MEMORY_TEST
`endif

module memory  #(
     parameter WIDTH	  = 32,
     parameter RSBIT	  = 3,
     parameter PAGE_BYTES = 32,
     parameter BYTES	  = 512
  ) (
    input		clk,
    input		rst,
    input [RSBIT - 1:0] rs_i,
    input [WIDTH - 1:0] addr,
    input [WIDTH - 1:0] m_offset,
    input		store,
    input [1:0] 	width,

    output		     busy,
    output reg [RSBIT - 1:0] rs,
    output reg [2:0]	     exc,
    output reg [WIDTH - 1:0] result,

    // l2 api
    input  wire       l2_busy,
    input  wire       l2_ready,
    input  wire       l2_launch,
    output reg	      l2_write,
    output reg	      l2_start,
    output reg [WIDTH - 1:0] l2_page,
    input  wire[15:0] l2_data
);

// cache dimensions
localparam PAGE_WORDS  = PAGE_BYTES / 2;
localparam WORDS       = BYTES / 2;
localparam CACHE_LINES = BYTES / PAGE_BYTES;
localparam COMP_LINES  = CACHE_LINES / 2;	// two way cache
localparam CACHE_BITS  = $clog2 (COMP_LINES);
localparam OFFSET_BITS = $clog2 (PAGE_BYTES);

// state
localparam S_ZERO	 = 0;
localparam S_BEGIN	 = 1;
localparam S_POLL	 = 2;
localparam S_CHECK_BEGIN = 3;
localparam S_CHECK	 = 4;
localparam S_LOAD	 = 5;
localparam S_LOOP	 = 6;
localparam S_DONE	 = 7;

reg [2:0] st;
assign busy = |st;

reg [WIDTH - 1:0] maddr;	// memory effective address
reg [1:0]	  mwidth;	// access width
reg		  mstore;	// load/store
reg [RSBIT - 1:0] mrs;		// RS index

// cache memory
reg [15:0] vdata [0:WORDS - 1];
reg [WIDTH - CACHE_BITS - 1:0] vtag [0:CACHE_LINES - 1];
reg vvalid [0:CACHE_LINES - 1];
reg vlru   [0:COMP_LINES - 1];

// helpers
wire [OFFSET_BITS - 2:0]	  offset = maddr[OFFSET_BITS - 1:1];
wire [WIDTH  - OFFSET_BITS - 1:0] tag	 = maddr[WIDTH - 1:OFFSET_BITS];
wire [CACHE_BITS  - 1:0]	  index  = tag [CACHE_BITS - 1:0];
wire [CACHE_BITS     :0]	  slot0  = {index, 1'b0};
wire [CACHE_BITS     :0]	  slot1  = {index, 1'b1};

reg [$clog2 (WORDS) - 1:0]	at;
reg [$clog2 (PAGE_WORDS) - 1:0] count;
reg [$clog2 (WORDS) - 1:0]	l2_load;

// logic
integer i;
always @ (posedge clk)
begin
  if (rst) begin
    l2_start <= 0;
    l2_write <= 0;
    rs	     <= 0;
    st	     <= S_ZERO;
    for (i = 0; i < CACHE_LINES; i = i + 1) begin
      vvalid[i] <= 1'b0;
    end
  end else begin
    rs <= 0;

    case (st)
      S_ZERO: begin
	if (|rs_i) begin
	  maddr  <= addr + m_offset;
	  mwidth <= width;
	  mstore <= store;
	  mrs	 <= rs_i;
	  st	 <= S_BEGIN;
`ifdef MEMORY_TEST
	$display ("MEMORY(\t%x ea=%x width=%x store=%x", coreZ0.cycle, addr + m_offset, width, store);
`endif
	end
      end

      S_BEGIN: begin
	if (vvalid[slot0] && (vtag[slot0] == tag)) begin
	  at	      <= slot0 * PAGE_WORDS + offset;
	  vlru[index] <= 1'b1;
	  st	      <= S_DONE;
`ifdef MEMORY_TEST
	  $display ("dcache0\t%x addr %x slot0 %x offset %x", coreZ0.cycle, maddr, slot0, offset);
`endif
	end else if (vvalid[slot1] && (vtag[slot1] == tag)) begin
	  at	      <= slot1 * PAGE_WORDS + offset;
	  vlru[index] <= 1'b0;
	  st	      <= S_DONE;
`ifdef MEMORY_TEST
	  $display ("dcache1\t%x addr %x slot1 %x offset %x", coreZ0.cycle, maddr, slot1, offset);
`endif
	end else begin
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
	    st	     <= S_POLL;
	  end else begin
	    st	     <= S_CHECK_BEGIN;
	    l2_start <= 1'b1;
	  end
`ifdef MEMORY_TEST
	  $display ("dcache\t%x addr %x tag %x offset %x index %d (%d %d)",
	    coreZ0.cycle, maddr, tag, offset, index, slot0, slot1
	    );
`endif
	end
      end

      S_POLL: begin
	if (!l2_busy) begin
	  st	   <= S_CHECK_BEGIN;
	  l2_start <= 1'b1;
	end
      end

      S_CHECK_BEGIN: begin
	st <= S_CHECK;
      end

      S_CHECK: begin
	if (!l2_launch) begin
	  // collision with more priority module
	  st <= S_POLL;
	end else begin
	  st	<= S_LOAD;
	  count <= PAGE_WORDS - 1;
	end
      end

      S_LOAD: begin
	if (l2_ready) begin
	  st		 <= S_LOOP;
	  vdata[l2_load] <= l2_data;
	  l2_load	 <= l2_load + 1'b1;
`ifdef MEMORY_TEST
	  $display ("dcache+\t%x at %x = %x", coreZ0.cycle, l2_load, l2_data);
`endif
	end
      end

      S_LOOP: begin
	l2_start <= 0;
	count	 <= count - 1'b1;
	if (|count) begin
	  st <= S_LOAD;
	end else begin
	  st <= S_DONE;
`ifdef MEMORY_TEST
	  $display ("icache\t%x done", coreZ0.cycle);
`endif
	end
      end

      S_DONE: begin
	rs     <= mrs;
	result <= vdata[at];
	exc    <= `EXC_ALIGN;
	st     <= S_ZERO;
`ifdef MEMORY_TEST
	$display ("MEMORY)\t%x ea=%x result=%x @%x", coreZ0.cycle, maddr, result, mrs);
`endif
      end

    endcase
  end
end

endmodule
