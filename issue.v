`include "global.inc"

`ifndef SYNTH
//`define ISSUE_TEST
`endif

module issue  #(
    parameter WIDTH = 32,
    parameter SIZE  = 8
  ) (
    input  clk,
    input  rst,

    // request
    input		 new,
    input  [2:0]	 type,
    input  [4:0]	 rd,
    input  [4:0]	 rl,
    input  [4:0]	 rr,
    input  [3:0]	 fn,
    input  [WIDTH - 1:0] imm,
    input  [WIDTH - 1:0] vl,
    input  [WIDTH - 1:0] vr,
    input  [1:0]		 rob_wait,
    input  [$clog2 (SIZE):0]	 rob_rl,
    input  [$clog2 (SIZE):0]	 rob_rr,
    input  [$clog2 (SIZE):0]	 rob_next,

    // register commit bus
    input  [4:0]	     rwrite,
    input  [$clog2 (SIZE):0] rbus,
    input  [WIDTH - 1:0]     result,

    // status
    output		 full,

    // notify completion
    output reg		 ntf,
    output reg[2:0]	 exc,
    output reg[WIDTH - 1:0] val,
    output reg[$clog2 (SIZE):0] at,

    // l2 api
    input  wire 	     l2_busy,
    input  wire 	     l2_ready,
    input  wire 	     l2_launch,
    output wire 	     l2_write,
    output wire 	     l2_start,
    output wire[WIDTH - 1:0] l2_page,
    input  wire[15:0]	     l2_data
);

localparam BITS   = $clog2 (SIZE);
localparam NULLRS = 0;

`PREPRO_DEFIF (SIZE8, 0)

// rs state
localparam S_FREE = 3'd0;
localparam S_WAIT = 3'd1;
localparam S_EXEC = 3'd2;
localparam S_DONE = 3'd3;
localparam S_RDYA = 3'd4;
localparam S_RDYB = 3'd5;
localparam S_RDYM = 3'd6;

// first available entry
wire [BITS - 1:0] free = rs_st[1] == S_FREE ? 1
		       : rs_st[2] == S_FREE ? 2
		       : rs_st[3] == S_FREE ? 3
`ifdef SIZE8
		       : rs_st[4] == S_FREE ? 4
		       : rs_st[5] == S_FREE ? 5
		       : rs_st[6] == S_FREE ? 6
		       : rs_st[7] == S_FREE ? 7
`endif
		       : NULLRS
		       ;

// queue full
assign full = (free == NULLRS);

// rs to commit
wire [BITS - 1:0] commit = rs_st[1] == S_DONE ? 1
			 : rs_st[2] == S_DONE ? 2
			 : rs_st[3] == S_DONE ? 3
`ifdef SIZE8
			 : rs_st[4] == S_DONE ? 4
			 : rs_st[5] == S_DONE ? 5
			 : rs_st[6] == S_DONE ? 6
			 : rs_st[7] == S_DONE ? 7
`endif
			 : NULLRS
			 ;

// RS data
reg [2:0]	 rs_st	 [0:SIZE - 1]; // entry state
reg [2:0]	 rs_exc  [0:SIZE - 1]; // exception code
reg [2:0]	 rs_type [0:SIZE - 1]; // instruction kind wait state
reg [3:0]	 rs_fn	 [0:SIZE - 1]; // requested function
reg [4:0]	 rs_rno  [0:SIZE - 1]; // register to update
reg [1:0]	 rs_wait [0:SIZE - 1]; // two bits signaling wait on robl/robr
reg [BITS:0]	 rs_rob  [0:SIZE - 1]; // rob index assigned
reg [BITS:0]	 rs_robl [0:SIZE - 1]; // rob index to wait for left  operand
reg [BITS:0]	 rs_robr [0:SIZE - 1]; // rob index to wait for right operand
reg [WIDTH -1:0] rs_v0	 [0:SIZE - 1];
reg [WIDTH -1:0] rs_v1	 [0:SIZE - 1];

// alu (2 reg 1 cycle operations) functional unit
wire [BITS - 1:0] rs_alu = rs_st[1] == S_RDYA ? 1
			 : rs_st[2] == S_RDYA ? 2
			 : rs_st[3] == S_RDYA ? 3
`ifdef SIZE8
			 : rs_st[4] == S_RDYA ? 4
			 : rs_st[5] == S_RDYA ? 5
			 : rs_st[6] == S_RDYA ? 6
			 : rs_st[7] == S_RDYA ? 7
`endif
			 : NULLRS
			 ;

reg  [3:0]	   a_op;
reg  [BITS  - 1:0] a_rs_i;
wire [BITS  - 1:0] a_rs;
reg  [WIDTH - 1:0] a_vl, a_vr;
wire [WIDTH - 1:0] a_result;

