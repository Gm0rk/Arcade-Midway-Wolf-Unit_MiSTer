// ============================================================================
//  tb_finish.cpp - the finishing move player (rtl/wunit_finish.sv) on its own
//
//  Plays a FINISH HIM to the player through main RAM writes as the game
//  makes them (state variable, player blocks, the fighters' objects and
//  positions, the FINISH HIM state), picks a move, and writes what the
//  player holds on the controls, one line per running frame from the pick
//  until it is done:
//      IN0 IN1          (hex, active high)
//  then its OSD messages as "info N". tools/lua/finishing_moves.lua plays
//  such lines in MAME (tools/finishing_moves.py --mame ... --rtl).
//
//  Usage: Vwunit_finish [-umk3] [-table T] [-winner 1|2] [-left] [-opt N]
//                       [-char C] [-slot S] [-kstate W] [-nofinish]
//    -umk3      UMK3's RAM layout (default MK3's)
//    -table T   MRA config byte 14 (default 1)
//    -winner P  the player who won (default 1)
//    -left      the winner stands right of the loser (faces left)
//    -opt N     the OSD's character option (default 0)
//    -char C    the winner's character as the game numbers it (default 0)
//    -slot S    the move (0-5, 6 the Mercy)
//    -kstate W  the state variable's main RAM word (default 6096)
//    -nofinish  FINISH HIM is not running
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
// ============================================================================

#include "Vwunit_finish.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

static Vwunit_finish *top;

static void tick()
{
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
}

static void ram_write(unsigned word, unsigned data)
{
	top->ram_wr = 1;
	top->ram_wa = word;
	top->ram_wd = data;
	tick();
	top->ram_wr = 0;
	for (int i = 0; i < 4; i++) tick();
}

int main(int argc, char **argv)
{
	bool umk3 = false, left = false, finish = true;
	int table = 1, winner = 1, opt = 0, chr = 0, slot = 0;
	unsigned kst = 0x6096;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-umk3")) umk3 = true;
		else if (!strcmp(argv[i], "-left")) left = true;
		else if (!strcmp(argv[i], "-nofinish")) finish = false;
		else if (!strcmp(argv[i], "-table") && i + 1 < argc) table = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-winner") && i + 1 < argc) winner = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-opt") && i + 1 < argc) opt = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-char") && i + 1 < argc) chr = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-slot") && i + 1 < argc) slot = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-kstate") && i + 1 < argc) kst = strtoul(argv[++i], nullptr, 16);
	}
	Verilated::commandArgs(argc, argv);
	top = new Vwunit_finish;
	top->reset = 1;
	top->umk3 = umk3;
	top->table_id = table;
	top->kstate = kst;
	top->opt = opt;
	top->sel = 0;
	top->frame = 0;
	top->ram_wr = 0;
	for (int i = 0; i < 10; i++) tick();
	top->reset = 0;
	for (int i = 0; i < 10; i++) tick();

	// the fighters as the game keeps them
	unsigned b1 = kst + (umk3 ? 7 : 5), b2 = b1 + 0xBB;
	unsigned fh = kst + (umk3 ? 0x194 : 0x18F);
	unsigned o1 = 0x3045, o2 = 0x3066;            // their objects (words)
	ram_write(kst, 2);
	ram_write(b1, (0x01000000u + o1 * 16) & 0xFFFF);
	ram_write(b1 + 1, (0x01000000u + o1 * 16) >> 16);
	ram_write(b2, (0x01000000u + o2 * 16) & 0xFFFF);
	ram_write(b2 + 1, (0x01000000u + o2 * 16) >> 16);
	int xw = left ? 700 : 500, xl = 600;
	ram_write(o1 + 9, winner == 1 ? xw : xl);
	ram_write(o2 + 9, winner == 1 ? xl : xw);
	ram_write(b1 + 9, winner == 1 ? 0xA6 : 0);
	ram_write(b2 + 9, winner == 1 ? 0 : 0xA6);
	if (finish) ram_write(fh, 3);

	ram_write(b1 + 6, winner == 1 ? chr : 0);
	ram_write(b2 + 6, winner == 1 ? 0 : chr);

	top->sel_slot = slot;
	top->sel = 1;
	tick();
	top->sel = 0;
	if (top->info_req) printf("info %d\n", top->info);
	for (int i = 0; i < 10; i++) {
		tick();
		if (top->info_req) printf("info %d\n", top->info);
	}
	int frames = 0;
	while (top->busy && frames < 1000) {
		top->frame = 1;
		tick();
		top->frame = 0;
		if (top->info_req) printf("info %d\n", top->info);
		for (int i = 0; i < 20; i++) {
			tick();
			if (top->info_req) printf("info %d\n", top->info);
		}
		printf("%04X %04X\n", top->press0, top->press1);
		frames++;
	}
	delete top;
	return 0;
}
