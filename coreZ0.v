`include "global.inc"

module coreZ0 #(
     parameter WIDTH	= 16,
     parameter ROM_PAGE = 32,
     parameter ROB_SIZE = 4
  ) (
    input clk,
    input rst,

    // l2 cache
    output wire 	     l2_startI,
    output wire 	     l2_startD,
    output wire 	     l2_write,
    output wire[WIDTH - 1:0] l2_pageI,
    output wire[WIDTH - 1:0] l2_pageD,
    input  wire 	     l2_launchI,
    input  wire 	     l2_launchD,
    input  wire 	     l2_busy,
    input  wire 	     l2_ready,
    input  wire[15:0]	     l2_data,

    // status
    output reg		     led_r,
    output reg		     led_h,

    // debug
    input  wire 	     dbg_empty,
    output reg [15:0]	     dbg_data
);

// flush control line
reg flush;

// register file
wire [WIDTH - 1:0] r_vl, r_vr, r_result;
wire [4:0]	   r_rl, r_rr, r_rd;

regfile #(
    .WIDTH (WIDTH)
  ) rfile (
    .clk  (clk),
    .rst  (rst),
    .data (r_result),
    .r0   (r_rl),
    .r1   (r_rr),
    .rd   (r_rd),
    .v0   (r_vl),
    .v1   (r_vr)
);

// fetch
wire	    f_ready, f_dready, f_pcload;
wire [15:0] f_word;
wire [WIDTH - 1:0] f_pcin, f_pc, f_ip;

fetch #(
    .WIDTH	(WIDTH),
    .PAGE_BYTES (ROM_PAGE)
  ) fetch (
    .clk      (clk),
    .rst      (rst),
    .d_ready  (f_dready),
    .pcload   (f_pcload),
    .pcin     (f_pcin),
    .pc       (f_pc),
    .pcnext   (f_ip),
    .word     (f_word),
    .op_ready (f_ready),

    .l2_busy   (l2_busy),
    .l2_ready  (l2_ready),
    .l2_data   (l2_data),
    .l2_start  (l2_startI),
    .l2_launch (l2_launchI),
    .l2_page   (l2_pageI)
);

// decoder
wire d_new, d_full, d_dready;
wire [2:0] d_type;
wire [3:0] d_fn;
wire [4:0] d_rd;
wire [WIDTH - 1:0] d_imm, d_pc;

decode #(
    .DATA_WIDTH (WIDTH)
  ) dec (
    .clk     (clk),
    .rst     (rst | flush),
    .d_ready (f_dready),
    .i_ready (!d_full),
    .opready (f_ready),
    .op      (f_word),
    .pc_f    (f_pc),
    .pcnext  (f_ip),
    .new     (d_new),
    .rd      (d_rd),
    .rl      (r_rl),
    .rr      (r_rr),
    .type    (d_type),
    .imm     (d_imm),
    .pc      (d_pc),
    .fn      (d_fn)
);

// issue unit
wire [1:0] i_rob_wait;
wire [$clog2 (ROB_SIZE):0] i_rob_rl, i_rob_rr, i_rob_next, i_at, i_rbus;
wire i_ntf;
wire [2:0] i_exc;
wire [WIDTH - 1:0] i_val;

issue #(
    .WIDTH (WIDTH),
    .SIZE  (ROB_SIZE)
  ) issue (
    .clk      (clk),
    .rst      (rst | flush),
    .full     (d_full),
    .new      (d_new),
    .type     (d_type),
    .rd       (d_rd),
    .rl       (r_rl),
    .rr       (r_rr),
    .imm      (d_imm),
    .fn       (d_fn),
    .vl       (r_vl),
    .vr       (r_vr),
    .rob_wait (i_rob_wait),
    .rob_rl   (i_rob_rl),
    .rob_rr   (i_rob_rr),
    .rob_next (i_rob_next),

     // register commit bus
    .rbus     (i_rbus),
    .rwrite   (r_rd),
    .result   (r_result),

    // completion notify
    .ntf      (i_ntf),
    .exc      (i_exc),
    .val      (i_val),
    .at       (i_at),

    // l2 api
    .l2_busy   (l2_busy),
    .l2_ready  (l2_ready),
    .l2_write  (l2_write),
    .l2_data   (l2_data),
    .l2_start  (l2_startD),
    .l2_launch (l2_launchD),
    .l2_page   (l2_pageD)
);

// commit
wire [2:0] c_exc;
wire [WIDTH - 1:0] c_at;

commit #(
    .WIDTH (WIDTH),
    .SIZE  (ROB_SIZE * 2)
  ) commit (
    .clk      (clk),
    .rst      (rst | flush),

    .rl       (r_rl),
    .rr       (r_rr),
    .rob_wait (i_rob_wait),
    .rob_rl   (i_rob_rl),
    .rob_rr   (i_rob_rr),
    .rob_next (i_rob_next),

    .new      (d_new),
    .full     (d_full),
    .type     (d_type),
    .rno_i    (d_rd),
    .pc_i     (d_pc),
    .imm      (d_imm),

    .ntf      (i_ntf),
    .exc_n    (i_exc),
    .val      (i_val),
    .at       (i_at),

    .exc      (c_exc),
    .pc       (c_at),
    .rno      (r_rd),
    .rval     (r_result),
    .rbus     (i_rbus)
);

// control logic
reg [WIDTH - 1:0] cycle, core_pc;
reg [2:0] core_ex;
reg	  core_in;

assign f_pcin	= core_pc;
assign f_pcload = core_in;

reg [2:0] st;

localparam S_RUN    = 0;
localparam S_BRANCH = 1;
localparam S_END    = 2;
localparam S_DONE   = 3;
localparam S_MARK   = 4;
localparam S_WAIT   = 5;

always @ (posedge clk)
begin
  if (rst) begin
    dbg_data <= 1'b0;
    core_in  <= 1'b0;
    led_r    <= 1'b1;
    led_h    <= 1'b0;
    flush    <= 1'b0;
    st	     <= S_RUN;
    cycle    <= 0;
  end else begin
    dbg_data <= 0;
    cycle    <= cycle + 1'b1;
    case (st)
      S_RUN: begin
	if (&c_exc) begin
	  st	  <= S_BRANCH;
	  core_pc <= r_result;
	  core_in <= 1'b1;
	  flush   <= 1'b1;
`ifdef TEST_OFF
	  $display ("BRANCH\t%x @%x to %x", cycle, c_at, r_result);
`endif
	end else if (|c_exc) begin
	  st	  <= S_END;
	  core_pc <= c_at;
	  core_ex <= c_exc;
	  core_in <= 1'b1;
	  flush   <= 1'b1;
`ifdef TEST
	  $display ("coreZ0\t%x pc=%x exc=%x val=%x", cycle, c_at, c_exc, r_result);
`endif
	end
      end

      S_BRANCH: begin
	if (f_ready && f_pc == core_pc) begin
`ifdef TEST_OFF
	  $display ("FLUSH\t%x ready %x %x", cycle, f_pc, f_word);
`endif
	  flush   <= 1'b0;
	  core_in <= 1'b0;
	  st	  <= S_RUN;
	end
      end

      S_END: begin
	st	 <= S_DONE;
	dbg_data <= {"@", core_pc[15:8]};
      end

      S_DONE: begin
	st	 <= S_MARK;
	dbg_data <= {".", core_pc[7:0]};
      end

      S_MARK: begin
	st	 <= S_WAIT;
	dbg_data <= {"!", {5'b0, core_ex}};
      end

      S_WAIT: begin
	if (dbg_empty) begin
	  led_h <= 1'b1;
	end
      end

    endcase
  end
end

endmodule
