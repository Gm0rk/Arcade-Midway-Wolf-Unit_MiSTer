//============================================================================
//  T-Unit / Wolf Unit DMA blitter
//
//  Copies an image from the graphics ROM into the 512x512 frame store. Each
//  written entry is {palette byte, pixel byte}. Behaviour follows MAME's
//  midtunit_v.cpp (dma_w, dma_draw, dma_done), including:
//    - register 1 (command) bit 15 starts a blit and reads back set until the
//      blit's time is up; any write to it drops the completion interrupt
//    - reading register 0 returns register 1 (Rampage and Open Ice poll it)
//    - registers 12/13 are the left/right clip in bank 0 and the top/bottom
//      clip in bank 1 (register 15 bit 5 picks the bank)
//    - 1 to 8 bits per pixel (command bits 12-14, 0 = 8)
//    - skip compression (command bit 7): every row starts with a byte whose
//      nibbles give the pixels left out before and after it, each scaled by
//      1 << (command bits 8-9 / 10-11)
//    - start / end skip (register 0): command bit 6 set takes them from the
//      low / high byte, clear takes no start skip and the whole word as the
//      end skip (MK vs NBA Jam / Hangtime / Open Ice)
//    - X and Y scaling with 8.8 steps (registers 10/11, 0 = 1.0)
//    - X flip (command bit 4) and Y flip (bit 5); positions wrap at 1024 / 512
//    - clipping on all four edges
//    - zero / non-zero pixels each skipped, copied or drawn in the colour
//      register (command bits 0-3)
//    - completion 41 ns per pixel of the unclipped (scaled) image, counted
//      from the command write as MAME's timer is (the setup clocks before
//      the timer can be loaded, and any wait for the previous blit to finish
//      drawing, come off it)
//
//  One engine runs every mode. MAME has separate scaled and unscaled
//  routines, but with steps of 1.0 the scaled formulas give exactly the
//  unscaled ones (row and pixel advance, pre-skip, start skip), so the
//  general form is used throughout.
//
//  Graphics ROM: MAME's 32 MB "video" region is one little-endian bit stream
//  (pixel n of a b-bit image is bits offset + n*b and up). The blitter reads
//  it as 8-byte lines (gfx_line = byte address / 8) and keeps two of them, the
//  line under the source pointer and the next, so a pixel that straddles two
//  lines is extracted in one go. The board maps lines to SDRAM.
//
//  Rows are assembled in a double-buffered row RAM and handed to the VRAM
//  controller as one burst each, so a row costs one DDR3 transaction. Each
//  drawn pixel is written into the row RAM on its own (four 16-bit lanes)
//  with a valid bit per entry, so when a scaled row runs past 1024 columns
//  and wraps over itself the later pixel wins, as in MAME.
//
//  Timing (clk_sys 96 MHz): at most one multiply or one wide sum per clock.
//  Products the row loop needs (row advance, start skip, compressed rows
//  skipped by Y scaling) are registered in one state and added in the next;
//  all source reads (pixels and skip bytes) go through one pointer, o, so
//  the window's "line present" check has no multiplexer in front of it.
//
//  Known difference: MAME stores pixels at x 512-1023 into the next row of
//  its frame store (its row pointer has no column wrap); here they are
//  dropped. Only blits whose right clip is past 511 can reach them.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_dma
(
	input             clk,
	input             reset,

	input             fast,          // count the completion timer down by 2 this clock
	                                 // (shorter video frames, see midway_wunit.sv)

	// register file (16-bit words 0-15), CPU side
	input             reg_wr,
	input       [3:0] reg_idx,
	input      [15:0] reg_wdata,
	output     [15:0] reg_rdata,
	output            reg_wr_wait,   // hold a new start until the current blit has drawn
	output     [15:0] palette_reg,   // DMA_PALETTE, also used by CPU VRAM writes

	output reg        irq,           // INT1

	// graphics ROM, 8-byte lines of MAME's video region
	output reg [24:3] gfx_line,
	output reg        gfx_req,       // toggle
	input             gfx_ack,
	input      [63:0] gfx_data,

	// VRAM row write-back (see wunit_vram)
	output reg        blt_req,       // toggle
	input             blt_ack,
	output reg  [8:0] blt_row,
	output reg  [6:0] blt_lo,
	output reg  [6:0] blt_hi,
	input       [6:0] blt_raddr,
	input       [6:0] blt_rbase,     // blt_raddr less this clock's step, and the step
	input             blt_radv,
	output reg [63:0] blt_q,
	output reg  [7:0] blt_be
);

