`include "global.inc"

//`define I2C_TEST
`define I2C_DEBUG

module i2c_master #(
    parameter DIVIDER = 16
  ) (
`ifdef I2C_DEBUG
    output reg [15:0] dbg_data,
`endif
    input			    i_clk,
    input			    i_rst,
    input			    i_enable,
    input	[6:0]		    i_device_addr,
    input			    i_rw,
    input	[7:0]		    i_nbytes,
    input	[7:0]		    i_mosi_data,
    output reg			    o_need_data,
    output reg			    o_data_ready,
    output reg	[7:0]		    o_miso_data,
    output reg			    o_busy,
    inout			    io_sda,
    output reg			    io_scl
);

localparam S_IDLE	= 4'h0;
localparam S_START	= 4'h1;
localparam S_WRITE_ADDR = 4'h2;
localparam S_CHECK_ACK	= 4'h3;
localparam S_READ_REG	= 4'h4;
localparam S_SEND_NACK	= 4'h5;
localparam S_SEND_STOP	= 4'h6;
localparam S_WRITE_DATA = 4'h7;
localparam S_SEND_ACK	= 4'h8;

reg [7:0] saved_device_addr;
reg [7:0] saved_nbytes, saved_byte;
reg [3:0] state;
reg [3:0] post_state;
reg [1:0] proc_counter;
reg [3:0] bit_counter;

wire more_nbytes = |saved_nbytes;

reg sda_out;
reg post_sda_out;
reg ack_recieved;
reg enable;
reg rw;

// tri state buffer for sda
wire sda_oe;
assign sda_oe = (state != S_IDLE && state != S_CHECK_ACK && state != S_READ_REG);
assign io_sda = sda_oe ? sda_out : 1'bz;

// i2c divider tick generator
reg    [$clog2 (DIVIDER):0] divider_counter;
wire   divider_tick;
assign divider_tick = (divider_counter == DIVIDER) ? 1 : 0;

always @(posedge i_clk) begin
  if (i_rst) begin
    divider_counter <= 0;
  end else begin
    if (divider_counter == DIVIDER) begin
      divider_counter <= 0;
    end else begin
      divider_counter <= divider_counter + 1;
    end
  end
end

always @(posedge i_clk) begin
  if (i_rst) begin
`ifdef I2C_DEBUG
    dbg_data	      <= 0;
`endif
    sda_out	      <= 1;
    io_scl	      <= 1;
    proc_counter      <= 0;
    bit_counter       <= 0;
    ack_recieved      <= 0;
    o_miso_data       <= 0;
    o_need_data       <= 0;
    o_data_ready      <= 0;
    saved_device_addr <= 0;
    enable	      <= 0;
    o_busy	      <= 0;
    rw		      <= 0;
    post_state	      <= S_IDLE;
    state	      <= S_IDLE;
  end else begin
`ifdef I2C_DEBUG
    dbg_data <= 0;
`endif
    o_data_ready <= 1'b0;

    if (divider_tick) begin
      case (state)

	S_IDLE: begin
	  proc_counter	    <= 0;
	  sda_out	    <= 1;
	  io_scl	    <= 1;
	  enable	    <= i_enable;
	  saved_device_addr <= {i_device_addr, i_rw};
	  saved_nbytes	    <= i_nbytes;
	  o_busy	    <= 0;
	  o_need_data	    <= 0;
	  ack_recieved	    <= 0;
	  rw		    <= i_rw;
	  if (enable) begin
	    state      <= S_START;
	    post_state <= S_WRITE_ADDR;
`ifdef I2C_TEST
	    $display ("i2cbus\t\tslave %x rw %d nbytes %d", i_device_addr, i_rw, i_nbytes);
`endif
	  end
	end

	S_START: begin
	  case (proc_counter)
	    0: begin
	      proc_counter <= 1;
	      o_busy	   <= 1;
	      enable	   <= 0;
	    end
	    1: begin
	      sda_out <= 0;
	      proc_counter <= 2;
	    end
	    2: begin
	      proc_counter <= 3;
	      bit_counter  <= 8;
	    end
	    3: begin
	      io_scl	   <= 0;
	      proc_counter <= 0;
	      state	   <= post_state;
	      o_need_data  <= ~rw;
	      sda_out	   <= saved_device_addr[7];
`ifdef I2C_TEST
	      $display ("i2cbus start %t = %d", $time, saved_device_addr[7]);
`endif
	    end
	  endcase
	end

	S_WRITE_ADDR: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;
	      proc_counter <= 1;
	    end
	    1: begin
	      if (io_scl == 1) begin
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      io_scl	   <= 0;
	      bit_counter  <= bit_counter - 1;
	      proc_counter <= 3;
	    end
	    3: begin
	      if (bit_counter == 0) begin
		bit_counter  <= 8;
		saved_nbytes <= saved_nbytes - 1;
		state	     <= S_CHECK_ACK;
`ifdef I2C_DEBUG_OFF
		dbg_data     <= {"@", saved_device_addr};
`endif
		if (rw) begin
		  post_state   <= S_READ_REG;
		  post_sda_out <= 1;
		end else begin
		  post_sda_out <= i_mosi_data[7];
		  post_state   <= S_WRITE_DATA;
		  saved_byte   <= i_mosi_data;
		  o_need_data  <= 1'b0;
		end
`ifdef IC2_TEST
		$display ("i2cbus dataW %t data = %x need_data = %d", $time, i_mosi_data, o_need_data);
