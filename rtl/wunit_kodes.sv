//============================================================================
//  Kombat Kode player (Mortal Kombat 3, Ultimate Mortal Kombat 3)
//
//  The OSD's "Kombat Kodes" page picks a kode; this module waits for the
//  screen the game takes it on and enters it on the player controls, as two
//  players would.
//
//  Kombat Kodes (both games, every revision). On the VS screen before a
//  two-player fight each player has three icons, each 0-9, stepped by Low
//  Punch, Block and Low Kick (P1 the first three digits, P2 the last three).
//  When the screen ends the game looks the six digits up in a table in its
//  program ROM and runs the matching kode, which shows its message under
//  the fighters. MK3 has 19 kodes, UMK3 those and 29 more (stages, more
//  messages, 2 on 2 Explosive Kombat); tools/kombat_kodes.py checks every
//  kode below against each set's table.
//
//  Ultimate Kombat Kodes. At game over, while a hidden character is still
//  locked (UMK3: Mileena, Ermac or Classic Sub-Zero; MK3 from revision 1.0
//  on: Smoke), the game shows "ENTER (AN / THE) ULTIMATE KOMBAT KODE": ten
//  icons, P1 then P2 stepping theirs with High Punch, Low Punch, Block, Low
//  Kick and High Kick, and a countdown. A kode that matches unlocks its
//  character and the game stores that in its CMOS (MK3: CMOS item 10h =
//  EDB0h, also set by the EJB menu's SMOKE item). Both games use the same
//  screen state and buttons.
//
//  Both screens set the game's state variable (in main RAM, its address
//  from the MRA: config bytes 12-13) and run for a few seconds: the VS
//  screen state 9, about 230 frames, the Ultimate Kombat Kode screen state
//  13h, about 580. The game starts reading the buttons 11-16 frames in.
//  The player starts 24 frames after the state was written, and only while
//  the kode still fits in the screen (the VS screen: up to frame 120, the
//  game over screen: up to frame 400); a kode picked later waits for the
//  next such screen.
//
//  Entering: in round n (1-9) every button whose digit is n or more is
//  pressed, all at once, for 4 frames, then released for 4. A kode takes as
//  many rounds as its largest digit, at most 72 frames. The game steps an
//  icon on each press (backwards while the player holds Up, which the
//  player never does).
//
//  Frames are the top level's running frames (osd_frame), so a paused game
//  pauses the kode with it.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_kodes
(
	input             clk,
	input             reset,
	input             sel,           // one clock: a kode was picked in the OSD
	input       [5:0] sel_idx,       // which, as numbered in kode() below
	input             state_wr,      // one clock: the game wrote its state variable
	input      [15:0] state_val,
	input             frame,         // one clock at the start of each running frame
	output reg [15:0] press0,        // IN0 bits held (active high)
	output reg [15:0] press1,        // IN1 bits held (active high)
	output reg        info_req,      // one clock: show OSD info message `info`
	output reg  [7:0] info,          // 1 waiting for a VS screen, 2 for game over, 3 entered
	output            busy           // a kode is waiting or being entered
);

// a kode: {Ultimate Kombat Kode, ten BCD digits, the first on top}; a VS
// screen kode fills the first six
function automatic [40:0] vs(input [23:0] d);
	vs = {1'b0, d, 16'h0000};
endfunction

