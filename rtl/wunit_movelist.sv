//============================================================================
//  wunit_movelist - the Move List window (MK3, UMK3) and the Secret Codes
//  window (NBA Hangtime, Maximum Hangtime, 2 On 2 Open Ice Challenge)
//
//  With the OSD's "Move List" or "Secret Codes" on, this draws one page over
//  the game: a grid of 56 x 30 characters (7 x 8 dots each, the MiSTer
//  OSD's font), centred in the 400 x 254 picture, over the game's logo,
//  dimmed (MK3, UMK3, Open Ice, NBA Hangtime, NBA Maximum Hangtime), or the
//  game's picture dimmed to a quarter. tools/move_list.py writes the pages (a fighter's
//  moves, a list of secret codes) as four ROM images. A row is a list of
//  segments, runs of text in one colour at a column:
//
//    row   4096 x 12: {page, row} -> the row's first segment (0: empty)
//    seg   4096 x 29: [13:0] the segment's first character in the text ROM,
//          [19:14] its length, [25:20] its column, [27:26] its colour
//          (0 white, 1 yellow, 2 cyan, 3 gray), [28] the row's last one
//    text  16384 x 7: the character codes - 32
//    font  768 x 8: {code - 32, glyph row} -> the row's dots, bit x column x
//
//  tools/movelist_logo.py writes the logos: 200 x 127 dots of 16 colours
//  each (a dot covers 2 x 2 of the picture), logo 1 to 5 in turn:
//
//    logo  127000 x 4: the colour of each dot, row by row
//    pal   80 x 24: the colours (RGB, already dimmed), 16 a logo
//
//  The board's video changes with each ce_pix; the counters here follow it
//  so that they always name the dot on the outputs now. While a character
//  cell is on screen the next one is fetched (its segment, character and
//  glyph row: about 10 clocks of the 84 a cell has), and taken over when
//  the cell ends; in the horizontal blanking the row's first segment and
//  the line's first cell are. The logo's dot is read for the dot on the
//  outputs (two clocks of the 12 a dot has).
//  The picture goes through unchanged (same clock, no delay) when the
//  window is off, and the timing signals always do.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_movelist #(
	parameter ROW_HEX  = "rtl/wunit_movelist_row.hex",
	parameter SEG_HEX  = "rtl/wunit_movelist_seg.hex",
	parameter TEXT_HEX = "rtl/wunit_movelist_text.hex",
	parameter FONT_HEX = "rtl/wunit_movelist_font.hex",
	parameter LOGO_HEX = "rtl/wunit_movelist_logo.hex",
	parameter PAL_HEX  = "rtl/wunit_movelist_pal.hex",
	parameter X0       = 4,          // the grid's first dot in the line
	parameter Y0       = 7           // the grid's first line in the picture
)
(
	input            clk,
	input            ce_pix,
	input            enable,         // the window is shown
	input      [6:0] page,           // the page (a fighter's moves, a list of codes)
	input      [2:0] logo,           // behind it: 0 the dimmed game, else a logo: 1 MK3,
	                                 // 2 UMK3, 3 Open Ice, 4 NBA Hangtime, 5 Maximum Hangtime

	input      [7:0] r_in,
	input      [7:0] g_in,
	input      [7:0] b_in,
	input            hb_in,
	input            vb_in,

	output     [7:0] r_out,
	output     [7:0] g_out,
	output     [7:0] b_out
);

localparam COLS = 56, ROWS = 30, CW = 7, CH = 8;
// a line starts in cell CX0 (before the grid; X0 >= 1), at its dot PX0
localparam integer PX0 = (CW - X0 % CW) % CW;
localparam integer CX0 = -((X0 + CW - 1) / CW);
localparam LW = 200, LH = 127;          // a logo's dots

//----------------------------------------------------------------------------
// ROMs
//----------------------------------------------------------------------------

