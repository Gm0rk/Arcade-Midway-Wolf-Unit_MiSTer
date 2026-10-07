//============================================================================
//  ADSP-2105 digital signal processor
//
//  The Analog Devices ADSP-2105 as the Midway DCS sound board uses it. The
//  instruction set follows MAME's core (devices/cpu/adsp2100: adsp2100.cpp,
//  2100ops.hxx) exactly, including its arithmetic quirks (MAC products are
//  formed in 32 bits, MAC rounding looks at the product's low half, MR2 is
//  kept as a 16-bit field), because MAME is what the games are checked
//  against. The chip's control registers, timer and SPORT1 autobuffering
//  follow MAME's DCS driver (mame/shared/dcs.cpp), which emulates them for
//  the CPU core (so SPORT1 behaves as MAME's DCS boards make it). The board
//  itself stays outside: its module decodes the external spaces and the
//  boot memory.
//
//  Execution model
//  ---------------
//  A multi-cycle state machine on clk_sys (96 MHz). The real chip runs one
//  instruction per cycle at 10 MHz, as MAME counts it. `tick` gives one
//  pulse per 10 MHz cycle and each pulse is a token; an instruction needs a
//  token to start. When memory is slow (the board's ROM is in SDRAM) tokens
//  pile up and the following instructions run back to back until the core
//  has caught up, so on average the program runs at exactly 10 MIPS and
//  keeps MAME's timing. Up to 8191 tokens are kept (819 us). The most the
//  DCS programs owe is about 2700, just after a boot: MAME loads a boot page
//  in no time, here it takes up to 200 us, and the new program starts by
//  copying code out of the sound ROM.
//
//  An instruction takes 5 clocks without memory (fetch, opcode, decode,
//  execute, write back), 7 with a memory access and 9 with two in internal
//  memory; external memory adds the board's latency. The S_TOP clock reads
//  internal program memory, so such a fetch needs no clock of its own.
//    S_TOP   instruction boundary: SPORT1 half-buffer moves, interrupts,
//            start of the fetch
//    S_OPW   opcode arrives; next PC and the DO-loop end check
//    S_DEC   decode: condition, operands, DAG addresses, memory plan
//    S_ACC   memory access issued (the ALU, MAC product and shifter work
//            during it: they never need the memory's data)
//    S_ACCW  memory access done
//    S_EX1   execute when there is no memory access
//    S_EX2   write back: MAC accumulate, registers, flags, stacks, PC
//
//  Memory
//  ------
//  Inside the chip (mode MMAP = 0): program RAM 0000-03FF (1K x 24, loaded
//  by the boot), data RAM 3800-39FF (512 x 16), control registers
//  3FE0-3FFF. Everything else goes to the external port: ext_req (one
//  clock) with ext_pm (program or data space), ext_we, ext_addr, ext_wdata;
//  the board answers with ext_ack (one clock) and ext_rdata (24 bits for
//  program memory, data space words in [15:0]).
//
//  Boot: after reset, and when the program writes the system control
//  register with bit 9 set, the chip resets and loads its program RAM from
//  the 8-bit boot memory (boot_req / boot_addr / boot_ack / boot_data, byte
//  addresses within the page; the board picks the page). Byte 3 gives the
//  length, (n + 1) x 8 words of 4 bytes with the opcode in bytes 0-2 (MAME
//  load_boot_data). Registers keep their values over a reset, as in MAME.
//
//  Control registers (MAME dcs.cpp adsp_control_r/w): writes are stored and
//  read back, except
//    3FE5  program flags (MAME's toggling bits 1-2)
//    3FEF  SPORT1 autobuffer: bit 1 off stops transmission
//    3FF1  SPORT1 SCLK divider, 3FF2 SPORT1 control (bit 14 internal clock)
//    3FFB-3FFD  timer scale, count, period (count reads the live value;
//               the timer counts instruction cycles)
//    3FFF  system control: bit 9 reboots (and reads back 0), bit 11 off
//          stops SPORT1
//
//  SPORT1 transmit with autobuffering is the DCS's DAC output, done the way
//  MAME's DCS driver does it (dcs.cpp sound_tx_callback, dcs_irq) so the
//  program sees exactly what it sees there. Writing TX1 while SPORT1 and
//  its autobuffer are on starts it (the word written is not sent): the
//  autobuffer's I register (AUTOBUF bits 11-9; M = {I bit 2, bits 8-7},
//  L = the same number as I) is rounded down to a multiple of 16, and from
//  then on every half buffer (L / 2M words of 32 x (SCLKDIV + 1) cycles
//  with the internal clock, else 320 cycles, MAME's 31250 Hz external clock)
//  the words from I on are moved to a FIFO in one go, I steps past them, and
//  at the end of the buffer I goes back to its base and the SPORT1 transmit
//  interrupt is raised. These moments count instruction cycles, as MAME's
//  timer does, so they fall between the same two instructions as there.
//  The FIFO feeds the DAC on the tick, one word per word period
//  (sport1_data, one-clock sport1_strobe), starting 16 words after the first
//  half buffer so the token debt never starves it. Up to 448 words a block.
//
//  Interrupts (ADSP-2101 family priority): IRQ2 (vector 04, IMASK bit 5),
//  IRQ1 / SPORT1 transmit (10, bit 2), IRQ0 / SPORT1 receive (14, bit 1),
//  timer (18, bit 0). ICNTL bits 0-2 make IRQ0-2 edge (latched) or level
//  sensitive, ICNTL bit 4 allows nesting. They are checked before every
//  instruction (MAME at each time slice and after RTI or IMASK writes).
//
//  IDLE does nothing: MAME only ends its time slice there and carries on
//  with the next instruction.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module adsp2105
(
	input             clk,           // 96 MHz
	input             reset,         // held: chip in reset; released: boot, then run
	input             dac_reset,     // clears the DAC FIFO (system reset; a chip reset
	                                 // lets it play out, as MAME's DAC buffer does)
	input             tick,          // one clock per instruction cycle (10 MHz)

	// external program / data memory
	output reg        ext_req,       // one clock: start an access
	output reg        ext_pm,        // 1 program space, 0 data space
	output reg        ext_we,
	output reg [13:0] ext_addr,
	output reg [23:0] ext_wdata,     // program word, or data word in [15:0]
	input             ext_ack,       // one clock: done (ext_rdata valid for reads)
	input      [23:0] ext_rdata,

	// boot memory (8 bits, byte address within the boot page)
	output reg        boot_req,      // one clock
	output reg [11:0] boot_addr,
	input             boot_ack,      // one clock: boot_data valid
	input       [7:0] boot_data,
	output reg        booting,       // a boot load is running

	// interrupt pins
	input             irq2,          // level
	input             irq1,          // level (SPORT1 transmit shares its vector)
	input             irq0,          // level

	// SPORT1 transmit (DAC)
	output reg [15:0] sport1_data,   // the word last sent
	output reg        sport1_strobe, // one clock per word sent
	output reg        sport1_on,     // transmitting

	// debug
	output reg [13:0] dbg_pc,        // address of the instruction decoded
	output reg [23:0] dbg_op,
	output reg        dbg_retire,    // one clock per instruction (at decode)
	output reg        dbg_irq        // one clock per interrupt taken
);

//----------------------------------------------------------------------------
// Constants
//----------------------------------------------------------------------------

// data register file slots (per bank): group-0 codes 0-15, then AF, MF, SB
localparam [4:0] R_AX0 = 5'd0,  R_AX1 = 5'd1,  R_MX0 = 5'd2,  R_MX1 = 5'd3,
                 R_AY0 = 5'd4,  R_AY1 = 5'd5,  R_MY0 = 5'd6,  R_MY1 = 5'd7,
                 R_SI  = 5'd8,  R_SE  = 5'd9,  R_AR  = 5'd10, R_MR0 = 5'd11,
                 R_MR1 = 5'd12, R_MR2 = 5'd13, R_SR0 = 5'd14, R_SR1 = 5'd15,
                 R_AF  = 5'd16, R_MF  = 5'd17, R_SB  = 5'd18;

// ASTAT bits
localparam AZ = 0, AN = 1, AV = 2, AC = 3, AS = 4, AQ = 5, MV = 6, SS = 7;
// MSTAT bits
localparam M_BANK = 0, M_REV = 1, M_STICKY = 2, M_SAT = 3, M_INT = 4, M_TIMER = 5, M_GO = 6;
// SSTAT bits
localparam PC_EMPTY = 0, PC_OVER = 1, CNT_EMPTY = 2, CNT_OVER = 3,
           STAT_EMPTY = 4, STAT_OVER = 5, LOOP_EMPTY = 6, LOOP_OVER = 7;

// control registers (index from 3FE0)
localparam [4:0] C_PFDATA = 5'd5, C_PFCTL = 5'd6, C_S1AUTO = 5'd15, C_S1SCLK = 5'd17,
                 C_S1CTL = 5'd18, C_TSCALE = 5'd27, C_TCOUNT = 5'd28, C_TPERIOD = 5'd29,
                 C_SYSCTL = 5'd31;