alu #(
    .WIDTH (WIDTH),
    .RSBIT (BITS)
  ) alu (
    .clk    (clk),
    .rst    (rst),
    .rs_i   (a_rs_i),
    .vl     (a_vl),
    .vr     (a_vr),
    .op     (a_op),
    .rs     (a_rs),
    .result (a_result)
);

// branch alu (2 reg 1 cycle operations) functional unit
wire [BITS - 1:0] rs_balu = rs_st[1] == S_RDYB ? 1
			  : rs_st[2] == S_RDYB ? 2
			  : rs_st[3] == S_RDYB ? 3
`ifdef SIZE8
			  : rs_st[4] == S_RDYB ? 4
			  : rs_st[5] == S_RDYB ? 5
			  : rs_st[6] == S_RDYB ? 6
			  : rs_st[7] == S_RDYB ? 7
`endif
			  : NULLRS
			  ;

reg  [2:0]	   b_op;
reg  [BITS  - 1:0] b_rs_i;
reg  [WIDTH - 1:0] b_vl, b_vr;
wire [BITS  - 1:0] b_rs;
wire		   b_taken;

balu #(
    .WIDTH (WIDTH),
    .RSBIT (BITS)
  ) balu (
    .clk    (clk),
    .rst    (rst),
    .rs_i   (b_rs_i),
    .vl     (b_vl),
    .vr     (b_vr),
    .op     (b_op),
    .rs     (b_rs),
    .taken  (b_taken)
);

// memory unit (multicycle)
wire [BITS - 1:0] rs_mem = rs_st[1] == S_RDYM ? 1
			 : rs_st[2] == S_RDYM ? 2
			 : rs_st[3] == S_RDYM ? 3
`ifdef SIZE8
			 : rs_st[4] == S_RDYM ? 4
			 : rs_st[5] == S_RDYM ? 5
			 : rs_st[6] == S_RDYM ? 6
			 : rs_st[7] == S_RDYM ? 7
`endif
			 : NULLRS
			 ;

reg [BITS  - 1:0] m_rs_i;
reg [WIDTH - 1:0] m_addr;
reg [WIDTH - 1:0] m_offset;
reg		  m_store;
reg [1:0]	  m_width;

wire		   m_busy;
wire [BITS  - 1:0] m_rs;
wire [2:0]	   m_exc;
wire [WIDTH - 1:0] m_result;

memory #(
    .WIDTH (WIDTH),
    .RSBIT (BITS)
  ) mem (
    .clk      (clk),
    .rst      (rst),
    .rs_i     (m_rs_i),
    .addr     (m_addr),
    .m_offset (m_offset),
    .store    (m_store),
    .width    (m_width),
    .busy     (m_busy),
    .rs       (m_rs),
    .exc      (m_exc),
    .result   (m_result),

    .l2_busy   (l2_busy),
    .l2_ready  (l2_ready),
    .l2_data   (l2_data),
    .l2_write  (l2_write),
    .l2_start  (l2_start),
    .l2_launch (l2_launch),
    .l2_page   (l2_page)
);

// logic
integer i;

always @ (posedge clk)
begin
  if (rst) begin
    ntf <= 1'b0;
    for (i = 1; i < SIZE; i++)
      rs_st[i] <= S_FREE;
  end else begin

    // hints
    //assume (rs_alu != rs_balu);

`ifndef SYNTH
    // debug
    if (coreZ0.cycle == 16'h39f0) begin
      $display ("RSDUMP\t%x free=%x full=%x", coreZ0.cycle, free, full);
      for (i = 1; i < SIZE; i++)
	if (rs_st[i] != S_FREE) begin
	  $display ("RS#%x\t%x st=%x wait=%x%x robl=%x robr=%x type=%x",
	    i[3:0], coreZ0.cycle, rs_st[i], rs_wait[i][1], rs_wait[i][0],
	    rs_robl[i], rs_robr[i], rs_type[i]
	    );
      end
    end
`endif

    // new issue
    if (new & |free) begin
      rs_exc [free] <= `EXC_NONE;
      rs_type[free] <= type;
      rs_fn  [free] <= fn;
      rs_rno [free] <= rd;
      rs_rob [free] <= rob_next;
      rs_wait[free] <= rob_wait;
      rs_robl[free] <= rob_rl;
      rs_robr[free] <= rob_rr;
      rs_v0  [free] <= vl;
      rs_v1  [free] <= &rr & !(&type) ? imm : vr;
      case (type)
	`I_ONE: begin
	  rs_st  [free] <= S_RDYA;
	  rs_type[free] <= S_RDYA;
	 end
	`I_BRA: begin
	  rs_st  [free] <= S_RDYB;
	  rs_type[free] <= S_RDYB;
	 end
	`I_ST : begin
	  rs_st  [free] <= S_RDYM;
	  rs_type[free] <= S_RDYM;
	end
	default: begin
	  rs_st [free] <= S_DONE;
	  rs_exc[free] <= `EXC_OP;
	end
      endcase
      if (|rob_wait) rs_st[free] <= S_WAIT;
`ifdef ISSUE_TEST
      $display ("ISSUE+\t%x @%x/%x K%x fn%x rd=%x rl=%x(%x) rr=%x(%x) imm=%x wait=%b%b vl=%x vr=%x",
	coreZ0.cycle, free, rob_next, type, fn, rd, rl, rob_rl, rr, rob_rr, imm, rob_wait[1], rob_wait[0], vl, vr
	);
