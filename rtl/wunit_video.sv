//============================================================================
//  Wolf Unit video output
//
//  Turns the frame store into pixels the way MAME's scanline_update does
//  (midtunit_v.cpp):
//    - at the start of every displayed line the row the 34010 points at
//      (DPYADR) is fetched from VRAM into a line buffer
//    - pixels from HEBLNK to HSBLNK read consecutive entries of that row,
//      starting at the column address and wrapping at 512
//    - each 16-bit entry, masked to 15 bits, is the pen: an index into the
//      32768-colour xRGB555 palette
//
//  The Wolf Unit clocks the 34010's video counters once per pixel (VCLK =
//  pixel clock = 8 MHz), so HCOUNT, HEBLNK and HSBLNK are pixel positions.
//  There is no autoerase on the T or Wolf Units.
//
//  Palette RAM. The 32 K x 16 palette lives here: the CPU writes it through
//  pal_we and reads it back through pal_rreq/pal_rack, and the display reads
//  it once per pixel. One simple dual-port RAM serves both readers, which
//  saves the second 64-block copy the Y Unit kept for the CPU: the display
//  owns the read port in one clock of each 12-clock pixel, a CPU read takes
//  any other clock.
//
//  All video signals are delayed by one pixel so the line buffer and palette
//  RAM reads complete between pixel clocks.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_video
(
	input             clk,
	input             reset,

	input             ce_pix,        // 8 MHz pixel enable (also VCLK)

	// timing and display address from the 34010
	input       [9:0] hcount,
	input       [9:0] heblnk,
	input       [9:0] hsblnk,
	input             hsync_in,
	input             vsync_in,
	input             hblank_in,
	input             vblank_in,
	input             disp_en,
	input             line_start,
	input             line_vis,
	input      [11:0] line_row,
	input      [13:0] line_col,

	// palette RAM, CPU side
	input             pal_we,        // write pal_wdata at pal_addr (one clock)
	input      [14:0] pal_addr,
	input      [15:0] pal_wdata,
	input             pal_rreq,      // toggle: read pal_addr
	output reg        pal_rack,
	output reg [15:0] pal_rdata,

	// VRAM requests (see wunit_vram)
	output reg        disp_req,
	input             disp_ack,
	output reg  [8:0] disp_row,
	input             lb_we,
	input       [6:0] lb_addr,
	input      [63:0] lb_data,

	// video out
	output reg  [7:0] r,
	output reg  [7:0] g,
	output reg  [7:0] b,
	output reg        hsync,
	output reg        vsync,
	output reg        hblank,
	output reg        vblank
);

//----------------------------------------------------------------------------
// Line buffer: two banks of one 512-entry row (128 beats of 4 entries)
//----------------------------------------------------------------------------

reg  [63:0] linebuf [0:255];
reg         fill_bank;           // bank the current fetch writes
reg         show_bank;           // bank being displayed
reg   [7:0] lb_raddr;
reg  [63:0] lb_q;

always @(posedge clk) begin
	if (lb_we) linebuf[{fill_bank, lb_addr}] <= lb_data;
	lb_q <= linebuf[lb_raddr];
end

//----------------------------------------------------------------------------
// Row fetch: each displayed line asks VRAM for its row; the line is shown
// from its own HEBLNK on, out of the bank just filled
//----------------------------------------------------------------------------

reg   [8:0] col_start;           // first entry of the line
reg         line_on;             // this line shows pixels

always @(posedge clk) begin
	if (reset) begin
		disp_req  <= disp_ack;
		fill_bank <= 1'b0;
		show_bank <= 1'b0;
		line_on   <= 1'b0;
	end
	else if (line_start) begin
		line_on <= line_vis & disp_en;
		if (line_vis & disp_en) begin
			disp_row  <= line_row[8:0];
			disp_req  <= ~disp_req;
			fill_bank <= ~fill_bank;
			show_bank <= ~fill_bank;
			col_start <= {line_col[7:0], 1'b0};
		end
	end
end

//----------------------------------------------------------------------------
// Pixel pipeline
//
// The cycle after each ce_pix the beam position is captured (HCOUNT has
// moved on by then) and the line buffer is addressed (stage 0). The entry is
// there in stage 1 and its pen goes to the palette's read address; the
// palette reads it in stage 2 and the colour is taken in stage 3, well
// before the next ce_pix, which outputs it together with the timing signals
// captured with it.
//----------------------------------------------------------------------------

reg         ce_pix_d;
reg   [3:0] stage;
reg   [1:0] lane;
reg         a_hs, a_vs, a_hb, a_vb, a_on;
reg  [14:0] a_rgb;
reg  [14:0] pen;

// pixel within the active area. HCOUNT has already moved on with the ce_pix
// that started this pipeline; the blanking captured with it was worked out
// from the same count, so the first unblanked pixel (HCOUNT = HEBLNK) shows
// the first entry, as MAME's x = heblnk does.
wire  [9:0] act_x = hcount - heblnk;
wire  [8:0] entry = col_start + act_x[8:0];
wire [15:0] ent   = lb_q[{lane, 4'b0000} +: 16];

// palette RAM: one write port (CPU), one read port (display in stage 2, CPU
// otherwise)
reg  [15:0] palram [0:32767];
reg  [14:0] pal_ra;
reg  [15:0] pal_q;
reg         cpu_rd;              // the read port served the CPU this clock
reg         cpu_pend;            // a CPU read is waiting for the port

always @(posedge clk) begin
	if (pal_we) palram[pal_addr] <= pal_wdata;
	pal_q <= palram[pal_ra];
end

always @(*) begin
	pal_ra = pen;
	if (!stage[2] && cpu_pend)
		pal_ra = pal_addr;
end

function automatic [7:0] pal5(input [4:0] c);
	pal5 = {c, c[4:2]};
endfunction

always @(posedge clk) begin
	ce_pix_d <= ce_pix;
	stage    <= {stage[2:0], 1'b0};
	cpu_rd   <= 1'b0;

	if (ce_pix_d) begin
		a_hs     <= hsync_in;
		a_vs     <= vsync_in;
		a_hb     <= hblank_in;
		a_vb     <= vblank_in;
		a_on     <= line_on & ~hblank_in & ~vblank_in;
		lb_raddr <= {show_bank, entry[8:2]};
		lane     <= entry[1:0];
		stage[0] <= 1'b1;
	end
	if (stage[1])                       // line buffer data valid
		pen <= ent[14:0];
	if (stage[3])                       // palette data valid
		a_rgb <= a_on ? pal_q[14:0] : 15'd0;

	// CPU palette reads use the port outside stage 2 (in reset the board
	// sets its request to pal_rack: one end of the handshake only)
	if (reset)
		cpu_pend <= 1'b0;
	else begin
		if (pal_rreq != pal_rack && !cpu_pend && !cpu_rd)
			cpu_pend <= 1'b1;
		if (cpu_pend && !stage[2]) begin
			cpu_pend <= 1'b0;
			cpu_rd   <= 1'b1;
		end
		if (cpu_rd) begin
			pal_rdata <= pal_q;
			pal_rack  <= pal_rreq;
		end
	end

	if (ce_pix) begin
		r      <= pal5(a_rgb[14:10]);
		g      <= pal5(a_rgb[9:5]);
		b      <= pal5(a_rgb[4:0]);
		hsync  <= a_hs;
		vsync  <= a_vs;
		hblank <= a_hb;
		vblank <= a_vb;
	end
end

endmodule