//----------------------------------------------------------------------------
// Registers: 0-15 as the CPU sees them, 16/17 the left/right clip
//----------------------------------------------------------------------------

localparam R_LRSKIP  = 5'd0;
localparam R_COMMAND = 5'd1;
localparam R_OFFLO   = 5'd2;
localparam R_OFFHI   = 5'd3;
localparam R_XSTART  = 5'd4;
localparam R_YSTART  = 5'd5;
localparam R_WIDTH   = 5'd6;
localparam R_HEIGHT  = 5'd7;
localparam R_PALETTE = 5'd8;
localparam R_COLOR   = 5'd9;
localparam R_SCALEX  = 5'd10;
localparam R_SCALEY  = 5'd11;
localparam R_TOPCLIP = 5'd12;
localparam R_BOTCLIP = 5'd13;
localparam R_CONFIG  = 5'd15;
localparam R_LCLIP   = 5'd16;
localparam R_RCLIP   = 5'd17;

reg  [15:0] r [0:17];

// register write mapping (MAME register_map)
wire  [4:0] reg_map = (!r[R_CONFIG][5] && reg_idx == 4'd12) ? R_LCLIP :
                      (!r[R_CONFIG][5] && reg_idx == 4'd13) ? R_RCLIP : {1'b0, reg_idx};

assign reg_rdata   = (reg_idx == 4'd0) ? r[R_COMMAND] : r[{1'b0, reg_idx}];
assign palette_reg = r[R_PALETTE];

//----------------------------------------------------------------------------
// Row buffers: 2 banks of one 512-entry row, as four 16-bit lanes (entry
// lane = column bit 1:0) so a pixel is written on its own, plus a valid bit
// per entry of the row being filled and of the row being flushed. Entries
// not drawn in a row go out with no byte enabled, whatever an older row
// left in the RAM.
//----------------------------------------------------------------------------

reg  [15:0] rowl0 [0:255];
reg  [15:0] rowl1 [0:255];
reg  [15:0] rowl2 [0:255];
reg  [15:0] rowl3 [0:255];
reg         rb_we;
reg   [9:0] rb_wcol;                    // {bank, column}
reg  [15:0] rb_wdata;
reg         fill_bank;                  // bank being filled
reg         flush_bank;                 // bank the VRAM controller is reading
reg [511:0] valid;                      // entries drawn in the fill bank
reg [511:0] flush_valid;                // the same for the bank being flushed
reg         vw_en;                      // set valid[vw_col] next clock (the
reg   [8:0] vw_col;                     // 512-way decode gets a clock of its own)
reg  [63:0] rb_q;
reg   [3:0] rb_v;

