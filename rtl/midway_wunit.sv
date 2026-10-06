//============================================================================
//  Midway Wolf Unit CPU board
//
//  TMS34010 plus everything on its local bus (MAME midwunit.cpp main_map):
//    0x00000000-0x003FFFFF  frame store (VRAM, in DDR3)       entries 0-0x7FFFF
//    0x01000000-0x013FFFFF  main RAM, 512 KB (SDRAM, through a cache)
//    0x01400000-0x0145FFFF  CMOS, 48 KB (one write per enable)
//    0x01480000-0x014FFFFF  CMOS write enable
//    0x01600000-0x0160001F  security PIC
//    0x01680000-0x0168001F  sound board data latch (DCS)
//    0x01800000-0x0187FFFF  I/O: inputs, DSW, status, control (16-word window)
//    0x01880000-0x018FFFFF  palette RAM, 32768 x xRGB555
//    0x01A00000-0x01A000FF  DMA blitter registers (mirrored at +0x80000)
//    0x01B00000-0x01B0001F  control register (graphics bank, video bank)
//    0x02000000-0x06FFFFFF  graphics ROM read-back (bank of 8 MB, words)
//    0xFF800000-0xFFFFFFFF  program ROM, 1 MB (SDRAM, through a cache)
//  (34010 bit addresses; unmapped reads return 0 as in MAME)
//
//  Built from the Y Unit board (midway_yunit.sv): the CPU, its registered
//  bus, the clock enables, the frame store and the program ROM cache are the
//  same. What changes is the map above and:
//    - main RAM is 4x larger, too large for block RAM next to everything
//      else, so it sits in SDRAM behind a 16 KB write-through cache
//    - VCLK is 8 MHz: one pixel per VCLK (the Y Unit had two)
//    - the I/O block can be reordered (WWF WrestleMania picks one of five
//      maps by writing word 0; MAME wwfmania_io_0_w)
//    - the palette is 32K colours and the pens are 15 bits
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module midway_wunit
(
	input             clk,           // 96 MHz
	input             reset,
	input             pause,

	// game configuration
	input      [63:0] gfx_slots,     // byte n: packed index of 4 MB graphics slot n, FF empty
	input      [11:0] year,          // for the security PIC's date
	input             io_remap,      // WWF: a write to I/O word 0 picks the I/O order
	input       [1:0] vtiming,       // MiSTer option: 0 native frame (54.7 Hz), 1 277 lines
	                                 // (57.1 Hz), 2 263 lines (60.1 Hz); see "Video timing"

	// inputs as the CPU reads them (active low): IN0, IN1, DSW, IN2
	input      [15:0] in0,
	input      [15:0] in1,
	input      [15:0] dsw,
	input      [15:0] in2,

	// sound board (DCS) host interface
	output reg        snd_wr,        // one clock: write snd_wdata to the input latch
	output reg  [7:0] snd_wdata,
	output reg        snd_rd,        // one clock: the output latch was read
	input       [7:0] snd_rdata,     // output latch
	input      [15:0] snd_ctrl,      // latch status (DCS control_r)
	output reg        snd_reset,     // sound CPU held in reset (I/O control bit 4)

	// SDRAM: program ROM / main RAM / graphics read-back (CPU) and blitter source
	output reg [24:1] cpu_sd_addr,
	output reg        cpu_sd_req,
	input             cpu_sd_ack,
	input      [63:0] cpu_sd_data,
	output reg        cpu_sd_we,
	output reg [15:0] cpu_sd_din,

	output     [24:3] dma_sd_addr,
	output            dma_sd_req,
	input             dma_sd_ack,
	input      [63:0] dma_sd_data,

	// DDR3 (VRAM)
	input             ddr_busy,
	output      [7:0] ddr_burstcnt,
	output     [28:0] ddr_addr,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	output            ddr_rd,
	output     [63:0] ddr_din,
	output      [7:0] ddr_be,
	output            ddr_we,

	// CMOS access for NVRAM load/save (word address, 24 K words)
	input      [14:0] nv_addr,
	input             nv_we,
	input      [15:0] nv_din,
	output     [15:0] nv_dout,
	output            cmos_write,    // the game wrote its CMOS (NVRAM needs saving)

	// video
	output            ce_pix,
	output      [7:0] vid_r,
	output      [7:0] vid_g,
	output      [7:0] vid_b,
	output            vid_hs,
	output            vid_vs,
	output            vid_hb,
	output            vid_vb,

	// debug
	output     [31:0] dbg_pc,
	output            dbg_retire
);

// SDRAM byte addresses of the regions (see the ROM layout in the MRA files)
localparam [24:0] ROM_BASE = 25'h000_0000;
localparam [24:0] GFX_BASE = 25'h050_2000;
localparam [24:0] RAM_BASE = 25'h1F8_0000;     // main RAM, the top 512 KB

//----------------------------------------------------------------------------
// Clock enables
//
// Everything runs from one 24-step phase counter at 96 MHz:
//  - cpu_ce enables the 34010's logic on every other clock (48 MHz). Its
//    paths are constrained as two-cycle paths in the SDC, which is what lets
//    the instruction logic close timing.
//  - ce_cyc is the 34010 machine cycle (50 MHz / 8 = 6.25 MHz) from a
//    fractional divider stepped at 48 MHz, so it always falls in a cpu_ce
//    cycle.
//  - VCLK and the pixel clock are both 8 MHz (96 MHz / 12): the Wolf Unit
//    clocks the 34010's video counters once per pixel. They fall in cpu_ce
//    cycles too.
// Each enable is registered from the phase it will be high in.
//----------------------------------------------------------------------------

