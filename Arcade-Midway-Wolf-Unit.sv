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
// The main page of every game: Video Settings (P1); the game's own items
// (MK3 / UMK3, lines H2: Kombat Kodes with its category pages P3-P7, Move
// List, Finishing Moves P9; the Hangtimes and Open Ice: Secret Codes);
// DIP Switches (P2: each game's switches, Service Credit, Tilt); Secret
// Menu (MK3 / UMK3, P8) or Secret Midway Menu (Hangtimes); Service Mode;
// Pause when OSD is Open; Reset and Reset and close OSD. See
// status_menumask for the mask bits. The framework reads at most 10,239
// bytes of this string and has pages 1-9 only.
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
	"-;",
	// MK3 / UMK3: Kombat Kodes (P3, categories P4-P7), Move List, Finishing Moves (P9)
	"H2P3,Kombat Kodes;",
	"P3-;",
	"P3P4,Fight;",
	"P3P5,Round 1 Winner Battles;",
	"H6P3P6,Kombat Zone;",
	"P3P7,Messages;",
	"P4-;",
	"P4RI,Throwing Disabled 100-100;",
	"P4RJ,Blocking Disabled 020-020;",
	"P4RK,No Powerbars 987-123;",
	"P4RL,Unlimited Run 466-466;",
	"P4RM,Dark Kombat 688-422;",
	"P4RN,Randper Kombat 460-460;",
	"P4RO,Psycho Kombat 985-125;",
	"P4RP,P1 Half Power 033-000;",
	"P4RQ,P2 Half Power 000-033;",
	"P4RR,P1 Quarter Power 707-000;",
	"P4RS,P2 Quarter Power 000-707;",
	"H6P4RT,Sans Power 044-440;",
	"H6P4RU,Uppercut Recovery 788-322;",
	"H6P4RV,Throwing Encouraged 010-010;",
	"H6P4r0,Silent Kombat 300-300;",
	"H6P4r1,Explosive Kombat 227-227;",
	"H6P4r2,Explosive No Throws 022-220;",
	"P4r3,Galaga 642-468;",
	"P5-;",
	"P5r4,Motaro 969-141;",
	"P5r5,Shao Kahn 033-564;",
	"P5r6,Noob Saibot 769-342;",
	"P5r7,Smoke 205-205;",
	"P6-;",
	"H6P6r8,Subway 880-088;",
	"H6P6r9,Street 079-035;",
	"H6P6rA,Rooftop 343-343;",
	"H6P6rB,Kahn's Tower 880-220;",
	"H6P6rC,The Bridge 077-022;",
	"H6P6rD,Soul Chamber 123-901;",
	"H6P6rE,Bell Tower 091-190;",
	"H6P6rF,Kombat Temple 600-040;",
	"H6P6rG,The Graveyard 666-333;",
	"H6P6rH,The Pit 3 820-028;",
	"H6P6rI,River Kombat 002-003;",
	"H6P6rJ,Scorpion's Lair 666-444;",
	"H6P6rK,Kahn's Kave 004-700;",
	"H6P6rL,Jade's Desert 330-033;",
	"H6P6rM,Scislac Busorez 933-933;",
	"H6P6rN,Noob Saibot Dorfen 050-050;",
	"P7-;",
	"P7rO,Hold Flippers 987-666;",
	"P7R[103],No Fear 282-282;",
	"P7R[104],No Knowledge 123-926;",
	"H6P7R[105],Revision 999-999;",
	"H6P7R[106],MK Live Tour 550-550;",
	"H6P7R[107],Rain Can Be Found 717-313;",
	"H6P7R[108],Don't Jump At Me 448-844;",
	"H6P7R[109],Skunky !! 122-221;",
	"H6P7R[64],Whatcha Gun Do ? 004-400;",
	"P3-;",
	"P3-,Ultimate Kombat Kodes;",
	"H6P3R[65], Mileena 22264-22264;",
	"H6P3R[66], Ermac 12344-44321;",
	"H6P3R[67], Classic Sub-Zero 81835-81835;",
	"h6P3R[73], Smoke 10902-22234;",
	// Move List / Finishing Moves: tools/finishing_moves.py --write prints these lines
	"H6O[117:113],Move List,Off,Classic Sub-Zero,Cyrax,Ermac,Human Smoke,Jade,Jax,Kabal,Kano,Kitana,Kung Lao,Liu Kang,Mileena,Nightwolf,Reptile,Scorpion,Sektor,Shang Tsung,Sheeva,Sindel,Smoke,Sonya,Stryker,Sub-Zero;",
	"h6H2O[117:113],Move List,Off,Cyrax,Jax,Kabal,Kano,Kung Lao,Liu Kang,Nightwolf,Sektor,Shang Tsung,Sheeva,Sindel,Smoke,Sonya,Stryker,Sub-Zero;",
	"H2P9,Finishing Moves;",
	"P9-;",
	"h6P9O[72:68],Character,Cyrax,Jax,Kabal,Kano,Kung Lao,Liu Kang,Nightwolf,Sektor,Shang Tsung,Sheeva,Sindel,Smoke,Sonya,Stryker,Sub-Zero;",
	"H6P9O[72:68],Character,Classic Sub-Zero,Cyrax,Ermac,Human Smoke,Jade,Jax,Kabal,Kano,Kitana,Kung Lao,Liu Kang,Mileena,Nightwolf,Reptile,Scorpion,Sektor,Shang Tsung,Sheeva,Sindel,Smoke,Sonya,Stryker,Sub-Zero;",
	"P9-;",
	"H0HBP9rP,Eye Laser LP BL BL HK;",
	"H0HCh3P9rP,Kiss of Death B F D D RN;",
	"H0HCH3P9rP,Kiss of Death D D D F LK;",
	"H0HDh3P9rP,Arm Blades (BL) U D F U;",
	"H0HDH3P9rP,Arm Blades (BL) D B U F D;",
	"H0HEh3P9rP,Spirit Light (BL) U U B F, BL;",
	"H0HEH3P9rP,Spirit Light D F F HK;",
	"H0HFh3P9rP,Ice Breath B B D B RN;",
	"H0HFH3P9rP,Ice Breath D F B HK;",
	"H7HBP9rP,Taser F F F LK;",
	"H7HCP9rP,Scream RN BL BL RN+BL;",
	"H7HDh3P9rP,Compactor LP RN RN BL;",
	"H7HDH3P9rP,Compactor B B B HK;",
	"H7HEh3P9rP,Self-Destruct (BL) D D F U RN;",
	"H7HEH3P9rP,Self-Destruct (BL) D B U F D RN;",
	"H7HFP9rP,Tornado RN BL RN BL D;",
	"H8HBh3P9rP,Head Inflation D D B F BL;",
	"H8HBH3P9rP,Head Inflation B B F D BL;",
	"H8HCh3P9rP,Ground Pound F D D F LP;",
	"H8HCH3P9rP,Ground Pound F F F LP;",
	"H8HDh3P9rP,Spike Bed (LP) D F F D;",
	"H8HDH3P9rP,Spike Bed (LP) D F D F;",
	"H8HEh3P9rP,Inferno F F D D LK;",
	"H8HEH3P9rP,Inferno F F F B F LK;",
	"H8HFh3P9rP,Earth Bomb (BL) U U F D;",
	"H9HBP9rP,Fan Decap B D F F HK;",
	"H9HCP9rP,Staff Shake (BL) U U D F, HP;",
	"H9HDP9rP,Nail Spit B B B F LK;",
	"H9HEP9rP,Hell Clones (BL) F F D U, RN;",
	"H9HFP9rP,Head Snack B F D BL;",
	"HAHBP9rP,TK Slam (BL) D U D D D, BL;",
	"HAHCP9rP,Head Rip D D D F HP;",
	"H0HBP9rQ,Skeleton Rip (LP) F D D F;",
	"H0HCh3P9rQ,Bubble Crush (BL+RN) U U B D;",
	"H0HDh3P9rQ,Giant Stomp RN BL RN RN LK;",
	"H0HDH3P9rQ,Giant Stomp RN RN RN BL LK;",
	"H0HEh3P9rQ,Axe Lightning (HP) B B D;",
	"H0HEH3P9rQ,Axe Lightning B B B HP;",
	"H0HFh3P9rQ,Freeze Shatter BL BL RN BL RN;",
	"H0HFH3P9rQ,Freeze Shatter D F D F LP;",
	"H7HBP9rQ,Time Bomb D F D F BL;",
	"H7HCP9rQ,Hair Spin RN RN BL RN BL;",
	"H7HDP9rQ,Flamethrower F F F B BL;",
	"H7HEh3P9rQ,Helicopter (BL) D D U D HP;",
	"H7HEH3P9rQ,Helicopter (BL) U U U D HP;",
	"H7HFh3P9rQ,Hat Slice F F B D HP;",
	"H7HFH3P9rQ,Hat Slice (RN) F F B HP;",
	"H8HBP9rQ,Scary Face RN BL BL BL HK;",
	"H8HCh3P9rQ,Skin Rip (HK) B F F;",
	"H8HCH3P9rQ,Skin Rip (HK) F F F;",
	"H8HDP9rQ,Soul Steal (LP) RN BL RN BL;",
	"H8HEh3P9rQ,Arcade Drop (RN+BL) U D U U, BL+RN;",
	"H8HEH3P9rQ,Arcade Drop (RN+BL) U U U U, BL+RN;",
	"H8HFh3P9rQ,Bomb Swallow (BL+RN) D D F U;",
	"H9HBP9rQ,Kiss of Death RN RN BL BL LK;",
	"H9HCP9rQ,Staff Impale RN RN RN BL RN;",
	"H9HDP9rQ,Bone Spit D F D F LP;",
	"H9HEP9rQ,Toasty (BL) D D U, HK;",
	"H9HFP9rQ,Acid Spit (BL) F F U U, HK;",
	"HAhCP9rQ,Head Punch RN BL RN RN HK;",
	"H0HBh3P9rR,Stage (BL) U U B LK;",
	"hFH3P9rR,Stage F F F RN;",
	"h8HFH3P9rR,Stage F F F RN;",
	"H0HCh3P9rR,Stage F F D HP;",
	"H0HDh3P9rR,Stage D F D LP;",
	"H0HEh3P9rR,Stage RN RN BL;",
	"H0HFh3P9rR,Stage B D F F HK;",
	"H7HBh3P9rR,Stage (BL) F U U HK;",
	"H7HCh3P9rR,Stage D D D LP;",
	"H7HDh3P9rR,Stage RN RN RN D;",
	"H7HEh3P9rR,Stage RN BL RN;",
	"H7HFh3P9rR,Stage D D F F LK;",
	"H8HBh3P9rR,Stage BL BL HK;",
	"H8HCh3P9rR,Stage D F D F LP;",
	"H8HDh3P9rR,Stage (BL) U U B LP;",
	"H8HEh3P9rR,Stage RN BL BL LK;",
	"H8HFh3P9rR,Stage F F D LK;",
	"H9HBP9rR,Stage F D D LK;",
	"H9HCP9rR,Stage B F D RN;",
	"H9HDP9rR,Stage D D D LP;",
	"H9HEP9rR,Stage (BL) F U U, LP;",
	"HAHDP9rR,Stage (BL) F U U, LP;",
	"H9HFP9rR,Stage BL RN BL BL;",
	"HAHBP9rR,Stage RN RN RN RN LK;",
	"HAHCP9rR,Stage F D F F HP;",
	"H0HBP9rS,Animality (HP) BL BL BL;",
	"H0HCP9rS,Animality (LP) B F D F;",
	"H0HDP9rS,Animality (LP) F F D F;",
	"H0HEh3P9rS,Animality F F D D;",
	"H0HEH3P9rS,Animality D D D;",
	"H0HFh3P9rS,Animality (BL) F U U;",
	"H0HFH3P9rS,Animality (BL) U U U;",
	"H7HBP9rS,Animality RN RN RN BL;",
	"H7HCh3P9rS,Animality (BL) F F U, HP;",
	"H7HCH3P9rS,Animality F F HP;",
	"H7HDh3P9rS,Animality F F D U;",
	"H7HDH3P9rS,Animality D D D U;",
	"H7HEh3P9rS,Animality (BL) U U D D;",
	"H7HFP9rS,Animality RN RN RN RN BL;",
	"H8HBh3P9rS,Animality (HP) F F D F;",
	"H8HCP9rS,Animality RN BL BL BL BL;",
	"H8HDP9rS,Animality (HP) RN RN RN;",
	"H8HEP9rS,Animality D D U;",
	"H8HFH3P9rS,Animality D F F BL;",
	"H9HBP9rS,Animality D D D D RN;",
	"H9HCP9rS,Animality F D F F LK;",
	"H9HDP9rS,Animality F D D F HK;",
	"H9HEP9rS,Animality (BL) F U U, HK;",
	"H9HFP9rS,Animality (BL) D D D U, HK;",
	"H0HBh3P9rT,Friendship LK RN RN HK;",
	"H0HCh3P9rT,Friendship B F B D+RN;",
	"H0HDh3P9rT,Friendship LK RN RN LK;",
	"H0HEh3P9rT,Friendship RN RN RN D;",
	"H0HFh3P9rT,Friendship LK RN RN U;",
	"H7HBh3P9rT,Friendship LP RN RN LP;",
	"H7HCh3P9rT,Friendship RN RN RN RN RN U;",
	"H7HDh3P9rT,Friendship RN RN RN RN D;",
	"H7HEh3P9rT,Friendship RN RN RN U;",
	"H7HFh3P9rT,Friendship RN LP RN LK;",
	"H8HBh3P9rT,Friendship RN LK RN RN U;",
	"H8HCh3P9rT,Friendship F F D F HP;",
	"H8HDh3P9rT,Friendship LK RN RN D;",
	"H8HEh3P9rT,Friendship RN RN RN+D;",
	"H8HFh3P9rT,Friendship RN RN RN HK;",
	"H9HBP9rT,Friendship D B F F LP;",
	"H9HCP9rT,Friendship B D B B HK;",
	"H9HDP9rT,Friendship D B F HP;",
	"H9HEP9rT,Friendship B F F B LK;",
	"H9HFP9rT,Friendship D F F B HK;",
	"H0HBP9rU,Babality F F D D LK;",
	"H0HCh3P9rU,Babality D D F LK;",
	"H0HDh3P9rU,Babality D D D LK;",
	"H0HEh3P9rU,Babality F B F B LP;",
	"H0HFh3P9rU,Babality D B B HK;",
	"H7HBh3P9rU,Babality D F F B HP;",
	"H7HCh3P9rU,Babality RN RN RN U;",
	"H7HDh3P9rU,Babality B D D D HK;",
	"H7HEh3P9rU,Babality F F B HP;",
	"H7HFh3P9rU,Babality D F F HP;",
	"H8HBh3P9rU,Babality RN RN LK;",
	"H8HCh3P9rU,Babality D D D B HK;",
	"H8HDh3P9rU,Babality RN RN RN LK;",
	"H8HEh3P9rU,Babality D D D HK;",
	"H8HFh3P9rU,Babality D D B B HK;",
	"H9HBP9rU,Babality F F D F HK;",
	"H9HCP9rU,Babality D D F D HK;",
	"H9HDP9rU,Babality D D F F HP;",
	"H9HEP9rU,Babality D B B F HP;",
	"HAHDP9rU,Babality D B B F HP;",
	"H9HFP9rU,Babality F F B D LK;",
	"P9-;",
	"hEP9rV,Mercy (RN) D D;",
	"h7HEP9rV,Mercy (RN) D D;",
	"H7HEh3P9rV,Mercy (RN) D D;",
	// NBA Hangtime, Maximum Hangtime / Open Ice: Secret Codes
	"h2H3O[93:92],Secret Codes,Off,Page 1,Page 2;",
	"h2H7O[112:110],Secret Codes,Off,Secret Players 1,Secret Players 2,Secret Players 3,Tonight's Game,Face-off;",
	"H2-;",
	"h2HA-;",
	// DIP Switches (P2), every game: one list in alphabetical order, each game's lines shown (see DSW)
	"P2,DIP Switches;",
	"P2-;",
	"H2P2O[127],Attract Sound,On,Off;",
	"h2H7P2O[127],Attract Sound,On,Off;",
	"H5P2O[126],Bill Validator,Off,On;",
	"H2P2O[94],Blood,On,Off;",
	"h2HAP2O[94],Cabinet,2-player,4-player;",
	"H2P2O[124:120],Coinage,USA-1,USA-2,USA-3,USA-4,USA-ECA,USA-Free Play,German-1,German-2,German-3,German-4,German-5,German-ECA,German-Free Play,French-1,French-2,French-3,French-4,French-ECA,French-Free Play;",
	"h2H9P2O[124:120],Coinage,USA-1,USA-2,USA-3,USA-4,USA-9,USA-10,USA-ECA,USA-Free Play,German-1,German-2,German-3,German-4,German-5,German-ECA,German-Free Play,French-1,French-2,French-3,French-4,French-11,French-12,French-ECA,French-Free Play;",
	"h4P2O[122:120],Coinage,1,2,3,4,ECA,Free Play;",
	"P2O[125],Coinage Source,CMOS,Dipswitch;",
	"H4P2O[119],Counters,Two,One;",
	"h4P2O[116:115],Counters,One 1/1,One Totalizing,Two 1/1;",
	"h5P2O[114:113],Country,USA,French,German;",
	"h2H7P2O[95],Head Size,Normal,Large;",
	"h2h7P2O[117],Powerup Test,Off,On;",
	"h2H8P2O[94],Realtime Clock,No,Yes;",
	"P2T[12],Service Credit;",
	"P2O[118],Test Switch,Off,On;",
	"P2T[13],Tilt;",
	"H2P2O[95],Violence,On,Off;",
	// Secret Menu (MK3, UMK3: P8) / Secret Midway Menu (Hangtimes: back to Off once entered)
	"H2P8,Secret Menu;",
	"P8-;",
	"P8R[16],Open EJB Menu (Attract Mode);",
	"P8-,  Hidden Alternate Test Menu;",
	"H6P8-;",
	"H6P8O[17],Scorpion - Smoke Voice Fix,Off,On;",
	"H6P8-,  \"Get over here!\" and;",
	"H6P8-,  \"Come here!\" cut off Fix;",
	"h2H3O[16],Secret Midway Menu,Off,On;",
	"O[9],Service Mode,Off,On;",
	"O[8],Pause when OSD is Open,On,Off;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,B1,B2,B3,B4,B5,B6,Start,Coin,Test,Pause;",
	"jn,A,B,X,Y,L,R,Start,Select,,;",
	"I,Kode set for next VS screen,Kode set for next game over,Kombat Kode entered,Only during FINISH HIM,The winner is another fighter,Finishing move entered,Finishing moves need this release's MRA,The winner has no such move;",
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
reg         is_openice;              // 2 On 2 Open Ice Challenge: its Secret Codes line
reg         is_wwf;                  // WWF WrestleMania
reg         is_rampage;              // Rampage World Tour
reg         alt_present;             // the MRA brought a patched program copy (UMK3)
reg         smm_clear;               // set the Secret Midway Menu option back to Off

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

	// the Secret Midway Menu option goes back to Off once its code starts
	.status_in           (status & ~(128'd1 << 16)),
	.status_set          (smm_clear),

	// bits (set: an H line hides): 1 CRT Adjust off, 2 not MK3 / UMK3 (H2:
	// their lines, h2: the other games'), 4 WWF or a Hangtime, 5 a
	// Hangtime, 6 not UMK3 (4 and 5 are 0 on MK3 / UMK3). Bits 0, 3 and
	// 7-15 are on MK3 / UMK3 the finishing moves' (character, MK3 1.x
	// table; their lines are on the MK-only page P9), on the other games 3
	// not a Hangtime, 7 not Open Ice, 8 not WWF, 9 not Open Ice or Rampage,
	// A (10) not a Hangtime or Open Ice
	.status_menumask     (is_mk ? {fin_menu[15:7], ~is_umk3, 1'b0, 1'b0, fin_menu[3], 1'b0, ~status[101], fin_menu[0]} :
	                              {5'b11111, ~(is_hangtime | is_openice), ~(is_openice | is_rampage), ~is_wwf, ~is_openice,
	                               1'b1, is_hangtime, is_wwf | is_hangtime, ~is_hangtime, 1'b1, ~status[101], 1'b1}),

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
// the core's reset, registered: its sources (a 26-bit count among them) and
// its fan-out into every block then each get a clock of their own; this
// also takes the framework's RESET into clk_sys
wire reset_in = RESET | status[0] | buttons[1] | rom_download | ~rom_loaded | (boot_hold != 26'd0) | ram_clearing |
                (opt_rst != 8'd0);
reg  reset = 1'b1;
always @(posedge clk_sys) reset <= reset_in;

//////////////////////////////////////////////////////////////////
// Game configuration
//
// MRA ROM index 1: byte 0 the game id, bytes 1-8 where each 4 MB slot of
// MAME's graphics region went in the ROM image (FF: not present), byte 9
// FF, bytes 10-11 where a patched copy of the program ROM starts (8 KB
// units, little endian; 0: none), bytes 12-13 the word in main RAM of the
// game's state variable that the Kombat Kode and finishing move players
// watch (MK3, UMK3; little endian; 0: none), byte 14 the finishing moves'
// table on MK3 / UMK3 (rtl/wunit_finish.sv: 0 none, 1 UMK3 / MK3 2.x, 2
// MK3 1.x) and on the Hangtimes the secret player variant
// (tools/hangtime_secrets.py: 0 none, 1 NBA Hangtime, 2-4 Maximum
// Hangtime L1.03, L1.0 / M1.0, L0.9), byte 15 0. Older MRAs end at byte 9,
// 11 or 13.
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
// Downloads: ROMs (index 0), game configuration (1), NVRAM (2). The MRAs
// carry no DIP switches: they are in the core's OSD (see DSW)
//
// ROM layout (byte addresses, the same in the MRA and in SDRAM):
//   0x000000  program, 1 MB (16-bit little endian)
//   0x100000  DCS sound ROMs, 4 x 1 MB
//   0x500000  security PIC program, 8 KB
//   0x502000  graphics, the used 4 MB slots of MAME's video region
// Main RAM is the top 512 KB of the SDRAM (0x1F80000); it is cleared after
// each ROM download, as MAME starts with it zeroed.
//////////////////////////////////////////////////////////////////

reg   [7:0] cfg [0:15];              // the configuration bytes as they arrive
reg  [15:0] cfg_alt;                 // patched program copy, 8 KB units (0: none)
reg  [15:0] cfg_kstate;              // the game's state variable, word in main RAM (0: none)
reg   [1:0] cfg_fin;                 // the finishing moves' table (0: none)
reg   [2:0] cfg_ht;                  // the Hangtimes' secret player variant (0: none)

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

	game_id   <= cfg[0][2:0];
	gfx_slots <= {cfg[8], cfg[7], cfg[6], cfg[5], cfg[4], cfg[3], cfg[2], cfg[1]};
	cfg_alt   <= {cfg[11], cfg[10]};
	cfg_kstate <= {cfg[13], cfg[12]};
	cfg_fin   <= (cfg[0][2:0] != G_MK3 && cfg[0][2:0] != G_UMK3) || cfg[14] > 8'd2 ? 2'd0 : cfg[14][1:0];
	cfg_ht    <= cfg[0][2:0] != G_NBAHANGT || cfg[14] > 8'd4 ? 3'd0 : cfg[14][2:0];
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
// (DIP Switches page), handled in "OSD service credit and tilt" below.
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
			// B1 high punch, B2 low punch, B3 high kick, B4 low kick, B5 block,
			// B6 run; MAME's IN0 has high punch, block, high kick (bits 4-6),
			// IN1 low punch, low kick, run (bits 0-2)
			in0[3:0]  = udlr(joy0);  in0[6:4]  = {joy0[6], joy0[8], joy0[4]};
			in0[11:8] = udlr(joy1);  in0[14:12] = {joy1[6], joy1[8], joy1[4]};
			in1[2:0]  = {joy0[9], joy0[7], joy0[5]};
			in1[6:4]  = {joy1[9], joy1[7], joy1[5]};
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

// the Move List and Secret Codes windows (see Video) hold the game too
wire [4:0] ml_sel = status[117:113];      // Move List: 0 off, else the OSD's character + 1
wire movelist_on = is_mk && ml_sel != 5'd0 && ml_sel <= (is_umk3 ? 5'd23 : 5'd15);
wire secrets_on  = ((status[93:92] != 2'd0) & is_hangtime) | ((status[112:110] != 3'd0) & is_openice);
reg  window_on;                           // either window is up (registered: see Video)
wire pause = pause_toggle | (OSD_STATUS & ~status[8]) | window_on;

//////////////////////////////////////////////////////////////////
// DSW
//
// Every game takes its DIP switches from the OSD's "DIP Switches" page
// (P2, with Service Credit and Tilt), not the MRA (the MRAs have none, so
// the framework's own DIP entry stays hidden). Each option's first setting
// is MAME's default for that game (MK3 / UMK3 0xFD7D, WWF 0x7FFD, the
// Hangtimes 0x7F7D, Open Ice 0xEBBE, Rampage 0xFBBE). Options of the same
// name share status bits across games; games without one (names left off
// a game's list) keep MAME's default:
//   118 Test Switch      119 Counters (Two, One)   116-115 Counters (3-way)
//   124-120 Coinage (each game's list, MAME's order)  125 Coinage Source
//   126 Bill Validator   127 Attract Sound         117 Powerup Test
//   94 Blood / Cabinet / Realtime Clock            95 Violence / Head Size
//   114-113 Country (Hangtimes; MK3 / UMK3 use 117-113 for the Move List)
//////////////////////////////////////////////////////////////////

reg  [4:0] mk_coin;                  // MK3 / UMK3: USA-1 ... French-Free Play
always @(*) begin
	case (status[124:120])
		5'd0:  mk_coin = 5'd31;  5'd1:  mk_coin = 5'd15;  5'd2:  mk_coin = 5'd23;  5'd3:  mk_coin = 5'd7;
		5'd4:  mk_coin = 5'd27;  5'd5:  mk_coin = 5'd3;   5'd6:  mk_coin = 5'd29;  5'd7:  mk_coin = 5'd13;
		5'd8:  mk_coin = 5'd21;  5'd9:  mk_coin = 5'd5;   5'd10: mk_coin = 5'd25;  5'd11: mk_coin = 5'd9;
		5'd12: mk_coin = 5'd1;   5'd13: mk_coin = 5'd30;  5'd14: mk_coin = 5'd14;  5'd15: mk_coin = 5'd22;
		5'd16: mk_coin = 5'd6;   5'd17: mk_coin = 5'd26;  5'd18: mk_coin = 5'd2;
		default: mk_coin = 5'd31;
	endcase
end

reg  [4:0] coin23;                   // Open Ice, Rampage: USA-1 ... French-Free Play
always @(*) begin
	case (status[124:120])
		5'd0:  coin23 = 5'd31;  5'd1:  coin23 = 5'd30;  5'd2:  coin23 = 5'd29;  5'd3:  coin23 = 5'd28;
		5'd4:  coin23 = 5'd26;  5'd5:  coin23 = 5'd25;  5'd6:  coin23 = 5'd27;  5'd7:  coin23 = 5'd24;
		5'd8:  coin23 = 5'd23;  5'd9:  coin23 = 5'd22;  5'd10: coin23 = 5'd21;  5'd11: coin23 = 5'd20;
		5'd12: coin23 = 5'd18;  5'd13: coin23 = 5'd19;  5'd14: coin23 = 5'd16;  5'd15: coin23 = 5'd15;
		5'd16: coin23 = 5'd14;  5'd17: coin23 = 5'd13;  5'd18: coin23 = 5'd12;  5'd19: coin23 = 5'd10;
		5'd20: coin23 = 5'd9;   5'd21: coin23 = 5'd11;  5'd22: coin23 = 5'd8;
		default: coin23 = 5'd31;
	endcase
end

reg  [2:0] coin6;                    // WWF, Hangtimes: 1, 2, 3, 4, ECA, Free Play
always @(*) begin
	case (status[122:120])
		3'd0: coin6 = 3'd7;  3'd1: coin6 = 3'd3;  3'd2: coin6 = 3'd5;
		3'd3: coin6 = 3'd1;  3'd4: coin6 = 3'd6;  3'd5: coin6 = 3'd0;
		default: coin6 = 3'd7;
	endcase
end

wire [1:0] counters3 = 2'd3 - status[116:115];     // One 1/1, One Totalizing, Two 1/1: 3, 2, 1
wire [1:0] country   = 2'd3 - status[114:113];     // USA, French, German: 3, 2, 1

//                    15 Violence  14 Blood     13    12 Attract    11    10 Bill        9 Powerup 8
wire [15:0] mk_dsw = {~status[95], ~status[94], 1'b1, ~status[127], 1'b1, ~status[126], 1'b0,     1'b1,
                      status[125], mk_coin, status[119], ~status[118]};
//                    7 Source     6-2 Coinage  1 Counters   0 Test Switch

//                     15 Source    14-12 Coinage 11-10 Country 9-8 Counters 7     6 Bill        5-4
wire [15:0] wwf_dsw = {status[125], coin6,        2'd3,         counters3,   1'b1, ~status[126], 2'b11,
                       ~status[94], 1'b1, status[117], ~status[118]};
//                     3 Realtime Clock 2  1 Powerup   0 Test Switch

//                    15 Source    14-12 Coinage 11-10 Country 9-8 Counters 7 Cabinet   6 Bill  5-2
wire [15:0] ht_dsw = {status[125], coin6,        country,      counters3,   status[94], 1'b1,   4'b1111,
                      status[117], ~status[118]};
//                    1 Powerup    0 Test Switch

//                    15 Test       14-13  12 Cabinet  11 Head Size  10 Powerup 9 Attract     8 Bill
wire [15:0] oi_dsw = {~status[118], 2'b11, status[94], ~status[95],  1'b0,      ~status[127], ~status[126],
                      1'b1, status[119], coin23, status[125]};
//                    7     6 Counters   5-1 Coinage 0 Source

//                    15 Test       14-11    10 Powerup   9     8 Bill
wire [15:0] rw_dsw = {~status[118], 4'b1111, status[117], 1'b1, ~status[126],
                      1'b1, status[119], coin23, status[125]};
//                    7     6 Counters   5-1 Coinage 0 Source

reg [15:0] dsw;
always @(posedge clk_sys)
	dsw <= is_mk ? mk_dsw : is_wwf ? wwf_dsw : is_hangtime ? ht_dsw : is_openice ? oi_dsw : rw_dsw;

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
// "Open EJB Menu" (MK3, UMK3: on the Secret Menu page, P8) and "Secret
// Midway Menu" (NBA Hangtime, Maximum Hangtime: Off / On, back to Off once
// started) enter the game's own button code for its hidden menu
// (rtl/wunit_macro.sv lists the codes); the buttons are pressed on IN0 on
// top of the controls. They share status bit 16; only the game's own line
// is shown.
//
// "Scorpion - Smoke Voice Fix" (UMK3, Secret Menu page; its lines are the
// option and a two-line note, the OSD being 32 characters wide) runs the
// patched copy of the program ROM the MRA loads after the graphics:
// Scorpion's "Get over here!" and "Come here!" keep their sound channel when
// the spear's blood sounds come (the game gave them the lowest priority, so
// the hit cut them off after 12 frames); the same copy gives the EJB menu
// back the CHARACTER ENDINGS item that MK3 had and UMK3 left out of its menu
// (its code is still in the ROM), and an ending shows the story as well as
// the cast roll. The copy is chosen at reset; changing the option resets the
// game. (tools/cut_content.py)
//////////////////////////////////////////////////////////////////

reg         prog_alt;                // running the patched program copy
reg         opt_d;
reg         code_d;
wire [15:0] macro_press;

always @(posedge clk_sys) begin
	is_mk       <= (game_id == G_MK3) || (game_id == G_UMK3);
	is_hangtime <= (game_id == G_NBAHANGT);
	is_openice  <= (game_id == G_OPENICE);
	is_wwf      <= (game_id == G_WWF);
	is_rampage  <= (game_id == G_RMPGWT);
	alt_present <= (cfg_alt != 16'd0);

	if (reset)
		prog_alt <= status[17] & alt_present;

	opt_d  <= status[17];
	code_d <= status[16];
	// on the Hangtimes "Secret Midway Menu" is an Off / On option: once On
	// has started the code, the option is set back to Off
	smm_clear <= is_hangtime & status[16] & ~code_d;
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
// The "Kombat Kodes" page (P3) links to four category pages (Fight, Round
// 1 Winner Battles, Kombat Zone, Messages: P4-P7; the OSD has one level of
// pages, so Back from a category goes to the main menu) and lists the
// Ultimate Kombat Kodes itself (the OSD has nine pages). The kodes are the
// ones the game's program ROM has (the UMK3-only lines and pages hidden on
// MK3, MK3's Smoke kode on UMK3), each a trigger on status bits 18-56,
// 103-109, 64-67, then 73, in order (tools/kombat_kodes.py KODE_BITS: 57-63
// went to the finishing moves, 68-72 were taken). A pick is entered by the player (rtl/wunit_kodes.sv) at the
// next screen that takes it: the VS screen of a two-player fight, or, for
// an Ultimate Kombat Kode, the game over screen. It finds those by
// the game's state variable, whose main RAM word the MRA gives (config
// bytes 12-13). An OSD message says the kode is waiting, then entered.
//////////////////////////////////////////////////////////////////

wire [50:0] kode_bits = {status[73], status[67:64], status[109:103], status[56:18]};
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
// The "Finishing Moves" page (P9) has a Character option (the game's
// characters in alphabetical order, MK3's 15 or UMK3's 23: status bits
// 72-68) and below it the moves of that character only, each by name and
// input: each line carries
// two menu mask bits, the character's number / 5 and % 5, that the player
// clears for the picked character (see rtl/wunit_finish.sv; lines that
// differ for MK3 1.0 / p4.0 also bit 3, which on MK3 / UMK3 says whether
// the MRA gave the MK3 1.x table). Each move is a trigger on status bits
// 57-62 by slot (Fatality 1, Fatality 2, Stage Fatality, Animality,
// Friendship, Babality), the Mercy on 63 (written rP-rV, MiSTer's short
// form for bits 32-63: the page has 160-odd lines). The Mercy line shows
// for every fighter that has one (all but MK3 1.x's Cyrax) and enters the
// winner's own. The player
// enters a pick at FINISH HIM on the winner's controls; the lines, the
// programs and the table byte of the MRA (config byte 14) come from
// tools/finishing_moves.py.
//////////////////////////////////////////////////////////////////

wire  [6:0] fin_bits = status[63:57];
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
	.char_id   (),
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
	.dsw            (dsw),
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

// ---- Move List window (MK3, UMK3) and Secret Codes window (NBA Hangtime,
// Maximum Hangtime, Open Ice): rtl/wunit_movelist.sv ----
//
// OSD "Move List" (status bits 117-113: Off, then the game's characters in
// the OSD's alphabetical order) draws that fighter's moves over the game's
// logo (tools/movelist_logo.py), and the game pauses while the window is
// up. Pages (tools/move_list.py, in the same order): UMK3 0-22, MK3 rev
// 2.x 23-37, MK3 rev 1.x 38-52 (the MRA's finishing moves table). OSD
// "Secret Codes" (bits 93-92: Off, Page 1 the secret players with who they
// are and the match-up codes, Page 2 the hidden NBA players) shows the
// Hangtimes' lists the same way, over the game's logo: pages 53-60, two per
// variant (MRA byte 14), 61 (over the dimmed game) when the MRA names none;
// on Open Ice (bits 112-110: Off, Secret Players 1-3, Tonight's Game codes,
// face-off codes) pages 62-66. The picture passes unchanged otherwise.

wire [6:0] ml_page = is_openice  ? 7'd61 + {4'd0, status[112:110]} :
                     is_hangtime ? (cfg_ht == 3'd0 ? 7'd61 : 7'd51 + {3'b000, cfg_ht, 1'b0} + {6'd0, status[93]}) :
                     (is_umk3 ? 7'd0 : cfg_fin == 2'd2 ? 7'd38 : 7'd23) + {2'b00, ml_sel} - 7'd1;
// behind the text the game's logo (tools/movelist_logo.py: 1 MK3, 2 UMK3,
// 3 Open Ice, 4 NBA Hangtime, 5 Maximum Hangtime), the dimmed game when
// the Hangtime MRA names no variant
wire [2:0] ml_logo = movelist_on ? (is_umk3 ? 3'd2 : 3'd1) :
                     is_openice  ? 3'd3 :
                     is_hangtime ? (cfg_ht == 3'd0 ? 3'd0 : cfg_ht == 3'd1 ? 3'd4 : 3'd5) : 3'd0;
wire [7:0] ml_r, ml_g, ml_b;

// the window's selection, registered: it only changes with the OSD, and the
// game-type and option logic behind it then stays off the window's
// per-dot paths (the logo ROM's address, the picture into the CRT stage)
reg  [6:0] window_page;
reg  [2:0] window_logo;
always @(posedge clk_sys) begin
	window_on   <= movelist_on | secrets_on;
	window_page <= ml_page;
	window_logo <= ml_logo;
end

wunit_movelist movelist
(
	.clk     (clk_sys),
	.ce_pix  (ce_pix),
	.enable  (window_on),
	.page    (window_page),
	.logo    (window_logo),
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