// states
localparam [3:0] S_RESET = 4'd0,  S_BOOTLEN = 4'd1, S_BOOTW = 4'd2, S_TOP  = 4'd3,
                 S_OPW   = 4'd4,  S_DEC     = 4'd5, S_ACC   = 4'd6, S_ACCW = 4'd7,
                 S_EX1   = 4'd8,  S_EX2     = 4'd9;

// access kinds (what S_ACCW does with the result)
localparam [1:0] K_M1 = 2'd0, K_M2 = 2'd1, K_DMA = 2'd2;

//----------------------------------------------------------------------------
// Helper functions (MAME 2100ops.hxx)
//----------------------------------------------------------------------------

function automatic [15:0] sext8(input [15:0] v);
	sext8 = {{8{v[7]}}, v[7:0]};
endfunction

function automatic [15:0] sext14(input [15:0] v);
	sext14 = {{2{v[13]}}, v[13:0]};
endfunction

// circular buffer base mask for a length (MAME m_mask_table)
function automatic [13:0] lmask(input [13:0] l);
	if      (l > 14'h2000) lmask = 14'h0000;
	else if (l > 14'h1000) lmask = 14'h2000;
	else if (l > 14'h0800) lmask = 14'h3000;
	else if (l > 14'h0400) lmask = 14'h3800;
	else if (l > 14'h0200) lmask = 14'h3c00;
	else if (l > 14'h0100) lmask = 14'h3e00;
	else if (l > 14'h0080) lmask = 14'h3f00;
	else if (l > 14'h0040) lmask = 14'h3f80;
	else if (l > 14'h0020) lmask = 14'h3fc0;
	else if (l > 14'h0010) lmask = 14'h3fe0;
	else if (l > 14'h0008) lmask = 14'h3ff0;
	else if (l > 14'h0004) lmask = 14'h3ff8;
	else if (l > 14'h0002) lmask = 14'h3ffc;
	else if (l > 14'h0001) lmask = 14'h3ffe;
	else                   lmask = 14'h3fff;
endfunction

// post-modify with circular wrap (MAME modify_address): {wrapped up, new I}
function automatic [14:0] circ(input [13:0] i, input [13:0] m, input [13:0] b, input [13:0] l);
	reg [13:0] n;
	reg [14:0] top;
	begin
		n   = i + m;
		top = {1'b0, b} + {1'b0, l};
		if (n < b)                 circ = {1'b0, n + l};
		else if ({1'b0, n} >= top) circ = {1'b1, n - l};
		else                       circ = {1'b0, n};
	end
endfunction

function automatic [13:0] rev14(input [13:0] v);
	integer k;
	for (k = 0; k < 14; k = k + 1)
		rev14[k] = v[13 - k];
endfunction

// leading zeros of a 16-bit value (16 for zero)
function automatic [4:0] lz16(input [15:0] v);
	integer k;
	reg     found;
	begin
		lz16  = 5'd16;
		found = 1'b0;
		for (k = 15; k >= 0; k = k - 1)
			if (!found && v[k]) begin
				lz16  = 5'd15 - k[4:0];
				found = 1'b1;
			end
	end
endfunction

// condition codes other than 14 (NOT CE, which counts the counter down)
function automatic cond_flags(input [3:0] c, input [7:0] s);
	case (c)
		4'd0:  cond_flags = s[AZ];
		4'd1:  cond_flags = !s[AZ];
		4'd2:  cond_flags = !((s[AN] ^ s[AV]) | s[AZ]);
		4'd3:  cond_flags = (s[AN] ^ s[AV]) | s[AZ];
		4'd4:  cond_flags = s[AN] ^ s[AV];
		4'd5:  cond_flags = !(s[AN] ^ s[AV]);
		4'd6:  cond_flags = s[AV];
		4'd7:  cond_flags = !s[AV];
		4'd8:  cond_flags = s[AC];
		4'd9:  cond_flags = !s[AC];
		4'd10: cond_flags = s[AS];
		4'd11: cond_flags = !s[AS];
		4'd12: cond_flags = s[MV];
		4'd13: cond_flags = !s[MV];
		default: cond_flags = 1'b1;
	endcase
endfunction

// ALU (MAME alu_op_ar / alu_op_af): {flags, result}
function automatic [23:0] alu(input [3:0] f, input [15:0] x, input [15:0] y, input [7:0] s_in, input sticky);
	reg [16:0] r, d;
	reg  [7:0] s;
	begin
		s = s_in;
		// CLR_FLAGS: C, N, Z, and V unless sticky
		s[AC] = 1'b0; s[AN] = 1'b0; s[AZ] = 1'b0;
		if (!sticky) s[AV] = 1'b0;
		r = 17'd0;
		d = 17'd0;
		case (f)
			4'h0: r = {1'b0, y};
			4'h1: begin
				r = {1'b0, y} + 17'd1;
				if (y == 16'h7fff) s[AV] = 1'b1;
				else if (y == 16'hffff) s[AC] = 1'b1;
			end
			4'h2: begin
				d = {1'b0, y} + {16'd0, s_in[AC]};
				r = {1'b0, x} + d;
				s[AV] = s[AV] | (x[15] ^ d[15] ^ r[15] ^ r[16]);
				s[AC] = r[16];
			end
			4'h3: begin
				r = {1'b0, x} + {1'b0, y};
				s[AV] = s[AV] | (x[15] ^ y[15] ^ r[15] ^ r[16]);
				s[AC] = r[16];
			end
			4'h4: r = {1'b0, ~y};
			4'h5: begin
				r = 17'd0 - {1'b0, y};
				if (y == 16'h8000) s[AV] = 1'b1;
				if (y == 16'h0000) s[AC] = 1'b1;
			end
			4'h6: begin
				r = {1'b0, x} - {1'b0, y} + {16'd0, s_in[AC]} - 17'd1;
				s[AV] = s[AV] | (x[15] ^ y[15] ^ r[15] ^ r[16]);
				s[AC] = !r[16];
			end
			4'h7: begin
				r = {1'b0, x} - {1'b0, y};
				s[AV] = s[AV] | (x[15] ^ y[15] ^ r[15] ^ r[16]);
				s[AC] = !r[16];
			end
			4'h8: begin
				r = {1'b0, y} - 17'd1;
				if (y == 16'h8000) s[AV] = 1'b1;
				else if (y == 16'h0000) s[AC] = 1'b1;
			end
			4'h9: begin
				r = {1'b0, y} - {1'b0, x};
				s[AV] = s[AV] | (y[15] ^ x[15] ^ r[15] ^ r[16]);
				s[AC] = !r[16];
			end
			4'hA: begin
				r = {1'b0, y} - {1'b0, x} + {16'd0, s_in[AC]} - 17'd1;
				s[AV] = s[AV] | (y[15] ^ x[15] ^ r[15] ^ r[16]);
				s[AC] = !r[16];
			end
			4'hB: r = {1'b0, ~x};
			4'hC: r = {1'b0, x & y};
			4'hD: r = {1'b0, x | y};
			4'hE: r = {1'b0, x ^ y};
			default: r = x[15] ? (17'd0 - {1'b0, x}) : {1'b0, x};     // ABS
		endcase
		if (f == 4'hF) begin
			s[AS] = x[15];
			s[AZ] = (x == 16'h0000);
			if (x == 16'h8000) begin
				s[AN] = 1'b1;
				s[AV] = 1'b1;
			end
		end
		else begin
			s[AN] = r[15];
			s[AZ] = (r[15:0] == 16'h0000);
		end
		alu = {s, r[15:0]};
	end
endfunction

// MAC product (MAME mac_op_*): the product formed in 32 bits, shifted left
// once in fractional mode
function automatic [31:0] mac_prod(input [3:0] f, input [15:0] x, input [15:0] y, input integer_mode);
	reg        xs, ys;
	reg [33:0] p;
	begin
		// signedness: RND forms and SS signed x signed; SU, US, UU per op
		xs = (f[3:2] == 2'b00) ? 1'b1 : !f[1];
		ys = (f[3:2] == 2'b00) ? 1'b1 : !f[0];
		p = $signed({xs & x[15], x}) * $signed({ys & y[15], y});
		mac_prod = integer_mode ? p[31:0] : {p[30:0], 1'b0};
	end
endfunction

//----------------------------------------------------------------------------
// State
//----------------------------------------------------------------------------

reg   [3:0] st;
reg  [12:0] tok;                // instruction cycles owed (see the header)

// data registers, two banks of 32 slots (MSTAT bit 0 selects)
reg  [15:0] rf [0:63];
reg   [6:0] mstat;
wire        bk = mstat[M_BANK];

// DAG registers
reg  [13:0] ir [0:7];
reg  [13:0] mr [0:7];           // M registers (14 bits, read sign-extended)
reg  [13:0] lr [0:7];
reg  [13:0] br [0:7];           // circular buffer bases (set when I or L is written)

reg   [7:0] px;
reg  [13:0] cntr;
reg   [7:0] astat;
reg   [7:0] sstat;
reg   [5:0] imask;
reg   [4:0] icntl;

// sequencer
reg  [13:0] pc;
reg  [13:0] ppc;
reg         loop_on;            // a DO loop is active
reg  [13:0] loop_end;
reg   [3:0] loop_cond;
reg  [13:0] pcs [0:15];         // PC stack
reg   [4:0] pc_sp;
reg  [13:0] cnts [0:3];         // counter stack
reg   [2:0] cnt_sp;
reg  [17:0] loops [0:3];        // loop stack {end, condition}
reg   [2:0] loop_sp;
reg  [20:0] stats [0:3];        // status stack {mstat, imask, astat}
reg   [2:0] stat_sp;
reg         reboot;             // system control bit 9 written
reg   [2:0] flags_out;          // FL0-FL2 / FLAG OUT (no pins used)
reg         flag_out;

// interrupts
reg         lat0, lat1, lat2, latt;      // latched requests (IRQ0, IRQ1, IRQ2, timer)
reg         pin0_d, pin1_d, pin2_d;      // pin levels last clock (edge detect)
reg         s1tx_pulse;                  // SPORT1 transmit wrap, seen as a level once

// internal memories and control registers
reg  [23:0] pm_int [0:1023];
reg  [15:0] dm_int [0:511];
reg  [15:0] creg [0:31];
reg  [23:0] pm_q;                        // registered reads (S_TOP: at pc, else at a_addr)
reg  [15:0] dm_q;
reg   [1:0] progflags;
reg         pmw_en, dmw_en;              // internal RAM writes, done the next clock
reg   [9:0] pmw_addr;
reg   [8:0] dmw_addr;
reg  [23:0] pmw_data;
reg  [15:0] dmw_data;
reg         f_int;                       // the fetch is from internal program RAM

// timer
reg   [7:0] tscale_cnt;
reg  [15:0] tcount;

// SPORT1 autobuffer (MAME dcs.cpp: m_ireg, m_incs, m_size, the half-buffer timer)
reg         ab_on;                       // the half-buffer timer runs
reg   [2:0] ab_ireg;
reg  [13:0] ab_incs, ab_size;
reg  [21:0] ab_per;                      // word period (cycles)
reg  [21:0] ab_pcnt;                     // instruction cycles into the word period
reg  [13:0] ab_wcnt;                     // word periods into the half buffer
reg  [13:0] ab_count;                    // words per half buffer: size / (2 incs)
reg         ab_due;                      // a half buffer is due at the next boundary
reg         ab_blk;                      // moving it
reg  [14:0] ab_reg;                      // MAME's reg while moving
reg  [13:0] ab_left;
reg         dv_busy;                     // count = size / (2 incs), one bit a clock
reg   [3:0] dv_n;
reg  [14:0] dv_r;
reg  [13:0] dv_q;
// DAC FIFO, read on the tick
reg  [15:0] ab_fifo [0:511];
reg   [8:0] ab_wr, ab_rd;
reg  [15:0] ab_q;
reg         fw_en;
reg   [8:0] fw_addr;
reg  [15:0] fw_data;
reg  [21:0] o_cnt;                       // ticks into the word period
reg         o_run;                       // sending
reg   [4:0] o_wait;                      // word periods before the first word
reg         o_armed;                     // the first half buffer is in

// boot
reg   [9:0] boot_last;                   // last word to load
reg   [9:0] boot_i;
reg   [1:0] boot_j;
reg  [15:0] boot_acc;

// access unit
reg         a_pm, a_we;
reg  [13:0] a_addr;
reg  [23:0] a_wdata;
reg   [1:0] a_kind;
wire        a_int_pm = a_pm && (a_addr[13:10] == 4'd0);
wire        a_int_dm = !a_pm && (a_addr[13:9] == 5'b11100);
wire        a_ctl    = !a_pm && (a_addr[13:5] == 9'h1FF);
wire        a_ext    = !(a_int_pm || a_int_dm || a_ctl);
reg  [15:0] ctl_q;                       // control register read

// current instruction
reg  [23:0] op;
wire  [7:0] opc = op[23:16];
reg         cok;                         // its condition holds

// memory plan
reg         m1_on, m1_pm, m1_we, m2_on;
reg  [13:0] m1_addr, m2_addr;
reg  [23:0] m1_wdata;
reg  [23:0] m1_q, m2_q;

// DAG post-modify results, written back at the end
reg         d1_on, d2_on;
reg   [2:0] d1_i, d2_i;
reg  [13:0] d1_v, d2_v;

// operands latched at decode
reg  [15:0] o_ax, o_ay, o_mx, o_my, o_sx;   // ALU x/y, MAC x/y, shifter x
reg  [15:0] o_mv;                           // register value for moves and memory writes
reg  [47:0] o_mr;                           // MR as {MR2, MR1, MR0}
reg  [31:0] o_sr;                           // SR as {SR1, SR0}
reg  [15:0] o_se, o_sb, o_af, o_ay0;

// execute results
reg  [15:0] x_alu;
reg   [7:0] x_ast;                       // ASTAT after the ALU / shifter / divide
reg  [31:0] x_prod;
reg  [31:0] x_sr;
reg  [15:0] x_se, x_sb;
reg  [15:0] x_af, x_ay0;                 // DIVS / DIVQ

//----------------------------------------------------------------------------
// Instruction classes (MAME execute_run switch on op[23:16])
//----------------------------------------------------------------------------

wire c_cond_am = (opc[7:3] == 5'b00100);                 // 20-27 conditional ALU/MAC
wire c_move_am = (opc[7:3] == 5'b00101);                 // 28-2F with register move
wire c_mem_am  = (opc[7:6] == 2'b01) && (opc[5:4] != 2'b00);   // 50-7F with memory
wire c_dual    = (opc[7:6] == 2'b11);                    // C0-FF dual read
wire c_am      = c_cond_am | c_move_am | c_mem_am | c_dual;
// result {MR, AR, MF, AF} from op[18:17] (dual read: op[17], MR or AR)
wire am_alu    = op[17];
wire am_f      = c_dual ? 1'b0 : op[18];
wire c_shift   = (opc >= 8'h0E) && (opc <= 8'h13);
wire c_shimm   = (opc == 8'h0F);

// conditional instruction classes (condition in op[3:0])
wire c_has_cond = (opc == 8'h02 && !op[15]) || opc == 8'h0A || opc == 8'h0B || opc == 8'h0E ||
                  (opc[7:3] == 5'b00011) || c_cond_am;

//----------------------------------------------------------------------------
// Interrupt selection (MAME adsp2101 check_irqs)
//----------------------------------------------------------------------------

wire p2 = icntl[2] ? lat2 : irq2;
wire p1 = icntl[1] ? lat1 : (irq1 | s1tx_pulse);
wire p0 = icntl[0] ? lat0 : irq0;
wire take2 = p2   & imask[5];
wire take1 = p1   & imask[2];
wire take0 = p0   & imask[1];
wire taket = latt & imask[0];
wire irq_any = take2 | take1 | take0 | taket;

// SPORT1 word period in instruction cycles
wire [16:0] s1_div    = {1'b0, creg[C_S1SCLK]} + 17'd1;
wire [21:0] s1_period = creg[C_S1CTL][14] ? {s1_div, 5'd0} : 22'd320;

// autobuffer registers
wire  [2:0] ab_i = creg[C_S1AUTO][11:9];
wire  [2:0] ab_m = {ab_i[2], creg[C_S1AUTO][8:7]};
wire  [8:0] ab_lvl = ab_wr - ab_rd;

//----------------------------------------------------------------------------
// Register access helpers
//----------------------------------------------------------------------------

// MAME read_reg0-3 (no side effects; TOPPCSTACK's pop is done by the caller)
function automatic [15:0] rd_grp(input [1:0] g, input [3:0] c);
	case (g)
		2'd0: rd_grp = rf[{bk, 1'b0, c}];
		2'd1, 2'd2: case (c[3:2])
			2'd0:    rd_grp = {2'b00, ir[{g[1], c[1:0]}]};
			2'd1:    rd_grp = {{2{mr[{g[1], c[1:0]}][13]}}, mr[{g[1], c[1:0]}]};   // (no nested call: Verilator 5.020 misorders it)
			default: rd_grp = {2'b00, lr[{g[1], c[1:0]}]};      // L, and codes 12-15 read L too
		endcase
		default: case (c)
			4'h0: rd_grp = {8'h00, astat};
			4'h1: rd_grp = {9'h000, mstat};
			4'h2: rd_grp = {8'h00, sstat};
			4'h3: rd_grp = {10'h000, imask};
			4'h4: rd_grp = {11'h000, icntl};
			4'h5: rd_grp = {2'b00, cntr};
			4'h6: rd_grp = rf[{bk, R_SB}];
			4'h7: rd_grp = {8'h00, px};
			4'hF: rd_grp = {2'b00, (pc_sp != 5'd0) ? pcs[pc_sp[3:0] - 4'd1] : pcs[0]};
			default: rd_grp = 16'h0000;          // RX0, RX1 (nothing received), invalid
		endcase
	endcase
endfunction

function automatic [4:0] alu_x_slot(input [2:0] c);
	case (c)
		3'd0: alu_x_slot = R_AX0; 3'd1: alu_x_slot = R_AX1; 3'd2: alu_x_slot = R_AR;  3'd3: alu_x_slot = R_MR0;
		3'd4: alu_x_slot = R_MR1; 3'd5: alu_x_slot = R_MR2; 3'd6: alu_x_slot = R_SR0; default: alu_x_slot = R_SR1;
	endcase
endfunction

function automatic [4:0] mac_x_slot(input [2:0] c);
	case (c)
		3'd0: mac_x_slot = R_MX0; 3'd1: mac_x_slot = R_MX1; 3'd2: mac_x_slot = R_AR;  3'd3: mac_x_slot = R_MR0;
		3'd4: mac_x_slot = R_MR1; 3'd5: mac_x_slot = R_MR2; 3'd6: mac_x_slot = R_SR0; default: mac_x_slot = R_SR1;
	endcase
endfunction

function automatic [4:0] sh_x_slot(input [2:0] c);
	case (c)
		3'd0, 3'd1: sh_x_slot = R_SI;
		3'd2: sh_x_slot = R_AR;  3'd3: sh_x_slot = R_MR0; 3'd4: sh_x_slot = R_MR1;
		3'd5: sh_x_slot = R_MR2; 3'd6: sh_x_slot = R_SR0; default: sh_x_slot = R_SR1;
	endcase
endfunction

//----------------------------------------------------------------------------
// Shifter (MAME shift_op / shift_op_imm): {SS, SE, SB, SR} after the op
//----------------------------------------------------------------------------

function automatic [64:0] shifter(input [3:0] f, input [7:0] sc, input [15:0] x,
                                  input [31:0] sr_in, input [15:0] se_in, input [15:0] sb_in,
                                  input [7:0] st_in);
	reg signed [8:0]  s;          // shift code, signed
	reg signed [8:0]  ns;         // -s
	reg        [4:0]  n;          // |s| for in-range shifts
	reg        [31:0] xv, r;
	reg        [15:0] se, sb, v;
	reg               ss;
	reg        [4:0]  cnt;
	begin
		s  = $signed({sc[7], sc});
		ns = -s;
		n  = (s > 0) ? s[4:0] : ns[4:0];
		r  = sr_in;
		se = se_in;
		sb = sb_in;
		ss = st_in[SS];
		case (f)
			4'h0, 4'h1: begin                                   // LSHIFT (HI)
				xv = {x, 16'h0000};
				if (s > 0) xv = (s < 32) ? (xv << n) : 32'd0;
				else       xv = (s > -32) ? (xv >> n) : 32'd0;
				r = f[0] ? (sr_in | xv) : xv;
			end
			4'h2, 4'h3: begin                                   // LSHIFT (LO)
				xv = {16'h0000, x};
				if (s > 0) xv = (s < 32) ? (xv << n) : 32'd0;
				else       xv = (s > -32) ? (xv >> n) : 32'd0;
				r = f[0] ? (sr_in | xv) : xv;
			end
			4'h4, 4'h5, 4'h6, 4'h7: begin                       // ASHIFT (HI / LO)
				xv = f[1] ? {{16{x[15]}}, x} : {x, 16'h0000};
				if (s > 0) xv = (s < 32) ? (xv << n) : 32'd0;
				else       xv = (s > -32) ? ($signed(xv) >>> n) : ($signed(xv) >>> 31);
				r = f[0] ? (sr_in | xv) : xv;
			end
			4'h8, 4'h9: begin                                   // NORM (HI)
				xv = {x, 16'h0000};
				if (s > 0) xv = $signed({st_in[AC], xv[31:1]}) >>> ((s - 9'sd1) & 9'sd31);
				else       xv = (s > -32) ? (xv << n) : 32'd0;
				r = f[0] ? (sr_in | xv) : xv;
			end
			4'hA, 4'hB: begin                                   // NORM (LO)
				xv = {16'h0000, x};
				if (s > 0) xv = (s < 32) ? (xv >> n) : 32'd0;
				else       xv = (s > -32) ? (xv << n) : 32'd0;
				r = f[0] ? (sr_in | xv) : xv;
			end
			4'hC, 4'hD: begin                                   // EXP (HI), EXP (HIX)
				if (f[0] && st_in[AV]) begin
					se = 16'd1;
					ss = !x[15];
				end
				else begin
					ss  = x[15];
					cnt = x[15] ? lz16(~x) : lz16(x);
					se  = 16'd1 - {11'd0, cnt};
				end
			end
			4'hE: begin                                         // EXP (LO)
				if (se_in == 16'hFFF1) begin
					v   = st_in[SS] ? ~x : x;
					se  = 16'hFFF1 - {11'd0, lz16(v)};
				end
			end
			default: begin                                      // EXPADJ
				v   = x[15] ? ~x : x;
				cnt = lz16(v);                                  // MAME res = cnt - 1
				if ($signed({11'd0, cnt} - 16'd1) < $signed(16'd0 - sb_in))
					sb = 16'd1 - {11'd0, cnt};
			end
		endcase
		shifter = {ss, se, sb, r};
	end
endfunction

//----------------------------------------------------------------------------
// Internal RAMs (one write port each; a write lands the clock after it is
// requested, long before the next access)
//----------------------------------------------------------------------------

always @(posedge clk) begin
	if (pmw_en) pm_int[pmw_addr] <= pmw_data;
	pm_q <= pm_int[(st == S_TOP) ? pc[9:0] : a_addr[9:0]];
end

always @(posedge clk) begin
	if (dmw_en) dm_int[dmw_addr] <= dmw_data;
	dm_q <= dm_int[a_addr[8:0]];
end

always @(posedge clk) begin
	if (fw_en) ab_fifo[fw_addr] <= fw_data;
	ab_q <= ab_fifo[ab_rd];
end

//----------------------------------------------------------------------------
// Main state machine
//----------------------------------------------------------------------------

integer k;
reg        tok_use;
reg [14:0] cw;                     // circ() result
reg [23:0] ar;                     // alu() result
reg [64:0] shr;                    // shifter() result
reg [47:0] macr;                   // MAC accumulate result
reg        mac_sub, mac_rnd;
reg [15:0] mvv;                    // value moved
reg [15:0] w0v;                    // group-0 write value
reg  [3:0] w0c;                    // group-0 write code
reg        w0on;
reg  [2:0] di;

// group-0 register write (MAME write_reg0): SE and MR2 sign-extend 8 bits,
// MR1 also sets MR2 to its sign
task automatic wr0(input [3:0] c, input [15:0] v);
	case (c)
		4'h9:    rf[{bk, R_SE}]  <= sext8(v);
		4'hC:    begin rf[{bk, R_MR1}] <= v; rf[{bk, R_MR2}] <= {16{v[15]}}; end
		4'hD:    rf[{bk, R_MR2}] <= sext8(v);
		default: rf[{bk, 1'b0, c}] <= v;
	endcase
endtask

// counter stack push (MAME cntr_stack_push), the new value goes to CNTR
task automatic cntr_push(input [13:0] v);
	begin
		if (cnt_sp != 3'd4) begin
			cnts[cnt_sp[1:0]] <= cntr;
			cnt_sp <= cnt_sp + 3'd1;
			sstat[CNT_EMPTY] <= 1'b0;
		end
		else
			sstat[CNT_OVER] <= 1'b1;
		cntr <= v;
	end
endtask

// PC stack push of a value
task automatic pc_push(input [13:0] v);
	begin
		if (pc_sp != 5'd16) begin
			pcs[pc_sp[3:0]] <= v;
			pc_sp <= pc_sp + 5'd1;
			sstat[PC_EMPTY] <= 1'b0;
		end
		else
			sstat[PC_OVER] <= 1'b1;
	end
endtask

// PC stack pop (the popped value is pcs[pc_sp - 1], or pcs[0] when empty)
task automatic pc_pop;
	if (pc_sp != 5'd0) begin
		pc_sp <= pc_sp - 5'd1;
		if (pc_sp == 5'd1) sstat[PC_EMPTY] <= 1'b1;
	end
endtask

wire [13:0] pc_top = (pc_sp != 5'd0) ? pcs[pc_sp[3:0] - 4'd1] : pcs[0];

// loop stack pop (MAME loop_stack_pop)
task automatic loop_pop;
	if (loop_sp != 3'd0) begin
		loop_sp <= loop_sp - 3'd1;
		if (loop_sp == 3'd1) begin
			loop_on <= 1'b0;
			sstat[LOOP_EMPTY] <= 1'b1;
		end
		else begin
			loop_end  <= loops[loop_sp[1:0] - 2'd2][17:4];
			loop_cond <= loops[loop_sp[1:0] - 2'd2][3:0];
		end
	end
endtask

// counter stack pop (MAME cntr_stack_pop)
task automatic cntr_pop;
	begin
		if (cnt_sp != 3'd0) begin
			cnt_sp <= cnt_sp - 3'd1;
			if (cnt_sp == 3'd1) sstat[CNT_EMPTY] <= 1'b1;
			cntr <= cnts[cnt_sp[1:0] - 2'd1];
		end
		else
			cntr <= cnts[0];
	end
endtask

// status stack pop (MAME stat_stack_pop)
task automatic stat_pop;
	reg [20:0] e;
	begin
		if (stat_sp != 3'd0) begin
			stat_sp <= stat_sp - 3'd1;
			if (stat_sp == 3'd1) sstat[STAT_EMPTY] <= 1'b1;
			e = stats[stat_sp[1:0] - 2'd1];
		end
		else
			e = stats[0];
		mstat <= e[20:14];
		imask <= e[13:8];
		astat <= e[7:0];
	end
endtask

task automatic stat_push;
	if (stat_sp != 3'd4) begin
		stats[stat_sp[1:0]] <= {mstat, imask, astat};
		stat_sp <= stat_sp + 3'd1;
		sstat[STAT_EMPTY] <= 1'b0;
	end
	else
		sstat[STAT_OVER] <= 1'b1;
endtask

// SPORT1 off (MAME: timer reset, DAC disabled)
task automatic ab_stop;
	begin
		ab_on       <= 1'b0;
		ab_due      <= 1'b0;
		ab_blk      <= 1'b0;
		o_run       <= 1'b0;
		o_armed     <= 1'b0;
		ab_rd       <= ab_wr;
		sport1_on   <= 1'b0;
		sport1_data <= 16'h0000;
	end
endtask

// group 1-3 register writes (MAME write_reg1-3)
task automatic wr_grp(input [1:0] g, input [3:0] c, input [15:0] v);
	reg [2:0] n;
	begin
		n = {g[1], c[1:0]};
		case (g)
			2'd0: wr0(c, v);
			2'd1, 2'd2: case (c[3:2])
				2'd0: begin ir[n] <= v[13:0]; br[n] <= v[13:0] & lmask(lr[n]); end
				2'd1: mr[n] <= v[13:0];
				2'd2: begin lr[n] <= v[13:0]; br[n] <= ir[n] & lmask(v[13:0]); end
				default: ;
			endcase
			default: case (c)
				4'h0: astat <= v[7:0];
				4'h1: mstat <= v[6:0];
				4'h3: imask <= v[5:0];
				4'h4: icntl <= v[4:0];
				4'h5: cntr_push(v[13:0]);
				4'h6: rf[{bk, R_SB}] <= {{11{v[4]}}, v[4:0]};
				4'h7: px <= v[7:0];
				4'hB: begin                                      // TX1 (MAME sound_tx_callback)
					if (creg[C_SYSCTL][11] && creg[C_S1AUTO][1]) begin
						// I rounded down to 16 (its base follows), the half-buffer
						// timer restarted with this instruction as its first cycle
						ir[ab_i]  <= ir[ab_i] & 14'h3FF0;
						br[ab_i]  <= ir[ab_i] & 14'h3FF0 & lmask(lr[ab_i]);
						ab_ireg   <= ab_i;
						ab_incs   <= mr[ab_m];
						ab_size   <= lr[ab_i];
						ab_per    <= s1_period;
						ab_on     <= (mr[ab_m] != 14'd0) && !mr[ab_m][13];
						ab_pcnt   <= 22'd1;
						ab_wcnt   <= 14'd0;
						ab_due    <= 1'b0;
						dv_busy   <= 1'b1;
						dv_n      <= 4'd0;
						dv_r      <= 15'd0;
						dv_q      <= lr[ab_i];
						if (!o_armed) begin
							o_cnt  <= 22'd0;
							o_wait <= 5'd0;
						end
					end
					else
						ab_stop();
				end
				4'hC: begin                                      // IFC
					if (v[1])  lat0 <= 1'b0;
					if (v[2])  lat1 <= 1'b0;
					if (v[5])  lat2 <= 1'b0;
					if (v[7])  lat0 <= 1'b1;
					if (v[8])  lat1 <= 1'b1;
					if (v[11]) lat2 <= 1'b1;
				end
				4'hD: cntr <= v[13:0];                            // OWRCNTR
				4'hF: pc_push(v[13:0]);                           // TOPPCSTACK
				default: ;                                         // SSTAT, RX, TX0: nothing
			endcase
		endcase
	end
endtask

// control register write (MAME dcs.cpp adsp_control_w)
task automatic ctl_write(input [4:0] r, input [15:0] v);
	begin
		creg[r] <= v;
		if (r == C_SYSCTL) begin
			if (v[9]) begin
				creg[r] <= 16'h0000;
				reboot  <= 1'b1;
			end
			if (!v[11])
				ab_stop();
		end
		if (r == C_S1AUTO && !v[1])
			ab_stop();
		if (r == C_TCOUNT) begin
			tcount     <= v;
			tscale_cnt <= 8'd0;
		end
	end
endtask

always @(posedge clk) begin
	ext_req       <= 1'b0;
	boot_req      <= 1'b0;
	dbg_retire    <= 1'b0;
	dbg_irq       <= 1'b0;
	sport1_strobe <= 1'b0;
	tok_use        = 1'b0;

	pmw_en        <= 1'b0;
	dmw_en        <= 1'b0;
	fw_en         <= 1'b0;

	// control register read at the access address (valid the next clock)
	ctl_q <= (a_addr[4:0] == C_TCOUNT) ? tcount :
	         (a_addr[4:0] == C_PFDATA) ? ((creg[C_PFCTL] & creg[C_PFDATA]) |
	                                      ({13'd0, progflags, 1'b0} & ~creg[C_PFCTL])) :
	         creg[a_addr[4:0]];

	// pin edges (for edge-sensitive interrupts)
	pin0_d <= irq0;
	pin1_d <= irq1;
	pin2_d <= irq2;
	if (irq0 && !pin0_d) lat0 <= 1'b1;
	if (irq1 && !pin1_d) lat1 <= 1'b1;
	if (irq2 && !pin2_d) lat2 <= 1'b1;

	//----------------------------------------------------------------------
	// DAC: one FIFO word per word period of ticks, from 16 periods after the
	// first half buffer came in
	//----------------------------------------------------------------------
	if (dac_reset) begin
		o_run       <= 1'b0;
		o_armed     <= 1'b0;
		ab_rd       <= ab_wr;
		sport1_on   <= 1'b0;
		sport1_data <= 16'h0000;
	end
	else if (tick && o_armed) begin
		if (o_cnt + 22'd1 >= ab_per) begin
			o_cnt <= 22'd0;
			if (!o_run) begin
				o_wait <= o_wait + 5'd1;
				if (o_wait == 5'd15) begin
					o_run     <= 1'b1;
					sport1_on <= 1'b1;
				end
			end
			else if (ab_lvl != 9'd0) begin
				sport1_data   <= ab_q;
				sport1_strobe <= 1'b1;
				ab_rd         <= ab_rd + 9'd1;
			end
		end
		else
			o_cnt <= o_cnt + 22'd1;
	end

	if (reset) begin
		st          <= S_RESET;
		tok         <= 13'd0;
		booting     <= 1'b0;
		ab_on       <= 1'b0;
		ab_due      <= 1'b0;
		ab_blk      <= 1'b0;
		dv_busy     <= 1'b0;
		for (k = 0; k < 32; k = k + 1) creg[k] <= 16'h0000;
		tcount      <= 16'h0000;
		tscale_cnt  <= 8'd0;
		progflags   <= 2'd0;
	end
	else begin
		// count = size / (2 incs) for the half buffer (MAME m_size / (2 * m_incs))
		if (dv_busy) begin : div
			reg [14:0] rem;
			rem = {dv_r[13:0], dv_q[13]};
			if (rem >= {ab_incs, 1'b0}) begin
				dv_r <= rem - {ab_incs, 1'b0};
				dv_q <= {dv_q[12:0], 1'b1};
			end
			else begin
				dv_r <= rem;
				dv_q <= {dv_q[12:0], 1'b0};
			end
			dv_n <= dv_n + 4'd1;
			if (dv_n == 4'd13) begin
				dv_busy  <= 1'b0;
				ab_count <= {dv_q[12:0], rem >= {ab_incs, 1'b0}};
				if ({dv_q[12:0], rem >= {ab_incs, 1'b0}} == 14'd0)
					ab_on <= 1'b0;                     // no words: nothing to time
			end
		end

		case (st)

		//------------------------------------------------------------------
		// reset (MAME device_reset) and boot load
		//------------------------------------------------------------------
		S_RESET: begin
			pc        <= 14'd0;
			loop_on   <= 1'b0;
			mstat     <= 7'd0;
			sstat     <= 8'h55;
			pc_sp     <= 5'd0;
			cnt_sp    <= 3'd0;
			stat_sp   <= 3'd0;
			loop_sp   <= 3'd0;
			imask     <= 6'd0;
			reboot    <= 1'b0;
			flag_out  <= 1'b0;
			flags_out <= 3'd0;
			lat0 <= 1'b0; lat1 <= 1'b0; lat2 <= 1'b0; latt <= 1'b0;
			s1tx_pulse <= 1'b0;
			booting   <= 1'b1;
			boot_addr <= 12'd3;
			boot_req  <= 1'b1;
			st        <= S_BOOTLEN;
		end

		S_BOOTLEN: if (boot_ack) begin
			boot_last <= {boot_data[6:0], 3'b111};          // (n + 1) * 8 - 1
			boot_i    <= 10'd0;
			boot_j    <= 2'd0;
			boot_addr <= 12'd0;
			boot_req  <= 1'b1;
			st        <= S_BOOTW;
		end

		S_BOOTW: if (boot_ack) begin
			if (boot_j != 2'd2) begin
				boot_acc  <= {boot_acc[7:0], boot_data};
				boot_j    <= boot_j + 2'd1;
				boot_addr <= boot_addr + 12'd1;
				boot_req  <= 1'b1;
			end
			else begin
				pmw_en   <= 1'b1;
				pmw_addr <= boot_i;
				pmw_data <= {boot_acc, boot_data};
				if (boot_i == boot_last) begin
					booting <= 1'b0;
					st      <= S_TOP;
				end
				else begin
					boot_i    <= boot_i + 10'd1;
					boot_j    <= 2'd0;
					boot_addr <= boot_addr + 12'd2;               // skip the fourth byte
					boot_req  <= 1'b1;
				end
			end
		end

		//------------------------------------------------------------------
		// instruction boundary (a_addr = pc, a_pm = 1 on entry)
		//------------------------------------------------------------------
		S_TOP: begin
			if (ab_due) begin
				// half buffer due (MAME dcs_irq): its words from I on
				ab_due  <= 1'b0;
				ab_blk  <= 1'b1;
				ab_reg  <= {1'b0, ir[ab_ireg]};
				ab_left <= ab_count;
			end
			else if (ab_blk && ab_left != 14'd0) begin
				a_pm   <= 1'b0;
				a_we   <= 1'b0;
				a_addr <= ab_reg[13:0];
				a_kind <= K_DMA;
				st     <= S_ACC;
			end
			else if (ab_blk) begin
				// I past the words, or back to its base (and the SPORT1
				// transmit interrupt) at the end of the buffer
				ab_blk  <= 1'b0;
				o_armed <= 1'b1;
				if (ab_reg >= {1'b0, br[ab_ireg]} + {1'b0, ab_size}) begin
					ir[ab_ireg] <= br[ab_ireg];
					lat1        <= 1'b1;
					s1tx_pulse  <= 1'b1;
				end
				else begin
					ir[ab_ireg] <= ab_reg[13:0];
					br[ab_ireg] <= ab_reg[13:0] & lmask(lr[ab_ireg]);
				end
			end
			else if (irq_any) begin
				// MAME generate_irq: push PC and status, vector, mask
				dbg_irq <= 1'b1;
				pc_push(pc);
				stat_push();
				s1tx_pulse <= 1'b0;
				if (take2) begin
					lat2   <= 1'b0;
					pc     <= 14'h0004;
					imask  <= icntl[4] ? 6'b000000 : 6'b000000;
				end
				else if (take1) begin
					lat1   <= 1'b0;
					pc     <= 14'h0010;
					imask  <= icntl[4] ? (imask & 6'b111000) : 6'b000000;
				end
				else if (take0) begin
					lat0   <= 1'b0;
					pc     <= 14'h0014;
					imask  <= icntl[4] ? (imask & 6'b111100) : 6'b000000;
				end
				else begin
					latt   <= 1'b0;
					pc     <= 14'h0018;
					imask  <= icntl[4] ? (imask & 6'b111110) : 6'b000000;
				end
			end
			else begin
				s1tx_pulse <= 1'b0;
				if (tok != 13'd0 || tick) begin
					tok_use = 1'b1;
					ppc     <= pc;
					f_int   <= (pc[13:10] == 4'd0);
					if (pc[13:10] == 4'd0)
						st <= S_OPW;                               // pm_q has the opcode next clock
					else begin
						ext_req  <= 1'b1;
						ext_pm   <= 1'b1;
						ext_we   <= 1'b0;
						ext_addr <= pc;
						st       <= S_OPW;
					end
				end
			end
		end

		//------------------------------------------------------------------
		// opcode arrives: next PC, DO-loop end (MAME, before the instruction)
		//------------------------------------------------------------------
		S_OPW: if (f_int || ext_ack) begin
			op <= f_int ? pm_q : ext_rdata;
			if (!loop_on || pc != loop_end)
				pc <= pc + 14'd1;
			else if (loop_cond == 4'd14) begin
				// NOT CE: count down; at the end pop the counter, then the loop
				if (cntr > 14'd1) begin
					cntr <= cntr - 14'd1;
					pc   <= pc_top;
				end
				else begin
					cntr_pop();
					loop_pop();
					pc_pop();
					pc <= pc + 14'd1;
				end
			end
			else if (cond_flags(loop_cond, astat))
				pc <= pc_top;
			else begin
				loop_pop();
				pc_pop();
				pc <= pc + 14'd1;
			end
			st <= S_DEC;
		end

		//------------------------------------------------------------------
		// decode
		//------------------------------------------------------------------
		S_DEC: begin
			dbg_pc     <= ppc;
			dbg_op     <= op;
			dbg_retire <= 1'b1;

			// condition (NOT CE counts the counter down and pops it at the end)
			if (c_has_cond && op[3:0] == 4'd14) begin
				if (cntr > 14'd1) begin
					cok  <= 1'b1;
					cntr <= cntr - 14'd1;
				end
				else begin
					cok <= 1'b0;
					cntr_pop();
				end
			end
			else
				cok <= cond_flags(op[3:0], astat);

			// operands
			o_ax  <= rf[{bk, alu_x_slot(op[10:8])}];
			o_ay  <= (op[12:11] == 2'd0) ? rf[{bk, R_AY0}] : (op[12:11] == 2'd1) ? rf[{bk, R_AY1}] :
			         (op[12:11] == 2'd2) ? rf[{bk, R_AF}] : 16'h0000;
			o_mx  <= rf[{bk, mac_x_slot(op[10:8])}];
			o_my  <= (op[12:11] == 2'd0) ? rf[{bk, R_MY0}] : (op[12:11] == 2'd1) ? rf[{bk, R_MY1}] :
			         (op[12:11] == 2'd2) ? rf[{bk, R_MF}] : 16'h0000;
			o_sx  <= rf[{bk, sh_x_slot(op[10:8])}];
			o_mr  <= {rf[{bk, R_MR2}], rf[{bk, R_MR1}], rf[{bk, R_MR0}]};
			o_sr  <= {rf[{bk, R_SR1}], rf[{bk, R_SR0}]};
			o_se  <= rf[{bk, R_SE}];
			o_sb  <= rf[{bk, R_SB}];
			o_af  <= rf[{bk, R_AF}];
			o_ay0 <= rf[{bk, R_AY0}];

			// value for moves and memory writes
			if (opc == 8'h0D)
				o_mv <= rd_grp(op[9:8], op[3:0]);
			else if (opc[7:4] == 4'h9)
				o_mv <= rd_grp(op[19:18], op[3:0]);
			else if (opc[7:5] == 3'b101)                            // A0-BF immediate data
				o_mv <= op[19:4];
			else if (c_move_am)
				o_mv <= rf[{bk, 1'b0, op[3:0]}];
			else
				o_mv <= rf[{bk, 1'b0, op[7:4]}];

			// memory plan
			m1_on <= 1'b0;
			m2_on <= 1'b0;
			d1_on <= 1'b0;
			d2_on <= 1'b0;
			m1_pm <= 1'b0;
			m1_we <= 1'b0;
			if (opc == 8'h11 || opc[7:4] == 4'h5) begin
				// program memory through DAG2
				m1_on    <= 1'b1;
				m1_pm    <= 1'b1;
				m1_we    <= (opc == 8'h11) ? op[15] : op[19];
				m1_addr  <= ir[{1'b1, op[3:2]}];
				m1_wdata <= {rf[{bk, 1'b0, op[7:4]}], px};
				cw = circ(ir[{1'b1, op[3:2]}], mr[{1'b1, op[1:0]}], br[{1'b1, op[3:2]}], lr[{1'b1, op[3:2]}]);
				d2_on <= 1'b1; d2_i <= {1'b1, op[3:2]}; d2_v <= cw[13:0];
			end
			else if (opc == 8'h12 || opc[7:4] == 4'h6 || opc[7:4] == 4'hA || c_dual) begin
				// data memory through DAG1 (bit-reversed when MSTAT says so)
				m1_on    <= 1'b1;
				m1_we    <= (opc == 8'h12) ? op[15] : (opc[7:4] == 4'h6) ? op[19] : (opc[7:4] == 4'hA);
				m1_addr  <= mstat[M_REV] ? rev14(ir[{1'b0, op[3:2]}]) : ir[{1'b0, op[3:2]}];
				m1_wdata <= {8'h00, (opc[7:4] == 4'hA) ? op[19:4] : rf[{bk, 1'b0, op[7:4]}]};
				cw = circ(ir[{1'b0, op[3:2]}], mr[{1'b0, op[1:0]}], br[{1'b0, op[3:2]}], lr[{1'b0, op[3:2]}]);
				d1_on <= 1'b1; d1_i <= {1'b0, op[3:2]}; d1_v <= cw[13:0];
				if (c_dual) begin
					// and program memory through DAG2 (I in op[7:6], M in op[5:4])
					m2_on   <= 1'b1;
					m2_addr <= ir[{1'b1, op[7:6]}];
					cw = circ(ir[{1'b1, op[7:6]}], mr[{1'b1, op[5:4]}], br[{1'b1, op[7:6]}], lr[{1'b1, op[7:6]}]);
					d2_on <= 1'b1; d2_i <= {1'b1, op[7:6]}; d2_v <= cw[13:0];
				end
			end
			else if (opc == 8'h13 || opc[7:4] == 4'h7 || opc[7:4] == 4'hB) begin
				// data memory through DAG2
				m1_on    <= 1'b1;
				m1_we    <= (opc == 8'h13) ? op[15] : (opc[7:4] == 4'h7) ? op[19] : 1'b1;
				m1_addr  <= ir[{1'b1, op[3:2]}];
				m1_wdata <= {8'h00, (opc[7:4] == 4'hB) ? op[19:4] : rf[{bk, 1'b0, op[7:4]}]};
				cw = circ(ir[{1'b1, op[3:2]}], mr[{1'b1, op[1:0]}], br[{1'b1, op[3:2]}], lr[{1'b1, op[3:2]}]);
				d2_on <= 1'b1; d2_i <= {1'b1, op[3:2]}; d2_v <= cw[13:0];
			end
			else if (opc[7:5] == 3'b100) begin
				// data memory, immediate address
				m1_on    <= 1'b1;
				m1_we    <= opc[4];
				m1_addr  <= op[17:4];
				m1_wdata <= {8'h00, rd_grp(op[19:18], op[3:0])};
			end
			st <= S_EX1;
		end

		//------------------------------------------------------------------
		// execute: ALU, MAC product, shifter, divide (operands from decode).
		// With a memory access the access starts here too.
		//------------------------------------------------------------------
		S_EX1: begin
			// ALU (AR result saturates when MSTAT says so)
			ar = alu(op[16:13], o_ax, o_ay, astat, mstat[M_STICKY]);
			x_alu <= (am_alu && !am_f && mstat[M_SAT] && ar[16 + AV]) ?
			         (ar[16 + AC] ? 16'h8000 : 16'h7fff) : ar[15:0];
			x_ast <= ar[23:16];

			// MAC product
			x_prod <= mac_prod(op[16:13], o_mx, o_my, mstat[M_INT]);

			// shifter (immediate shift code or SE)
			shr = shifter(op[14:11], c_shimm ? op[7:0] : o_se[7:0], o_sx, o_sr, o_se, o_sb, astat);
			x_sr <= shr[31:0];
			x_sb <= shr[47:32];
			x_se <= shr[63:48];
			if (c_shift && op[14:12] == 3'b110)                       // EXP / EXP HIX: SS
				x_ast <= {shr[64], astat[6:0]};
			else if (c_shift)
				x_ast <= astat;

			// DIVS / DIVQ
			if (opc == 8'h06) begin
				x_ast <= {astat[7:6], o_ax[15] ^ o_ay[15], astat[4:0]};
				x_af  <= {o_ay[14:0], o_ay0[15]};
				x_ay0 <= {o_ay0[14:0], o_ax[15] ^ o_ay[15]};
			end
			else if (opc == 8'h07) begin : divq
				reg [16:0] r;
				reg [15:0] t;
				r = astat[AQ] ? ({1'b0, o_af} + {1'b0, o_ax}) : ({1'b0, o_af} - {1'b0, o_ax});
				t = r[15:0] ^ o_ax;
				x_ast <= {astat[7:6], t[15], astat[4:0]};
				x_af  <= {r[14:0], o_ay0[15]};
				x_ay0 <= {o_ay0[14:0], ~t[15]};
			end

			if (m1_on) begin
				a_pm    <= m1_pm;
				a_we    <= m1_we;
				a_addr  <= m1_addr;
				a_wdata <= m1_wdata;
				a_kind  <= K_M1;
				st      <= S_ACC;
			end
			else
				st <= S_EX2;
		end

		//------------------------------------------------------------------
		// memory access (a_* set by the state before)
		//------------------------------------------------------------------
		S_ACC: begin
			if (a_int_pm) begin
				pmw_en   <= a_we;
				pmw_addr <= a_addr[9:0];
				pmw_data <= a_wdata;
			end
			else if (a_int_dm) begin
				dmw_en   <= a_we;
				dmw_addr <= a_addr[8:0];
				dmw_data <= a_wdata[15:0];
			end
			else if (a_ctl) begin
				if (a_we) ctl_write(a_addr[4:0], a_wdata[15:0]);
				else if (a_addr[4:0] == C_PFDATA) progflags <= progflags ^ 2'b11;
			end
			else begin
				ext_req   <= 1'b1;
				ext_pm    <= a_pm;
				ext_we    <= a_we;
				ext_addr  <= a_addr;
				ext_wdata <= a_wdata;
			end
			st <= S_ACCW;
		end

		S_ACCW: if (!a_ext || ext_ack) begin : accw
			reg [23:0] q;
			q = a_int_pm ? pm_q : a_int_dm ? {8'h00, dm_q} : a_ctl ? {8'h00, ctl_q} : ext_rdata;
			case (a_kind)
				K_M1: begin
					m1_q <= q;
					if (m2_on) begin
						a_pm   <= 1'b1;
						a_we   <= 1'b0;
						a_addr <= m2_addr;
						a_kind <= K_M2;
						st     <= S_ACC;
					end
					else
						st <= S_EX2;
				end
				K_M2: begin
					m2_q <= q;
					st   <= S_EX2;
				end
				default: begin
					// a half-buffer word to the FIFO (MAME: reg += m_incs, no wrap)
					fw_en   <= 1'b1;
					fw_addr <= ab_wr;
					fw_data <= q[15:0];
					ab_wr   <= ab_wr + 9'd1;
					ab_reg  <= ab_reg + {ab_incs[13], ab_incs};
					ab_left <= ab_left - 14'd1;
					st      <= S_TOP;
				end
			endcase
		end

		//------------------------------------------------------------------
		// write back
		//------------------------------------------------------------------
		S_EX2: begin
			// DAG post-modify
			if (d1_on) ir[d1_i] <= d1_v;
			if (d2_on) ir[d2_i] <= d2_v;

			// ALU / MAC with an unconditional class, or a condition that holds
			if (c_am && (!c_cond_am || cok)) begin
				if (am_alu) begin
					if (am_f) rf[{bk, R_AF}] <= x_alu;
					else      rf[{bk, R_AR}] <= x_alu;
					astat <= x_ast;
				end
				else if (op[16:13] != 4'd0) begin
					// MAC accumulate (MAME: rounding looks at the product). One
					// add of three: base, the product or its complement, and
					// the rounding constant with the subtraction's carry in
					mac_sub = (op[16:13] == 4'h3 || op[16:15] == 2'b11);
					mac_rnd = (op[16:15] == 2'b00);
					macr = ((op[16:13] == 4'h1 || op[16:13] == 4'h4 || op[16:13] == 4'h5 ||
					         op[16:13] == 4'h6 || op[16:13] == 4'h7) ? 48'd0 : o_mr) +
					       ({{16{x_prod[31]}}, x_prod} ^ {48{mac_sub}}) +
					       {32'd0, mac_rnd, 14'd0, mac_sub};
					if (mac_rnd && x_prod[15:0] == 16'h8000) macr[16] = 1'b0;
					if (am_f)
						rf[{bk, R_MF}] <= macr[31:16];
					else begin
						rf[{bk, R_MR0}] <= macr[15:0];
						rf[{bk, R_MR1}] <= macr[31:16];
						rf[{bk, R_MR2}] <= macr[47:32];
						astat[MV] <= !((macr[39:31] == 9'h000) || (macr[39:31] == 9'h1ff));
					end
				end
			end

			// shifter
			if (c_shift && (opc != 8'h0E || cok)) begin
				if (op[14:11] < 4'hC) begin
					// LSHIFT / ASHIFT / NORM
					rf[{bk, R_SR0}] <= x_sr[15:0];
					rf[{bk, R_SR1}] <= x_sr[31:16];
				end
				else if (opc != 8'h0F) begin
					// EXP, EXP HIX, EXP LO, EXPADJ
					rf[{bk, R_SE}] <= x_se;
					rf[{bk, R_SB}] <= x_sb;
					astat <= x_ast;
				end
			end

			// per instruction
			case (opc)
				8'h02: if (!op[15] && cok) begin               // FLAG OUT (IDLE: nothing)
					if (op[5]) flag_out <= 1'b0;
					if (op[4]) flag_out <= ~flag_out;
					if (op[7]) flags_out[0] <= 1'b0;
					if (op[6]) flags_out[0] <= ~flags_out[0];
					if (op[9]) flags_out[1] <= 1'b0;
					if (op[8]) flags_out[1] <= ~flags_out[1];
					if (op[11]) flags_out[2] <= 1'b0;
					if (op[10]) flags_out[2] <= ~flags_out[2];
				end
				8'h03: if (!op[1]) begin                       // jump / call on FLAG IN (always 0)
					if (op[0]) pc_push(pc);
					pc <= {op[3:2], op[15:4]};
				end
				8'h04: begin                                   // stack control
					if (op[4]) pc_pop();
					if (op[3]) loop_pop();
					if (op[2]) cntr_pop();
					if (op[1]) begin
						if (op[0]) stat_pop();
						else       stat_push();
					end
				end
				8'h05: if (astat[MV]) begin                    // SAT MR
					if (o_mr[39]) begin
						rf[{bk, R_MR2}] <= 16'hffff; rf[{bk, R_MR1}] <= 16'h8000; rf[{bk, R_MR0}] <= 16'h0000;
					end
					else begin
						rf[{bk, R_MR2}] <= 16'h0000; rf[{bk, R_MR1}] <= 16'h7fff; rf[{bk, R_MR0}] <= 16'hffff;
					end
				end
				8'h06, 8'h07: begin                            // DIVS, DIVQ
					astat <= x_ast;
					rf[{bk, R_AF}]  <= x_af;
					rf[{bk, R_AY0}] <= x_ay0;
				end
				8'h09: begin                                   // MODIFY (I, M)
					di = op[4:2];
					cw = circ(ir[di], mr[{di[2], op[1:0]}], br[di], lr[di]);
					ir[di] <= cw[13:0];
				end
				8'h0A: if (cok) begin                          // RTS / RTI
					pc <= pc_top;
					pc_pop();
					if (op[4]) stat_pop();
				end
				8'h0B: if (cok) begin                          // JUMP / CALL (I4-I7)
					if (op[4]) pc_push(pc);
					pc <= ir[{1'b1, op[7:6]}];
				end
				8'h0C: begin                                   // mode control
					mstat <= {op[3]  ? op[2]  : mstat[M_GO],
					          op[15] ? op[14] : mstat[M_TIMER],
					          op[13] ? op[12] : mstat[M_INT],
					          op[11] ? op[10] : mstat[M_SAT],
					          op[9]  ? op[8]  : mstat[M_STICKY],
					          op[7]  ? op[6]  : mstat[M_REV],
					          op[5]  ? op[4]  : mstat[M_BANK]};
					if (op[15] && op[14] && !mstat[M_TIMER]) tscale_cnt <= 8'd0;
				end
				8'h0D: begin                                   // register move
					if (op[9:8] == 2'd3 && op[3:0] == 4'hF) pc_pop();   // reading TOPPCSTACK pops
					wr_grp(op[11:10], op[7:4], o_mv);
				end
				8'h10: begin                                   // shift with register move (after the shift)
					case (op[3:0])
						4'hE:    mvv = x_sr[15:0];
						4'hF:    mvv = x_sr[31:16];
						4'h9:    mvv = (op[14:11] >= 4'hC) ? x_se : rf[{bk, R_SE}];
						default: mvv = rf[{bk, 1'b0, op[3:0]}];
					endcase
					wr0(op[7:4], mvv);
				end
				8'h11: if (!op[15]) begin                      // shift with program memory read
					wr0(op[7:4], m1_q[23:8]);
					px <= m1_q[7:0];
				end
				8'h12, 8'h13: if (!op[15])
					wr0(op[7:4], m1_q[15:0]);
				8'h14, 8'h15, 8'h16, 8'h17: begin              // DO ... UNTIL
					if (loop_sp != 3'd4) begin
						loops[loop_sp[1:0]] <= op[17:0];
						loop_sp   <= loop_sp + 3'd1;
						loop_on   <= 1'b1;
						loop_end  <= op[17:4];
						loop_cond <= op[3:0];
						sstat[LOOP_EMPTY] <= 1'b0;
					end
					else
						sstat[LOOP_OVER] <= 1'b1;
					pc_push(pc);
				end
				8'h18, 8'h19, 8'h1A, 8'h1B: if (cok)          // JUMP
					pc <= op[17:4];
				8'h1C, 8'h1D, 8'h1E, 8'h1F: if (cok) begin    // CALL
					pc_push(pc);
					pc <= op[17:4];
				end
				default: ;
			endcase

			// ALU/MAC with register move (after the op, value from before)
			if (c_move_am)
				wr0(op[7:4], o_mv);

			// immediate loads
			if (opc[7:4] == 4'h3)
				wr_grp(opc[3:2], op[3:0], sext14({2'b00, op[17:4]}));
			if (opc[7:4] == 4'h4)
				wr0(op[3:0], op[19:4]);

			// memory reads into registers (after the op)
			if (opc[7:4] == 4'h5 && !op[19]) begin
				wr0(op[7:4], m1_q[23:8]);
				px <= m1_q[7:0];
			end
			if ((opc[7:4] == 4'h6 || opc[7:4] == 4'h7) && !op[19])
				wr0(op[7:4], m1_q[15:0]);
			if (opc[7:4] == 4'h8)
				wr_grp(op[19:18], op[3:0], m1_q[15:0]);
			if (opc[7:4] == 4'h9 && op[19:18] == 2'd3 && op[3:0] == 4'hF)
				pc_pop();                                      // DM(addr) = TOPPCSTACK pops
			if (c_dual) begin
				case (op[19:18])
					2'd0: rf[{bk, R_AX0}] <= m1_q[15:0];
					2'd1: rf[{bk, R_AX1}] <= m1_q[15:0];
					2'd2: rf[{bk, R_MX0}] <= m1_q[15:0];
					2'd3: rf[{bk, R_MX1}] <= m1_q[15:0];
				endcase
				case (op[21:20])
					2'd0: rf[{bk, R_AY0}] <= m2_q[23:8];
					2'd1: rf[{bk, R_AY1}] <= m2_q[23:8];
					2'd2: rf[{bk, R_MY0}] <= m2_q[23:8];
					2'd3: rf[{bk, R_MY1}] <= m2_q[23:8];
				endcase
				px <= m2_q[7:0];
			end

			// the next fetch, or a reboot
			if (reboot)
				st <= S_RESET;
			else
				st <= S_TOP;
		end

		default: st <= S_RESET;
		endcase

		// instruction cycles (as MAME counts them): the timer, the half-buffer
		// timer (the instruction starting now is counted)
		if (tok_use) begin
			if (mstat[M_TIMER]) begin
				if (tscale_cnt >= creg[C_TSCALE][7:0]) begin
					tscale_cnt <= 8'd0;
					if (tcount == 16'd0) begin
						tcount <= creg[C_TPERIOD];
						latt   <= 1'b1;
					end
					else
						tcount <= tcount - 16'd1;
				end
				else
					tscale_cnt <= tscale_cnt + 8'd1;
			end
			if (ab_on) begin
				if (ab_pcnt + 22'd1 >= ab_per) begin
					ab_pcnt <= 22'd0;
					if (ab_wcnt + 14'd1 >= ab_count) begin
						ab_wcnt <= 14'd0;
						ab_due  <= 1'b1;
					end
					else
						ab_wcnt <= ab_wcnt + 14'd1;
				end
				else
					ab_pcnt <= ab_pcnt + 22'd1;
			end
		end

		// tokens: one per tick, one per instruction started
		case ({tick, tok_use})
			2'b10: if (tok != 13'h1FFF) tok <= tok + 13'd1;
			2'b01: tok <= tok - 13'd1;
			default: ;
		endcase
	end
end

endmodule