reg   [4:0] ph;
reg         cpu_ce, ce_pix_r;
always @(posedge clk) begin
	ph       <= (ph == 5'd23) ? 5'd0 : ph + 5'd1;
	cpu_ce   <= ph[0];                               // next phase is even
	ce_pix_r <= (ph == 5'd23) || (ph == 5'd11);      // next phase 0 or 12
end
assign ce_pix = ce_pix_r;
wire ce_vclk  = ce_pix_r;

//----------------------------------------------------------------------------
// Video timing (MiSTer option for 15 kHz TVs)
//
// Every game runs a 289-line frame at 15.81 kHz: 54.7 Hz, which some TVs do
// not hold well. The shorter frames drop blank lines in the 34010's CRT
// controller (see tms34010.sv): 277 lines for 57.1 Hz or 263 for 60.1 Hz.
// The games count time in frames, so they run 289/277 (+4.3 %) or 289/263
// (+9.9 %) faster either way; the CPU's machine cycle and the blitter's
// completion time are sped up by the same ratio, so a frame still gets the
// real board's cycles. The sound board keeps its own clock.
//----------------------------------------------------------------------------

wire  [1:0] vt = (vtiming == 2'd3) ? 2'd0 : vtiming;   // 3 is not used: native

reg   [9:0] frame_lines;
always @(posedge clk)
	frame_lines <= (vt == 2'd1) ? 10'd277 : (vt == 2'd2) ? 10'd263 : 10'd0;

// step (6.25 MHz in kHz, times 289/277 or 289/263 for the shorter frames)
// and the level at which a step wraps, so the accumulator update is one add
// or subtract and one compare
reg  [16:0] cyc_acc;
reg         ce_cyc;
reg  [16:0] cyc_step, cyc_thr;
always @(posedge clk) begin
	case (vt)
		2'd1:    cyc_step <= 17'd6521;   // 57 Hz
		2'd2:    cyc_step <= 17'd6868;   // 60 Hz
		default: cyc_step <= 17'd6250;   // native
	endcase
	cyc_thr <= 17'd48000 - cyc_step;
end

// blitter completion time: one extra count off its timer at 289/277 - 1 or
// 289/263 - 1 of the clocks (16-bit fraction)
reg  [15:0] dma_frac, dma_fstep;
reg         dma_fast;
always @(posedge clk) begin
	dma_fstep <= (vt == 2'd1) ? 16'd2839 : (vt == 2'd2) ? 16'd6479 : 16'd0;
	{dma_fast, dma_frac} <= {1'b0, dma_frac} + {1'b0, dma_fstep};
end

always @(posedge clk) begin
	ce_cyc <= 1'b0;
	if (reset)
		cyc_acc <= 17'd0;
	else if (ph[0]) begin
		// steps of 6.25 MHz out of 48 MHz: acc + step >= 48000 is
		// acc >= 48000 - step, and acc + step - 48000 is acc - (48000 - step)
		if (cyc_acc >= cyc_thr) begin
			cyc_acc <= cyc_acc - cyc_thr;
			ce_cyc  <= ~pause;
		end
		else
			cyc_acc <= cyc_acc + cyc_step;
	end
end

//----------------------------------------------------------------------------
// TMS34010
//----------------------------------------------------------------------------

wire [27:0] mem_addr;
wire [31:0] mem_baddr;
wire        mem_rd, mem_wr, mem_srt;
wire [15:0] mem_wdata;
reg  [15:0] mem_rdata;
reg         mem_ack;

wire        cpu_hs, cpu_vs, cpu_hb, cpu_vb, disp_en;
wire  [9:0] hcount, vcount, heblnk, hsblnk, cpu_vsblnk;
wire        line_start, line_vis;
wire [11:0] line_row;
wire [13:0] line_col;
wire        dma_irq;
wire [31:0] cpu_pc;
wire        cpu_retire;

// power-up raster, until the game programs the CRT controller: MAME's
// 506-dot line with the picture at 101-500 (pixels, one per VCLK) and lines
// 20-273, the values the games then program themselves
tms34010 #(
	.DEF_HTOTAL (10'd505),
	.DEF_HESYNC (10'd43),
	.DEF_HEBLNK (10'd101),
	.DEF_HSBLNK (10'd501),
	.DEF_VSBLNK (10'd274)
) cpu
(
	.clk        (clk),
	.ce         (cpu_ce),
	.reset      (reset),
	.ce_cyc     (ce_cyc),
	.ce_vclk    (ce_vclk),
	.pause      (pause),
	.frame_lines(frame_lines),

	.mem_addr   (mem_addr),
	.mem_baddr  (mem_baddr),
	.mem_rd     (mem_rd),
	.mem_wr     (mem_wr),
	.mem_srt    (mem_srt),
	.mem_wdata  (mem_wdata),
	.mem_rdata  (mem_rdata),
	.mem_ack    (mem_ack),

	.int1       (dma_irq),
	.int2       (1'b0),

	.hsync      (cpu_hs),
	.vsync      (cpu_vs),
	.hblank     (cpu_hb),
	.vblank     (cpu_vb),
	.hcount     (hcount),
	.vcount     (vcount),
	.heblnk     (heblnk),
	.hsblnk     (hsblnk),
	.vsblnk     (cpu_vsblnk),
	.disp_en    (disp_en),
	.line_start (line_start),
	.line_vis   (line_vis),
	.line_row   (line_row),
	.line_col   (line_col),

	.dbg_pc     (cpu_pc),
	.dbg_st     (),
	.dbg_retire (cpu_retire),
	.dbg_cycles ()
);

assign dbg_pc = cpu_pc;

// CPU pulses last two clocks (one cpu_ce period); count them once
assign dbg_retire = cpu_retire & cpu_ce;

//----------------------------------------------------------------------------
// CPU bus, registered on the board side
//
// The CPU's request, address and data come straight out of its registers
// through its bus multiplexer and I/O range check. Decoding them on the same
// clock gave the longest single-clock paths at 96 MHz on the Y Unit, so the
// board decodes a copy registered one clock later. That costs nothing on
// fast accesses: the CPU only looks at mem_ack on cpu_ce edges, every other
// clock, so an access accepted one clock later is still seen on the same
// cpu_ce edge.
//
// When the CPU takes an acknowledge (mem_ack high on a cpu_ce edge) it moves
// on at once, but the copy still holds the finished request for one more
// clock; b_stale keeps the state machine from serving it twice.
//----------------------------------------------------------------------------

reg         b_rd, b_wr, b_srt, b_stale;
reg  [27:0] b_addr;
reg  [21:3] b_baddr;
reg  [15:0] b_wdata;
always @(posedge clk) begin
	b_rd    <= mem_rd;
	b_wr    <= mem_wr;
	b_srt   <= mem_srt;
	b_addr  <= mem_addr;
	b_baddr <= mem_baddr[21:3];
	b_wdata <= mem_wdata;
	b_stale <= cpu_ce & mem_ack;
end

//----------------------------------------------------------------------------
// Address decode (word addresses, from the registered copy)
//----------------------------------------------------------------------------

wire [27:0] wa = b_addr;

wire sel_vram  = (wa[27:18] == 10'd0);
wire sel_ram   = (wa[27:18] == 10'h004);
wire sel_cmos  = (wa[27:15] == 13'h0028) && (wa[14:13] != 2'b11);
wire sel_cmosen= (wa[27:15] == 13'h0029);
wire sel_sec   = (wa[27:1]  == 27'h00B_0000);              // words 0x160000-0x160001
wire sel_snd   = (wa[27:1]  == 27'h00B_4000);              // words 0x168000-0x168001
wire sel_io    = (wa[27:15] == 13'h0030);
wire sel_pal   = (wa[27:15] == 13'h0031);
wire sel_dma   = (wa[27:16] == 12'h01A) && (wa[14:4] == 11'd0);
wire sel_ctrl  = (wa[27:1]  == 27'h00D_8000);              // words 0x1B0000-0x1B0001
wire sel_gfx   = (wa[27:21] != 7'd0) && (wa[27:20] <= 8'h06) && (wa[27:23] == 5'd0);
wire sel_rom   = (wa[27:19] == 9'h1FF);

//----------------------------------------------------------------------------
// Program ROM cache: 2048 lines of 8 bytes, direct mapped (as on the Y Unit)
//----------------------------------------------------------------------------

reg  [63:0] rc_data [0:2047];
reg   [6:0] rc_tag  [0:2047];      // {valid, tag}
reg  [63:0] rc_q;
reg   [6:0] rct_q;
reg         rc_we;
reg  [10:0] rc_wa;
reg  [63:0] rc_wd;
reg   [6:0] rc_wt;

wire [16:0] rom_line = wa[18:2];       // 8-byte line within the 1 MB ROM

always @(posedge clk) begin
	if (rc_we) begin
		rc_data[rc_wa] <= rc_wd;
		rc_tag[rc_wa]  <= rc_wt;
	end
	rc_q  <= rc_data[rom_line[10:0]];
	rct_q <= rc_tag[rom_line[10:0]];
end

//----------------------------------------------------------------------------
// Main RAM cache: 2048 lines of 8 bytes, direct mapped, write-through
//
// Main RAM is 256 K words in SDRAM. Reads that hit come from here in two
// clocks; a miss fetches the 8-byte line over channel 1 and keeps it. Writes
// go to SDRAM every time (and into the cached line when it is present). A
// write is posted: the CPU moves on at once, and the next SDRAM access the
// board makes waits for it, so nothing can read the old value.
//
// The data is four 16-bit lanes so a write updates one word without reading
// the line first.
//----------------------------------------------------------------------------

reg  [15:0] mc_d0 [0:2047];
reg  [15:0] mc_d1 [0:2047];
reg  [15:0] mc_d2 [0:2047];
reg  [15:0] mc_d3 [0:2047];
reg   [5:0] mc_tag [0:2047];           // {valid, tag}
reg  [63:0] mc_q;
reg   [5:0] mct_q;
reg   [3:0] mc_we;                     // per lane
reg  [10:0] mc_wa;
reg  [63:0] mc_wd;
reg         mc_twe;
reg   [5:0] mc_wt;

wire [15:0] ram_line = wa[17:2];       // 8-byte line within the 512 KB

always @(posedge clk) begin
	if (mc_we[0]) mc_d0[mc_wa] <= mc_wd[15:0];
	if (mc_we[1]) mc_d1[mc_wa] <= mc_wd[31:16];
	if (mc_we[2]) mc_d2[mc_wa] <= mc_wd[47:32];
	if (mc_we[3]) mc_d3[mc_wa] <= mc_wd[63:48];
	if (mc_twe)   mc_tag[mc_wa] <= mc_wt;
	mc_q  <= {mc_d3[ram_line[10:0]], mc_d2[ram_line[10:0]], mc_d1[ram_line[10:0]], mc_d0[ram_line[10:0]]};
	mct_q <= mc_tag[ram_line[10:0]];
end

wire mc_hit = (mct_q == {1'b1, ram_line[15:11]});

// both caches are cleared by walking them after reset (a ROM reload is
// followed by a reset, so stale lines never survive a game change)
reg         c_clr;
reg  [10:0] c_clr_a;

//----------------------------------------------------------------------------
// CMOS (24 K x 16). Port B serves NVRAM load/save.
//
// An explicit altsyncram (true dual-port M10K) rather than an inferred
// array: Quartus 17 would not infer a true dual-port RAM from either template
// on the Y Unit and fell back to registers. Both ports use clk; addresses and
// write data are registered inside the block and the outputs are not, so
// q_a/q_b hold the word addressed on the previous clock.
//
// The mixed-port mode is don't care: an NVRAM save reading port B on the
// clock the CPU writes the same word may get either value, but that CPU
// write marks the CMOS dirty again so the next save carries it.
//
// A behavioural model of altsyncram for simulation is not part of the core;
// Quartus supplies the real one.
//----------------------------------------------------------------------------

wire [15:0] cmos_q;
reg         cmos_we;
reg         cmos_en;           // one write allowed (MAME m_cmos_write_enable)

altsyncram #(
	.operation_mode                     ("BIDIR_DUAL_PORT"),
	.intended_device_family             ("Cyclone V"),
	.lpm_type                           ("altsyncram"),
	.ram_block_type                     ("M10K"),
	.width_a                            (16),
	.widthad_a                          (15),
	.numwords_a                         (24576),
	.width_b                            (16),
	.widthad_b                          (15),
	.numwords_b                         (24576),
	.width_byteena_a                    (1),
	.width_byteena_b                    (1),
	.address_reg_b                      ("CLOCK0"),
	.indata_reg_b                       ("CLOCK0"),
	.wrcontrol_wraddress_reg_b          ("CLOCK0"),
	.outdata_reg_a                      ("UNREGISTERED"),
	.outdata_reg_b                      ("UNREGISTERED"),
	.outdata_aclr_a                     ("NONE"),
	.outdata_aclr_b                     ("NONE"),
	.clock_enable_input_a               ("BYPASS"),
	.clock_enable_input_b               ("BYPASS"),
	.clock_enable_output_a              ("BYPASS"),
	.clock_enable_output_b              ("BYPASS"),
	.read_during_write_mode_port_a      ("NEW_DATA_NO_NBE_READ"),
	.read_during_write_mode_port_b      ("NEW_DATA_NO_NBE_READ"),
	.read_during_write_mode_mixed_ports ("DONT_CARE"),
	.power_up_uninitialized             ("FALSE")
) cmos_mem
(
	// port A: TMS34010
	.clock0         (clk),
	.address_a      (wa[14:0]),
	.data_a         (b_wdata),
	.wren_a         (cmos_we),
	.q_a            (cmos_q),

	// port B: NVRAM load/save and CMOS clear from the top level
	.clock1         (1'b1),
	.address_b      (nv_addr),
	.data_b         (nv_din),
	.wren_b         (nv_we),
	.q_b            (nv_dout),

	// unused controls
	.aclr0          (1'b0),
	.aclr1          (1'b0),
	.addressstall_a (1'b0),
	.addressstall_b (1'b0),
	.byteena_a      (1'b1),
	.byteena_b      (1'b1),
	.clocken0       (1'b1),
	.clocken1       (1'b1),
	.clocken2       (1'b1),
	.clocken3       (1'b1),
	.rden_a         (1'b1),
	.rden_b         (1'b1),
	.eccstatus      ()
);

assign cmos_write = cmos_we;

//----------------------------------------------------------------------------
// Graphics ROM addressing
//
// MAME's "video" region is 32 MB; the MRA packs the 4 MB slots that hold
// data, and gfx_slots says where each one went. A byte in an empty slot reads
// as 0 (the region's fill).
//----------------------------------------------------------------------------

function automatic [25:0] gfx_map(input [24:0] g, input [63:0] slots);
	reg [7:0] p;
	begin
		p = slots[{g[24:22], 3'b000} +: 8];
		gfx_map = {p[7], GFX_BASE + {p[2:0], g[21:0]}};     // {empty, SDRAM byte}
	end
endfunction

// CPU read-back: bank (control bits 8-9) * 8 MB + word offset * 2
reg   [1:0] gfx_bank;
wire [24:0] gfx_byte = {gfx_bank, 23'd0} + {1'b0, wa[22:0] - 23'h20_0000, 1'b0};

//----------------------------------------------------------------------------
// I/O block (MAME io_r / io_w)
//
// A 16-word window repeated over 0x01800000-0x0187FFFF. Each word goes
// through an order table before use (identity, mod 8, unless WWF picked
// another order): 0-3 read IN0, IN1, DSW, IN2; 4 reads the PIC status
// (bit 12) and the sound latch status; 5-7 read FFFF. Word 1 is the control
// register: bit 4 holds the sound CPU in reset, bit 5 restarts the PIC.
// Word 3 is the watchdog, which MAME leaves off (MK3 resets with it on).
//----------------------------------------------------------------------------

reg   [2:0] io_map [0:15];
reg  [15:0] io_ctrl;
wire  [2:0] io_off = io_map[wa[3:0]];

reg         pic_wr, pic_rd, pic_rst;
reg   [7:0] pic_wdata;
wire  [7:0] pic_rdata;
wire        pic_status;

wunit_pic pic
(
	.clk       (clk),
	.reset     (reset),
	.year      (year),
	.pic_reset (pic_rst),
	.wr        (pic_wr),
	.wdata     (pic_wdata),
	.rd        (pic_rd),
	.rdata     (pic_rdata),
	.status    (pic_status)
);

// WWF WrestleMania's I/O orders (MAME wwfmania_io_0_w); 0 and anything
// above 4 leave the identity order. Entry n (3 bits at 3n) is where window
// word n goes. Written as whole 48-bit constants rather than an array
// inside the function, which Quartus 17 handles badly.
// identity order: word n -> n mod 8 (entry 15 first)
localparam [47:0] IO_IDENT = {3'd7, 3'd6, 3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0,
                              3'd7, 3'd6, 3'd5, 3'd4, 3'd3, 3'd2, 3'd1, 3'd0};

function automatic [47:0] io_order(input [15:0] sel);
	reg [47:0] m;
	begin
		m = IO_IDENT;
		case (sel)
			16'd1: begin m[4*3 +: 3] = 3'd0; m[8*3 +: 3] = 3'd1; m[1*3 +: 3]  = 3'd2; m[9*3 +: 3]  = 3'd3; m[2*3 +: 3] = 3'd4; end
			16'd2: begin m[8*3 +: 3] = 3'd0; m[2*3 +: 3] = 3'd1; m[4*3 +: 3]  = 3'd2; m[6*3 +: 3]  = 3'd3; m[1*3 +: 3] = 3'd4; end
			16'd3: begin m[1*3 +: 3] = 3'd0; m[8*3 +: 3] = 3'd1; m[2*3 +: 3]  = 3'd2; m[10*3 +: 3] = 3'd3; m[5*3 +: 3] = 3'd4; end
			16'd4: begin m[2*3 +: 3] = 3'd0; m[4*3 +: 3] = 3'd1; m[1*3 +: 3]  = 3'd2; m[7*3 +: 3]  = 3'd3; m[8*3 +: 3] = 3'd4; end
			default: ;
		endcase
		io_order = m;
	end
endfunction

wire [47:0] io_new = io_order(b_wdata);

//----------------------------------------------------------------------------
// Control register (MAME midwunit_control_w): bits 8-9 graphics ROM bank for
// CPU read-back, bit 11 selects what CPU VRAM accesses see (1: pixel bytes,
// 0: palette bytes)
//----------------------------------------------------------------------------

reg  [15:0] control;
wire        videobank = control[11];
always @(posedge clk) gfx_bank <= control[9:8];

//----------------------------------------------------------------------------
// DMA blitter
//----------------------------------------------------------------------------

reg         dma_reg_wr;
wire [15:0] dma_rdata;
wire        dma_wr_wait;
wire [15:0] dma_palette;

wire  [8:0] blt_row;
wire  [6:0] blt_lo, blt_hi, blt_raddr;
wire [63:0] blt_q;
wire  [7:0] blt_be;
wire        blt_req, blt_ack;
wire [24:3] dma_gfx_line;
wire [25:0] dma_map = gfx_map({dma_gfx_line, 3'd0}, gfx_slots);   // {empty, SDRAM byte}
wire        dma_gfx_req_i;
reg         dma_gfx_ack_i;
reg  [63:0] dma_gfx_data_i;

wunit_dma dma
(
	.clk         (clk),
	.reset       (reset),
	.fast        (dma_fast),

	.reg_wr      (dma_reg_wr),
	.reg_idx     (wa[3:0]),
	.reg_wdata   (b_wdata),
	.reg_rdata   (dma_rdata),
	.reg_wr_wait (dma_wr_wait),
	.palette_reg (dma_palette),

	.irq         (dma_irq),

	.gfx_line    (dma_gfx_line),
	.gfx_req     (dma_gfx_req_i),
	.gfx_ack     (dma_gfx_ack_i),
	.gfx_data    (dma_gfx_data_i),

	.blt_req     (blt_req),
	.blt_ack     (blt_ack),
	.blt_row     (blt_row),
	.blt_lo      (blt_lo),
	.blt_hi      (blt_hi),
	.blt_raddr   (blt_raddr),
	.blt_q       (blt_q),
	.blt_be      (blt_be)
);

// Blitter source lines through the slot map. A line in an empty slot is
// answered here with zeros and never reaches SDRAM.
reg         dsd_req;
reg  [24:3] dsd_addr;
reg         dg_busy;
reg         dg_empty;
assign dma_sd_req  = dsd_req;
assign dma_sd_addr = dsd_addr;

always @(posedge clk) begin
	if (reset) begin
		dma_gfx_ack_i <= dma_gfx_req_i;
		dsd_req       <= dma_sd_ack;
		dg_busy       <= 1'b0;
	end
	else if (!dg_busy) begin
		if (dma_gfx_req_i != dma_gfx_ack_i) begin
			dg_busy  <= 1'b1;
			dg_empty <= dma_map[25];
			if (!dma_map[25]) begin
				dsd_addr <= dma_map[24:3];
				dsd_req  <= ~dsd_req;
			end
		end
	end
	else if (dg_empty) begin
		dma_gfx_data_i <= 64'd0;
		dma_gfx_ack_i  <= dma_gfx_req_i;
		dg_busy        <= 1'b0;
	end
	else if (dsd_req == dma_sd_ack) begin
		dma_gfx_data_i <= dma_sd_data;
		dma_gfx_ack_i  <= dma_gfx_req_i;
		dg_busy        <= 1'b0;
	end
end

//----------------------------------------------------------------------------
// VRAM controller
//----------------------------------------------------------------------------

wire        disp_req, disp_ack;
wire  [8:0] disp_row;
wire        lb_we;
wire  [6:0] lb_addr;
wire [63:0] lb_data;

reg         srt_req;
wire        srt_ack;
reg         srt_wr;
reg  [18:0] srt_entry;
wire [15:0] srt_first;

reg         vcpu_req;
wire        vcpu_ack;
reg         vcpu_wr;
reg  [16:0] vcpu_qaddr;
reg         vcpu_half;
reg   [3:0] vcpu_be;
reg  [31:0] vcpu_wdata;
wire [31:0] vcpu_rdata;

wunit_vram vram
(
	.clk            (clk),
	.reset          (reset),

	.ddr_busy       (ddr_busy),
	.ddr_burstcnt   (ddr_burstcnt),
	.ddr_addr       (ddr_addr),
	.ddr_dout       (ddr_dout),
	.ddr_dout_ready (ddr_dout_ready),
	.ddr_rd         (ddr_rd),
	.ddr_din        (ddr_din),
	.ddr_be         (ddr_be),
	.ddr_we         (ddr_we),

	.disp_req       (disp_req),
	.disp_ack       (disp_ack),
	.disp_row       (disp_row),
	.lb_we          (lb_we),
	.lb_addr        (lb_addr),
	.lb_data        (lb_data),

	.srt_req        (srt_req),
	.srt_ack        (srt_ack),
	.srt_wr         (srt_wr),
	.srt_entry      (srt_entry),
	.srt_first      (srt_first),

	.blt_req        (blt_req),
	.blt_ack        (blt_ack),
	.blt_row        (blt_row),
	.blt_lo         (blt_lo),
	.blt_hi         (blt_hi),
	.blt_raddr      (blt_raddr),
	.blt_q          (blt_q),
	.blt_be         (blt_be),

	.cpu_req        (vcpu_req),
	.cpu_ack        (vcpu_ack),
	.cpu_wr         (vcpu_wr),
	.cpu_qaddr      (vcpu_qaddr),
	.cpu_half       (vcpu_half),
	.cpu_be         (vcpu_be),
	.cpu_wdata      (vcpu_wdata),
	.cpu_rdata      (vcpu_rdata)
);

wire vram_idle = (vcpu_req == vcpu_ack) && (srt_req == srt_ack);

//----------------------------------------------------------------------------
// Video (and the palette RAM, which lives there)
//----------------------------------------------------------------------------

reg         pal_we;
reg         pal_rreq;
wire        pal_rack;
wire [15:0] pal_rdata;

wunit_video video
(
	.clk          (clk),
	.reset        (reset),
	.ce_pix       (ce_pix_r),

	.hcount       (hcount),
	.heblnk       (heblnk),
	.hsblnk       (hsblnk),
	.hsync_in     (cpu_hs),
	.vsync_in     (cpu_vs),
	.hblank_in    (cpu_hb),
	.vblank_in    (cpu_vb),
	.disp_en      (disp_en),
	.line_start   (line_start & cpu_ce),     // one clock per CPU pulse
	.line_vis     (line_vis),
	.line_row     (line_row),
	.line_col     (line_col),

	.pal_we       (pal_we),
	.pal_addr     (wa[14:0]),
	.pal_wdata    (b_wdata),
	.pal_rreq     (pal_rreq),
	.pal_rack     (pal_rack),
	.pal_rdata    (pal_rdata),

	.disp_req     (disp_req),
	.disp_ack     (disp_ack),
	.disp_row     (disp_row),
	.lb_we        (lb_we),
	.lb_addr      (lb_addr),
	.lb_data      (lb_data),

	.r            (vid_r),
	.g            (vid_g),
	.b            (vid_b),
	.hsync        (vid_hs),
	.vsync        (vid_vs),
	.hblank       (vid_hb),
	.vblank       (vid_vb)
);

//----------------------------------------------------------------------------
// Bus cycle state machine
//----------------------------------------------------------------------------

localparam S_IDLE    = 4'd0;
localparam S_CMOS    = 4'd1;     // CMOS read data arrives
localparam S_ROM     = 4'd2;     // ROM cache tag check
localparam S_ROMFILL = 4'd3;     // waiting for the SDRAM line
localparam S_GFX     = 4'd4;     // graphics read-back: slot map
localparam S_GFXRD   = 4'd5;     // graphics read-back from SDRAM
localparam S_VRAMRD  = 4'd6;     // VRAM read: wait for the bridge, then the data
localparam S_VRAMWR  = 4'd7;     // VRAM write: wait for a free slot
localparam S_SRT     = 4'd8;     // shift-register transfer
localparam S_DMAWAIT = 4'd9;     // blitter start held while it is busy
localparam S_RAM     = 4'd10;    // RAM cache tag check (read)
localparam S_RAMFILL = 4'd11;    // RAM line from SDRAM
localparam S_RAMWR   = 4'd12;    // RAM write: cache update and SDRAM write
localparam S_PAL     = 4'd13;    // palette read
localparam S_GFXSD   = 4'd14;    // graphics read-back: SDRAM request

reg   [3:0] bstate;
reg         vram_sent;
reg  [24:0] gfx_b;               // region byte of a read-back
reg  [25:0] gfx_sd;              // {empty, SDRAM byte} of it

// The CPU holds a request until it sees mem_ack in a cpu_ce cycle, so the ack
// is held until then; while it is up, and for the one clock after it is
// taken (b_stale), the same request is not served again.
wire        req = (b_rd | b_wr) & ~mem_ack & ~b_stale;

// channel 1 is free: no line read or posted RAM write is outstanding
wire        sd_idle = (cpu_sd_req == cpu_sd_ack);

integer i;
always @(posedge clk) begin
	if (cpu_ce)
		mem_ack <= 1'b0;
	cmos_we    <= 1'b0;
	pal_we     <= 1'b0;
	rc_we      <= 1'b0;
	mc_we      <= 4'd0;
	mc_twe     <= 1'b0;
	snd_wr     <= 1'b0;
	snd_rd     <= 1'b0;
	dma_reg_wr <= 1'b0;
	pic_wr     <= 1'b0;
	pic_rd     <= 1'b0;
	pic_rst    <= 1'b0;

	if (reset) begin
		mem_ack     <= 1'b0;
		bstate      <= S_IDLE;
		cpu_sd_req  <= cpu_sd_ack;
		cpu_sd_we   <= 1'b0;
		vcpu_req    <= vcpu_ack;
		srt_req     <= srt_ack;
		pal_rreq    <= pal_rack;
		control     <= 16'd0;
		io_ctrl     <= 16'd0;
		snd_reset   <= 1'b0;
		cmos_en     <= 1'b0;
		c_clr       <= 1'b1;
		c_clr_a     <= 11'd0;
		vram_sent   <= 1'b0;
		for (i = 0; i < 16; i = i + 1)
			io_map[i] <= 3'(i);
	end
	else begin
		// clear both caches after reset
		if (c_clr) begin
			rc_we   <= 1'b1;
			rc_wa   <= c_clr_a;
			rc_wt   <= 7'd0;
			mc_twe  <= 1'b1;
			mc_wa   <= c_clr_a;
			mc_wt   <= 6'd0;
			c_clr_a <= c_clr_a + 11'd1;
			if (c_clr_a == 11'h7FF) c_clr <= 1'b0;
		end

		case (bstate)
			S_IDLE: if (req && !c_clr) begin
				if (b_srt) begin
					// VRAM shift-register transfer of two rows
					if (vram_idle) begin
						srt_wr    <= b_wr;
						srt_entry <= b_baddr[21:3];
						srt_req   <= ~srt_req;
						bstate    <= S_SRT;
					end
				end
				else if (b_wr) begin
					// ---- writes ----
					if (sel_vram)
						bstate <= S_VRAMWR;
					else if (sel_dma) begin
						dma_reg_wr <= 1'b1;
						bstate     <= S_DMAWAIT;
					end
					else if (sel_ram)
						bstate <= S_RAMWR;
					else begin
						mem_ack <= 1'b1;
						if (sel_cmos && cmos_en) begin
							cmos_we <= 1'b1;
							cmos_en <= 1'b0;
						end
						if (sel_cmosen)
							cmos_en <= 1'b1;
						if (sel_pal)
							pal_we <= 1'b1;
						if (sel_ctrl)
							control <= b_wdata;
						if (sel_sec && !wa[0]) begin
							pic_wr    <= 1'b1;
							pic_wdata <= b_wdata[7:0];
						end
						if (sel_snd && !wa[0]) begin
							snd_wr    <= 1'b1;
							snd_wdata <= b_wdata[7:0];
						end
						if (sel_io) begin
							if (io_remap && wa[14:0] == 15'd0) begin
								// WWF: word 0 (not its mirrors) picks the I/O
								// order and is not stored
								for (i = 0; i < 16; i = i + 1)
									io_map[i] <= io_new[i * 3 +: 3];
							end
							else if (io_off == 3'd1) begin
								io_ctrl   <= b_wdata;
								snd_reset <= b_wdata[4];
								pic_rst   <= b_wdata[5];
							end
						end
					end
				end
				else begin
					// ---- reads ----
					if (sel_cmos)
						bstate <= S_CMOS;
					else if (sel_ram)
						bstate <= S_RAM;
					else if (sel_rom)
						bstate <= S_ROM;
					else if (sel_pal) begin
						pal_rreq <= ~pal_rreq;
						bstate   <= S_PAL;
					end
					else if (sel_gfx) begin
						gfx_b  <= gfx_byte;
						bstate <= S_GFX;
					end
					else if (sel_vram)
						bstate <= S_VRAMRD;
					else begin
						mem_ack <= 1'b1;
						if (sel_dma)
							mem_rdata <= dma_rdata;
						else if (sel_ctrl)
							mem_rdata <= control;
						else if (sel_sec) begin
							mem_rdata <= {8'h00, pic_rdata};
							pic_rd    <= 1'b1;
						end
						else if (sel_snd) begin
							mem_rdata <= {8'h00, snd_rdata};
							snd_rd    <= 1'b1;
						end
						else if (sel_io)
							case (io_off)
								3'd0:    mem_rdata <= in0;
								3'd1:    mem_rdata <= in1;
								3'd2:    mem_rdata <= dsw;
								3'd3:    mem_rdata <= in2;
								3'd4:    mem_rdata <= {3'b000, pic_status, 12'h000} | snd_ctrl;
								default: mem_rdata <= 16'hFFFF;
							endcase
						else
							mem_rdata <= 16'h0000;
					end
				end
			end

			S_CMOS: begin
				// the read address went to the CMOS with the request
				mem_ack   <= 1'b1;
				mem_rdata <= cmos_q;
				bstate    <= S_IDLE;
			end

			S_PAL: if (pal_rreq == pal_rack) begin
				mem_ack   <= 1'b1;
				mem_rdata <= pal_rdata;
				bstate    <= S_IDLE;
			end

			S_ROM: begin
				if (rct_q == {1'b1, rom_line[16:11]}) begin
					mem_ack   <= 1'b1;
					mem_rdata <= rc_q[{wa[1:0], 4'b0000} +: 16];
					bstate    <= S_IDLE;
				end
				else if (sd_idle) begin
					cpu_sd_addr <= ROM_BASE[24:1] + {5'd0, rom_line, 2'b00};
					cpu_sd_we   <= 1'b0;
					cpu_sd_req  <= ~cpu_sd_req;
					bstate      <= S_ROMFILL;
				end
			end

			S_ROMFILL: if (sd_idle) begin
				rc_we     <= 1'b1;
				rc_wa     <= rom_line[10:0];
				rc_wd     <= cpu_sd_data;
				rc_wt     <= {1'b1, rom_line[16:11]};
				mem_ack   <= 1'b1;
				mem_rdata <= cpu_sd_data[{wa[1:0], 4'b0000} +: 16];
				bstate    <= S_IDLE;
			end

			S_RAM: begin
				if (mc_hit) begin
					mem_ack   <= 1'b1;
					mem_rdata <= mc_q[{wa[1:0], 4'b0000} +: 16];
					bstate    <= S_IDLE;
				end
				else if (sd_idle) begin
					cpu_sd_addr <= RAM_BASE[24:1] + {6'd0, ram_line, 2'b00};
					cpu_sd_we   <= 1'b0;
					cpu_sd_req  <= ~cpu_sd_req;
					bstate      <= S_RAMFILL;
				end
			end

			S_RAMFILL: if (sd_idle) begin
				mc_we     <= 4'b1111;
				mc_wa     <= ram_line[10:0];
				mc_wd     <= cpu_sd_data;
				mc_twe    <= 1'b1;
				mc_wt     <= {1'b1, ram_line[15:11]};
				mem_ack   <= 1'b1;
				mem_rdata <= cpu_sd_data[{wa[1:0], 4'b0000} +: 16];
				bstate    <= S_IDLE;
			end

			S_RAMWR: if (sd_idle) begin
				// the tag of this line was read with the request: update the
				// cached word on a hit, and post the SDRAM write
				if (mc_hit) begin
					mc_we[wa[1:0]] <= 1'b1;
					mc_wa          <= ram_line[10:0];
					mc_wd          <= {4{b_wdata}};
				end
				cpu_sd_addr <= RAM_BASE[24:1] + {6'd0, wa[17:0]};
				cpu_sd_we   <= 1'b1;
				cpu_sd_din  <= b_wdata;
				cpu_sd_req  <= ~cpu_sd_req;
				mem_ack     <= 1'b1;
				bstate      <= S_IDLE;
			end

			S_GFX: begin
				// slot map in a clock of its own (it follows an add)
				gfx_sd <= gfx_map(gfx_b, gfx_slots);
				bstate <= S_GFXSD;
			end

			S_GFXSD: begin
				if (gfx_sd[25]) begin
					mem_ack   <= 1'b1;               // empty slot: the region's 0
					mem_rdata <= 16'h0000;
					bstate    <= S_IDLE;
				end
				else if (sd_idle) begin
					cpu_sd_addr <= {gfx_sd[24:3], 2'b00};
					cpu_sd_we   <= 1'b0;
					cpu_sd_req  <= ~cpu_sd_req;
					bstate      <= S_GFXRD;
				end
			end

			S_GFXRD: if (sd_idle) begin
				mem_ack   <= 1'b1;
				mem_rdata <= cpu_sd_data[{gfx_b[2:1], 4'b0000} +: 16];
				bstate    <= S_IDLE;
			end

			S_VRAMWR: if (vram_idle) begin
				// two entries per CPU word: the pixel bytes carry the DMA
				// palette register along, the palette bytes leave pixels alone
				vcpu_wr    <= 1'b1;
				vcpu_qaddr <= wa[17:1];
				vcpu_half  <= wa[0];
				if (videobank) begin
					vcpu_be    <= 4'b1111;
					vcpu_wdata <= {dma_palette[15:8], b_wdata[15:8], dma_palette[7:0], b_wdata[7:0]};
				end
				else begin
					vcpu_be    <= 4'b1010;
					vcpu_wdata <= {b_wdata[15:8], 8'h00, b_wdata[7:0], 8'h00};
				end
				vcpu_req <= ~vcpu_req;
				mem_ack  <= 1'b1;                // posted
				bstate   <= S_IDLE;
			end

			S_VRAMRD: begin
				if (!vram_sent) begin
					if (vram_idle) begin
						vcpu_wr    <= 1'b0;
						vcpu_qaddr <= wa[17:1];
						vcpu_half  <= wa[0];
						vcpu_req   <= ~vcpu_req;
						vram_sent  <= 1'b1;
					end
				end
				else if (vcpu_req == vcpu_ack) begin
					vram_sent <= 1'b0;
					mem_ack   <= 1'b1;
					mem_rdata <= videobank ? {vcpu_rdata[23:16], vcpu_rdata[7:0]} : {vcpu_rdata[31:24], vcpu_rdata[15:8]};
					bstate    <= S_IDLE;
				end
			end

			S_SRT: if (srt_req == srt_ack) begin
				mem_ack   <= 1'b1;
				mem_rdata <= srt_first;
				bstate    <= S_IDLE;
			end

			S_DMAWAIT: begin
				// keep offering the write until the blitter takes it
				if (dma_wr_wait)
					dma_reg_wr <= 1'b1;
				else begin
					mem_ack <= 1'b1;
					bstate  <= S_IDLE;
				end
			end

			default: bstate <= S_IDLE;
		endcase
	end
end

endmodule