function automatic [40:0] ukk(input [39:0] d);
	ukk = {1'b1, d};
endfunction

// the OSD's kodes, in its order (status bits 18-56, 103-109, 64-67, then 73 in
// the top level: tools/kombat_kodes.py KODE_BITS)
function automatic [40:0] kode(input [5:0] n);
	case (n)
		// fighting (11-16 UMK3 only)
		6'd0:  kode = vs(24'h100100);       // THROWING DISABLED
		6'd1:  kode = vs(24'h020020);       // BLOCKING DISABLED
		6'd2:  kode = vs(24'h987123);       // NO POWERBARS
		6'd3:  kode = vs(24'h466466);       // UNLIMITED RUN
		6'd4:  kode = vs(24'h688422);       // DARK KOMBAT
		6'd5:  kode = vs(24'h460460);       // RANDPER KOMBAT
		6'd6:  kode = vs(24'h985125);       // PSYCHO KOMBAT
		6'd7:  kode = vs(24'h033000);       // PLAYER 1 HALF POWER
		6'd8:  kode = vs(24'h000033);       // PLAYER 2 HALF POWER
		6'd9:  kode = vs(24'h707000);       // PLAYER 1 QUARTER POWER
		6'd10: kode = vs(24'h000707);       // PLAYER 2 QUARTER POWER
		6'd11: kode = vs(24'h044440);       // UNIKORIV REFERRI: SANS POWER
		6'd12: kode = vs(24'h788322);       // FAST UPPERCUT RECOVERY ENABLED
		6'd13: kode = vs(24'h010010);       // THROWING ENCOURAGED
		6'd14: kode = vs(24'h300300);       // SILENT KOMBAT
		6'd15: kode = vs(24'h227227);       // EXPLOSIVE KOMBAT (2 on 2)
		6'd16: kode = vs(24'h022220);       // EXPLOSIVE KOMBAT / THROWING DISABLED (2 on 2)
		6'd17: kode = vs(24'h642468);       // YOU ARE ENTERING THE LAND OF RELLIM (Galaga)
		// the winner of round 1 battles
		6'd18: kode = vs(24'h969141);       // MOTARO
		6'd19: kode = vs(24'h033564);       // SHAO KAHN
		6'd20: kode = vs(24'h769342);       // NOOB SAIBOT
		6'd21: kode = vs(24'h205205);       // SMOKE
		// KOMBAT ZONE: (UMK3)
		6'd22: kode = vs(24'h880088);       // SUBWAY
		6'd23: kode = vs(24'h079035);       // STREET
		6'd24: kode = vs(24'h343343);       // ROOFTOP
		6'd25: kode = vs(24'h880220);       // KAHN'S TOWER
		6'd26: kode = vs(24'h077022);       // THE BRIDGE
		6'd27: kode = vs(24'h123901);       // SOUL CHAMBER
		6'd28: kode = vs(24'h091190);       // BELL TOWER
		6'd29: kode = vs(24'h600040);       // KOMBAT TEMPLE
		6'd30: kode = vs(24'h666333);       // THE GRAVEYARD
		6'd31: kode = vs(24'h820028);       // THE PIT 3
		6'd32: kode = vs(24'h002003);       // RIVER KOMBAT
		6'd33: kode = vs(24'h666444);       // SCORPION'S LAIR
		6'd34: kode = vs(24'h004700);       // KAHN'S KAVE
		6'd35: kode = vs(24'h330033);       // JADE'S DESERT
		6'd36: kode = vs(24'h933933);       // SCISLAC BUSOREZ
		6'd37: kode = vs(24'h050050);       // NOOB SAIBOT DORFEN
		// messages (41-46 UMK3 only)
		6'd38: kode = vs(24'h987666);       // HOLD FLIPPERS DURING CASINO RUN
		6'd39: kode = vs(24'h282282);       // NO FEAR = EB BUTTON, SKYDIVE, MAX COUNTDOWN
		6'd40: kode = vs(24'h123926);       // THERE IS NO KNOWLEDGE THAT IS NOT POWER
		6'd41: kode = vs(24'h999999);       // REVISION 1.x
		6'd42: kode = vs(24'h550550);       // SEE THE MORTAL KOMBAT LIVE TOUR !!
		6'd43: kode = vs(24'h717313);       // RAIN CAN BE FOUND IN THE GRAVEYARD
		6'd44: kode = vs(24'h448844);       // DON'T JUMP AT ME - MXV
		6'd45: kode = vs(24'h122221);       // SKUNKY !! - E.F.
		6'd46: kode = vs(24'h004400);       // WHATCHA GUN DO ? - E.B.
		// Ultimate Kombat Kodes (47-49 UMK3, 50 MK3: status bit 73)
		6'd47: kode = ukk(40'h22264_22264); // Mileena
		6'd48: kode = ukk(40'h12344_44321); // Ermac
		6'd49: kode = ukk(40'h81835_81835); // Classic Sub-Zero
		6'd50: kode = ukk(40'h10902_22234); // Smoke (MK3)
		default: kode = 41'd0;
	endcase
endfunction

