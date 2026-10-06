//============================================================================
//  DCS sound board placeholder
//
//  Stands in for the DCS board (ADSP-2105, MAME shared/dcs.cpp) until it is
//  built: the 34010 sees the same latches and status bits, so the games run,
//  without sound.
//
//  Host interface (MAME dcs_audio_device, REV_DCS1):
//    - data_w: the byte goes to the input latch; "input empty" (control
//      bit 11) drops until the DSP reads it, about 2 us later in MAME
//    - data_r: returns the output latch and sets "output empty" (bit 10)
//    - control_r: the latch control word, bits 10 and 11
//    - reset (I/O control bit 4 high): both latches empty
//
//  What the DSP answers. Traced in MAME for every game, the only exchange
//  the games wait on is the version query: they send 03 E7 and read one
//  byte back once "output empty" drops. The reply and its delay are per
//  game (dcs_version, dcs_delay); every other command is taken off the
//  latch and ignored.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module dcs_stub
(
	input             clk,           // 96 MHz
	input             reset,
	input             dcs_reset,     // sound CPU held in reset

	input       [7:0] dcs_version,   // reply to the version query
	input      [19:0] dcs_delay,     // clocks from the query to the reply

	input             host_wr,       // one clock: write host_data to the input latch
	input       [7:0] host_data,
	input             host_rd,       // one clock: the host read the output latch
	output reg  [7:0] host_q,        // output latch
	output     [15:0] control        // latch control (MAME control_r)
);

localparam [7:0] ACK_CLOCKS = 8'd192;   // 2 us: the DSP takes a byte

reg         in_empty, out_empty;
reg   [7:0] ack_cnt;
reg   [7:0] last;                       // previous command byte
reg         reply_pend;
reg  [19:0] reply_cnt;

assign control = {4'b0000, in_empty, out_empty, 10'd0};

always @(posedge clk) begin
	if (reset || dcs_reset) begin
		in_empty   <= 1'b1;
		out_empty  <= 1'b1;
		ack_cnt    <= 8'd0;
		reply_pend <= 1'b0;
		last       <= 8'h00;
		if (reset) host_q <= 8'h00;
	end
	else begin
		// the DSP takes the input byte a little after it arrives
		if (ack_cnt != 8'd0) begin
			ack_cnt <= ack_cnt - 8'd1;
			if (ack_cnt == 8'd1) in_empty <= 1'b1;
		end

		if (host_wr) begin
			in_empty <= 1'b0;
			ack_cnt  <= ACK_CLOCKS;
			last     <= host_data;
			if (last == 8'h03 && host_data == 8'hE7) begin
				reply_pend <= 1'b1;
				reply_cnt  <= dcs_delay;
			end
		end

		// the version reply
		if (reply_pend) begin
			if (reply_cnt == 20'd0) begin
				reply_pend <= 1'b0;
				host_q     <= dcs_version;
				out_empty  <= 1'b0;
			end
			else
				reply_cnt <= reply_cnt - 20'd1;
		end

		if (host_rd)
			out_empty <= 1'b1;
	end
end

endmodule