`endif
    end

    // alu unit
    a_rs_i <= NULLRS;
    if (|rs_alu) begin
      a_rs_i	    <= rs_alu;
      a_vl	    <= rs_v0[rs_alu];
      a_vr	    <= rs_v1[rs_alu];
      a_op	    <= rs_fn[rs_alu];
      rs_st[rs_alu] <= S_EXEC;
    end

    // alu commit
    if (|a_rs) begin
      rs_st[a_rs] <= S_DONE;
      rs_v0[a_rs] <= a_result;
`ifdef ISSUE_TEST
      $display ("ISSUE=\t%x @%x ALU=%x", coreZ0.cycle, a_rs, a_result);
`endif
    end

    // branch alu unit
    b_rs_i <= NULLRS;
    if (|rs_balu) begin
      b_rs_i	     <= rs_balu;
      b_vl	     <= rs_v0[rs_balu];
      b_vr	     <= rs_v1[rs_balu];
      b_op	     <= rs_fn[rs_balu][2:0];
      rs_st[rs_balu] <= S_EXEC;
    end

    // branch alu commit
    if (|b_rs) begin
      rs_st[b_rs] <= S_DONE;
      if (b_taken) begin
	rs_exc[b_rs] <= `EXC_BPRED;
      end
`ifdef ISSUE_TEST
      $display ("ISSUE=\t%x @%x TAKEN=%x", coreZ0.cycle, b_rs, b_taken);
`endif
    end

    // memory unit
    m_rs_i <= NULLRS;
    if (!m_busy & |rs_mem) begin
      m_rs_i	    <= rs_mem;
      m_addr	    <= rs_v0[rs_mem];
      m_offset	    <= rs_v1[rs_mem];
      m_store	    <= rs_fn[rs_mem][2];
      m_width	    <= rs_fn[rs_mem][1:0];
      rs_st[rs_mem] <= S_EXEC;
    end

    // memory commit
    if (|m_rs) begin
      rs_st [m_rs] <= S_DONE;
      rs_v0 [m_rs] <= m_result;
      rs_exc[m_rs] <= m_exc;
`ifdef ISSUE_TEST
      $display ("ISSUE=\t%x @%x mem exc=%x result=%x", coreZ0.cycle, m_rs, m_exc, m_result);
`endif
    end

    // rob commit
    ntf <= 1'b0;
    if (|commit) begin
      ntf <= 1'b1;
      val <= rs_v0 [commit];
      exc <= rs_exc[commit];
      at  <= rs_rob[commit];
      rs_st[commit] <= S_FREE;
    end

    // register commit notify
    if (rwrite != `R_ZERO) begin
      //$display ("ISSUE$\t%x reg=%x @%x = %x", coreZ0.cycle, rwrite, rbus, result);
      for (i = 1; i < SIZE; i++) begin
	if (rs_st[i] == S_WAIT) begin
	   if (rs_wait[i][1] && rs_robl[i] == rbus) begin
	     rs_wait[i][1] <= 1'b0;
	     rs_v0[i]	   <= result;
	     if (!rs_wait[i][0] || rs_robr[i] == rbus) begin
		rs_st[i] <= rs_type[i];
	     end
`ifdef ISSUE_TEST
	     $display ("ISSUEl\t%x @%x = %x", coreZ0.cycle, i[3:0], result);
`endif
	   end
	   if (rs_wait[i][0] && rs_robr[i] == rbus) begin
	     rs_wait[i][0] <= 1'b0;
	     rs_v1[i]	   <= result;
	     if (!rs_wait[i][1] || rs_robl[i] == rbus) begin
		rs_st[i] <= rs_type[i];
	     end
`ifdef ISSUE_TEST
	     $display ("ISSUEr\t%x @%x = %x", coreZ0.cycle, i[3:0], result);
`endif
	   end
	end
      end
    end

  end
end

endmodule
