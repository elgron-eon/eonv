`include "global.inc"

//`define MCACHE_TEST

module mcache #(
     parameter ADDR_WIDTH = 16,
     parameter MEM_PAGE   = 32,
     parameter ROM_TOP	  = 16'h2000,
     parameter BYTES	  = 1024
  ) (
    input clk,
    input rst,
    input [ADDR_WIDTH - 1:0] pageI,	// page from ICache
    input [ADDR_WIDTH - 1:0] pageD,	// page from DCache
    input	      startI,
    input	      startD,
    input	      writeReq,
    output reg	      launchI,
    output reg	      launchD,
    output reg	      busy,
    output reg	      ready,
    output reg [15:0] data,

    // ram
    input  wire        ram_busy,
    input  wire        ram_ready,
    output wire        ram_start,
    input  wire [ 7:0] ram_o_byte,
    output reg	[ 7:0] ram_i_byte,
    output reg	[15:0] ram_page,

    // rom
    input  wire        rom_busy,
    input  wire        rom_ready,
    input  wire[7:0]   rom_data,
    output reg	       rom_start,
    output reg[15:0]   rom_page
);

// dummies
assign ram_start  = 0;

// cache dimensions
localparam PAGE_WORDS  = MEM_PAGE / 2;
localparam WORDS       = BYTES / 2;
localparam CACHE_LINES = BYTES / MEM_PAGE;
localparam COMP_LINES  = CACHE_LINES / 2;	// two way cache
localparam CACHE_BITS  = $clog2 (COMP_LINES);
localparam OFFSET_BITS = $clog2 (MEM_PAGE);

//state
reg [3:0] st;
localparam S_IDLE	= 0;
localparam S_REQUEST	= 1;
localparam S_WRITE	= 2;
localparam S_WRITE_LOOP = 3;
localparam S_READ	= 4;
localparam S_READ_LOOP	= 5;
localparam S_ROM_BEGIN	= 6;
localparam S_ROM_LOAD	= 7;
localparam S_ROM_LOOP	= 8;
localparam S_RAM_BEGIN	= 9;

localparam READ  = 1'b0;
localparam WRITE = 1'b1;

// cache memory
reg [15:0] vdata [0:WORDS - 1];
reg [ADDR_WIDTH - CACHE_BITS - 1:0] vtag [0:CACHE_LINES - 1];
reg vvalid [0:CACHE_LINES - 1];
reg vlru   [0:COMP_LINES - 1];

// internal helpers
reg [$clog2 (WORDS) - 1:0]	      at;
reg [$clog2 (PAGE_WORDS) - 1:0]       count;
reg				      rw;
reg [ADDR_WIDTH  - OFFSET_BITS - 1:0] tag;