`endif
	      end else begin
		sda_out <= saved_device_addr[bit_counter - 1];
		//$display ("i2cbus addrW %t bit %d = %d", $time, bit_counter, saved_device_addr[bit_counter - 1]);
	      end
	      proc_counter <= 0;
	    end
	  endcase
	end

	S_CHECK_ACK: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;
	      proc_counter <= 1;
	    end
	    1: begin
	      if (io_scl == 1) begin
		ack_recieved <= 0;
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      io_scl <= 0;
	      if (io_sda == 0) begin
		ack_recieved <= 1;
	      end
	      proc_counter <= 3;
	    end
	    3: begin
`ifdef I2C_TEST
	      $display ("i2cbus chack %t ack %x post_sda=%x", $time, ack_recieved, post_sda_out);
`endif
`ifdef I2C_DEBUG
	      //dbg_data  <= {"?", 7'b0, ack_recieved};
`endif
	      if (ack_recieved) begin
		state	     <= post_state;
		ack_recieved <= 0;
		sda_out      <= post_sda_out;
	      end else begin
		state <= S_IDLE;
	      end
	      proc_counter <= 0;
	    end
	  endcase
	end

	S_WRITE_DATA: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;
	      proc_counter <= 1;
	    end
	    1: begin
	      if (io_scl == 1) begin
		ack_recieved <= 0;
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      io_scl	   <= 0;
	      bit_counter  <= bit_counter -1;
	      proc_counter <= 3;
	    end
	    3: begin
	      if (bit_counter == 0) begin
		saved_nbytes <= saved_nbytes - 1;
`ifdef I2C_DEBUG
		dbg_data     <= {|saved_nbytes ? "\n" : ">", saved_byte};
`endif
		if (more_nbytes) begin
		  post_sda_out <= i_mosi_data[7];
		  post_state   <= S_WRITE_DATA;
		  state        <= S_CHECK_ACK;
		  bit_counter  <= 8;
		  saved_byte   <= i_mosi_data;
		  o_need_data  <= 1'b0;
`ifdef I2C_TEST
		  $display ("i2cbus again %t data=%x need_data=%x nbytes=%x bit7=%x", $time, i_mosi_data, o_need_data, saved_nbytes, i_mosi_data[7]);
`endif
		end else begin
		  state        <= S_CHECK_ACK;
		  post_state   <= S_SEND_STOP;
		  post_sda_out <= 0;
		  bit_counter  <= 8;
		  sda_out      <= 0;
		end
	      end else begin
		if (more_nbytes)
		  o_need_data <= 1'b1;
		sda_out <= saved_byte[bit_counter - 1];
`ifdef I2C_TEST
		$display ("i2cbus write %t bit %x=%x", $time, bit_counter - 1, saved_byte[bit_counter - 1]);
`endif
	      end
	      proc_counter <= 0;
	    end
	  endcase
	end

	S_READ_REG: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;
	      proc_counter <= 1;
	    end
	    1: begin
	      if (io_scl == 1) begin
		ack_recieved <= 0;
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      io_scl <= 0;
	      //sample data on this rising edge of scl
	      o_miso_data[bit_counter - 1] <= io_sda;
	      bit_counter  <= bit_counter - 1;
	      proc_counter <= 3;
	      //$display ("i2cbus readb %t bit %d = %d (%d)", $time, bit_counter - 1, io_sda, saved_nbytes);
	      end
	    3: begin
	      if (bit_counter == 0) begin
		o_data_ready <= 1'b1;
		state	     <= more_nbytes ? S_SEND_ACK : S_SEND_NACK;
		sda_out      <= more_nbytes ? 1'b0 : 1'b1;
		bit_counter  <= 8;
`ifdef I2C_DEBUG
		if (!more_nbytes) dbg_data <= {"<", o_miso_data};
`endif
`ifdef I2C_TEST
		$display ("i2cbus rbyte %t = %x (%d)", $time, o_miso_data, saved_nbytes);
`endif
	      end
	      proc_counter <= 0;
	    end
	  endcase
	end

	S_SEND_NACK: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;  // 1 == NACK
	      sda_out	   <= 1;
	      proc_counter <= 1;
	    end
	    1: begin
	      if (io_scl == 1) begin
		ack_recieved <= 0;
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      proc_counter <= 3;
	      io_scl	   <= 0;
	    end
	    3: begin
	      state	   <= S_SEND_STOP;
	      proc_counter <= 0;
	      sda_out	   <= 0;
`ifdef I2C_TEST
	      $display ("i2cbus nack! %t", $time);
`endif
	    end
	  endcase
	end

	S_SEND_ACK: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;
	      proc_counter <= 1;
	      sda_out	   <= 0; // 0 = ack
	    end
	    1: begin
	      if (io_scl == 1) begin
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      proc_counter <= 3;
	      io_scl	   <= 0;
	    end
	    3: begin
	      state	   <= S_READ_REG;
	      proc_counter <= 0;
	      saved_nbytes <= saved_nbytes - 1'b1;
`ifdef I2C_DEBUG
	      //dbg_data     <= {"+", saved_nbytes - 1'b1};
`endif
	      //$display ("i2cbus !ack! %t = %x", $time, o_miso_data);
	    end
	  endcase
	end

	S_SEND_STOP: begin
	  case (proc_counter)
	    0: begin
	      io_scl	   <= 1;
	      proc_counter <= 1;
	    end
	    1: begin
	      if (io_scl == 1) begin
		proc_counter <= 2;
	      end
	    end
	    2: begin
	      proc_counter <= 3;
	      sda_out	   <= 1;
	    end
	    3: begin
`ifdef I2C_TEST
	      $display ("i2cbus stop! %t", $time);
`endif
`ifdef I2C_DEBUG_OFF
	      dbg_data	   <= {".", 8'hff};
`endif
	      state	   <= S_IDLE;
	      proc_counter <= 0;
	    end
	  endcase
	end

      endcase
    end
  end
end

endmodule