// the button of each digit, digit 0 in the low 16 bits (MAME's midwunit.cpp
// MK3 ports: IN0 P1 HP 0010 BL 0020 HK 0040, P2 HP 1000 BL 2000 HK 4000;
// IN1 P1 LP 0001 LK 0002, P2 LP 0010 LK 0020)
//                              9        8        7        6        5        4        3        2        1        0
localparam [159:0] VS_IN0  = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h2000,16'h0000,16'h0000,16'h0020,16'h0000};
localparam [159:0] VS_IN1  = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0020,16'h0000,16'h0010,16'h0002,16'h0000,16'h0001};
localparam [159:0] UKK_IN0 = {16'h4000,16'h0000,16'h2000,16'h0000,16'h1000,16'h0040,16'h0000,16'h0020,16'h0000,16'h0010};
localparam [159:0] UKK_IN1 = {16'h0000,16'h0020,16'h0000,16'h0010,16'h0000,16'h0000,16'h0002,16'h0000,16'h0001,16'h0000};

// the buttons pressed in round r: {IN1, IN0}
function automatic [31:0] round_mask(input [40:0] k, input [3:0] r);
	reg [15:0] m0, m1;
	reg  [3:0] d;
	integer i;
	begin
		m0 = 16'h0000;
		m1 = 16'h0000;
		for (i = 0; i < 10; i = i + 1) begin
			d = k[39 - 4 * i -: 4];
			if (r != 4'd0 && d >= r) begin
				m0 = m0 | (k[40] ? UKK_IN0[16 * i +: 16] : VS_IN0[16 * i +: 16]);
				m1 = m1 | (k[40] ? UKK_IN1[16 * i +: 16] : VS_IN1[16 * i +: 16]);
			end
		end
		round_mask = {m1, m0};
	end
endfunction

localparam [15:0] ST_VS  = 16'h0009;   // the game's state: VS screen of a two-player fight
localparam [15:0] ST_UKK = 16'h0013;   // Ultimate Kombat Kode screen
localparam  [9:0] FIRST    = 10'd24;   // frames after the state write: the first press
localparam  [9:0] VS_LAST  = 10'd120;  // the last start that fits the VS screen
localparam  [9:0] UKK_LAST = 10'd400;  // and the game over screen
localparam  [2:0] HOLD = 3'd4, GAP = 3'd4;

reg  [40:0] k;                 // the kode
reg         armed;             // waiting for its screen
reg         run;               // entering it
reg   [3:0] rnd;               // round
reg         gap_phase;         // released between rounds
reg   [2:0] left;              // frames left in this phase
reg  [15:0] gstate;            // the game's state variable as last written
reg   [9:0] since;             // running frames since that write (saturates)

wire [40:0] sel_kode  = kode(sel_idx);
wire [31:0] next_mask = round_mask(k, rnd + 4'd1);
wire        window    = (gstate == (k[40] ? ST_UKK : ST_VS)) && (since >= FIRST) &&
                        (since <= (k[40] ? UKK_LAST : VS_LAST));

assign busy = armed | run;

always @(posedge clk) begin
	info_req <= 1'b0;

	if (reset) begin
		armed  <= 1'b0;
		run    <= 1'b0;
		press0 <= 16'h0000;
		press1 <= 16'h0000;
		gstate <= 16'h0000;
		since  <= 10'd0;
	end
	else begin
		if (state_wr) begin
			gstate <= state_val;
			since  <= 10'd0;
		end
		else if (frame && since != 10'h3FF)
			since <= since + 10'd1;

		if (sel && !run && sel_kode != 41'd0) begin
			// a new pick replaces one still waiting
			k        <= sel_kode;
			armed    <= 1'b1;
			info     <= sel_kode[40] ? 8'd2 : 8'd1;
			info_req <= 1'b1;
		end
		else if (frame && armed && window) begin
			armed            <= 1'b0;
			run              <= 1'b1;
			rnd              <= 4'd1;
			gap_phase        <= 1'b0;
			left             <= HOLD;
			{press1, press0} <= round_mask(k, 4'd1);
		end
		else if (frame && run) begin
			if (left > 3'd1)
				left <= left - 3'd1;
			else if (!gap_phase) begin
				press0    <= 16'h0000;
				press1    <= 16'h0000;
				gap_phase <= 1'b1;
				left      <= GAP;
			end
			else if (next_mask == 32'd0) begin
				run      <= 1'b0;
				info     <= 8'd3;
				info_req <= 1'b1;
			end
			else begin
				rnd              <= rnd + 4'd1;
				gap_phase        <= 1'b0;
				left             <= HOLD;
				{press1, press0} <= next_mask;
			end
		end
	end
end

endmodule
