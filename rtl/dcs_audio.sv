//============================================================================
//  Midway DCS sound board, ROM-based, 8K RAM (Wolf Unit)
//
//  MAME mame/shared/dcs.cpp, dcs_audio_8k_device (REV_DCS1): an ADSP-2105
//  at 10 MHz (rtl/adsp2105), 8K words of external RAM, the sound ROMs (up to
//  4 x 1 MB, 8 bits wide) behind a bank register, the latches to the 34010
//  and a 16-bit DAC on the DSP's SPORT1.
//
//  DSP memory map (dcs_8k_program_map / dcs_8k_data_map):
//    program 0000-03FF  ADSP-2105 internal RAM (in the core)
//            0800-1FFF  external RAM, 6K x 24
//            3000-3003  the latches again (MAME input_latch32_r /
//                       output_latch32_w: data in bits 23-8)
//    data    0000-07FF  RAM, 2K x 16
//            0800-1FFF  the external program RAM's upper 16 bits (a write
//                       keeps the low 8)
//            2000-2FFF  sound ROM window: 4K words of the bank, each the
//                       ROM byte with FF above it (MAME's region is 16 bits
//                       wide, ERASEFF, the ROMs on the even bytes)
//            3000       bank select (bits 9-0: 1024 banks of 4K)
//            3400-3403  read: input latch (empties it); write: output latch
//            3800-39FF, 3FE0-3FFF  internal (in the core)
//  Anything else reads 0.
//
//  Boot: the DSP boots from the bank's 4K bytes (MAME dcs_boot: page = the
//  data bank at that moment). A reset from the host sets the bank to 0
//  first; a reboot through the DSP's system control register uses the bank
//  the program selected.
//
//  Host interface (MAME dcs_audio_device):
//    data_w     the byte goes to the input latch, which raises IRQ2 (level)
//               until the DSP reads it
//    data_r     the output latch's low byte; reading empties it
//    control_r  bit 11 input latch empty, bit 10 output latch empty
//    reset_w    I/O control bit 4: the DSP held in reset; at its start the
//               bank and both latches clear (MAME dcs_reset), at its end
//               the DSP boots and runs
//
//  The sound ROMs sit in SDRAM from 0x100000, chip n at n x 1 MB, so the
//  byte of ROM word w is at 0x100000 + w. They are read through channel 0
//  (the highest priority) in 8-byte lines, with a 32-line cache in front:
//  the DSP streams compressed sound from a handful of places at once.
//
//  The DSP runs at MAME's 10 MHz on average: a 10 MHz tick from clk_sys
//  (x 5 / 48) feeds the core's instruction tokens and clocks the DAC words
//  out, so the DAC's 31250 Hz comes out exact; the timer and the half-buffer
//  moves count instruction cycles, as in MAME.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module dcs_audio
(
	input             clk,           // 96 MHz
	input             reset,         // system reset
	input             dcs_reset,     // the host holds the DSP in reset

	// host (34010) side
	input             host_wr,       // one clock: write host_data to the input latch
	input       [7:0] host_data,
	input             host_rd,       // one clock: the host read the output latch
	output      [7:0] host_q,        // output latch, low byte
	output     [15:0] control,       // latch control (MAME control_r)

	// sound ROM: SDRAM channel 0, 8-byte lines (req toggles, ack follows)
	output reg [24:3] rom_addr,
	output reg        rom_req,
	input             rom_ack,
	input      [63:0] rom_data,

	// DAC
	output reg [15:0] sample,        // signed, held between words
	output reg        sample_strobe, // one clock per word

	// debug
	output     [13:0] dbg_pc,
	output     [23:0] dbg_op,
	output            dbg_retire,
	output            dbg_irq,
	output reg        dbg_wr,        // one clock: the DSP wrote external data memory
	output reg [13:0] dbg_waddr,
	output reg [15:0] dbg_wdata
);

localparam [24:0] ROM_BASE = 25'h010_0000;

//----------------------------------------------------------------------------
// 10 MHz instruction cycle tick (96 MHz x 5 / 48)
//----------------------------------------------------------------------------

