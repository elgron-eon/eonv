`include "global.inc"

//`define SPI_TEST
//`define SPI_DEBUG

module spi_bus #(
    parameter SPI_MODE		= 0,
    parameter CLKS_PER_HALF_BIT = 8,
    parameter CS_INACTIVE_CLKS	= 1
  ) (
   // Control/Data Signals,
   input	i_Rst_L,     // FPGA Reset
   input	i_Clk,	     // FPGA Clock

   // TX (MOSI) Signals
   input [6:0]	i_TX_Count,	 // # bytes per CS low
   input [7:0]	i_TX_Byte,	 // Byte to transmit on MOSI
   input	i_TX_DV,	 // Data Valid Pulse with i_TX_Byte
   output	o_TX_Ready,	 // Transmit Ready for next byte

   // RX (MISO) Signals
   output reg  [6:0] o_RX_Count,  // Index RX byte
   output wire	     o_RX_DV,	  // Data Valid pulse (1 clock cycle)
   output wire [7:0] o_RX_Byte,   // Byte received on MISO

   // SPI Interface
   output o_SPI_Clk,
   input  i_SPI_MISO,
   output o_SPI_MOSI,
   output o_SPI_CS_n
);

localparam IDLE        = 2'b00;
localparam TRANSFER    = 2'b01;
localparam CS_INACTIVE = 2'b10;

reg [1:0] r_SM_CS;
reg r_CS_n;
reg [$clog2(CS_INACTIVE_CLKS)	- 1:0] r_CS_Inactive_Count;
reg [6:0] r_TX_Count;
wire w_Master_Ready;

assign o_SPI_CS_n = r_CS_n;
assign o_TX_Ready = ((r_SM_CS == IDLE) | (r_SM_CS == TRANSFER && w_Master_Ready == 1'b1 && r_TX_Count > 0)) & ~i_TX_DV;

// Instantiate Master
spi_master #(
    .SPI_MODE (SPI_MODE),
    .CLKS_PER_HALF_BIT (CLKS_PER_HALF_BIT)
  ) spi_master (
    // Control/Data Signals,
    .i_Rst_L (i_Rst_L), 	   // FPGA Reset
    .i_Clk (i_Clk),		   // FPGA Clock

    // TX (MOSI) Signals
    .i_TX_Byte (i_TX_Byte),	   // Byte to transmit
    .i_TX_DV (i_TX_DV), 	   // Data Valid Pulse
    .o_TX_Ready (w_Master_Ready),  // Transmit Ready for Byte

    // RX (MISO) Signals
    .o_RX_DV   (o_RX_DV),	   // Data Valid pulse (1 clock cycle)
    .o_RX_Byte (o_RX_Byte),	   // Byte received on MISO

    // SPI Interface
    .o_SPI_Clk (o_SPI_Clk),
    .i_SPI_MISO (i_SPI_MISO),
    .o_SPI_MOSI (o_SPI_MOSI)
);

// Purpose: Keep track of RX_Count
always @(posedge i_Clk) begin
  if (r_CS_n) begin
    o_RX_Count <= 0;
  end else if (o_RX_DV) begin
    o_RX_Count <= o_RX_Count + 1'b1;
  end
end

// Purpose: Control CS line using State Machine
always @(posedge i_Clk) begin // or negedge i_Rst_L) begin
  if (~i_Rst_L) begin
    r_SM_CS		<= IDLE;
    r_CS_n		<= 1'b1;   // Resets to high
    r_TX_Count		<= 0;
    r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
  end else begin
    case (r_SM_CS)
      IDLE: begin
	if (r_CS_n & i_TX_DV) begin	// Start of transmission
	  r_TX_Count <= i_TX_Count - 1; // Register TX Count
	  r_CS_n     <= 1'b0;		// Drive CS low
	  r_SM_CS    <= TRANSFER;	// Transfer bytes
`ifdef SPI_TEST
	  $display ("spibus begin %t count %x", $time, i_TX_Count);
`endif
	end
      end

      TRANSFER: begin
	// wait until SPI is done transferring to do next thing
	if (w_Master_Ready) begin
	  if (|r_TX_Count) begin
	    if (i_TX_DV) begin
	      r_TX_Count <= r_TX_Count - 1;
`ifdef SPI_TEST
	      $display ("spibus loop  %t count %x", $time, r_TX_Count);
`endif
	    end
	  end else begin
	    r_CS_n		<= 1'b1; // we done, so set CS high
	    r_CS_Inactive_Count <= CS_INACTIVE_CLKS;
	    r_SM_CS		<= CS_INACTIVE;
`ifdef SPI_TEST
	  $display ("spibus done  %t", $time);
`endif
	  end
	end
      end

      CS_INACTIVE: begin
	if (r_CS_Inactive_Count > 0) begin
	  r_CS_Inactive_Count <= r_CS_Inactive_Count - 1'b1;
	end else begin
	  r_SM_CS <= IDLE;
	end
      end

      default: begin
	r_CS_n	<= 1'b1; // we done, so set CS high
	r_SM_CS <= IDLE;
      end
    endcase
  end
end

endmodule