reg [11:0] row_rom  [0:4095];
reg [28:0] seg_rom  [0:4095];
reg  [6:0] text_rom [0:16383];
reg  [7:0] font_rom [0:767];
reg  [3:0] logo_rom [0:5 * LW * LH - 1];
reg [23:0] pal_rom  [0:79];

initial begin
	$readmemh(ROW_HEX, row_rom);
	$readmemh(SEG_HEX, seg_rom);
	$readmemh(TEXT_HEX, text_rom);
	$readmemh(FONT_HEX, font_rom);
	$readmemh(LOGO_HEX, logo_rom);
	$readmemh(PAL_HEX, pal_rom);
end

reg [11:0] row_a, seg_a;
reg [13:0] text_a;
reg  [9:0] font_a;
reg [11:0] row_q;
reg [28:0] seg_q;
reg  [6:0] text_q;
reg  [7:0] font_q;

always @(posedge clk) begin
	row_q  <= row_rom[row_a];
	seg_q  <= seg_rom[seg_a];
	text_q <= text_rom[text_a];
	font_q <= font_rom[font_a];
end

//----------------------------------------------------------------------------
// The dot on the outputs. At each ce_pix the inputs still show the dot that
// ends: a blanked one starts the line again, the first blanked one after
// the picture ends a line.
//----------------------------------------------------------------------------

reg        hb_q;
reg  [8:0] y;                    // the line of the picture
reg  [2:0] px;                   // the dot in the cell
reg  [6:0] cx;                   // the cell (negative before the grid)
reg        line_end;             // one clock: a line ended (fetch the first cell)
reg        cell_start;           // one clock: a cell started (fetch the next)
reg  [8:0] x;                    // the dot in the line
reg [14:0] lrow;                 // the logo's row: its first dot (y / 2 * LW)

