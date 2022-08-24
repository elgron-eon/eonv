`include "global.inc"

`ifndef SYNTH
//`define COMMIT_TEST
`endif

module commit  #(
    parameter WIDTH = 32,
    parameter SIZE  = 8
  ) (
    input  clk,
    input  rst,

    // register status query
    input  [4:0] rl,
    input  [4:0] rr,
    output [1:0] rob_wait,
    output [$clog2 (SIZE) - 1:0] rob_rl,
    output [$clog2 (SIZE) - 1:0] rob_rr,
    output [$clog2 (SIZE) - 1:0] rob_next,

    // new request
    input	 new,
    input	 full,
    input  [2:0] type,
    input  [4:0] rno_i,
    input  [WIDTH - 1:0] imm,
    input  [WIDTH - 1:0] pc_i,

    // completion notification
    input	 ntf,
    input  [2:0] exc_n,
    input  [WIDTH - 1:0] val,
    input  [$clog2 (SIZE) - 1:0] at,

    // commit broadcast
    output reg[4:0]	    rno,
    output reg[2:0]	    exc,
    output reg[WIDTH - 1:0] pc,
    output reg[WIDTH - 1:0] rval,
    output reg[$clog2 (SIZE) - 1:0] rbus
);

localparam BITS = $clog2 (SIZE);

// register map
reg		 rrob [0:31];
reg [BITS - 1:0] rmap [0:31];
assign rob_rl	= rmap[rl];
assign rob_rr	= rmap[rr];
assign rob_wait = {rrob[rl], rrob[rr]};

// ROB: circular buffer
reg  [BITS - 1:0] head;
reg  [BITS - 1:0] tail;
wire empty = head == tail;

assign rob_next = tail;

// buffer data
reg		  rob_busy [0:SIZE - 1]; // entry state
reg [2:0]	  rob_exc  [0:SIZE - 1]; // exception code
reg [2:0]	  rob_typ  [0:SIZE - 1]; // instruction kind
reg [4:0]	  rob_rno  [0:SIZE - 1]; // register to update
reg [WIDTH - 1:0] rob_val  [0:SIZE - 1]; // result value
reg [WIDTH - 1:0] rob_pc   [0:SIZE - 1]; // opcode pc

// current reg to commit
wire [4:0] current = rob_rno[head];

integer i;

always @ (posedge clk)
begin
  if (rst) begin
    rno  <= `R_ZERO;
    exc  <= `EXC_NONE;
    head <= 0;
    tail <= 0;
    for (i = 0; i < 32; i++)
	rrob[i] = 1'b0;
  end else begin
    // defaults
    rno <= `R_ZERO;
    exc <= `EXC_NONE;

    // new request
    if (new & !full) begin
      rob_busy[tail] <= 1'b1;
      rob_typ [tail] <= type;
      rob_rno [tail] <= rno_i;
      rob_pc  [tail] <= pc_i;
      rob_val [tail] <= imm;
      tail	     <= tail + 1'b1;
      if (rno_i != `R_ZERO) begin
	rmap[rno_i] <= tail;
	rrob[rno_i] <= 1'b1;
	//$display ("rmap\t%x update R%x @ %x", coreZ0.cycle, rno_i, tail);
      end
`ifdef COMMIT_TEST
      $display ("ROB++\t%x K%x rd=%x (%x, %x) PC=%x imm=%x", coreZ0.cycle, type, rno_i, head, tail, pc_i, imm);
`endif
    end

    // notify ready
    if (ntf) begin
      rob_busy[at] <= 1'b0;
      rob_exc [at] <= exc_n;
      if (! (|exc_n))
	rob_val [at] <= val;
`ifdef COMMIT_TEST
      $display ("ROB==\t%x @%x exc=%x imm=%x (%x/%x)", coreZ0.cycle, at, exc_n, val, head, tail);
`endif
    end

    // commit
    if (!empty & !rob_busy[head]) begin
      rno  <= current;
      exc  <= rob_exc[head];
      rval <= rob_val[head];
      pc   <= rob_pc [head];
      rbus <= head;
      head <= head + 1'b1;
      if (rmap[current] == head)
	rrob[current] <= 1'b0;
`ifdef COMMIT_TEST
      $display ("COMMIT\t%x pc=%x exc=%x rno=%x val=%x (%x, %x)", coreZ0.cycle, rob_pc[head], rob_exc[head], rob_rno[head], rob_val[head], head, tail);
`endif
    end

  end
end

endmodule
