//============================================================================
//  Secret menu code player
//
//  Some Wolf Unit games open a hidden menu when a button code is entered on
//  the player controls. The OSD can enter it for the player: this module
//  presses the code's buttons on IN0, frame by frame, on top of the real
//  inputs, exactly as a player would.
//
//  Codes (IN0 bits as MAME numbers them, see midwunit.cpp):
//
//    1  EJB menu, Mortal Kombat 3 and Ultimate MK3 (all revisions): in
//       attract mode, P1 Block x5, P2 Block x10, P1 Block x3, P2 Block x1,
//       P1 Block x2, P2 Block x2, P1 Block x3, P2 Block x3. The developers'
//       test menu: extra audits, credits, the Penacho/Miller game, Smoke or
//       the hidden characters, character endings, fatality demonstration.
//
//    2  Secret Midway Menu, NBA Hangtime and Maximum Hangtime (all
//       revisions): both players hold Up and their three buttons; 53 frames
//       later (when the game's counter runs out) both must be holding Down.
//       The game then shows the design team screen and polls a 15-button
//       password on it: P1 Turbo x2, P2 Shoot x3, P2 Pass x2, P1 Shoot,
//       P1 Pass, P2 Turbo x2, P1 Turbo x4 (each a single button, released
//       in between). Statistics pages follow (dunks, play time, averages,
//       teams, stored initials and PINs).
//
//  Each step holds a set of IN0 bits for `hold` frames, then releases them
//  for `gap` frames. A frame is one clock of `frame` (the start of a vertical
//  blank while the game runs), so the code keeps pace with the game when it
//  is paused. A start request waits for the next frame before the first
//  press, so every press lasts whole frames.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
//============================================================================

module wunit_macro
(
	input             clk,
	input             reset,
	input             start,         // one clock: enter the code
	input       [1:0] code,          // 0 none, 1 EJB menu, 2 Secret Midway Menu
	input             frame,         // one clock at the start of each running frame
	output reg [15:0] press,         // IN0 bits held (active high)
	output            busy
);

// one step: {last, IN0 bits, hold frames, gap frames}
localparam [15:0] P1_BLOCK = 16'h0020, P2_BLOCK = 16'h2000;     // MK3 IN0
localparam [15:0] P1_SHOOT = 16'h0010, P1_PASS = 16'h0020, P1_TURBO = 16'h0040;  // Hangtime IN0
localparam [15:0] P2_SHOOT = 16'h1000, P2_PASS = 16'h2000, P2_TURBO = 16'h4000;

function automatic [32:0] stp(input last, input [15:0] mask, input [7:0] hold, input [7:0] gap);
	stp = {last, mask, hold, gap};
endfunction

// EJB menu: 29 presses of a Block button, 4 frames down and 4 up (the game
// takes 2 to 6 frame presses in MAME)
function automatic [32:0] ejb_step(input [5:0] n);
	reg [15:0] m;
	begin
		if      (n <  6'd5)  m = P1_BLOCK;      //  0- 4  P1 x5
		else if (n < 6'd15)  m = P2_BLOCK;      //  5-14  P2 x10
		else if (n < 6'd18)  m = P1_BLOCK;      // 15-17  P1 x3
		else if (n < 6'd19)  m = P2_BLOCK;      // 18     P2 x1
		else if (n < 6'd21)  m = P1_BLOCK;      // 19-20  P1 x2
		else if (n < 6'd23)  m = P2_BLOCK;      // 21-22  P2 x2
		else if (n < 6'd26)  m = P1_BLOCK;      // 23-25  P1 x3
		else                 m = P2_BLOCK;      // 26-28  P2 x3
		ejb_step = stp(n == 6'd28, m, 8'd4, 8'd4);
	end
endfunction

// Secret Midway Menu: the two-player hold, then the password once the
// secret process has started (the design team screen)
function automatic [32:0] smm_step(input [5:0] n);
	begin
		case (n)
			6'd0:    smm_step = stp(1'b0, 16'h7171, 8'd4,  8'd0);   // Up + 3 buttons, both players
			6'd1:    smm_step = stp(1'b0, 16'h0202, 8'd70, 8'd6);   // Down, both, past frame 53
			6'd2,
			6'd3:    smm_step = stp(1'b0, P1_TURBO, 8'd4,  8'd4);
			6'd4,
			6'd5,
			6'd6:    smm_step = stp(1'b0, P2_SHOOT, 8'd4,  8'd4);
			6'd7,
			6'd8:    smm_step = stp(1'b0, P2_PASS,  8'd4,  8'd4);
			6'd9:    smm_step = stp(1'b0, P1_SHOOT, 8'd4,  8'd4);
			6'd10:   smm_step = stp(1'b0, P1_PASS,  8'd4,  8'd4);
			6'd11,
			6'd12:   smm_step = stp(1'b0, P2_TURBO, 8'd4,  8'd4);
			6'd13,
			6'd14,
			6'd15:   smm_step = stp(1'b0, P1_TURBO, 8'd4,  8'd4);
			default: smm_step = stp(1'b1, P1_TURBO, 8'd4,  8'd4);   // 16, the last
		endcase
	end
endfunction

reg   [1:0] run;                    // the code being played (0: idle)
reg         armed;                  // started, waiting for the first frame
reg   [5:0] n;                      // step
reg         gap_phase;              // releasing between presses
reg   [7:0] left;                   // frames left in this phase

// this step and the next, {last, mask, hold, gap}
wire [32:0] cur = (run == 2'd2) ? smm_step(n)        : ejb_step(n);
wire [32:0] nxt = (run == 2'd2) ? smm_step(n + 6'd1) : ejb_step(n + 6'd1);

wire        cur_last = cur[32];
wire [15:0] cur_mask = cur[31:16];
wire  [7:0] cur_hold = cur[15:8];
wire  [7:0] cur_gap  = cur[7:0];

assign busy = armed | (run != 2'd0);

always @(posedge clk) begin
	if (reset) begin
		run   <= 2'd0;
		armed <= 1'b0;
		press <= 16'h0000;
	end
	else if (start && code != 2'd0 && !busy) begin
		run       <= code;
		armed     <= 1'b1;
		n         <= 6'd0;
		gap_phase <= 1'b0;
	end
	else if (frame && armed) begin
		// the first press starts with a frame
		armed <= 1'b0;
		press <= cur_mask;
		left  <= cur_hold;
	end
	else if (frame && run != 2'd0) begin
		if (left > 8'd1)
			left <= left - 8'd1;
		else if (!gap_phase && cur_gap != 8'd0) begin
			press     <= 16'h0000;
			gap_phase <= 1'b1;
			left      <= cur_gap;
		end
		else if (cur_last) begin
			press <= 16'h0000;
			run   <= 2'd0;
		end
		else begin
			n         <= n + 6'd1;
			gap_phase <= 1'b0;
			press     <= nxt[31:16];
			left      <= nxt[15:8];
		end
	end
end

endmodule
