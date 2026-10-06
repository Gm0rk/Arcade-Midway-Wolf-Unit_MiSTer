//============================================================================
//  sim_top - the Wolf Unit board as the simulator sees it
//
//  The board (rtl/midway_wunit.sv), the sound board placeholder and the real
//  SDRAM controller (rtl/sdram.sv, with its data bus split for simulation).
//  The C++ side (tb_board.cpp) models the SDRAM chip on its pins, the DDR3
//  bridge on its Avalon port, and captures the video. ROM downloads are
//  skipped: the C++ side writes the ROM image straight into its SDRAM model.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module sim_top
(
	input             clk,
	input             reset,
	input             sdram_init,

	// configuration (what the MRA's rom index 1 and the DIP switches give)
	input      [63:0] gfx_slots,
	input      [11:0] year,
	input             io_remap,
	input       [7:0] dcs_version,
	input      [19:0] dcs_delay,
	input      [15:0] in0,
	input      [15:0] in1,
	input      [15:0] dsw,
	input      [15:0] in2,

	// SDRAM pins
	input      [15:0] SDRAM_DQ_I,
	output     [15:0] SDRAM_DQ_O,
	output            SDRAM_DQ_OE,
	output     [12:0] SDRAM_A,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output      [1:0] SDRAM_BA,
	output            SDRAM_nCS,
	output            SDRAM_nWE,
	output            SDRAM_nRAS,
	output            SDRAM_nCAS,

	// DDR3 bridge
	input             ddr_busy,
	output      [7:0] ddr_burstcnt,
	output     [28:0] ddr_addr,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	output            ddr_rd,
	output     [63:0] ddr_din,
	output      [7:0] ddr_be,
	output            ddr_we,

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

wire [24:1] cpu_sd_addr;
wire [24:3] dma_sd_addr;
wire        cpu_sd_req, dma_sd_req, snd_sd_ack, sp_sd_ack;
wire        cpu_sd_ack, dma_sd_ack;
wire [63:0] cpu_sd_data, dma_sd_data;
wire        cpu_sd_we;
wire [15:0] cpu_sd_din;

wire        snd_wr, snd_rd, snd_reset;
wire  [7:0] snd_wdata, snd_rdata;
wire [15:0] snd_ctrl;

midway_wunit board
(
	.clk            (clk),
	.reset          (reset),
	.pause          (1'b0),

	.gfx_slots      (gfx_slots),
	.year           (year),
	.io_remap       (io_remap),
	.vtiming        (2'd0),

	.in0            (in0),
	.in1            (in1),
	.dsw            (dsw),
	.in2            (in2),

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

	.ddr_busy       (ddr_busy),
	.ddr_burstcnt   (ddr_burstcnt),
	.ddr_addr       (ddr_addr),
	.ddr_dout       (ddr_dout),
	.ddr_dout_ready (ddr_dout_ready),
	.ddr_rd         (ddr_rd),
	.ddr_din        (ddr_din),
	.ddr_be         (ddr_be),
	.ddr_we         (ddr_we),

	.nv_addr        (15'd0),
	.nv_we          (1'b0),
	.nv_din         (16'd0),
	.nv_dout        (),
	.cmos_write     (),

	.ce_pix         (ce_pix),
	.vid_r          (vid_r),
	.vid_g          (vid_g),
	.vid_b          (vid_b),
	.vid_hs         (vid_hs),
	.vid_vs         (vid_vs),
	.vid_hb         (vid_hb),
	.vid_vb         (vid_vb),

	.dbg_pc         (dbg_pc),
	.dbg_retire     (dbg_retire)
);

dcs_stub sound
(
	.clk         (clk),
	.reset       (reset),
	.dcs_reset   (snd_reset),
	.dcs_version (dcs_version),
	.dcs_delay   (dcs_delay),
	.host_wr     (snd_wr),
	.host_data   (snd_wdata),
	.host_rd     (snd_rd),
	.host_q      (snd_rdata),
	.control     (snd_ctrl)
);

sdram sdram
(
	.init        (sdram_init),
	.clk         (clk),

	.SDRAM_DQ_I  (SDRAM_DQ_I),
	.SDRAM_DQ_O  (SDRAM_DQ_O),
	.SDRAM_DQ_OE (SDRAM_DQ_OE),
	.SDRAM_A     (SDRAM_A),
	.SDRAM_DQML  (SDRAM_DQML),
	.SDRAM_DQMH  (SDRAM_DQMH),
	.SDRAM_BA    (SDRAM_BA),
	.SDRAM_nCS   (SDRAM_nCS),
	.SDRAM_nWE   (SDRAM_nWE),
	.SDRAM_nRAS  (SDRAM_nRAS),
	.SDRAM_nCAS  (SDRAM_nCAS),
	.SDRAM_CKE   (),
	.SDRAM_CLK   (),

	.ch0_addr    (22'd0),
	.ch0_req     (snd_sd_ack),
	.ch0_ack     (snd_sd_ack),
	.ch0_dout    (),

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

	.wr_addr     (24'd0),
	.wr_data     (16'd0),
	.wr_be       (2'b11),
	.wr_req      (1'b0),
	.wr_ack      ()
);

endmodule