reg [5:0] tick_acc;
reg       tick;
always @(posedge clk) begin
	tick <= 1'b0;
	if (reset)
		tick_acc <= 6'd0;
	else if (tick_acc >= 6'd43) begin
		tick_acc <= tick_acc - 6'd43;
		tick     <= 1'b1;
	end
	else
		tick_acc <= tick_acc + 6'd5;
end

//----------------------------------------------------------------------------
// The DSP
//----------------------------------------------------------------------------

wire        ext_req, ext_pm, ext_we;
wire [13:0] ext_addr;
wire [23:0] ext_wdata;
reg         ext_ack;
reg  [23:0] ext_rdata;
wire        boot_req;
wire [11:0] boot_addr;
reg         boot_ack;
reg   [7:0] boot_data;
wire        booting;
wire [15:0] sport1_data;
wire        sport1_strobe, sport1_on;

reg         in_full, out_full;
reg  [15:0] in_data, out_data;
reg  [10:0] bank;
reg         dcs_reset_d;

adsp2105 dsp
(
	.clk           (clk),
	.reset         (reset | dcs_reset),
	.dac_reset     (reset),
	.tick          (tick),

	.ext_req       (ext_req),
	.ext_pm        (ext_pm),
	.ext_we        (ext_we),
	.ext_addr      (ext_addr),
	.ext_wdata     (ext_wdata),
	.ext_ack       (ext_ack),
	.ext_rdata     (ext_rdata),

	.boot_req      (boot_req),
	.boot_addr     (boot_addr),
	.boot_ack      (boot_ack),
	.boot_data     (boot_data),
	.booting       (booting),

	.irq2          (in_full),
	.irq1          (1'b0),
	.irq0          (1'b0),

	.sport1_data   (sport1_data),
	.sport1_strobe (sport1_strobe),
	.sport1_on     (sport1_on),

	.dbg_pc        (dbg_pc),
	.dbg_op        (dbg_op),
	.dbg_retire    (dbg_retire),
	.dbg_irq       (dbg_irq)
);

always @(posedge clk) begin
	sample_strobe <= sport1_strobe;
	if (reset)
		sample <= 16'h0000;
	else if (sport1_strobe || !sport1_on)
		sample <= sport1_data;
end

//----------------------------------------------------------------------------
// External RAM
//----------------------------------------------------------------------------

// program 0800-1FFF, 24 bits; the data space sees the upper 16
reg  [15:0] xr_hi [0:6143];
reg   [7:0] xr_lo [0:6143];
reg  [12:0] xr_a;
reg         xr_we_hi, xr_we_lo;
reg  [23:0] xr_d;
reg  [15:0] xr_qh;
reg   [7:0] xr_ql;
always @(posedge clk) begin
	if (xr_we_hi) xr_hi[xr_a] <= xr_d[23:8];
	if (xr_we_lo) xr_lo[xr_a] <= xr_d[7:0];
	xr_qh <= xr_hi[xr_a];
	xr_ql <= xr_lo[xr_a];
end

// data 0000-07FF
reg  [15:0] dr [0:2047];
reg  [10:0] dr_a;
reg         dr_we;
reg  [15:0] dr_d, dr_q;
always @(posedge clk) begin
	if (dr_we) dr[dr_a] <= dr_d;
	dr_q <= dr[dr_a];
end

//----------------------------------------------------------------------------
// Sound ROM line cache (32 lines of 8 bytes, direct mapped)
//----------------------------------------------------------------------------

reg  [63:0] lc_data [0:31];
reg  [16:0] lc_tag  [0:31];
reg  [31:0] lc_val;
reg   [4:0] lc_ra;
reg  [63:0] lc_q;
reg  [16:0] lc_tq;
reg         lc_we;
reg   [4:0] lc_wa;
reg  [63:0] lc_wd;
reg  [16:0] lc_wt;
always @(posedge clk) begin
	if (lc_we) begin
		lc_data[lc_wa] <= lc_wd;
		lc_tag[lc_wa]  <= lc_wt;
	end
	lc_q  <= lc_data[lc_ra];
	lc_tq <= lc_tag[lc_ra];
end

//----------------------------------------------------------------------------
// Board logic: decode the DSP's external accesses
//----------------------------------------------------------------------------

localparam [2:0] B_IDLE = 3'd0, B_RAM = 3'd1, B_RAMQ = 3'd2, B_ROM = 3'd3, B_ROMCHK = 3'd4, B_ROMWAIT = 3'd5;

reg   [2:0] bst;
reg         b_pm, b_we, b_boot;
reg  [13:0] b_addr;
reg  [23:0] b_wdata;
reg   [1:0] b_src;                       // B_RAM result: 0 ext RAM (24), 1 ext RAM hi (DM), 2 data RAM
reg  [21:0] b_line;                      // ROM line (byte address / 8)
reg   [2:0] b_byte;

wire  [7:0] lc_byte = lc_q[{b_byte, 3'b000} +: 8];
wire  [7:0] rd_byte = rom_data[{b_byte, 3'b000} +: 8];

assign host_q  = out_data[7:0];
assign control = {4'b0000, !in_full, !out_full, 10'd0};

always @(posedge clk) begin
	ext_ack  <= 1'b0;
	boot_ack <= 1'b0;
	xr_we_hi <= 1'b0;
	xr_we_lo <= 1'b0;
	dr_we    <= 1'b0;
	lc_we    <= 1'b0;
	dbg_wr   <= 1'b0;

	dcs_reset_d <= dcs_reset;

	// host side of the latches. A host write in the clock the DSP reads the
	// input latch: the DSP takes the old byte, the new one stays pending
	// (the DSP's read below leaves in_full set)
	if (host_wr) begin
		in_data <= {8'h00, host_data};
		in_full <= 1'b1;
	end
	if (host_rd)
		out_full <= 1'b0;

	if (reset || (dcs_reset && !dcs_reset_d)) begin
		// MAME dcs_reset: bank 0, both latches empty
		bank     <= 11'd0;
		in_full  <= 1'b0;
		out_full <= 1'b0;
	end
	if (reset) begin
		bst    <= B_IDLE;
		lc_val <= 32'd0;
	end
	else case (bst)
		B_IDLE: begin
			if (boot_req) begin
				// boot byte: the bank's page
				b_boot <= 1'b1;
				b_line <= (ROM_BASE[24:3] + {3'd0, bank[9:0], 9'd0}) + {13'd0, boot_addr[11:3]};
				b_byte <= boot_addr[2:0];
				lc_ra  <= boot_addr[7:3];
				bst    <= B_ROM;
			end
			else if (ext_req) begin
				b_boot  <= 1'b0;
				b_pm    <= ext_pm;
				b_we    <= ext_we;
				b_addr  <= ext_addr;
				b_wdata <= ext_wdata;
				dbg_wr    <= ext_we && !ext_pm;
				dbg_waddr <= ext_addr;
				dbg_wdata <= ext_wdata[15:0];

				if (ext_pm) begin
					if (ext_addr >= 14'h0800 && ext_addr < 14'h2000) begin
						xr_a     <= ext_addr[12:0] - 13'h0800;
						xr_d     <= ext_wdata;
						xr_we_hi <= ext_we;
						xr_we_lo <= ext_we;
						b_src    <= 2'd0;
						bst      <= B_RAM;
					end
					else if (ext_addr[13:2] == 12'hC00) begin
						// the latches through program space, data in bits 23-8
						if (ext_we) begin
							out_data <= ext_wdata[23:8];
							out_full <= 1'b1;
							ext_rdata <= 24'd0;
						end
						else begin
							ext_rdata <= {in_data, 8'h00};
							if (!host_wr) in_full <= 1'b0;   // a byte written now stays pending
						end
						ext_ack <= 1'b1;
					end
					else begin
						ext_rdata <= 24'd0;
						ext_ack   <= 1'b1;
					end
				end
				else begin
					if (ext_addr < 14'h0800) begin
						dr_a  <= ext_addr[10:0];
						dr_d  <= ext_wdata[15:0];
						dr_we <= ext_we;
						b_src <= 2'd2;
						bst   <= B_RAM;
					end
					else if (ext_addr < 14'h2000) begin
						xr_a     <= ext_addr[12:0] - 13'h0800;
						xr_d     <= {ext_wdata[15:0], 8'h00};
						xr_we_hi <= ext_we;
						b_src    <= 2'd1;
						bst      <= B_RAM;
					end
					else if (ext_addr < 14'h3000) begin
						if (ext_we) begin
							ext_rdata <= 24'd0;
							ext_ack   <= 1'b1;
						end
						else begin
							// ROM window: word (bank x 4K + offset), FF above the byte
							b_line <= (ROM_BASE[24:3] + {3'd0, bank[9:0], 9'd0}) + {13'd0, ext_addr[11:3]};
							b_byte <= ext_addr[2:0];
							lc_ra  <= ext_addr[7:3];
							bst    <= B_ROM;
						end
					end
					else begin
						if (ext_we && ext_addr == 14'h3000)
							bank <= ext_wdata[10:0];
						if (ext_addr[13:2] == 12'hD00) begin
							if (ext_we) begin
								out_data <= ext_wdata[15:0];
								out_full <= 1'b1;
							end
							else if (!host_wr)
								in_full <= 1'b0;             // a byte written now stays pending
						end
						ext_rdata <= (!ext_we && ext_addr[13:2] == 12'hD00) ? {8'h00, in_data} : 24'd0;
						ext_ack   <= 1'b1;
					end
				end
			end
		end

		// RAM: the address is in, its data comes out the next clock
		B_RAM: bst <= B_RAMQ;

		// ROM byte: cache tags read with the request
		B_ROM: bst <= B_ROMCHK;

		B_ROMCHK: begin
			if (lc_val[lc_ra] && lc_tq == b_line[21:5]) begin
				if (b_boot) begin
					boot_data <= lc_byte;
					boot_ack  <= 1'b1;
				end
				else begin
					ext_rdata <= {8'h00, 8'hFF, lc_byte};
					ext_ack   <= 1'b1;
				end
				bst <= B_IDLE;
			end
			else begin
				rom_addr <= b_line;
				rom_req  <= ~rom_req;
				bst      <= B_ROMWAIT;
			end
		end

		B_ROMWAIT: if (rom_ack == rom_req) begin
			lc_we          <= 1'b1;
			lc_wa          <= b_line[4:0];
			lc_wd          <= rom_data;
			lc_wt          <= b_line[21:5];
			lc_val[b_line[4:0]] <= 1'b1;
			if (b_boot) begin
				boot_data <= rd_byte;
				boot_ack  <= 1'b1;
			end
			else begin
				ext_rdata <= {8'h00, 8'hFF, rd_byte};
				ext_ack   <= 1'b1;
			end
			bst <= B_IDLE;
		end

		B_RAMQ: begin
			case (b_src)
				2'd0:    ext_rdata <= {xr_qh, xr_ql};
				2'd1:    ext_rdata <= {8'h00, xr_qh};
				default: ext_rdata <= {8'h00, dr_q};
			endcase
			ext_ack <= 1'b1;
			bst     <= B_IDLE;
		end

		default: bst <= B_IDLE;
	endcase
end

endmodule
