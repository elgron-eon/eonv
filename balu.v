`include "global.inc"

`ifndef SYNTH
//`define BALU_TEST
`endif

module balu #(
     parameter WIDTH = 32,
     parameter RSBIT = 3
  ) (
    input		clk,
    input		rst,
    input [RSBIT - 1:0] rs_i,
    input [WIDTH - 1:0] vl,
    input [WIDTH - 1:0] vr,
    input [2:0] 	op,

    output reg [RSBIT - 1:0] rs,
    output reg		     taken
);

function [0:0] balu (input [2:0] op, input [WIDTH - 1:0] vl, input [WIDTH - 1:0] vr);
  case (op)
    `BALU_EQ: balu = vl === vr;
    `BALU_NE: balu = ~(vl === vr);
    `BALU_LT: balu = vl < vr;
    default : balu = 1'b0;
  endcase
endfunction

wire acc = balu (op, vl, vr);

always @ (posedge clk)
begin
  if (rst) begin
    rs <= 0;
  end else begin
    rs <= 0;
    if (|rs_i) begin
      taken <= acc;
      rs    <= rs_i;
`ifdef BALU_TEST
      $display ("BALU\t%x @%x op=%x vl=%x vr=%x =%x", coreZ0.cycle, rs_i, op, vl, vr, acc);
`endif
    end
  end
end

endmodule
