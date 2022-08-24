`include "global.inc"

`ifndef SYNTH
//`define DECODE_TEST
`endif

// 0000 rd rz ----:	_ zext1 zext2 zext4 bswap sext1 sext2 sext4 csetz csetnz csetn csetnn csetp csetnp _ _
// 0000 sp rs ----:	jmpr jalr _ _ istat tlba tlbv _ get-i16 set-i16 leasp-i16 _ li-i32 lea-i32 _ _
// 0000 sp sp ----:	illegal nop syscall wait iret sret eret tlb enter-i16 signal-i16 _ _ jmp-i32 jal-i32 _ _
// 0001 rd rs ---- i16: ld1 ld1i ld2 ld2i ld4 ld4i ld8 _ st1 st2 st4 st8 _ _ _ cas
// 0010 rz rz ---- i16: beq bne blt blti ble blei bltf blef pbeq pbne pblt pblti pble pblei pbltf pblef
// 0011 rd rz ---- i16: _ _ _ _ add sub mul div and or xor shl shr shri cmp _
// ---- rd rz rs:		add sub mul div and or xor shl shr shri cmp _

module decode  #(
    parameter DATA_WIDTH = 32
  ) (
    input  clk,
    input  rst,
    input  opready,
    input  [15:0] op,
    input  [DATA_WIDTH - 1:0] pc_f,
    input  [DATA_WIDTH - 1:0] pcnext,
    input      i_ready,  // issue ready
    output     d_ready,  // ready to accept new word

    output reg	      new,	// issue
    output reg [4:0]  rl,
    output reg [4:0]  rr,
    output reg [4:0]  rd,
    output reg [2:0]  type,
    output reg [3:0]  fn,
    output reg [DATA_WIDTH - 1:0] pc,
    output reg [DATA_WIDTH - 1:0] imm
);

localparam EXT_WIDTH = DATA_WIDTH - 16;

// state
reg [2:0] st;

localparam S_ZERO = 0;
localparam S_IMMI = 1;
localparam S_IMMH = 2;
localparam S_IMML = 3;
localparam S_IMMB = 4;
localparam S_SET  = 5;

// decoder ready flag
assign d_ready = !(new & !i_ready);

// register getters
wire [3:0] w_rd = op[11:8];
wire [3:0] w_rl = op[ 7:4];
wire [3:0] w_rr = op[ 3:0];

wire	  w_rdz = w_rd == 4'hF;
wire[4:0] w_rrd = {1'b0, w_rd};
wire[4:0] w_rlz = w_rl == 4'hF ? `R_ZERO : {1'b0, w_rl};
wire[4:0] w_rrz = w_rr == 4'hF ? `R_ZERO : {1'b0, w_rr};

always @ (posedge clk)
begin
  if (rst) begin
    st	    <= S_ZERO;
    new     <= 1'b0;
  end else if (d_ready & !opready) begin
    new <= 1'b0;
  end else if (opready) begin
    case (st)
      S_ZERO: begin
	// defaults
	new  <= 1'b0;
	imm	<= {DATA_WIDTH {1'b0}};
	type	<= `I_BAD;
	rd	<= `R_ZERO;
	rl	<= `R_ZERO;
	rr	<= `R_ZERO;
	fn	<= `ALU_OR;
	pc	<= pc_f;

	// select four high bits
	case (op[15:12])
	  4'h0: begin
	    if (w_rdz) begin
	      if (w_rlz) begin
	      end else begin
		case (op[3:0])
		  4'h9: begin // set
		    type <= `I_ONE;
		    rl	 <= w_rl;
		    st	 <= S_SET;
		  end
		endcase
	      end
	    end else begin
	    end
	  end

	  4'h1: begin // memory
	    if (op[3]) begin
	      fn   <= {2'b0, op[1:0]};
	      type <= `I_ST;
	      rl   <= w_rrd;
	      rr   <= {1'b0, w_rl};
	      st   <= S_IMMI;
	    end else begin
	      fn   <= {1'b0, op[2:0]};
	      type <= `I_LD;
	      rd   <= w_rrd;
	      rl   <= {1'b0, w_rl};
	      st   <= S_IMMI;
	    end
	  end

	  4'h2: begin // branch
	    fn	 <= op[2:0];
	    type <= `I_BRA;
	    rl	 <= w_rdz ? `R_ZERO : w_rrd;
	    rr	 <= w_rlz;
	    st	 <= S_IMMB;
	  end

	  4'h3: begin // rri
	    fn	 <= op[3:0];
	    type <= `I_ONE;
	    rd	  <= w_rrd;
	    rl	  <= w_rlz;
	    st	  <= S_IMMI;
	  end

	  default: begin // rrr
	    fn	 <= op[15:12];
	    type <= `I_ONE;
	    rd	 <= w_rrd;
	    rl	 <= w_rlz;
	    rr	 <= {1'b0, w_rr};
	    new  <= 1'b1;
	  end
	endcase
      end

      S_IMMI: begin
	// sign extend
	imm	<= {{EXT_WIDTH {op[15]}}, op};
	st	<= S_ZERO;
	new	<= 1'b1;
      end

      S_IMMH: begin
	imm <= {op, 16'h0000};
	st  <= S_IMML;
      end

      S_IMML: begin
	imm[15:0] <= op;
	st	  <= S_ZERO;
	new	  <= 1'b1;
      end

      S_IMMB: begin
	// branch offset: sign extend and * 2
	imm	<= pcnext + {{EXT_WIDTH  - 1 {op[15]}}, op[15:0], 1'b0};
	st	<= S_ZERO;
	new	<= 1'b1;
      end

      S_SET: begin
	rd  <= {1'b1, op[3:0]};
	new <= 1'b1;
	st  <= S_ZERO;
      end
    endcase

`ifdef DECODE_TEST
    $display ("DECODE\t%x st=%d pc=%x pcnext=%x op=%x iready=%x", coreZ0.cycle, st, pc_f, pcnext, op, i_ready);
`endif

  end
end

endmodule