always @(posedge clk) begin
	line_end   <= 1'b0;
	cell_start <= 1'b0;
	if (ce_pix) begin
		hb_q <= hb_in;
		if (vb_in) begin
			y    <= 9'd0;
			lrow <= 15'd0;
		end
		else if (hb_in & ~hb_q) begin
			y <= y + 9'd1;
			if (y[0])
				lrow <= lrow + 15'(LW);
		end
		x <= hb_in ? 9'd0 : x + 9'd1;
		if (hb_in) begin
			px <= 3'(PX0);
			cx <= 7'(CX0);
			if (~hb_q)
				line_end <= 1'b1;
		end
		else if (px == 3'(CW - 1)) begin
			px <= 3'd0;
			cx <= cx + 7'd1;
			cell_start <= 1'b1;
		end
		else
			px <= px + 3'd1;
	end
end

wire [8:0] gy  = y - 9'(Y0);
wire [4:0] row = gy[7:3];
wire [2:0] ly  = gy[2:0];
wire       row_ok = (y >= 9'(Y0)) && (gy < 9'(ROWS * CH));

//----------------------------------------------------------------------------
// Fetch the next cell. At a line's end its row's first segment is read; for
// each cell the segments that end before it are passed over, then its
// character and glyph row are read.
//----------------------------------------------------------------------------

localparam F_IDLE = 4'd0, F_ROW = 4'd1, F_ROWQ = 4'd2, F_SEG = 4'd3, F_SEGQ = 4'd4,
           F_CELL = 4'd5, F_TEXT = 4'd6, F_TEXTQ = 4'd7, F_FONT = 4'd8, F_FONTQ = 4'd9;

reg  [3:0] fs;
reg  [6:0] f_col;                // the cell fetched (negative: before the grid)
reg        f_on;
reg  [1:0] f_colour;
reg        empty;                // the row has no segments
reg [13:0] s_text;               // the segment
reg  [5:0] s_len, s_col;
reg  [1:0] s_colour;
reg        s_last;
reg  [7:0] nx_dots, cur_dots;
reg  [1:0] nx_colour, cur_colour;

wire [6:0] s_end = {1'b0, s_col} + {1'b0, s_len};
wire [6:0] s_rel = f_col - {1'b0, s_col};
wire       f_neg = f_col[6];

always @(posedge clk) begin
	case (fs)
		F_IDLE:
			if (line_end) begin
				f_col <= cx + 7'd1;
				row_a <= {page, row};
				fs    <= F_ROW;
			end
			else if (cell_start) begin
				f_col <= cx + 7'd1;
				fs    <= F_CELL;
			end
		F_ROW:  fs <= F_ROWQ;
		F_ROWQ: begin
			empty <= row_q == 12'd0;
			seg_a <= row_q;
			fs    <= F_SEG;
		end
		F_SEG:  fs <= F_SEGQ;
		F_SEGQ: begin
			{s_last, s_colour, s_col, s_len, s_text} <= seg_q;
			fs <= F_CELL;
		end
		F_CELL:
			if (!empty && !s_last && !f_neg && f_col >= s_end) begin
				seg_a <= seg_a + 12'd1;          // past this segment: the next
				fs    <= F_SEG;
			end
			else begin
				f_on     <= row_ok && !empty && !f_neg && f_col < 7'(COLS) &&
				            f_col >= {1'b0, s_col} && f_col < s_end;
				f_colour <= s_colour;
				text_a   <= s_text + {7'd0, s_rel};
				fs       <= F_TEXT;
			end
		F_TEXT:  fs <= F_TEXTQ;
		F_TEXTQ: begin
			font_a <= {text_q, ly};
			fs     <= F_FONT;
		end
		F_FONT:  fs <= F_FONTQ;
		F_FONTQ: begin
			nx_dots   <= f_on ? font_q : 8'd0;
			nx_colour <= f_colour;
			fs        <= F_IDLE;
		end
		default: fs <= F_IDLE;
	endcase

	// the fetched cell comes on screen
	if (ce_pix && !hb_in && px == 3'(CW - 1)) begin
		cur_dots   <= nx_dots;
		cur_colour <= nx_colour;
	end
end

//----------------------------------------------------------------------------
// The logo's dot: its colour number, then its colour
//----------------------------------------------------------------------------

reg  [16:0] logo_base;            // the logo's first dot
always @(*) begin
	case (logo)
		3'd2:    logo_base = 17'(1 * LW * LH);
		3'd3:    logo_base = 17'(2 * LW * LH);
		3'd4:    logo_base = 17'(3 * LW * LH);
		3'd5:    logo_base = 17'(4 * LW * LH);
		default: logo_base = 17'd0;
	endcase
end

wire [16:0] logo_a = logo_base + {2'b00, lrow} + {9'd0, x[8:1]};
wire  [2:0] logo_n = logo - 3'd1;
reg   [3:0] logo_q;
reg  [23:0] pal_q;

always @(posedge clk) begin
	logo_q <= logo_rom[logo_a];
	pal_q  <= pal_rom[{logo_n, logo_q}];
end

//----------------------------------------------------------------------------
// Out: the text over the logo or the dimmed picture
//----------------------------------------------------------------------------

wire pic = ~hb_in & ~vb_in;
wire dot = cur_dots[px] & pic;
wire bg_logo = (logo != 3'd0) & pic;

reg [23:0] ink;
always @(*) begin
	case (cur_colour)
		2'd0: ink = 24'hFFFFFF;    // white
		2'd1: ink = 24'hFFE040;    // yellow
		2'd2: ink = 24'h60E0FF;    // cyan
		default: ink = 24'hA0A0A0; // gray
	endcase
end

assign r_out = !enable ? r_in : dot ? ink[23:16] : bg_logo ? pal_q[23:16] : {2'b00, r_in[7:2]};
assign g_out = !enable ? g_in : dot ? ink[15:8]  : bg_logo ? pal_q[15:8]  : {2'b00, g_in[7:2]};
assign b_out = !enable ? b_in : dot ? ink[7:0]   : bg_logo ? pal_q[7:0]   : {2'b00, b_in[7:2]};

endmodule