wire [CACHE_BITS  - 1:0] index = tag [CACHE_BITS - 1:0];
wire [CACHE_BITS     :0] slot0 = {index, 1'b0};
wire [CACHE_BITS     :0] slot1 = {index, 1'b1};

reg [ADDR_WIDTH - CACHE_BITS - 1:0] rom_tag;
reg [$clog2 (WORDS) - 1:0]	    rom_load;
reg				    rom_even;
reg [7:0]			    rom_byte;

integer i;

always @(posedge clk)
begin
  if (rst) begin
    ready   <= 1'b0;
    busy    <= 1'b0;
    at	    <= 0;
    launchD <= 1'b0;
    launchI <= 1'b0;
    st	    <= S_IDLE;
    for (i = 0; i < CACHE_LINES; i = i + 1) begin
      vvalid[i] <= 1'b0;
    end
    //$display ("MCACHE %d bytes %d lines(%d) index %d bits tag %d bits offset %d bits", BYTES, CACHE_LINES, COMP_LINES, CACHE_BITS, ADDR_WIDTH - OFFSET_BITS, OFFSET_BITS);
    //MCACHE	    1024 bytes	       64 lines(	32) index	    5 bits tag		12 bits offset		 4 bits
  end else begin
    case (st)

      S_IDLE: begin
	busy	<= 1'b0;
	launchD <= 1'b0;
	launchI <= 1'b0;
	if (startD) begin
	  // dcache has priority
	  tag	  <= pageD[ADDR_WIDTH  - OFFSET_BITS - 1:0];
	  rw	  <= writeReq;
	  st	  <= S_REQUEST;
	  launchD <= 1'b1;
	  busy	  <= 1'b1;
	end else if (startI) begin
	  tag	  <= pageI[ADDR_WIDTH  - OFFSET_BITS - 1:0];
	  rw	  <= READ;
	  st	  <= S_REQUEST;
	  launchI <= 1'b1;
	  busy	  <= 1'b1;
	end
      end

      S_REQUEST: begin
	launchD <= 1'b0;
	launchI <= 1'b0;
	count	<= PAGE_WORDS - 1;
	if (vvalid[slot0] && (vtag[slot0] == tag)) begin
	  at	      <= slot0 * PAGE_WORDS;
	  st	      <= rw ? S_WRITE : S_READ;
	  vlru[index] <= 1'b0;
`ifdef MCACHE_TEST
	  $strobe ("mcache slot0 %t at %x tag %x", $time, at, tag);
`endif
	end else if (vvalid[slot1] && (vtag[slot1] == tag)) begin
	  at	      <= slot1 * PAGE_WORDS;
	  st	      <= rw ? S_WRITE : S_READ;
	  vlru[index] <= 1'b0;
`ifdef MCACHE_TEST
	  $strobe ("mcache slot1 %t at %x tag %x", $time, at, tag);
`endif
	end else begin
	  // select slot
	  if (!vvalid[slot0] | (vvalid[slot1] & !vlru[index])) begin
	    at		  <= slot0 * PAGE_WORDS;
	    vvalid[slot0] <= 1'b1;
	    vtag[slot0]   <= tag;
	    vlru[index]   <= 1'b1;
`ifdef MCACHE_TEST
	  $strobe ("mcache load0 %t at %x tag %x slot %x", $time, at, tag, slot0);
`endif
	  end else begin
	    at		  <= slot1 * PAGE_WORDS;
	    vvalid[slot1] <= 1'b1;
	    vtag[slot1]   <= tag;
	    vlru[index]   <= 1'b0;
`ifdef MCACHE_TEST
	  $strobe ("mcache load1 %t at %x tag %x slot %x", $time, at, tag, slot1);
`endif
	  end

	  // ROM/RAM
	  st <= tag < ROM_TOP / MEM_PAGE ? S_ROM_BEGIN : S_RAM_BEGIN;
	end
      end

      S_READ: begin
	data  <= vdata[at];
	at    <= at + 1;
	ready <= 1'b1;
	st    <= S_READ_LOOP;
	//$display ("READ %x at %x count %x", vdata[at], at, count);
      end

      S_READ_LOOP: begin
	ready <= 1'b0;
	count <= count - 1'b1;
	st    <= |count ? S_READ : S_IDLE;
`ifdef MCACHE_TEST
	if (count == 0) $display ("mcache done. %t", $time);
`endif
      end

      S_ROM_BEGIN: begin
	if (!rom_busy) begin
	  st	    <= S_ROM_LOAD;
	  rom_even  <= 1'b1;
	  rom_page  <= tag;
	  rom_load  <= at;
	  rom_start <= 1'b1;
`ifdef MCACHE_TEST
	  $strobe ("mcache romgo %t page %x load at %x", $time, rom_page, rom_load);
`endif
	end
      end

      S_ROM_LOAD: begin
	if (rom_ready) begin
	  st	   <= S_ROM_LOOP;
	  rom_even <= ~rom_even;
	  if (rom_even) begin
	    rom_byte <= rom_data;
	  end else begin
	    vdata[rom_load] <= {rom_byte, rom_data};
	    rom_load	    <= rom_load + 1'b1;
`ifdef MCACHE_TEST
	    $display ("mcache rom++ %t at %x = %x", $time, rom_load, {rom_byte, rom_data});
`endif
	  end
	end
      end

      S_ROM_LOOP: begin
	rom_start <= 0;
	if (!rom_busy) begin
`ifdef MCACHE_TEST
	  $strobe ("mcache rom!! %t", $time);
`endif
	  st <= rw ? S_WRITE : S_READ;
	end else if (!rom_ready) begin
	  st <= S_ROM_LOAD;
	end
      end

    endcase
  end
end

endmodule
