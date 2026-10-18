//============================================================================
//  Finishing move player (Mortal Kombat 3, Ultimate Mortal Kombat 3)
//
//  The OSD's "Finishing Moves" page picks a character and one of its moves
//  (Fatality 1 and 2, Stage Fatality, Animality, Friendship, Babality, or
//  the Mercy every character shares). At FINISH HIM this module enters the
//  move on the controls of the round's winner, turned to the side that
//  player faces. The player stands at the right distance first: the module
//  only enters the inputs.
//
//  The moves are the games' own: each character has a table per button
//  (pressed, and for some moves released) of the joystick or button
//  sequences that start a move, how many frames the sequence may take and
//  what else must hold (distance, round, no block pressed in the round, ...).
//  tools/finishing_moves.py reads those tables out of the program ROMs and
//  writes the inputs as short programs in wunit_finish_moves.vh: UMK3 (all
//  revisions) and MK3 rev 2.0 / 2.1 share one table (MK3 has the first 15
//  characters), MK3 rev 1.0 and the p4.0 chip set have their own. The MRA
//  says which (config byte 14: 0 none, 1 the shared table, 2 MK3 1.x);
//  tools/lua/finishing_moves.lua plays every program in MAME at each
//  distance to check it.
//
//  What the game keeps in main RAM, from its state variable's word (MRA
//  config bytes 12-13, as the Kombat Kode player), UMK3 / MK3:
//    +7 / +5      player 1's block, player 2's 0BBh words on: +0 the
//                 fighter's object (32-bit pointer), +6 the character,
//                 +9 the energy (0: beaten)
//    +194 / +18F  3 while a FINISH HIM runs
//  and in the fighter's object, word 9 its X position (written every
//  frame). The module watches the board's main RAM writes for these.
//
//  A pick is entered only during FINISH HIM, by the player whose opponent's
//  energy is 0, and (but for the Mercy) only if that player fights as the
//  picked character; otherwise an OSD message says why. The Mercy is the
//  winner's own, whatever the OSD's character (MK3 1.0 / p4.0's Cyrax has
//  none: a message says so, as for any move a table lacks). The player starts
//  10 frames after the pick (frames are the top level's running frames,
//  osd_frame, so the OSD pausing the game holds the player too), then runs
//  the program, one step at a time:
//    tap      the inputs pressed for 4 frames, then 4 frames released
//    hold     the inputs pressed from now on, then 4 frames
//    release  the inputs let go, then 4 frames
//    wait     n frames
//    timing   taps from now on n frames pressed, n' after (also after a
//             hold or release); one frame
//  4 + 4 fits every sequence but one (the tightest that fits: Cyrax's Stage
//  Fatality, 18 frames allowed from its first button to its third); MK3
//  1.x's Jax Fatality 1 (five directions) needs 3 + 3. Forward and Back
//  become Right or Left by the side the opponent stands on.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_finish
(
	input             clk,
	input             reset,
	input       [4:0] opt,           // the OSD's character option (its alphabetical list)
	input             sel,           // one clock: a move was picked in the OSD
	input       [2:0] sel_slot,      // 0-5 the character's moves, 6 the Mercy
	input       [1:0] table_id,      // MRA config byte 14: 0 none, 1 UMK3 / MK3 2.x, 2 MK3 1.x
	input             umk3,          // the RAM layout: UMK3 (else MK3)
	input      [15:0] kstate,        // the game's state variable, main RAM word (0: none)
	input             ram_wr,        // the board's main RAM writes
	input      [17:0] ram_wa,
	input      [15:0] ram_wd,
	input             frame,         // one clock at the start of each running frame
	output reg [15:0] press0,        // IN0 bits held (active high)
	output reg [15:0] press1,        // IN1 bits held (active high)
	output reg        info_req,      // one clock: show OSD info message `info`
	output reg  [7:0] info,          // 4 not at FINISH HIM, 5 not the winner's character,
	                                 // 6 entered, 7 the MRA has no table, 8 the winner
	                                 // has no such move
	output reg [15:0] menu,          // OSD menu mask bits (set: hide): 0, 7-15 the
	                                 // character (0 7 8 9 A: its number / 5, B-F: % 5),
	                                 // 3 clear for the MK3 1.x table
	output      [4:0] char_id,       // the picked character, the game's number
	output            busy
);

//////////////////////////////////////////////////////////////////
// What the game keeps in main RAM
//////////////////////////////////////////////////////////////////

