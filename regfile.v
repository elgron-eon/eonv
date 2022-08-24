`include "global.inc"

module regfile
  #(
     parameter WIDTH = 16
  ) (
    input  clk,
    input  rst,
    input  [4:0] r0,
    input  [4:0] r1,
    input  [4:0] rd,
    input  [WIDTH - 1:0] data,

    output [WIDTH - 1:0] v0,
    output [WIDTH - 1:0] v1
);

// register file
reg [WIDTH - 1:0] rfile [0:31];

// register read is combinatorial
assign v0 = rfile[r0];
assign v1 = rfile[r1];

// register write is sequential
integer i;

always @ (posedge clk)
begin
  if (rst) begin
    rfile[`R_ZERO] <= 0; // zero value
`ifdef TEST
    rfile[19] <= 0;	// cycle count
    for (i = 0; i < 16; i++)
      rfile[i] <= i;
`endif
  end else begin
`ifdef TEST
    rfile[19] <= rfile[19] + 1'b1;
`endif

    if (rd != `R_ZERO) begin
      rfile[rd] <= data;
`ifdef TEST_OFF
      $display ("WRITE\t%x rd=%x result=%x", rfile[19], rd, data);
`endif
     end
  end
end

endmodule
