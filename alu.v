`include "global.inc"

`ifndef SYNTH
//`define ALU_TEST
`endif

module alu  #(
     parameter WIDTH = 32,
     parameter RSBIT = 3
  ) (
    input		clk,
    input		rst,
    input [RSBIT - 1:0] rs_i,
    input [WIDTH - 1:0] vl,
    input [WIDTH - 1:0] vr,
    input [3:0] 	op,

    output reg [RSBIT - 1:0] rs,
    output reg [WIDTH - 1:0] result
);

function [WIDTH - 1:0] alu (input [3:0] op, input [WIDTH - 1:0] vl, input [WIDTH - 1:0] vr);
    case (op)
	`ALU_ADD: alu = vl + vr;
	`ALU_SUB: alu = vl - vr;
	`ALU_AND: alu = vl & vr;
	`ALU_OR : alu = vl | vr;
	`ALU_XOR: alu = vl ^ vr;
	default : alu = 0;
    endcase
endfunction

wire [WIDTH - 1:0] acc = alu (op, vl, vr);

always @ (posedge clk)
begin
  if (rst) begin
    rs <= 0;
  end else begin
    rs <= 0;
    if (|rs_i) begin
      result <= acc;
      rs     <= rs_i;
`ifdef ALU_TEST
      $display ("ALU\t%x @%x op=%x vl=%x vr=%x =%x", coreZ0.cycle, rs_i, op, vl, vr, acc);
`endif
    end
  end
end

endmodule

