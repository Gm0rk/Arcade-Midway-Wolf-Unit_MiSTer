//============================================================================
//  Wolf Unit security PIC, simulated
//
//  The Wolf Unit has a PIC16C57 that gives the game its ID and a serial
//  number. The 34010 talks to it through one write register (low nibble:
//  command, bit 4: clock) and one read register (the byte last clocked out),
//  and sees a status bit in I/O word 4, bit 12.
//
//  This is MAME's midway_serial_pic_device: the PIC's answers are worked out
//  once and handed out a byte per clock, without running the PIC's own code.
//  MAME uses it for the sets whose PIC was never dumped (MK3, WWF, Open Ice)
//  with the serial number prefix 528, which is development PIC code that
//  every Wolf game accepts besides its own; this core uses it for every game.
//
//  Protocol (MAME write()/read()/status_r()/reset_w()):
//    - a write sets status to the clock bit (data bit 4); on a write with the
//      clock low, a non-zero command nibble is echoed back (the self-test
//      writes 1F, 0F and expects F), command 0 clocks out the next of the 16
//      serial bytes (wrapping)
//    - any read of the data register sets status
//    - I/O control bit 5 written high restarts the sequence
//
//  Serial data (generate_serial_data): serial number 528123456 (prefix 528,
//  MAME's 123450 base and its default low digit 6), date 11 December of the
//  game's year. MAME fills bytes 12 and 13 from its random number generator;
//  they only scramble the encoding, so this core uses 0 for both.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_pic
(
	input             clk,
	input             reset,

	input      [11:0] year,          // the game's year (MAME GAME() line)

	input             pic_reset,     // I/O control written with bit 5 high
	input             wr,            // 34010 write of the low byte (one clock)
	input       [7:0] wdata,
	input             rd,            // 34010 read of the data register (one clock)
	output reg  [7:0] rdata,
	output reg        status
);

//----------------------------------------------------------------------------
// Serial bytes. Bytes 0-9 come from the serial number digits (fixed here),
// 10-11 from the date, 12-15 are 0.
//----------------------------------------------------------------------------

reg  [15:0] date;
always @(posedge clk)
	date <= 16'h0174 * ({4'd0, year} - 16'd1980) + 16'h001F * 16'd11 + 16'd11;

function automatic [7:0] serial_byte(input [3:0] i, input [15:0] d);
	case (i)
		4'd0:  serial_byte = 8'h7E;
		4'd1:  serial_byte = 8'h64;
		4'd2:  serial_byte = 8'h01;
		4'd3:  serial_byte = 8'hA5;
		4'd4:  serial_byte = 8'h41;
		4'd5:  serial_byte = 8'hB9;
		4'd6:  serial_byte = 8'h14;
		4'd7:  serial_byte = 8'hBC;
		4'd8:  serial_byte = 8'h51;
		4'd9:  serial_byte = 8'h1D;
		4'd10: serial_byte = d[15:8];
		4'd11: serial_byte = d[7:0];
		default: serial_byte = 8'h00;
	endcase
endfunction

//----------------------------------------------------------------------------
// Protocol
//----------------------------------------------------------------------------

reg  [3:0] idx;

always @(posedge clk) begin
	if (reset || pic_reset) begin
		idx    <= 4'd0;
		status <= 1'b0;
		rdata  <= 8'h00;
	end
	else if (wr) begin
		status <= wdata[4];
		if (!wdata[4]) begin
			if (wdata[3:0] != 4'h0)
				rdata <= {4'h0, wdata[3:0]};
			else begin
				rdata <= serial_byte(idx, date);
				idx   <= idx + 4'd1;
			end
		end
	end
	else if (rd)
		status <= 1'b1;
end

endmodule