always @(posedge clk) begin
	if (rb_we && rb_wcol[1:0] == 2'd0) rowl0[rb_wcol[9:2]] <= rb_wdata;
	if (rb_we && rb_wcol[1:0] == 2'd1) rowl1[rb_wcol[9:2]] <= rb_wdata;
	if (rb_we && rb_wcol[1:0] == 2'd2) rowl2[rb_wcol[9:2]] <= rb_wdata;
	if (rb_we && rb_wcol[1:0] == 2'd3) rowl3[rb_wcol[9:2]] <= rb_wdata;
	rb_q <= {rowl3[{flush_bank, blt_raddr}], rowl2[{flush_bank, blt_raddr}],
	         rowl1[{flush_bank, blt_raddr}], rowl0[{flush_bank, blt_raddr}]};
	// the valid bits of entry blt_raddr: both candidates, the step picks
	rb_v <= blt_radv ? flush_valid[{blt_rbase + 7'd1, 2'b00} +: 4] : flush_valid[{blt_rbase, 2'b00} +: 4];
end

always @(*) begin
	blt_q  = rb_q;
	blt_be = {{2{rb_v[3]}}, {2{rb_v[2]}}, {2{rb_v[1]}}, {2{rb_v[0]}}};
end

//----------------------------------------------------------------------------
// Divider: q = n / d for the pre-skip, start skip and pixel count
// (restoring, one quotient bit per clock)
//
// The blit engine hands over the dividend in div_a and the divisor in div_d
// with div_go; div_n, the dividend as it shifts, belongs to this block alone
// (one driver per register: Quartus refuses a register written from two
// always blocks).
//----------------------------------------------------------------------------

reg         div_go;
reg         div_busy;
reg  [19:0] div_a;                      // dividend, from the blit engine
reg  [19:0] div_n;
reg  [15:0] div_d;
reg  [19:0] div_q;
reg  [19:0] div_r;
reg   [4:0] div_i;

wire [20:0] div_try = {div_r, div_n[19]} - {5'd0, div_d};

always @(posedge clk) begin
	if (reset)
		div_busy <= 1'b0;
	else if (div_go) begin
		div_busy <= 1'b1;
		div_n    <= div_a;
		div_r    <= 20'd0;
		div_i    <= 5'd20;
	end
	else if (div_busy) begin
		if (!div_try[20]) begin
			div_r <= div_try[19:0];
			div_q <= {div_q[18:0], 1'b1};
		end
		else begin
			div_r <= {div_r[18:0], div_n[19]};
			div_q <= {div_q[18:0], 1'b0};
		end
		div_n <= {div_n[18:0], 1'b0};
		div_i <= div_i - 5'd1;
		if (div_i == 5'd1)
			div_busy <= 1'b0;
	end
end

//----------------------------------------------------------------------------
// Blit state
//----------------------------------------------------------------------------

localparam B_IDLE    = 5'd0;
localparam B_SETUP   = 5'd1;
localparam B_CNTX    = 5'd2;     // pixel count: width / x step
localparam B_CNTY    = 5'd3;     //              height / y step
localparam B_CNTM    = 5'd4;     //              product, completion time
localparam B_ROW     = 5'd5;
localparam B_SKIPRD  = 5'd6;     // read the row's skip byte
localparam B_PREDIV  = 5'd7;     // pre-skip / x step
localparam B_PRE2    = 5'd8;
localparam B_CLIPY   = 5'd9;
localparam B_SSDIV   = 5'd10;    // start skip / x step
localparam B_SS2     = 5'd11;
localparam B_SS3     = 5'd12;    // start skip: add the source bits
localparam B_ENDSK   = 5'd13;
localparam B_PIX     = 5'd14;
localparam B_PDRAIN  = 5'd15;
localparam B_ROWEND  = 5'd16;
localparam B_FLUSH   = 5'd17;
localparam B_ADV     = 5'd18;
localparam B_ADV2    = 5'd19;
localparam B_SKROW   = 5'd20;    // scaled skip rows: read a skip byte
localparam B_SKROW2  = 5'd21;
localparam B_DRAIN   = 5'd22;
localparam B_WAIT    = 5'd23;
localparam B_CNTW    = 5'd24;    // pixel count: wait for the divider
localparam B_CNTW2   = 5'd25;
localparam B_TIME    = 5'd26;
localparam B_PREW    = 5'd27;    // pre-skip division running
localparam B_ADV3    = 5'd28;    // next row: add the product
localparam B_SKROW3  = 5'd29;    // scaled skip rows: bytes of the row
localparam B_SKROW4  = 5'd30;    //                   past them

localparam OP_SKIP = 2'd0, OP_COPY = 2'd1, OP_COLOR = 2'd2;

reg   [4:0] bstate;
reg         start_pending;

// latched at the start of a blit
reg  [15:0] cmd;
reg   [3:0] bpp;                        // 1-8
reg   [7:0] pmask;
reg   [1:0] zop, nzop;                  // what zero / non-zero pixels do
reg         need_src;                   // pixels are read (not colour-only)
reg         skip, xflip, yflip;
reg   [1:0] preskip, postskip;
reg   [9:0] xpos, width, height;
reg   [8:0] ypos;
reg  [15:0] pal, color;
reg  [15:0] xstep, ystep;
reg   [8:0] topclip, botclip;
reg   [9:0] lclip, rclip;
reg  [15:0] startskip, endskip;
reg  [31:0] offset;                     // bit offset of the current row
reg         no_draw;                    // nothing to draw (op 0, or bad offset)
reg  [11:0] kx0, kx1;                   // source bits per x step without / with a carry
reg  [12:0] wbits;                      // width * bpp
reg  [17:0] cnt_x;
reg  [35:0] pixels;
reg  [31:0] timer;                      // clk cycles until completion may be signalled
reg  [15:0] since;                      // clk cycles since the start was first written
reg         start_wr_q;

// row state
reg  [19:0] iy;                         // 8.8 row position
reg   [8:0] sy;
reg  [31:0] o;                          // source bit pointer
reg   [9:0] sx;
reg  signed [27:0] ix;                  // 8.8 column position
reg  signed [27:0] wfp;                 // 8.8 row end
reg  [14:0] pre_fp, post_fp;            // this row's skips, 8.8
reg  [15:0] tx;
reg   [8:0] ty;                         // source rows per y step (up to 256)
reg   [8:0] skrows;                     // compressed rows still to step over
reg   [9:0] rowpix;                     // pixels stored in a compressed row
reg  [13:0] bmul;                       // bpp x pixels (one product per clock)
reg  [21:0] mprod;                      // source rows x row bits

wire [15:0] skp_fp = {1'b0, pre_fp} + {1'b0, post_fp};       // this row's skips, 8.8
wire [27:0] ss_fp  = {4'd0, startskip, 8'd0};                // start skip, 8.8
wire [15:0] ss_d   = 16'(ss_fp - 28'(ix));                    // start skip left (when ix < it)

// pixel pipeline
reg         p0_v, p1_v;
reg   [7:0] p0_pix;
reg   [9:0] p0_sx, p1_sx;
reg         p0_in;
reg         p1_wr;
reg  [15:0] p1_val;

// row extent
reg         row_any;                    // something was written in this row
reg   [6:0] row_lo, row_hi;             // first and last beat written
reg         flush_busy;                 // a flush request is outstanding

// MAME draws a blit the moment it is started; here drawing takes time, so a
// second start that arrives while the first is still drawing is held off.
wire        start_wr    = reg_wr && (reg_idx == 4'd1) && reg_wdata[15];
assign reg_wr_wait      = start_wr && (bstate != B_IDLE) && (bstate != B_WAIT);

//----------------------------------------------------------------------------
// Source window: w0 holds the line of the pointer (sp), w1 the next one
//----------------------------------------------------------------------------

reg  [63:0] w0, w1;
reg  [21:0] t0, t1;
reg  [21:0] t1_prev;                    // t1 - 1, so "w1 follows the pointer's
                                        // line" is a compare without an add
reg         v0, v1;
reg         fetching;
reg  [21:0] fetch_tag;

// the window follows o: the pixel loop's pointer, and the skip-byte readers'
// (B_SKIPRD, B_SKROW) too
wire [31:0] sp      = o;
wire [21:0] sp_line = sp[27:6];
wire  [6:0] sp_end  = {1'b0, sp[5:0]} + ((bstate == B_PIX) ? {3'd0, bpp} : 7'd8);
wire        sp_two  = sp_end > 7'd64;           // the bits run into the next line
wire        have0   = v0 && (t0 == sp_line);
wire        have1   = v1 && (t1_prev == sp_line);
wire        have    = have0 && (!sp_two || have1);
wire [127:0] win    = {w1, w0};
wire  [7:0] sp_bits = win[{1'b0, sp[5:0]} +: 8];

// which states read the source
wire        src_state = ((bstate == B_PIX) && need_src) || (bstate == B_SKIPRD) || (bstate == B_SKROW);

always @(posedge clk) begin
	if (reset) begin
		v0       <= 1'b0;
		v1       <= 1'b0;
		fetching <= 1'b0;
		gfx_req  <= gfx_ack;
	end
	else if (bstate == B_SETUP) begin
		// a new blit: the ROM did not change, but start clean
		v0 <= 1'b0;
		v1 <= 1'b0;
	end
	else if (fetching) begin
		if (gfx_req == gfx_ack) begin
			fetching <= 1'b0;
			if (fetch_tag == sp_line) begin
				w0 <= gfx_data; t0 <= fetch_tag; v0 <= 1'b1;
			end
			else begin
				w1 <= gfx_data; t1 <= fetch_tag; t1_prev <= fetch_tag - 22'd1; v1 <= 1'b1;
			end
		end
	end
	else if (src_state) begin
		if (!have0) begin
			if (v1 && t1 == sp_line) begin
				// the pointer moved on to the prefetched line
				w0 <= w1; t0 <= t1; v0 <= 1'b1; v1 <= 1'b0;
			end
			else begin
				fetching  <= 1'b1;
				fetch_tag <= sp_line;
				gfx_line  <= sp_line;
				gfx_req   <= ~gfx_req;
			end
		end
		else if (!have1) begin
			fetching  <= 1'b1;
			fetch_tag <= sp_line + 22'd1;
			gfx_line  <= sp_line + 22'd1;
			gfx_req   <= ~gfx_req;
		end
	end
end

//----------------------------------------------------------------------------
// Blit engine
//----------------------------------------------------------------------------

// the pixel loop's next step: ix + xstep, and the source bits that adds
wire        ix_carry = ({1'b0, ix[7:0]} + {1'b0, xstep[7:0]}) > 9'd255;
wire        in_clip  = (sx >= lclip) && (sx <= rclip) && !sx[9];
wire signed [27:0] wend = $signed({{18{1'b0}}, width}) - $signed({12'd0, endskip});

integer i;
always @(posedge clk) begin
	rb_we <= 1'b0;
	vw_en <= 1'b0;
	div_go <= 1'b0;

	if (reset) begin
		for (i = 0; i < 18; i = i + 1)
			r[i] <= 16'd0;
		bstate        <= B_IDLE;
		irq           <= 1'b0;
		flush_busy    <= 1'b0;
		fill_bank     <= 1'b0;
		flush_bank    <= 1'b0;
		timer         <= 32'd0;
		blt_req       <= blt_ack;
		start_pending <= 1'b0;
		p0_v          <= 1'b0;
		p1_v          <= 1'b0;
	end
	else begin
		if (fast && (timer > 32'd1))
			timer <= timer - 32'd2;
		else if (timer != 32'd0)
			timer <= timer - 32'd1;

		// time since the start command, counted like the timer: from its
		// first clock on the bus (a start held by reg_wr_wait counts too)
		start_wr_q <= start_wr;
		if (start_wr && !start_wr_q)
			since <= 16'd0;
		else if (since < 16'hFFF0)
			since <= since + (fast ? 16'd2 : 16'd1);

		// ---- flush handshake ----
		if (flush_busy && (blt_req == blt_ack))
			flush_busy <= 1'b0;

		// ---- pixel pipeline stage 1: what this pixel writes ----
		p1_v  <= p0_v;
		p1_sx <= p0_sx;
		if (p0_pix == 8'd0) begin
			p1_wr  <= p0_v && p0_in && (zop != OP_SKIP);
			p1_val <= (zop == OP_COLOR) ? color : pal;
		end
		else begin
			p1_wr  <= p0_v && p0_in && (nzop != OP_SKIP);
			p1_val <= (nzop == OP_COLOR) ? color : (pal | {8'd0, p0_pix});
		end

		// ---- pixel pipeline stage 3: the entry's valid bit, set with its RAM
		// write; B_PDRAIN / B_ROWEND keep B_FLUSH a clock behind the last ----
		if (vw_en)
			valid[vw_col] <= 1'b1;

		// ---- pixel pipeline stage 2: into the row buffer ----
		// columns 512-1023 are outside the frame store's row
		if (p1_v && p1_wr && !p1_sx[9]) begin
			rb_we    <= 1'b1;
			rb_wcol  <= {fill_bank, p1_sx[8:0]};
			rb_wdata <= p1_val;
			vw_en    <= 1'b1;
			vw_col   <= p1_sx[8:0];
			row_any  <= 1'b1;
			if (!row_any || p1_sx[8:2] < row_lo) row_lo <= p1_sx[8:2];
			if (!row_any || p1_sx[8:2] > row_hi) row_hi <= p1_sx[8:2];
		end

		p0_v <= 1'b0;

		case (bstate)
			B_IDLE: if (start_pending) begin
				start_pending <= 1'b0;
				cmd       <= r[R_COMMAND];
				bpp       <= (r[R_COMMAND][14:12] == 3'd0) ? 4'd8 : {1'b0, r[R_COMMAND][14:12]};
				skip      <= r[R_COMMAND][7];
				xflip     <= r[R_COMMAND][4];
				yflip     <= r[R_COMMAND][5];
				preskip   <= r[R_COMMAND][9:8];
				postskip  <= r[R_COMMAND][11:10];
				xpos      <= r[R_XSTART][9:0];
				ypos      <= r[R_YSTART][8:0];
				width     <= r[R_WIDTH][9:0];
				height    <= r[R_HEIGHT][9:0];
				pal       <= {1'b0, r[R_PALETTE][14:8], 8'h00};
				color     <= {1'b0, r[R_PALETTE][14:8], r[R_COLOR][7:0]};
				xstep     <= (r[R_SCALEX] != 16'd0) ? r[R_SCALEX] : 16'h0100;
				ystep     <= (r[R_SCALEY] != 16'd0) ? r[R_SCALEY] : 16'h0100;
				topclip   <= r[R_TOPCLIP][8:0];
				botclip   <= r[R_BOTCLIP][8:0];
				lclip     <= r[R_LCLIP][9:0];
				rclip     <= r[R_RCLIP][9:0];
				if (r[R_COMMAND][6]) begin
					startskip <= {8'd0, r[R_LRSKIP][7:0]};
					endskip   <= {8'd0, r[R_LRSKIP][15:8]};
				end
				else begin
					startskip <= 16'd0;
					endskip   <= r[R_LRSKIP];
				end
				// source offset: mode C reads no pixels; the Wolf Unit takes
				// the whole 32 MB region (gfx_rom_large), with the F8000000
				// alias folded down
				if (r[R_COMMAND][3:0] == 4'hC)
					offset <= 32'd0;
				else if ({r[R_OFFHI], r[R_OFFLO]} >= 32'hF800_0000)
					offset <= {r[R_OFFHI], r[R_OFFLO]} - 32'hF800_0000;
				else
					offset <= {r[R_OFFHI], r[R_OFFLO]};
				bstate <= B_SETUP;
			end

			B_SETUP: begin
				pmask    <= 8'hFF >> (4'd8 - bpp);
				zop      <= cmd[2] ? OP_COLOR : cmd[0] ? OP_COPY : OP_SKIP;
				nzop     <= cmd[3] ? OP_COLOR : cmd[1] ? OP_COPY : OP_SKIP;
				need_src <= !(cmd[3] && cmd[2]);
				no_draw  <= (cmd[3:0] == 4'd0) || (offset >= 32'h1000_0000);
				kx0      <= bpp * xstep[15:8];
				wbits    <= width * bpp;
				// pixel count, first factor
				div_a    <= {2'd0, width, 8'd0};
				div_d    <= xstep;
				div_go   <= 1'b1;
				bstate   <= B_CNTX;
			end

			B_CNTX: begin                        // the divider starts
				kx1    <= kx0 + {8'd0, bpp};
				bstate <= B_CNTW;
			end

			B_CNTW: if (!div_busy && !div_go) begin
				cnt_x  <= div_q[17:0];
				div_a  <= {2'd0, height, 8'd0};
				div_d  <= ystep;
				div_go <= 1'b1;
				bstate <= B_CNTY;
			end

			B_CNTY: bstate <= B_CNTW2;

			B_CNTW2: if (!div_busy && !div_go) begin
				pixels <= cnt_x * div_q[17:0];
				bstate <= B_CNTM;
			end

			B_CNTM: begin
				// completion time: 41 ns per pixel = 3.9375 clk at 96 MHz (none
				// when the source offset is out of range)
				if (offset >= 32'h1000_0000)
					timer <= 32'd0;
				else if (pixels[35:30] != 6'd0)
					timer <= 32'hFFFF_FFFF;
				else
					timer <= 32'(((42'(pixels) << 6) - 42'(pixels)) >> 4);
				bstate <= B_TIME;
			end

			B_TIME: begin
				// the clocks already gone since the command write come off
				// (MAME's timer starts at the write)
				timer     <= (timer > {16'd0, since}) ? timer - {16'd0, since} : 32'd0;
				iy        <= 20'd0;
				sy        <= ypos;
				bstate    <= no_draw ? B_WAIT : B_ROW;
			end

			// ---------------- one row ----------------
			B_ROW: begin
				row_any   <= 1'b0;
				valid     <= 512'd0;
				o         <= offset;             // the skip byte or the first pixel
				if (iy >= {2'd0, height, 8'd0})
					bstate <= B_DRAIN;
				else if (skip)
					bstate <= B_SKIPRD;
				else begin
					sx      <= xpos;
					ix      <= 28'sd0;
					wfp     <= {10'd0, width, 8'd0};
					pre_fp  <= 15'd0;
					post_fp <= 15'd0;
					bstate  <= B_CLIPY;
				end
			end

			B_SKIPRD: if (have) begin
				// the skip byte: pixels before (low nibble) and after (high)
				o       <= o + 32'd8;
				pre_fp  <= {3'd0, sp_bits[3:0], 8'd0} << preskip;
				post_fp <= {3'd0, sp_bits[7:4], 8'd0} << postskip;
				sx      <= xpos;
				ix      <= 28'sd0;
				bstate  <= B_PREDIV;
			end

			B_PREDIV: begin
				// the row ends post pixels early; it starts tx = pre / xstep
				// steps in (a shift when the step is 1.0)
				wfp <= $signed({10'd0, width, 8'd0}) - $signed({13'd0, post_fp});
				if (pre_fp == 15'd0)
					bstate <= B_CLIPY;
				else if (xstep == 16'h0100) begin
					tx     <= {9'd0, pre_fp[14:8]};
					bstate <= B_PRE2;
				end
				else begin
					div_a  <= {5'd0, pre_fp};
					div_d  <= xstep;
					div_go <= 1'b1;
					bstate <= B_PREW;
				end
			end

			B_PREW: if (!div_busy && !div_go) begin
				tx     <= div_q[15:0];
				bstate <= B_PRE2;
			end

			B_PRE2: begin
				sx     <= xflip ? (xpos - tx[9:0]) : (xpos + tx[9:0]);
				ix     <= 28'(tx * xstep);
				bstate <= B_CLIPY;
			end

			B_CLIPY: begin
				if (sy < topclip || sy > botclip)
					bstate <= B_ADV;
				else if (ix < $signed(ss_fp)) begin
					// start skip: whole x steps up to it (ss_d / xstep steps)
					if (xstep == 16'h0100) begin
						tx     <= {ss_d[15:8], 8'd0};
						bstate <= B_SS2;
					end
					else begin
						div_a  <= {4'd0, ss_d};
						div_d  <= xstep;
						div_go <= 1'b1;
						bstate <= B_SSDIV;
					end
				end
				else
					bstate <= B_ENDSK;
			end

			B_SSDIV: if (!div_busy && !div_go) begin
				tx     <= 16'(div_q[15:0] * xstep);
				bstate <= B_SS2;
			end

			B_SS2: begin
				ix     <= ix + $signed({12'd0, tx});
				bmul   <= bpp * tx[15:8];
				bstate <= B_SS3;
			end

			B_SS3: begin
				o      <= o + {18'd0, bmul};
				bstate <= B_ENDSK;
			end

			B_ENDSK: begin
				// end skip
				if ((wfp >>> 8) > wend)
					wfp <= wend <<< 8;
				p0_v   <= 1'b0;
				bstate <= B_PIX;
			end

			// ---------------- pixels ----------------
			B_PIX: begin
				if (ix >= wfp)
					bstate <= B_PDRAIN;
				else if (have || !need_src) begin
					p0_v   <= 1'b1;
					p0_sx  <= sx;
					p0_in  <= in_clip;
					p0_pix <= sp_bits & pmask;
					sx     <= xflip ? (sx - 10'd1) : (sx + 10'd1);
					o      <= o + {20'd0, ix_carry ? kx1 : kx0};
					ix     <= ix + $signed({12'd0, xstep});
				end
			end

			B_PDRAIN: if (!p0_v && !p1_v)
				bstate <= B_ROWEND;

			B_ROWEND: bstate <= B_FLUSH;         // the last pixel is in the RAM

			B_FLUSH: if (!row_any || !flush_busy) begin
				// rows where nothing was drawn need no VRAM write at all
				if (row_any) begin
					flush_busy    <= 1'b1;
					flush_bank    <= fill_bank;
					flush_valid   <= valid;
					fill_bank     <= ~fill_bank;
					blt_row       <= sy;
					blt_lo        <= row_lo;
					blt_hi        <= row_hi;
					blt_req       <= ~blt_req;
				end
				bstate <= B_ADV;
			end

			// ---------------- next row ----------------
			B_ADV: begin
				sy <= yflip ? (sy - 9'd1) : (sy + 9'd1);
				// rows of source this y step moves over
				ty <= 9'((iy + {4'd0, ystep}) >> 8) - 9'(iy >> 8);
				iy <= iy + {4'd0, ystep};
				// compressed: pixels stored in this row (skips here are 8.8)
				rowpix <= ({1'b0, width} > {3'd0, skp_fp[15:8]}) ? width - {2'd0, skp_fp[15:8]} : 10'd0;
				bstate <= B_ADV2;
			end

			B_ADV2: begin
				// the product now, the sum in B_ADV3
				mprod <= ty * wbits;
				bmul  <= bpp * rowpix;
				if (skip && ty == 9'd0)
					bstate <= B_ROW;
				else begin
					skrows <= ty - 9'd1;
					bstate <= B_ADV3;
				end
			end

			B_ADV3: begin
				if (!skip) begin
					offset <= offset + {10'd0, mprod};
					bstate <= B_ROW;
				end
				else begin
					// past this row's skip byte and pixels, then whole
					// compressed rows (B_SKROW reads at o)
					o      <= offset + 32'd8 + {18'd0, bmul};
					bstate <= B_SKROW;
				end
			end

			B_SKROW: begin
				if (skrows == 9'd0) begin
					offset <= o;
					bstate <= B_ROW;
				end
				else if (have) begin
					// the skips here are in pixels (no 8.8)
					pre_fp  <= {11'd0, sp_bits[3:0]} << preskip;
					post_fp <= {11'd0, sp_bits[7:4]} << postskip;
					o       <= o + 32'd8;
					bstate  <= B_SKROW2;
				end
			end

			B_SKROW2: begin
				// skips in pixels here: at most 2 x 120
				rowpix <= ({1'b0, width} > {1'b0, skp_fp[9:0]}) ? width - skp_fp[9:0] : 10'd0;
				skrows <= skrows - 9'd1;
				bstate <= B_SKROW3;
			end

			B_SKROW3: begin
				bmul   <= bpp * rowpix;
				bstate <= B_SKROW4;
			end

			B_SKROW4: begin
				o      <= o + {18'd0, bmul};
				bstate <= B_SKROW;
			end

			B_DRAIN: if (!flush_busy)
				bstate <= B_WAIT;

			B_WAIT: begin
				if (start_pending)
					bstate <= B_IDLE;            // restarted: the old completion is cancelled
				else if ((timer == 32'd0 || timer == 32'd1) && !start_wr) begin
					r[R_COMMAND][15] <= 1'b0;
					irq              <= 1'b1;
					bstate           <= B_IDLE;
				end
			end

			default: bstate <= B_IDLE;
		endcase

		// ---- CPU register writes (last, so they win over the completion) ----
		if (reg_wr && !reg_wr_wait) begin
			r[reg_map] <= reg_wdata;
			if (reg_idx == 4'd1) begin
				irq <= 1'b0;                     // any command write acknowledges
				if (reg_wdata[15]) start_pending <= 1'b1;
			end
		end
	end
end

endmodule