reg  [17:0] a_b1, a_b2, a_fh;       // player blocks, FINISH HIM state
reg  [17:0] a_o1, a_o2;             // the X positions in the fighters' objects
reg  [31:4] obj1, obj2;             // the objects (34010 bit addresses)
reg  [15:0] x1, x2;                 // the X positions
reg  [15:0] e1, e2;                 // energy
reg   [4:0] c1, c2;                 // characters
reg  [15:0] fh;                     // FINISH HIM state (3: running)

reg         w_wr;                   // the write, registered
reg  [17:0] w_a;
reg  [15:0] w_d;
reg  [17:0] w_b1, w_b2;             // its offsets in the player blocks

always @(posedge clk) begin
	a_b1 <= {2'b00, kstate} + (umk3 ? 18'd7 : 18'd5);
	a_b2 <= {2'b00, kstate} + (umk3 ? 18'd7 + 18'hBB : 18'd5 + 18'hBB);
	a_fh <= {2'b00, kstate} + (umk3 ? 18'h194 : 18'h18F);
	a_o1 <= obj1[31:22] == 10'h004 ? obj1[21:4] + 18'd9 : 18'h3FFFF;
	a_o2 <= obj2[31:22] == 10'h004 ? obj2[21:4] + 18'd9 : 18'h3FFFF;

	w_wr <= ram_wr && kstate != 16'd0;
	w_a  <= ram_wa;
	w_d  <= ram_wd;
	w_b1 <= ram_wa - a_b1;
	w_b2 <= ram_wa - a_b2;

	if (reset) begin
		obj1 <= 28'd0;
		obj2 <= 28'd0;
		fh   <= 16'd0;
	end
	else if (w_wr) begin
		case (w_b1)
			18'd0: obj1[15:4]  <= w_d[15:4];
			18'd1: obj1[31:16] <= w_d;
			18'd6: c1          <= w_d[4:0];
			18'd9: e1          <= w_d;
			default: ;
		endcase
		case (w_b2)
			18'd0: obj2[15:4]  <= w_d[15:4];
			18'd1: obj2[31:16] <= w_d;
			18'd6: c2          <= w_d[4:0];
			18'd9: e2          <= w_d;
			default: ;
		endcase
		if (w_a == a_fh) fh <= w_d;
		if (w_a == a_o1) x1 <= w_d;
		if (w_a == a_o2) x2 <= w_d;
	end
end

//////////////////////////////////////////////////////////////////
// The programs (generated: tools/finishing_moves.py)
//
// idx_q <= the first step of move idx_a = {MK3 1.x table, character,
// slot}, 0 if there is no such move; step <= step pc of the programs
//   [15:13] 0 end, 1 tap, 2 hold, 3 release, 4 wait ([7:0] frames),
//           5 tap timing ([7:4] frames pressed, [3:0] after)
//   [9:0]   the inputs: U D F B HP LP HK LK BL RN (bit 9 to bit 0)
//////////////////////////////////////////////////////////////////

reg   [8:0] idx_a;
reg  [10:0] idx_q;
reg  [10:0] pc;
/* verilator lint_off UNUSEDSIGNAL */
reg  [15:0] step;                   // [12:10] unused
/* verilator lint_on UNUSEDSIGNAL */

`include "wunit_finish_moves.vh"

// the picked character, and the OSD lines to show for it: the menu mask
// bit of its number / 5 (0 7 8 9 A) and of its number % 5 (B-F) clear
wire  [4:0] sel_char = opt_char(umk3, opt);
assign      char_id  = sel_char;
/* verilator lint_off UNUSEDSIGNAL */
wire  [4:0] grp5 = sel_char / 5'd5;  // 0-4
wire  [4:0] ind5 = sel_char % 5'd5;
/* verilator lint_on UNUSEDSIGNAL */
wire  [2:0] grp = grp5[2:0];
wire  [2:0] ind = ind5[2:0];

always @(posedge clk) begin
	menu        <= 16'hFFFF;
	menu[2:1]   <= 2'b00;
	menu[6:4]   <= 3'b000;
	menu[3]     <= table_id != 2'd2;
	menu[0]     <= grp != 3'd0;
	menu[10:7]  <= ~(4'b0001 << (grp - 3'd1)) | {4{grp == 3'd0}};
	menu[15:11] <= ~(5'b00001 << ind);
end

//////////////////////////////////////////////////////////////////
// The player
//////////////////////////////////////////////////////////////////

localparam [7:0] LEAD = 8'd10;
localparam [2:0] OP_TAP = 3'd1, OP_HOLD = 3'd2, OP_REL = 3'd3, OP_WAIT = 3'd4, OP_TIME = 3'd5;

reg   [1:0] lk;                    // looking the pick up: 1 address, 2 read, 3 start
reg   [2:0] pick_slot;
reg   [4:0] pick_char;
reg         run;
reg         on;                    // a tap is pressed
reg   [7:0] left;                  // frames left in this phase
reg   [3:0] t_on, t_off;           // a tap: frames pressed, frames after
reg   [9:0] held, tapm;
reg         p2;                    // the winner is player 2
reg         right;                 // the winner faces right

assign busy = (lk != 2'd0) | run;

// the inputs as the winner's IN0 / IN1 bits (MAME's midwunit.cpp MK3
// ports: IN0 P1 U D L R HP BL HK in bits 0-6, P2 in bits 8-14; IN1 P1 LP
// LK RN in bits 0-2, P2 in bits 4-6)
wire  [9:0] m    = held | tapm;
wire        r_on = right ? m[7] : m[6];
wire        l_on = right ? m[6] : m[7];
wire  [6:0] pad0 = {m[3], m[1], m[5], r_on, l_on, m[8], m[9]};  // HK BL HP R L D U
wire  [2:0] pad1 = {m[0], m[2], m[4]};                          // RN LK LP

always @(posedge clk) begin
	idx_a  <= {table_id == 2'd2, pick_char, pick_slot};
	press0 <= !run ? 16'h0000 : p2 ? {1'b0, pad0, 8'h00} : {9'h000, pad0};
	press1 <= !run ? 16'h0000 : p2 ? {9'h000, pad1, 4'h0} : {13'h0000, pad1};
end

always @(posedge clk) begin
	info_req <= 1'b0;

	if (reset) begin
		lk   <= 2'd0;
		run  <= 1'b0;
		held <= 10'd0;
		tapm <= 10'd0;
	end
	else if (sel && !busy) begin
		pick_slot <= sel_slot;
		// the Mercy: the winner's own (every fighter's is the same input,
		// but a table may have none for one)
		pick_char <= (sel_slot == 3'd6) ? (e1 == 16'd0 ? c2 : c1) : sel_char;
		p2        <= e1 == 16'd0;
		right     <= e1 == 16'd0 ? $signed(x1) > $signed(x2) : $signed(x2) > $signed(x1);
		if (table_id == 2'd0 || kstate == 16'd0) begin
			info     <= 8'd7;
			info_req <= 1'b1;
		end
		else if (fh != 16'd3 || ((e1 == 16'd0) == (e2 == 16'd0))) begin
			info     <= 8'd4;
			info_req <= 1'b1;
		end
		else if (sel_slot != 3'd6 && (e1 == 16'd0 ? c2 : c1) != sel_char) begin
			info     <= 8'd5;
			info_req <= 1'b1;
		end
		else
			lk <= 2'd1;
	end
	else if (lk != 2'd0) begin
		lk <= lk + 2'd1;
		if (lk == 2'd3) begin
			if (idx_q != 11'd0) begin
				run  <= 1'b1;
				pc   <= idx_q;
				on    <= 1'b0;
				left  <= LEAD;
				held  <= 10'd0;
				tapm  <= 10'd0;
				t_on  <= 4'd4;
				t_off <= 4'd4;
			end
			else begin
				// the table has no such move for this fighter
				info     <= 8'd8;
				info_req <= 1'b1;
			end
		end
	end
	else if (frame && run) begin
		if (left > 8'd1)
			left <= left - 8'd1;
		else if (on) begin
			on   <= 1'b0;
			tapm <= 10'd0;
			left <= {4'd0, t_off};
		end
		else begin
			pc <= pc + 11'd1;
			case (step[15:13])
				OP_TAP: begin
					on   <= 1'b1;
					tapm <= step[9:0];
					left <= {4'd0, t_on};
				end
				OP_HOLD: begin
					held <= held | step[9:0];
					left <= {4'd0, t_off};
				end
				OP_REL: begin
					held <= held & ~step[9:0];
					left <= {4'd0, t_off};
				end
				OP_WAIT:
					left <= step[7:0];
				OP_TIME: begin
					t_on  <= step[7:4];
					t_off <= step[3:0];
					left  <= 8'd1;
				end
				default: begin
					run      <= 1'b0;
					held     <= 10'd0;
					info     <= 8'd6;
					info_req <= 1'b1;
				end
			endcase
		end
	end
end

endmodule
