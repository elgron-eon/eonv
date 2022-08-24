// default timescale
`timescale 1ns / 1ns

// zero reg
`define R_ZERO	  5'b11111

// exception codes
`define EXC_NONE  3'h0
`define EXC_OP	  3'h1
`define EXC_ALIGN 3'h2
`define EXC_ZERO  3'h3
`define EXC_BPRED 3'h7

// branch alu opcodes
`define BALU_EQ   3'd0
`define BALU_NE   3'd1
`define BALU_LT   3'd2

// alu opcodes
`define ALU_ADD   4'h4
`define ALU_SUB   4'h5
`define ALU_AND   4'h8
`define ALU_OR	  4'h9
`define ALU_XOR   4'ha

// instruction types
`define I_BAD	  3'd0
`define I_ONE	  3'd1
`define I_MUL	  3'd2
`define I_DIV	  3'd3
`define I_LD	  3'd4
`define I_ST	  3'd5
`define I_BRA	  3'd7

// preprocessor
`define PREPRO_1(d)	d
`define PREPRO_DEF(d)	d \

`define PREPRO_DEFIF(d, n) \
  `undef d \
  `ifdef PREPRO_``n \
    `PREPRO_DEF (`define d 1) \
  `endif

