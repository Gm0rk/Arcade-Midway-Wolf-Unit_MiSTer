//============================================================================
//  Midway Wolf Unit for MiSTer
//
//  Top level (emu): HPS interface, ROM loading, memories, per-game
//  configuration and inputs, the OSD's code players (hidden menus, Kombat
//  Kodes, finishing moves), video output with CRT Adjust and CRT V-Size,
//  audio. Nothing in sys/ is changed (MiSTer-devel rule): the CRT stage sits
//  here, in front of the framework's video path.
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
//  Sound: the DCS board (rtl/dcs_audio.sv: an ADSP-2105 at 10 MHz, its
//  sound ROMs in SDRAM, 16-bit mono at 31250 Hz).
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
	"H1P1O[89:86],CRT V-Size,0,+1,+2,+3,+4,+5,+6,+7,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[90],CRT V-Size Mode,PVM,Cabinet;",
	"P2,Controls;",
	"P2-;",
	"P2O[9],Service Mode,Off,On;",
	"P2T[12],Service Credit;",
	"P2T[13],Tilt;",
	"H5-;",
	"H2R[16],Open EJB Menu (attract mode);",
	"h2H3R[16],Open Secret Midway Menu;",
	"H4O[17],EJB Character Endings,Off,On;",
	"H2P3,Kombat Kodes;",
	"P3-;",
	"P3P4,Fight;",
	"P3P5,Round 1 Winner Battles;",
	"H6P3P6,Kombat Zone;",
	"P3P7,Messages;",
	"P3P8,Ultimate Kombat Kodes;",
	"P4-;",
	"P4R[18],Throwing Disabled 100-100;",
	"P4R[19],Blocking Disabled 020-020;",
	"P4R[20],No Powerbars 987-123;",
	"P4R[21],Unlimited Run 466-466;",
	"P4R[22],Dark Kombat 688-422;",
	"P4R[23],Randper Kombat 460-460;",
	"P4R[24],Psycho Kombat 985-125;",
	"P4R[25],P1 Half Power 033-000;",
	"P4R[26],P2 Half Power 000-033;",
	"P4R[27],P1 Quarter Power 707-000;",
	"P4R[28],P2 Quarter Power 000-707;",
	"H6P4R[29],Sans Power 044-440;",
	"H6P4R[30],Uppercut Recovery 788-322;",
	"H6P4R[31],Throwing Encouraged 010-010;",
	"H6P4R[32],Silent Kombat 300-300;",
	"H6P4R[33],Explosive Kombat 227-227;",
	"H6P4R[34],Explosive No Throws 022-220;",
	"P4R[35],Galaga 642-468;",
	"P5-;",
	"P5R[36],Motaro 969-141;",
	"P5R[37],Shao Kahn 033-564;",
	"P5R[38],Noob Saibot 769-342;",
	"P5R[39],Smoke 205-205;",
	"P6-;",
	"H6P6R[40],Subway 880-088;",
	"H6P6R[41],Street 079-035;",
	"H6P6R[42],Rooftop 343-343;",
	"H6P6R[43],Kahn's Tower 880-220;",
	"H6P6R[44],The Bridge 077-022;",
	"H6P6R[45],Soul Chamber 123-901;",
	"H6P6R[46],Bell Tower 091-190;",
	"H6P6R[47],Kombat Temple 600-040;",
	"H6P6R[48],The Graveyard 666-333;",
	"H6P6R[49],The Pit 3 820-028;",
	"H6P6R[50],River Kombat 002-003;",
	"H6P6R[51],Scorpion's Lair 666-444;",
	"H6P6R[52],Kahn's Kave 004-700;",
	"H6P6R[53],Jade's Desert 330-033;",
	"H6P6R[54],Scislac Busorez 933-933;",
	"H6P6R[55],Noob Saibot Dorfen 050-050;",
	"P7-;",
	"P7R[56],Hold Flippers 987-666;",
	"P7R[57],No Fear 282-282;",
	"P7R[58],No Knowledge 123-926;",
	"H6P7R[59],Revision 999-999;",
	"H6P7R[60],MK Live Tour 550-550;",
	"H6P7R[61],Rain Can Be Found 717-313;",
	"H6P7R[62],Don't Jump At Me 448-844;",
	"H6P7R[63],Skunky !! 122-221;",
	"H6P7R[64],Whatcha Gun Do ? 004-400;",
	"P8-;",
	"H6P8R[65],Mileena 22264-22264;",
	"H6P8R[66],Ermac 12344-44321;",
	"H6P8R[67],Classic Sub-Zero 81835-81835;",
	"h6P8R[73],Smoke 10902-22234;",
	// Move List / Finishing Moves: tools/finishing_moves.py --write prints these lines
	"H2P9,Move List / Finishing Moves;",
	"P9-;",
	"h6P9O[72:68],Character,Cyrax,Jax,Kabal,Kano,Kung Lao,Liu Kang,Nightwolf,Sektor,Shang Tsung,Sheeva,Sindel,Smoke,Sonya,Stryker,Sub-Zero;",
	"H6P9O[72:68],Character,Classic Sub-Zero,Cyrax,Ermac,Human Smoke,Jade,Jax,Kabal,Kano,Kitana,Kung Lao,Liu Kang,Mileena,Nightwolf,Reptile,Scorpion,Sektor,Shang Tsung,Sheeva,Sindel,Smoke,Sonya,Stryker,Sub-Zero;",
	"P9O[91],Move List,Off,On;",
	"P9-;",
	"H0HBP9R[103],Eye Laser LP BL BL HK;",
	"H0HBP9R[104],Skeleton Rip (LP) F D D F;",
	"H0HBh3P9R[105],Stage (BL) U U B LK;",
	"H0HBH3P9R[105],Stage F F F RN;",
	"H0HBP9R[106],Animality (HP) BL BL BL;",
	"H0HBh3P9R[107],Friendship LK RN RN HK;",
	"H0HBP9R[108],Babality F F D D LK;",
	"H0HCh3P9R[103],Kiss of Death B F D D RN;",
	"H0HCH3P9R[103],Kiss of Death D D D F LK;",
	"H0HCh3P9R[104],Bubble Crush (BL+RN) U U B D;",
	"H0HCh3P9R[105],Stage F F D HP;",
	"H0HCH3P9R[105],Stage F F F RN;",
	"H0HCP9R[106],Animality (LP) B F D F;",
	"H0HCh3P9R[107],Friendship B F B D+RN;",
	"H0HCh3P9R[108],Babality D D F LK;",
	"H0HDh3P9R[103],Arm Blades (BL) U D F U;",
	"H0HDH3P9R[103],Arm Blades (BL) D B U F D;",
	"H0HDh3P9R[104],Giant Stomp RN BL RN RN LK;",
	"H0HDH3P9R[104],Giant Stomp RN RN RN BL LK;",
	"H0HDh3P9R[105],Stage D F D LP;",
	"H0HDH3P9R[105],Stage F F F RN;",
	"H0HDP9R[106],Animality (LP) F F D F;",
	"H0HDh3P9R[107],Friendship LK RN RN LK;",
	"H0HDh3P9R[108],Babality D D D LK;",
	"H0HEh3P9R[103],Spirit Light (BL) U U B F, BL;",
	"H0HEH3P9R[103],Spirit Light D F F HK;",
	"H0HEh3P9R[104],Axe Lightning (HP) B B D;",
	"H0HEH3P9R[104],Axe Lightning B B B HP;",
	"H0HEh3P9R[105],Stage RN RN BL;",
	"H0HEH3P9R[105],Stage F F F RN;",
	"H0HEh3P9R[106],Animality F F D D;",
	"H0HEH3P9R[106],Animality D D D;",
	"H0HEh3P9R[107],Friendship RN RN RN D;",
	"H0HEh3P9R[108],Babality F B F B LP;",
	"H0HFh3P9R[103],Ice Breath B B D B RN;",
	"H0HFH3P9R[103],Ice Breath D F B HK;",
	"H0HFh3P9R[104],Freeze Shatter BL BL RN BL RN;",
	"H0HFH3P9R[104],Freeze Shatter D F D F LP;",
	"H0HFh3P9R[105],Stage B D F F HK;",
	"H0HFH3P9R[105],Stage F F F RN;",
	"H0HFh3P9R[106],Animality (BL) F U U;",
	"H0HFH3P9R[106],Animality (BL) U U U;",
	"H0HFh3P9R[107],Friendship LK RN RN U;",
	"H0HFh3P9R[108],Babality D B B HK;",
	"H7HBP9R[103],Taser F F F LK;",
	"H7HBP9R[104],Time Bomb D F D F BL;",
	"H7HBh3P9R[105],Stage (BL) F U U HK;",
	"H7HBH3P9R[105],Stage F F F RN;",
	"H7HBP9R[106],Animality RN RN RN BL;",
	"H7HBh3P9R[107],Friendship LP RN RN LP;",
	"H7HBh3P9R[108],Babality D F F B HP;",
	"H7HCP9R[103],Scream RN BL BL RN+BL;",
	"H7HCP9R[104],Hair Spin RN RN BL RN BL;",
	"H7HCh3P9R[105],Stage D D D LP;",
	"H7HCH3P9R[105],Stage F F F RN;",
	"H7HCh3P9R[106],Animality (BL) F F U, HP;",
	"H7HCH3P9R[106],Animality F F HP;",
	"H7HCh3P9R[107],Friendship RN RN RN RN RN U;",
	"H7HCh3P9R[108],Babality RN RN RN U;",
	"H7HDh3P9R[103],Compactor LP RN RN BL;",
	"H7HDH3P9R[103],Compactor B B B HK;",
	"H7HDP9R[104],Flamethrower F F F B BL;",
	"H7HDh3P9R[105],Stage RN RN RN D;",
	"H7HDH3P9R[105],Stage F F F RN;",
	"H7HDh3P9R[106],Animality F F D U;",
	"H7HDH3P9R[106],Animality D D D U;",
	"H7HDh3P9R[107],Friendship RN RN RN RN D;",
	"H7HDh3P9R[108],Babality B D D D HK;",
	"H7HEh3P9R[103],Self-Destruct (BL) D D F U RN;",
	"H7HEH3P9R[103],Self-Destruct (BL) D B U F D RN;",
	"H7HEh3P9R[104],Helicopter (BL) D D U D HP;",
	"H7HEH3P9R[104],Helicopter (BL) U U U D HP;",
	"H7HEh3P9R[105],Stage RN BL RN;",
	"H7HEH3P9R[105],Stage F F F RN;",
	"H7HEh3P9R[106],Animality (BL) U U D D;",
	"H7HEh3P9R[107],Friendship RN RN RN U;",
	"H7HEh3P9R[108],Babality F F B HP;",
	"H7HFP9R[103],Tornado RN BL RN BL D;",
	"H7HFh3P9R[104],Hat Slice F F B D HP;",
	"H7HFH3P9R[104],Hat Slice (RN) F F B HP;",
	"H7HFh3P9R[105],Stage D D F F LK;",
	"H7HFH3P9R[105],Stage F F F RN;",
	"H7HFP9R[106],Animality RN RN RN RN BL;",
	"H7HFh3P9R[107],Friendship RN LP RN LK;",
	"H7HFh3P9R[108],Babality D F F HP;",
	"H8HBh3P9R[103],Head Inflation D D B F BL;",
	"H8HBH3P9R[103],Head Inflation B B F D BL;",
	"H8HBP9R[104],Scary Face RN BL BL BL HK;",
	"H8HBh3P9R[105],Stage BL BL HK;",
	"H8HBH3P9R[105],Stage F F F RN;",
	"H8HBh3P9R[106],Animality (HP) F F D F;",
	"H8HBh3P9R[107],Friendship RN LK RN RN U;",
	"H8HBh3P9R[108],Babality RN RN LK;",
	"H8HCh3P9R[103],Ground Pound F D D F LP;",
	"H8HCH3P9R[103],Ground Pound F F F LP;",
	"H8HCh3P9R[104],Skin Rip (HK) B F F;",
	"H8HCH3P9R[104],Skin Rip (HK) F F F;",
	"H8HCh3P9R[105],Stage D F D F LP;",
	"H8HCH3P9R[105],Stage F F F RN;",
	"H8HCP9R[106],Animality RN BL BL BL BL;",
	"H8HCh3P9R[107],Friendship F F D F HP;",
	"H8HCh3P9R[108],Babality D D D B HK;",
	"H8HDh3P9R[103],Spike Bed (LP) D F F D;",
	"H8HDH3P9R[103],Spike Bed (LP) D F D F;",
	"H8HDP9R[104],Soul Steal (LP) RN BL RN BL;",
	"H8HDh3P9R[105],Stage (BL) U U B LP;",
	"H8HDH3P9R[105],Stage F F F RN;",
	"H8HDP9R[106],Animality (HP) RN RN RN;",
	"H8HDh3P9R[107],Friendship LK RN RN D;",
	"H8HDh3P9R[108],Babality RN RN RN LK;",
	"H8HEh3P9R[103],Inferno F F D D LK;",
	"H8HEH3P9R[103],Inferno F F F B F LK;",
	"H8HEh3P9R[104],Arcade Drop (RN+BL) U D U U, BL+RN;",
	"H8HEH3P9R[104],Arcade Drop (RN+BL) U U U U, BL+RN;",
	"H8HEh3P9R[105],Stage RN BL BL LK;",
	"H8HEH3P9R[105],Stage F F F RN;",
	"H8HEP9R[106],Animality D D U;",
	"H8HEh3P9R[107],Friendship RN RN RN+D;",
	"H8HEh3P9R[108],Babality D D D HK;",
	"H8HFh3P9R[103],Earth Bomb (BL) U U F D;",
	"H8HFh3P9R[104],Bomb Swallow (BL+RN) D D F U;",
	"H8HFh3P9R[105],Stage F F D LK;",
	"H8HFH3P9R[106],Animality D F F BL;",
	"H8HFh3P9R[107],Friendship RN RN RN HK;",
	"H8HFh3P9R[108],Babality D D B B HK;",
	"H9HBP9R[103],Fan Decap B D F F HK;",
	"H9HBP9R[104],Kiss of Death RN RN BL BL LK;",
	"H9HBP9R[105],Stage F D D LK;",
	"H9HBP9R[106],Animality D D D D RN;",
	"H9HBP9R[107],Friendship D B F F LP;",
	"H9HBP9R[108],Babality F F D F HK;",
	"H9HCP9R[103],Staff Shake (BL) U U D F, HP;",
	"H9HCP9R[104],Staff Impale RN RN RN BL RN;",
	"H9HCP9R[105],Stage B F D RN;",
	"H9HCP9R[106],Animality F D F F LK;",
	"H9HCP9R[107],Friendship B D B B HK;",
	"H9HCP9R[108],Babality D D F D HK;",
	"H9HDP9R[103],Nail Spit B B B F LK;",
	"H9HDP9R[104],Bone Spit D F D F LP;",
	"H9HDP9R[105],Stage D D D LP;",
	"H9HDP9R[106],Animality F D D F HK;",
	"H9HDP9R[107],Friendship D B F HP;",
	"H9HDP9R[108],Babality D D F F HP;",
	"H9HEP9R[103],Hell Clones (BL) F F D U, RN;",
	"H9HEP9R[104],Toasty (BL) D D U, HK;",
	"H9HEP9R[105],Stage (BL) F U U, LP;",
	"H9HEP9R[106],Animality (BL) F U U, HK;",
	"H9HEP9R[107],Friendship B F F B LK;",
	"H9HEP9R[108],Babality D B B F HP;",
	"H9HFP9R[103],Head Snack B F D BL;",
	"H9HFP9R[104],Acid Spit (BL) F F U U, HK;",
	"H9HFP9R[105],Stage BL RN BL BL;",
	"H9HFP9R[106],Animality (BL) D D D U, HK;",
	"H9HFP9R[107],Friendship D F F B HK;",
	"H9HFP9R[108],Babality F F B D LK;",
	"HAHBP9R[103],TK Slam (BL) D U D D D, BL;",
	"HAHBP9R[104],Head Punch RN BL RN RN HK;",
	"HAHBP9R[105],Stage RN RN RN RN LK;",
	"HAHCP9R[103],Head Rip D D D F HP;",
	"HAHCP9R[105],Stage F D F F HP;",
	"HAHDP9R[104],Head Punch RN BL RN RN HK;",
	"HAHDP9R[105],Stage (BL) F U U, LP;",
	"HAHDP9R[108],Babality D B B F HP;",
	"P9-;",
	"P9R[109],Mercy (RN) D D;",
	"-;",
	"DIP;",
	"-;",
	"O[8],Pause when OSD is open,On,Off;",
	"-;",
	"R[0],Reset;",
	"J1,B1,B2,B3,B4,B5,B6,Start,Coin,Test,Pause;",
	"jn,A,B,X,Y,L,R,Start,Select,,;",
	"I,Kode set for next VS screen,Kode set for next game over,Kombat Kode entered,Only during FINISH HIM,The winner is another fighter,Finishing move entered,Finishing moves need this release's MRA;",
	"V,v",`BUILD_DATE
};

// OSD items a game has (see "Hidden menus and cut content")
reg         is_mk;                   // MK3 / UMK3: EJB menu, Kombat Kodes
reg         is_umk3;                 // UMK3: its own Kombat Kodes
wire        kode_info_req;           // the Kombat Kode player's OSD messages
wire  [7:0] kode_info;
wire        fin_info_req;            // the finishing move player's
wire  [7:0] fin_info;
wire [15:0] fin_menu;                // and its menu mask bits
reg         is_hangtime;             // NBA Hangtime / Maximum Hangtime: Secret Midway Menu
reg         alt_present;             // the MRA brought a patched program copy (UMK3)
wire        has_hidden = is_mk | is_hangtime | alt_present;

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
	.info_req            (kode_info_req | fin_info_req),
	.info                (fin_info_req ? fin_info : kode_info),

	// bits 0 and 7-15: the finishing moves' character, bit 3 on MK3 / UMK3
	// their MK3 1.x table (Hangtime's elsewhere: the Hangtime line is h2H3)
	.status_menumask     ({fin_menu[15:7], ~is_umk3, ~has_hidden, ~alt_present, is_mk ? fin_menu[3] : ~is_hangtime,
	                       ~is_mk, ~status[101], fin_menu[0]}),

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
reg  [7:0] opt_rst = 8'd0;          // reset after the cut-content option changes
wire reset = RESET | status[0] | buttons[1] | rom_download | ~rom_loaded | (boot_hold != 26'd0) | ram_clearing |
             (opt_rst != 8'd0);

//////////////////////////////////////////////////////////////////
// Game configuration
//
// MRA ROM index 1: byte 0 the game id, bytes 1-8 where each 4 MB slot of
// MAME's graphics region went in the ROM image (FF: not present), byte 9
// FF, bytes 10-11 where a patched copy of the program ROM starts (8 KB
// units, little endian; 0: none), bytes 12-13 the word in main RAM of the
// game's state variable that the Kombat Kode and finishing move players
// watch (MK3, UMK3; little endian; 0: none), byte 14 the finishing moves'
// table (rtl/wunit_finish.sv: 0 none, 1 UMK3 / MK3 2.x, 2 MK3 1.x), byte 15
// 0. Older MRAs end at byte 9, 11 or 13.
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

localparam L_MK = 2'd0, L_WWF = 2'd1, L_4P = 2'd2, L_3P = 2'd3;

always @(posedge clk_sys) begin
	cfg_year     <= 12'd1994;
	cfg_io_remap <= 1'b0;
	cfg_pal_ring <= 1'b0;
	cfg_layout   <= L_MK;
	case (game_id)
		G_MK3:      ;
		G_UMK3:     cfg_pal_ring <= 1'b1;
		G_WWF:      begin cfg_year <= 12'd1995; cfg_io_remap <= 1'b1; cfg_layout <= L_WWF; end
		G_OPENICE:  begin cfg_year <= 12'd1995; cfg_layout <= L_4P; end
		G_NBAHANGT: begin cfg_year <= 12'd1996; cfg_layout <= L_4P; end
		G_RMPGWT:   begin cfg_year <= 12'd1997; cfg_layout <= L_3P; end
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
reg   [7:0] cfg [0:15];              // the configuration bytes as they arrive
reg  [15:0] cfg_alt;                 // patched program copy, 8 KB units (0: none)
reg  [15:0] cfg_kstate;              // the game's state variable, word in main RAM (0: none)
reg   [1:0] cfg_fin;                 // the finishing moves' table (0: none)

always @(posedge clk_sys) begin
	if (ioctl_wr && ioctl_index == 16'd1 && ioctl_addr == 27'd0) begin
		// a new configuration: forget the optional bytes of the last one
		cfg[10] <= 8'd0;
		cfg[11] <= 8'd0;
		cfg[12] <= 8'd0;
		cfg[13] <= 8'd0;
		cfg[14] <= 8'd0;
		cfg[15] <= 8'd0;
	end
	if (ioctl_wr && ioctl_index == 16'd1 && ioctl_addr < 27'd16) begin
		cfg[ioctl_addr[3:0]]         <= ioctl_dout[7:0];
		cfg[ioctl_addr[3:0] + 4'd1]  <= ioctl_dout[15:8];
	end
	if (ioctl_wr && ioctl_index == 16'd254 && ioctl_addr[26:3] == 24'd0)
		dsw[{ioctl_addr[2:1], 4'b0000} +: 16] <= ioctl_dout;

	game_id   <= cfg[0][2:0];
	gfx_slots <= {cfg[8], cfg[7], cfg[6], cfg[5], cfg[4], cfg[3], cfg[2], cfg[1]};
	cfg_alt   <= {cfg[11], cfg[10]};
	cfg_kstate <= {cfg[13], cfg[12]};
	cfg_fin   <= cfg[14] > 8'd2 ? 2'd0 : cfg[14][1:0];
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
// Joystick bits: 0 R, 1 L, 2 D, 3 U, then the MRA's <buttons> list in
// order: the game's buttons from bit 4, then Start, Coin, Test, Pause. The
// games have 6 (MK3, UMK3), 5 (WWF) or 3 buttons (Open Ice, NBA Hangtime,
// Rampage), so Start is bit 10, 9 or 7 (the CONF_STR's J1 line, used
// without an MRA, has 6 buttons). Ports are active low. The layouts follow MAME's input ports
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

// Start, Coin, Test, Pause of a controller: the four bits after the
// layout's buttons
wire [4:0] sys_at = (cfg_layout == L_MK) ? 5'd10 : (cfg_layout == L_WWF) ? 5'd9 : 5'd7;
wire [3:0] sys0 = joy0[sys_at +: 4], sys1 = joy1[sys_at +: 4];
wire [3:0] sys2 = joy2[sys_at +: 4], sys3 = joy3[sys_at +: 4];

wire       test_sw = status[9] | sys0[2] | sys1[2];
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
	in2[0]  = sys0[1];                // coin 1
	in2[1]  = sys1[1];                // coin 2
	in2[2]  = sys0[0];                // start 1
	in2[3]  = tilt_sw;                // tilt (slam switch)
	in2[4]  = test_sw;                // test
	in2[5]  = sys1[0];                // start 2
	in2[6]  = svc_sw;                 // service credit
	in2[7]  = sys2[1];                // coin 3
	in2[8]  = sys3[1];                // coin 4
	in2[9]  = sys2[0];                // start 3
	in2[10] = sys3[0];                // start 4

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
	pause_btn_d <= sys0[3] | sys1[3];
	if (reset) pause_toggle <= 1'b0;
	else if ((sys0[3] | sys1[3]) & ~pause_btn_d) pause_toggle <= ~pause_toggle;
end

// the Move List window (see Video) holds the game too
wire movelist_on = status[91] & is_mk;
wire pause = pause_toggle | (OSD_STATUS & ~status[8]) | movelist_on;

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

//////////////////////////////////////////////////////////////////
// Hidden menus and cut content
//
// "Open EJB Menu" (MK3, UMK3) and "Open Secret Midway Menu" (NBA Hangtime,
// Maximum Hangtime) enter the game's own button code for its hidden menu
// (rtl/wunit_macro.sv lists the codes); the buttons are pressed on IN0 on
// top of the controls. They share status bit 16; only the game's own line
// is shown.
//
// "EJB Character Endings" (UMK3) runs the patched copy of the program ROM
// the MRA loads after the graphics: the EJB menu gets back the CHARACTER
// ENDINGS item that MK3 had and UMK3 left out of its menu (its code is
// still in the ROM), and an ending shows the story as well as the cast
// roll. The copy is chosen at reset; changing the option resets the game.
//////////////////////////////////////////////////////////////////

reg         prog_alt;                // running the patched program copy
reg         opt_d;
reg         code_d;
wire [15:0] macro_press;

always @(posedge clk_sys) begin
	is_mk       <= (game_id == G_MK3) || (game_id == G_UMK3);
	is_hangtime <= (game_id == G_NBAHANGT);
	alt_present <= (cfg_alt != 16'd0);

	if (reset)
		prog_alt <= status[17] & alt_present;

	opt_d  <= status[17];
	code_d <= status[16];
	if (alt_present && (status[17] != opt_d))
		opt_rst <= 8'hFF;
	else if (opt_rst != 8'd0)
		opt_rst <= opt_rst - 8'd1;
end

wunit_macro macro
(
	.clk    (clk_sys),
	.reset  (reset),
	.start  (status[16] & ~code_d),
	.code   (is_mk ? 2'd1 : is_hangtime ? 2'd2 : 2'd0),
	.frame  (osd_frame),
	.press  (macro_press),
	.busy   ()
);

//////////////////////////////////////////////////////////////////
// Kombat Kodes (MK3, UMK3)
//
// The "Kombat Kodes" page links to five category pages (Fight, Round 1
// Winner Battles, Kombat Zone, Messages, Ultimate Kombat Kodes: P4-P8; the
// OSD has one level of pages, so Back from a category goes to the main
// menu) listing the kodes the game's program ROM has (the UMK3-only lines
// and pages hidden on MK3, MK3's Smoke kode on UMK3), each a trigger on
// status bits 18-67 in order, then 73 (MK3's Ultimate Kombat Kode: 68-72
// were taken). A pick is entered by the player (rtl/wunit_kodes.sv) at the
// next screen that takes it: the VS screen of a two-player fight, or, for
// an Ultimate Kombat Kode, the game over screen. It finds those by
// the game's state variable, whose main RAM word the MRA gives (config
// bytes 12-13). An OSD message says the kode is waiting, then entered.
//////////////////////////////////////////////////////////////////

wire [50:0] kode_bits = {status[73], status[67:18]};
reg  [50:0] kode_bits_d;
reg         kode_sel;
reg   [5:0] kode_idx;
wire [15:0] kode_press0, kode_press1;

wire        ram_wr;                  // main RAM writes from the board
wire [17:0] ram_wa;
wire [15:0] ram_wd;
reg         kstate_wr;               // one of them was to the state variable
reg  [15:0] kstate_val;

integer ki;
always @(posedge clk_sys) begin
	is_umk3 <= (game_id == G_UMK3);

	kode_bits_d <= kode_bits;
	kode_sel    <= 1'b0;
	for (ki = 50; ki >= 0; ki = ki - 1)
		if (kode_bits[ki] & ~kode_bits_d[ki]) begin
			kode_sel <= 1'b1;
			kode_idx <= ki[5:0];
		end

	kstate_wr  <= ram_wr && (cfg_kstate != 16'd0) && (ram_wa == {2'b00, cfg_kstate});
	kstate_val <= ram_wd;
end

wunit_kodes kodes
(
	.clk       (clk_sys),
	.reset     (reset),
	.sel       (kode_sel & is_mk),
	.sel_idx   (kode_idx),
	.state_wr  (kstate_wr),
	.state_val (kstate_val),
	.frame     (osd_frame),
	.press0    (kode_press0),
	.press1    (kode_press1),
	.info_req  (kode_info_req),
	.info      (kode_info),
	.busy      ()
);

//////////////////////////////////////////////////////////////////
// Finishing moves (MK3, UMK3)
//
// The "Move List / Finishing Moves" page (P9) has a Character option (the
// game's characters in alphabetical order, MK3's 15 or UMK3's 23: status
// bits 72-68), the Move List window (bit 91, see Video) and below them the
// moves of that character only, each by name and input: each line carries
// two menu mask bits, the character's number / 5 and % 5, that the player
// clears for the picked character (see rtl/wunit_finish.sv; lines that
// differ for MK3 1.0 / p4.0 also bit 3, which on MK3 / UMK3 says whether
// the MRA gave the MK3 1.x table). Each move is a trigger on status bits
// 103-108 by slot (Fatality 1, Fatality 2, Stage Fatality, Animality,
// Friendship, Babality), the Mercy, shared by all, on 109. The player
// enters a pick at FINISH HIM on the winner's controls; the lines, the
// programs and the table byte of the MRA (config byte 14) come from
// tools/finishing_moves.py.
//////////////////////////////////////////////////////////////////

wire  [6:0] fin_bits = status[109:103];
wire  [4:0] fin_char;
reg   [6:0] fin_bits_d;
reg         fin_sel;
reg   [2:0] fin_slot;
wire [15:0] fin_press0, fin_press1;

integer fi;
always @(posedge clk_sys) begin
	fin_bits_d <= fin_bits;
	fin_sel    <= 1'b0;
	for (fi = 6; fi >= 0; fi = fi - 1)
		if (fin_bits[fi] & ~fin_bits_d[fi]) begin
			fin_sel  <= 1'b1;
			fin_slot <= fi[2:0];
		end
end

wunit_finish finish
(
	.clk       (clk_sys),
	.reset     (reset),
	.opt       (status[72:68]),
	.sel       (fin_sel & is_mk),
	.sel_slot  (fin_slot),
	.table_id  (cfg_fin),
	.umk3      (is_umk3),
	.kstate    (cfg_kstate),
	.ram_wr    (ram_wr),
	.ram_wa    (ram_wa),
	.ram_wd    (ram_wd),
	.frame     (osd_frame),
	.press0    (fin_press0),
	.press1    (fin_press1),
	.info_req  (fin_info_req),
	.info      (fin_info),
	.menu      (fin_menu),
	.char_id   (fin_char),
	.busy      ()
);

midway_wunit board
(
	.clk            (clk_sys),
	.reset          (reset),
	.pause          (pause),

	.gfx_slots      (gfx_slots),
	.year           (cfg_year),
	.io_remap       (cfg_io_remap),
	.pal_ring       (cfg_pal_ring),
	.prog_base      (prog_alt ? cfg_alt[11:0] : 12'd0),
	.vtiming        (status[15:14]),    // 54.7 / 57 / 60 Hz frames (see midway_wunit.sv)

	.in0            (~(in0 | macro_press | kode_press0 | fin_press0)),
	.in1            (~(in1 | kode_press1 | fin_press1)),
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

	.ram_wr         (ram_wr),
	.ram_wa         (ram_wa),
	.ram_wd         (ram_wd),

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
// Sound board: DCS (mono, signed 16-bit to both channels)
//////////////////////////////////////////////////////////////////

wire [15:0] snd_sample;

dcs_audio sound
(
	.clk           (clk_sys),
	.reset         (reset),
	.dcs_reset     (snd_reset),

	.host_wr       (snd_wr),
	.host_data     (snd_wdata),
	.host_rd       (snd_rd),
	.host_q        (snd_rdata),
	.control       (snd_ctrl),

	.rom_addr      (snd_sd_addr),
	.rom_req       (snd_sd_req),
	.rom_ack       (snd_sd_ack),
	.rom_data      (snd_sd_data),

	.sample        (snd_sample),
	.sample_strobe (),

	.dbg_pc        (),
	.dbg_op        (),
	.dbg_retire    (),
	.dbg_irq       (),
	.dbg_wr        (),
	.dbg_waddr     (),
	.dbg_wdata     ()
);

assign AUDIO_L   = snd_sample;
assign AUDIO_R   = snd_sample;
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

	.ch0_addr    (snd_sd_addr),
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

// ---- Move List window (MK3, UMK3; rtl/wunit_movelist.sv) ----
//
// OSD "Move List" (status bit 91, on the Finishing Moves page) draws the
// moves of the fighter picked under "Character" over the dimmed game, which
// pauses while the window is up. Pages (tools/move_list.py): UMK3 0-22,
// MK3 rev 2.x 23-37, MK3 rev 1.x 38-52 (the MRA's finishing moves table),
// by the game's character number. The picture passes unchanged otherwise.

wire [5:0] ml_page = is_umk3 ? {1'b0, fin_char} : (cfg_fin == 2'd2 ? 6'd38 : 6'd23) + {1'b0, fin_char};
wire [7:0] ml_r, ml_g, ml_b;

wunit_movelist movelist
(
	.clk     (clk_sys),
	.ce_pix  (ce_pix),
	.enable  (movelist_on),
	.page    (ml_page),
	.r_in    (core_r),
	.g_in    (core_g),
	.b_in    (core_b),
	.hb_in   (core_hb),
	.vb_in   (core_vb),
	.r_out   (ml_r),
	.g_out   (ml_g),
	.b_out   (ml_b)
);

// ---- analog CRT stage: centred sync, CRT V-Size, CRT Adjust, Auto-Width (rtl/video/wunit_crt.sv) ----
//
// The analog sync is always the centred one (picture in the middle of a
// standard 15 kHz line and frame); HDMI sees the same picture either way.
// CRT Adjust (and with it CRT V-Size) is off while a scandoubler effect is
// on (its read rate assumes native 15 kHz).

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
	.vsize_osd   (status[89:86]),
	.vsize_mode  (status[90]),

	.r_in        (ml_r),
	.g_in        (ml_g),
	.b_in        (ml_b),
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

	.RGB_in             ({ml_r, ml_g, ml_b}),
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
