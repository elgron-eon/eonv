`include "global.inc"

`ifndef SYNTH
//`define FETCH_TEST
`endif

module fetch #(
     parameter WIDTH	  = 32,
     parameter PAGE_BYTES = 32
  ) (
    input clk,
    input rst,
    input d_ready,
    input pcload,
    input  [WIDTH - 1:0] pcin,

    output reg	[WIDTH - 1:0] pc,
    output reg	[WIDTH - 1:0] pcnext,
    output wire [15:0] word,
    output wire op_ready,

    // l2 api
    input  wire 	      l2_busy,
    input  wire 	      l2_ready,
    input  wire 	      l2_launch,
    output wire 	      l2_start,
    output wire [WIDTH - 1:0] l2_page,
    input  wire[15:0]	      l2_data
);

// icache
wire i_busy;

// i-cache instruction pointer
reg [WIDTH - 1:0] ip;

icache #(
    .PAGE_BYTES (PAGE_BYTES),
    .ADDR_WIDTH (WIDTH),
    .BYTES	(512)
  ) icache (
    .clk   (clk),
    .rst   (rst),
    .addr  (ip),
    .ready (op_ready),
    .busy  (i_busy),
    .out   (word),

    .l2_busy   (l2_busy),
    .l2_ready  (l2_ready),
    .l2_data   (l2_data),
    .l2_start  (l2_start),
    .l2_launch (l2_launch),
    .l2_page   (l2_page)
  );

// next pc
wire [WIDTH - 1:0] w_pcnext = pc + 2'b10;
wire [WIDTH - 1:0] w_ipnext = ip + 2'b10;

// set new pc
always @ (posedge clk)
begin
  if (rst) begin
    pc	   <= 0;
    pcnext <= 0;
    ip	   <= 0;
  end else if (pcload) begin
    ip	<= pcin;
    pc	<= pcin;
  end else begin
    ip	   <= w_pcnext;
    pcnext <= w_pcnext;

    if (op_ready & d_ready) begin
      pc     <= ip;
      pcnext <= w_ipnext;
      ip     <= w_ipnext;
`ifdef FETCH_TEST
      $display ("FETCH\t%x pc=%x next=%x word=%x", coreZ0.cycle, pc, pcnext, word);
`endif
    end
  end
end

endmodule
