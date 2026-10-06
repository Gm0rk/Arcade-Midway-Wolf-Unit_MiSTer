//============================================================================
//  Midway Wolf Unit for MiSTer
//
//  Top level (emu): HPS interface, ROM loading, memories, per-game
//  configuration and inputs, video output with CRT Adjust, audio.
//
//  Clocks: everything runs from one 96 MHz clock (clk_sys). The 34010 and
//  the pixel clock (8 MHz) are clock enables derived from it.
//
//  Memory:
//    SDRAM  program ROM, DCS sound ROMs, security PIC, graphics ROM, and the
//           512 KB main RAM (in the top 512 KB of the module)
//    DDR3   the 1 MB frame store (VRAM)
//    BRAM   CMOS, palette, caches and line buffers
//
//  Sound: the DCS board (ADSP-2105) is not in this build yet. dcs_stub.sv
//  answers the 34010 through the same latches so the games run, silently.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  Copyright (C) 2026 Gm0rk
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1        = 0;
assign VGA_SCALER    = 0;
assign VGA_DISABLE   = 0;
assign HDMI_FREEZE   = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////
// OSD
//////////////////////////////////////////////////////////////////

`include "build_id.v"
localparam CONF_STR = {
	"A.MIDWAYW;;",
	"-;",
	"P1,Video Settings;",
	"P1-;",
	"P1O[2:1],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1O[7:6],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1O[15:14],Video Timing,Native 54.7Hz,57Hz,60Hz;",
	"P1O[101],CRT Adjust,Off,On;",
	"H1P1O[102],CRT Auto-Width,Off,On;",
	"H1P1O[100:96],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[85:79],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[78:74],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P2,Controls;",
	"P2-;",
	"P2O[9],Service Mode,Off,On;",
	"P2T[12],Service Credit;",
	"P2T[13],Tilt;",
	"-;",
	"DIP;",
	"-;",
	"O[8],Pause when OSD is open,On,Off;",
	"-;",
	"R[0],Reset;",
	"J1,B1,B2,B3,B4,B5,B6,Start,Coin,Test,Pause;",
	"jn,A,B,X,Y,L,R,Start,Select,,;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire        direct_video;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [31:0] joy0, joy1, joy2, joy3;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire        ioctl_rd;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire [15:0] ioctl_din;
reg         ioctl_wait;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(1), .WIDE(1)) hps_io
(
	.clk_sys             (clk_sys),
	.HPS_BUS             (HPS_BUS),
	.EXT_BUS             (),
	.gamma_bus           (gamma_bus),

	.forced_scandoubler  (forced_scandoubler),
	.direct_video        (direct_video),

	.buttons             (buttons),
	.status              (status),
	.status_menumask     ({14'd0, ~status[101], 1'b0}),

	.ps2_key             (ps2_key),

	.joystick_0          (joy0),
	.joystick_1          (joy1),
	.joystick_2          (joy2),
	.joystick_3          (joy3),

	.ioctl_download      (ioctl_download),
	.ioctl_upload        (ioctl_upload),
	.ioctl_upload_req    (ioctl_upload_req),
	.ioctl_upload_index  (8'd2),
	.ioctl_index         (ioctl_index),
	.ioctl_wr            (ioctl_wr),
	.ioctl_rd            (ioctl_rd),
	.ioctl_addr          (ioctl_addr),
	.ioctl_dout          (ioctl_dout),
	.ioctl_din           (ioctl_din),
	.ioctl_wait          (ioctl_wait)
);

//////////////////////////////////////////////////////////////////
// Clocks and reset
//////////////////////////////////////////////////////////////////

wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk   (CLK_50M),
	.rst      (1'b0),
	.outclk_0 (clk_sys),
	.locked   (pll_locked)
);

wire rom_download = ioctl_download && (ioctl_index == 16'd0);
reg  rom_loaded = 1'b0;
reg  rom_was_dl;

// The NVRAM file follows the ROMs in a separate transfer. Hold the board in
// reset for half a second after any download so the game never boots on an
// empty CMOS that is about to be replaced.
reg  [25:0] boot_hold;
always @(posedge clk_sys) begin
	if (ioctl_download)
		boot_hold <= 26'd48_000_000;
	else if (boot_hold != 26'd0)
		boot_hold <= boot_hold - 26'd1;
end

wire ram_clearing;
wire reset = RESET | status[0] | buttons[1] | rom_download | ~rom_loaded | (boot_hold != 26'd0) | ram_clearing;

//////////////////////////////////////////////////////////////////
// Game configuration
//
// MRA ROM index 1: byte 0 the game id, bytes 1-8 where each 4 MB slot of
// MAME's graphics region went in the ROM image (FF: not present).
//////////////////////////////////////////////////////////////////

localparam G_MK3      = 3'd0;    // Mortal Kombat 3
localparam G_UMK3     = 3'd1;    // Ultimate Mortal Kombat 3
localparam G_WWF      = 3'd2;    // WWF WrestleMania
localparam G_OPENICE  = 3'd3;    // 2 On 2 Open Ice Challenge
localparam G_NBAHANGT = 3'd4;    // NBA Hangtime, NBA Maximum Hangtime
localparam G_RMPGWT   = 3'd5;    // Rampage World Tour

reg   [2:0] game_id;
reg  [63:0] gfx_slots;
reg  [11:0] cfg_year;            // the game's year (security PIC date)
reg         cfg_io_remap;        // WWF: I/O order chosen by the game
reg         cfg_pal_ring;        // UMK3: MAME's palette-ring penalty
reg   [1:0] cfg_layout;
reg   [7:0] cfg_dcs_ver;         // DCS ROM version byte (sound placeholder)
reg  [19:0] cfg_dcs_dly;         // and the time it took MAME's DCS to send it

localparam L_MK = 2'd0, L_WWF = 2'd1, L_4P = 2'd2, L_3P = 2'd3;

// DCS version replies and delays from MAME traces (tools/lua/ref_trace.lua)
always @(posedge clk_sys) begin
	cfg_year     <= 12'd1994;
	cfg_io_remap <= 1'b0;
	cfg_pal_ring <= 1'b0;
	cfg_layout   <= L_MK;
	cfg_dcs_ver  <= 8'h01;
	cfg_dcs_dly  <= 20'd584_560;     // 6.09 ms
	case (game_id)
		G_MK3:      ;
		G_UMK3:     begin cfg_dcs_ver <= 8'h02; cfg_dcs_dly <= 20'd587_480; cfg_pal_ring <= 1'b1; end
		G_WWF:      begin cfg_year <= 12'd1995; cfg_io_remap <= 1'b1; cfg_layout <= L_WWF;
		                  cfg_dcs_dly <= 20'd33_690; end
		G_OPENICE:  begin cfg_year <= 12'd1995; cfg_layout <= L_4P;
		                  cfg_dcs_ver <= 8'h12; cfg_dcs_dly <= 20'd584_090; end
		G_NBAHANGT: begin cfg_year <= 12'd1996; cfg_layout <= L_4P; cfg_dcs_dly <= 20'd27_600; end
		G_RMPGWT:   begin cfg_year <= 12'd1997; cfg_layout <= L_3P; cfg_dcs_dly <= 20'd586_860; end
		default: ;
	endcase
end

//////////////////////////////////////////////////////////////////
// Downloads: ROMs (index 0), game configuration (1), NVRAM (2), DIP
// switches (254)
//
// ROM layout (byte addresses, the same in the MRA and in SDRAM):
//   0x000000  program, 1 MB (16-bit little endian)
//   0x100000  DCS sound ROMs, 4 x 1 MB
//   0x500000  security PIC program, 8 KB
//   0x502000  graphics, the used 4 MB slots of MAME's video region
// Main RAM is the top 512 KB of the SDRAM (0x1F80000); it is cleared after
// each ROM download, as MAME starts with it zeroed.
//////////////////////////////////////////////////////////////////

reg  [63:0] dsw;
reg   [7:0] cfg [0:9];               // the configuration bytes as they arrive

always @(posedge clk_sys) begin
	if (ioctl_wr && ioctl_index == 16'd1 && ioctl_addr < 27'd10) begin
		cfg[ioctl_addr[3:0]]         <= ioctl_dout[7:0];
		cfg[ioctl_addr[3:0] + 4'd1]  <= ioctl_dout[15:8];
	end
	if (ioctl_wr && ioctl_index == 16'd254 && ioctl_addr[26:3] == 24'd0)
		dsw[{ioctl_addr[2:1], 4'b0000} +: 16] <= ioctl_dout;

	game_id   <= cfg[0][2:0];
	gfx_slots <= {cfg[8], cfg[7], cfg[6], cfg[5], cfg[4], cfg[3], cfg[2], cfg[1]};
end

reg  [24:1] sd_wr_addr;
reg  [15:0] sd_wr_data;
reg         sd_wr_req;
wire        sd_wr_ack;

// main RAM clear after a ROM download: 256 K zero words
reg         ram_clr;
reg  [18:1] ram_clr_a;
assign ram_clearing = ram_clr;

always @(posedge clk_sys) begin
	rom_was_dl <= rom_download;
	if (rom_download) begin
		rom_loaded <= 1'b0;
		ram_clr    <= 1'b0;
	end
	else if (rom_was_dl) begin
		rom_loaded <= 1'b1;
		ram_clr    <= 1'b1;
		ram_clr_a  <= 18'd0;
	end

	if (ioctl_wr && rom_download) begin
		sd_wr_addr <= ioctl_addr[24:1];
		sd_wr_data <= ioctl_dout;
		sd_wr_req  <= ~sd_wr_req;
		ioctl_wait <= 1'b1;
	end
	else if (sd_wr_req == sd_wr_ack) begin
		ioctl_wait <= 1'b0;
		if (ram_clr && !rom_was_dl) begin
			sd_wr_addr <= {6'b111111, ram_clr_a};          // 0x1F80000 + word * 2
			sd_wr_data <= 16'h0000;
			sd_wr_req  <= ~sd_wr_req;
			ram_clr_a  <= ram_clr_a + 18'd1;
			if (ram_clr_a == 18'h3FFFF) ram_clr <= 1'b0;
		end
	end
end

// NVRAM (CMOS): loaded through port B of the CMOS RAM, cleared when a new
// ROM set arrives so a game never sees another game's settings
reg  [14:0] cmos_clr_addr;
reg         cmos_clr;
reg         cmos_dirty;
wire [15:0] nv_dout;
wire        cmos_write;

wire        nv_dl = ioctl_download && ioctl_index == 16'd2;

always @(posedge clk_sys) begin
	if (rom_download && !rom_was_dl) begin
		cmos_clr      <= 1'b1;
		cmos_clr_addr <= 15'd0;
	end
	else if (cmos_clr) begin
		cmos_clr_addr <= cmos_clr_addr + 15'd1;
		if (cmos_clr_addr == 15'd24575) cmos_clr <= 1'b0;
	end

	// ask the HPS to save once the game has changed its CMOS
	if (cmos_write) cmos_dirty <= 1'b1;
	else if (ioctl_upload && ioctl_index == 16'd2) cmos_dirty <= 1'b0;
end

assign ioctl_upload_req = cmos_dirty;
assign ioctl_din        = nv_dout;

wire [14:0] nv_addr = cmos_clr ? cmos_clr_addr : ioctl_addr[15:1];
wire        nv_we   = cmos_clr | (nv_dl & ioctl_wr & (ioctl_addr[16:1] < 16'd24576));
wire [15:0] nv_din  = cmos_clr ? 16'h0000 : ioctl_dout;

//////////////////////////////////////////////////////////////////
// Inputs
//
// Joystick bits: 0 R, 1 L, 2 D, 3 U, 4-9 B1-B6, 10 Start, 11 Coin, 12 Test,
// 13 Pause. Ports are active low. The layouts follow MAME's input ports
// (midwunit.cpp): IN0 holds players 1 and 2 (stick and three buttons each),
// IN1 the fighting games' other three buttons or players 3 and 4, IN2 the
// coins, starts and cabinet switches.
//
// Service Credit and Tilt are not on the controllers: they are OSD items
// (Controls page), handled in "OSD service credit and tilt" below.
//////////////////////////////////////////////////////////////////

// {R, L, D, U} as MAME orders them (bit 0 up, 1 down, 2 left, 3 right)
function automatic [3:0] udlr(input [31:0] j);
	udlr = {j[0], j[1], j[2], j[3]};
endfunction

// the three IN0 / IN1 buttons of the team sports and Rampage: MAME's
// button 2 (shoot / punch) at bit 4, button 3 (pass / kick) at bit 5,
// button 1 (turbo / jump) at bit 6. MiSTer B1-B3 are buttons 1-3.
function automatic [6:0] team(input [31:0] j);
	team = {j[4], j[6], j[5], udlr(j)};
endfunction

wire       test_sw = status[9] | joy0[12] | joy1[12];
reg  [3:0] svc_cnt  = 4'd0;                 // service credit held while non-zero
reg  [3:0] tilt_cnt = 4'd0;                 // slam tilt held while non-zero
wire       svc_sw  = |svc_cnt;
wire       tilt_sw = |tilt_cnt;

// active-high port images, inverted at the end
reg  [15:0] in0, in1, in2;
always @(*) begin
	in0 = 16'h0000;
	in1 = 16'h0000;
	in2 = 16'h0000;

	// IN2: common to every game
	in2[0]  = joy0[11];               // coin 1
	in2[1]  = joy1[11];               // coin 2
	in2[2]  = joy0[10];               // start 1
	in2[3]  = tilt_sw;                // tilt (slam switch)
	in2[4]  = test_sw;                // test
	in2[5]  = joy1[10];               // start 2
	in2[6]  = svc_sw;                 // service credit
	in2[7]  = joy2[11];               // coin 3
	in2[8]  = joy3[11];               // coin 4
	in2[9]  = joy2[10];               // start 3
	in2[10] = joy3[10];               // start 4

	case (cfg_layout)
		L_MK: begin
			// B1 high punch, B2 block, B3 high kick, B4 low punch, B5 low kick, B6 run
			in0[3:0]  = udlr(joy0);  in0[6:4]  = joy0[6:4];
			in0[11:8] = udlr(joy1);  in0[14:12] = joy1[6:4];
			in1[2:0]  = joy0[9:7];
			in1[6:4]  = joy1[9:7];
		end
		L_WWF: begin
			// B1 punch, B2 defense, B3 power punch, B4 kick, B5 power kick
			in0[3:0]  = udlr(joy0);  in0[6:4]  = joy0[6:4];
			in0[11:8] = udlr(joy1);  in0[14:12] = joy1[6:4];
			in1[1:0]  = joy0[8:7];
			in1[5:4]  = joy1[8:7];
		end
		L_4P: begin
			// B1 turbo, B2 shoot / block, B3 pass / steal; four players
			in0[6:0]  = team(joy0);
			in0[14:8] = team(joy1);
			in1[6:0]  = team(joy2);
			in1[14:8] = team(joy3);
		end
		default: begin
			// Rampage: B1 jump, B2 punch, B3 kick; three players
			in0[6:0]  = team(joy0);
			in0[14:8] = team(joy1);
			in1[6:0]  = team(joy2);
		end
	endcase
end

//////////////////////////////////////////////////////////////////
// Pause
//////////////////////////////////////////////////////////////////

reg  pause_toggle;
reg  pause_btn_d;
always @(posedge clk_sys) begin
	pause_btn_d <= joy0[13] | joy1[13];
	if (reset) pause_toggle <= 1'b0;
	else if ((joy0[13] | joy1[13]) & ~pause_btn_d) pause_toggle <= ~pause_toggle;
end

wire pause = pause_toggle | (OSD_STATUS & ~status[8]);

//////////////////////////////////////////////////////////////////
// Wolf Unit board
//////////////////////////////////////////////////////////////////

wire [24:1] cpu_sd_addr;
wire [24:3] dma_sd_addr, snd_sd_addr;
wire        cpu_sd_req, dma_sd_req, snd_sd_req;
wire        cpu_sd_ack, dma_sd_ack, snd_sd_ack, sp_sd_ack;
wire [63:0] cpu_sd_data, dma_sd_data, snd_sd_data;
wire        cpu_sd_we;
wire [15:0] cpu_sd_din;

wire        snd_wr, snd_rd, snd_reset;
wire  [7:0] snd_wdata, snd_rdata;
wire [15:0] snd_ctrl;

wire        ce_pix;
wire  [7:0] core_r, core_g, core_b;
wire        core_hs, core_vs, core_hb, core_vb;

//////////////////////////////////////////////////////////////////
// OSD service credit and tilt
//
// Each OSD item is a trigger: the HPS sets its status bit briefly when it
// is selected. The matching cabinet switch is then held closed for 8
// frames (about 150 ms), long enough for the game's switch scan to accept
// it, like a real coin or slam switch. Frames are counted only while the
// game runs, so with "Pause when OSD is open" the switch closes when the
// OSD is shut.
//////////////////////////////////////////////////////////////////

reg  [1:0] osd_sw_d;
reg        osd_vb_d;
wire       osd_frame = core_vb & ~osd_vb_d & ~pause;   // start of a running frame

always @(posedge clk_sys) begin
	osd_sw_d <= status[13:12];
	osd_vb_d <= core_vb;

	if (reset) begin
		svc_cnt  <= 4'd0;
		tilt_cnt <= 4'd0;
	end
	else begin
		if (status[12] & ~osd_sw_d[0])   svc_cnt  <= 4'd8;
		else if (osd_frame && svc_sw)    svc_cnt  <= svc_cnt - 4'd1;

		if (status[13] & ~osd_sw_d[1])   tilt_cnt <= 4'd8;
		else if (osd_frame && tilt_sw)   tilt_cnt <= tilt_cnt - 4'd1;
	end
end

midway_wunit board
(
	.clk            (clk_sys),
	.reset          (reset),
	.pause          (pause),

	.gfx_slots      (gfx_slots),
	.year           (cfg_year),
	.io_remap       (cfg_io_remap),
	.pal_ring       (cfg_pal_ring),
	.vtiming        (status[15:14]),    // 54.7 / 57 / 60 Hz frames (see midway_wunit.sv)

	.in0            (~in0),
	.in1            (~in1),
	.dsw            (dsw[15:0]),
	.in2            (~in2),

	.snd_wr         (snd_wr),
	.snd_wdata      (snd_wdata),
	.snd_rd         (snd_rd),
	.snd_rdata      (snd_rdata),
	.snd_ctrl       (snd_ctrl),
	.snd_reset      (snd_reset),

	.cpu_sd_addr    (cpu_sd_addr),
	.cpu_sd_req     (cpu_sd_req),
	.cpu_sd_ack     (cpu_sd_ack),
	.cpu_sd_data    (cpu_sd_data),
	.cpu_sd_we      (cpu_sd_we),
	.cpu_sd_din     (cpu_sd_din),

	.dma_sd_addr    (dma_sd_addr),
	.dma_sd_req     (dma_sd_req),
	.dma_sd_ack     (dma_sd_ack),
	.dma_sd_data    (dma_sd_data),

	.ddr_busy       (DDRAM_BUSY),
	.ddr_burstcnt   (DDRAM_BURSTCNT),
	.ddr_addr       (DDRAM_ADDR),
	.ddr_dout       (DDRAM_DOUT),
	.ddr_dout_ready (DDRAM_DOUT_READY),
	.ddr_rd         (DDRAM_RD),
	.ddr_din        (DDRAM_DIN),
	.ddr_be         (DDRAM_BE),
	.ddr_we         (DDRAM_WE),

	.nv_addr        (nv_addr),
	.nv_we          (nv_we),
	.nv_din         (nv_din),
	.nv_dout        (nv_dout),
	.cmos_write     (cmos_write),

	.ce_pix         (ce_pix),
	.vid_r          (core_r),
	.vid_g          (core_g),
	.vid_b          (core_b),
	.vid_hs         (core_hs),
	.vid_vs         (core_vs),
	.vid_hb         (core_hb),
	.vid_vb         (core_vb),

	.dbg_pc         (),
	.dbg_retire     ()
);

assign DDRAM_CLK = clk_sys;

//////////////////////////////////////////////////////////////////
// Sound board (placeholder until the DCS board is in)
//////////////////////////////////////////////////////////////////

dcs_stub sound
(
	.clk       (clk_sys),
	.reset     (reset),
	.dcs_reset (snd_reset),

	.dcs_version (cfg_dcs_ver),
	.dcs_delay   (cfg_dcs_dly),

	.host_wr   (snd_wr),
	.host_data (snd_wdata),
	.host_rd   (snd_rd),
	.host_q    (snd_rdata),
	.control   (snd_ctrl)
);

assign snd_sd_req = snd_sd_ack;        // no sound ROM reads yet

assign AUDIO_L   = 16'd0;
assign AUDIO_R   = 16'd0;
assign AUDIO_S   = 1'b1;
assign AUDIO_MIX = 2'd0;

//////////////////////////////////////////////////////////////////
// SDRAM: sound board first (it cannot wait long), then the 34010 (program
// ROM, main RAM, graphics read-back), then the blitter; channel 3 is spare.
// ROM downloads and the main RAM clear use the write port.
//////////////////////////////////////////////////////////////////

sdram sdram
(
	.init        (~pll_locked),
	.clk         (clk_sys),

	.SDRAM_DQ    (SDRAM_DQ),
	.SDRAM_A     (SDRAM_A),
	.SDRAM_DQML  (SDRAM_DQML),
	.SDRAM_DQMH  (SDRAM_DQMH),
	.SDRAM_BA    (SDRAM_BA),
	.SDRAM_nCS   (SDRAM_nCS),
	.SDRAM_nWE   (SDRAM_nWE),
	.SDRAM_nRAS  (SDRAM_nRAS),
	.SDRAM_nCAS  (SDRAM_nCAS),
	.SDRAM_CKE   (SDRAM_CKE),
	.SDRAM_CLK   (SDRAM_CLK),

	.ch0_addr    (22'd0),
	.ch0_req     (snd_sd_req),
	.ch0_ack     (snd_sd_ack),
	.ch0_dout    (snd_sd_data),

	.ch1_addr    (cpu_sd_addr),
	.ch1_req     (cpu_sd_req),
	.ch1_ack     (cpu_sd_ack),
	.ch1_dout    (cpu_sd_data),
	.ch1_we      (cpu_sd_we),
	.ch1_din     (cpu_sd_din),
	.ch1_be      (2'b11),

	.ch2_addr    (dma_sd_addr),
	.ch2_req     (dma_sd_req),
	.ch2_ack     (dma_sd_ack),
	.ch2_dout    (dma_sd_data),

	.ch3_addr    (22'd0),
	.ch3_req     (sp_sd_ack),
	.ch3_ack     (sp_sd_ack),
	.ch3_dout    (),

	.wr_addr     (sd_wr_addr),
	.wr_data     (sd_wr_data),
	.wr_be       (2'b11),
	.wr_req      (sd_wr_req),
	.wr_ack      (sd_wr_ack)
);

//////////////////////////////////////////////////////////////////
// Video
//////////////////////////////////////////////////////////////////

// ---- analog CRT stage: centred sync, CRT Adjust, Auto-Width (rtl/video/wunit_crt.sv) ----
//
// The analog sync is always the centred one (picture in the middle of a
// standard 15 kHz line and frame); HDMI sees the same picture either way.
// CRT Adjust is off while a scandoubler effect is on (its read rate assumes
// native 15 kHz).

wire scandoubler = (status[5:3] != 3'd0) || forced_scandoubler;

wire       c_hs, c_vs;
wire       crt_on, rd_ce, de_osd;
wire [7:0] str_r, str_g, str_b;
wire       str_hs, str_vs;

wunit_crt wunit_crt
(
	.clk         (clk_sys),
	.ce_pix      (ce_pix),

	.crt_en      (status[101]),
	.autow       (status[102]),
	.scandoubler (scandoubler),
	.hsize_osd   (status[100:96]),
	.hpos_osd    (status[85:79]),
	.vshift_osd  (status[78:74]),

	.r_in        (core_r),
	.g_in        (core_g),
	.b_in        (core_b),
	.hs_in       (core_hs),
	.vs_in       (core_vs),
	.hb_in       (core_hb),
	.vb_in       (core_vb),

	.c_hs        (c_hs),
	.c_vs        (c_vs),

	.crt_on      (crt_on),
	.rd_ce       (rd_ce),
	.r_out       (str_r),
	.g_out       (str_g),
	.b_out       (str_b),
	.hs_out      (str_hs),
	.vs_out      (str_vs),
	.de_osd      (de_osd),

	.centred     (),
	.pic_dots    (),
	.h_eff       (),
	.str_act     ()
);

// ---- scandoubler / gamma (native stream) ----

wire [7:0] mix_r, mix_g, mix_b;
wire       mix_hs, mix_vs, mix_de;
wire [1:0] mix_sl;
wire       mix_ce;

arcade_video #(.WIDTH(512), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video          (clk_sys),
	.ce_pix             (ce_pix),

	.RGB_in             ({core_r, core_g, core_b}),
	.HBlank             (core_hb),
	.VBlank             (core_vb),
	.HSync              (c_hs),               // centred sync
	.VSync              (c_vs),

	.CLK_VIDEO          (CLK_VIDEO),
	.CE_PIXEL           (mix_ce),
	.VGA_R              (mix_r),
	.VGA_G              (mix_g),
	.VGA_B              (mix_b),
	.VGA_HS             (mix_hs),
	.VGA_VS             (mix_vs),
	.VGA_DE             (mix_de),
	.VGA_SL             (mix_sl),

	.fx                 (status[5:3]),
	.forced_scandoubler (forced_scandoubler),
	.gamma_bus          (gamma_bus)
);

assign CE_PIXEL = crt_on ? rd_ce  : mix_ce;
assign VGA_R    = crt_on ? str_r  : mix_r;
assign VGA_G    = crt_on ? str_g  : mix_g;
assign VGA_B    = crt_on ? str_b  : mix_b;
assign VGA_HS   = crt_on ? str_hs : mix_hs;
assign VGA_VS   = crt_on ? str_vs : mix_vs;
assign VGA_SL   = crt_on ? 2'd0   : mix_sl;

wire [1:0] ar = status[2:1];

video_freak video_freak
(
	.CLK_VIDEO   (CLK_VIDEO),
	.CE_PIXEL    (CE_PIXEL),
	.VGA_VS      (VGA_VS),
	.HDMI_WIDTH  (HDMI_WIDTH),
	.HDMI_HEIGHT (HDMI_HEIGHT),
	.VGA_DE      (VGA_DE),
	.VIDEO_ARX   (VIDEO_ARX),
	.VIDEO_ARY   (VIDEO_ARY),

	.VGA_DE_IN   (crt_on ? de_osd : mix_de),
	.ARX         ((ar == 2'd0) ? 12'd4 : ({10'd0, ar} - 12'd1)),
	.ARY         ((ar == 2'd0) ? 12'd3 : 12'd0),
	.CROP_SIZE   (12'd0),
	.CROP_OFF    (5'd0),
	.SCALE       ({1'b0, status[7:6]})
);

//////////////////////////////////////////////////////////////////

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = rom_download ? act_cnt[23] : 1'b0;

endmodule
