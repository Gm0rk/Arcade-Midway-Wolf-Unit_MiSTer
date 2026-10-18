// ============================================================================
//  tb_dcs.cpp - the DCS sound board (rtl/dcs_audio.sv) against MAME
//
//  Runs the board on its own: the sound ROMs from a ROM image as
//  tools/wunit_roms.py writes it (SDRAM layout, sound ROMs from 0x100000)
//  behind a channel 0 model with a fixed latency, and the host side played
//  from an events file that tools/dcs_trace.py makes from a MAME trace.
//
//  It writes one line per instruction, in tools/lua/dcs_trace.lua's form:
//  the registers before the instruction (AX0 AX1 AY0 AY1 AR AF MX0 MX1 MY0
//  MY1 MR0 MR1 MR2 MF SI SE SB SR0 SR1 I0-I7 CNTR ASTAT MSTAT IMASK PX, the
//  input latch's IRQ2 and data), then "PC: opcode". The main loop's waits
//  for the DAC buffer (PC 0137-0139, 013D-013F) are left out unless -raw,
//  as tools/dcs_trace.py events leaves them out of MAME's trace: they are
//  most of it. Instruction n of the rest is MAME's instruction n, and the
//  events say which instruction each host action comes before:
//    n W xx   the host writes xx to the input latch
//    n R      the host resets the DSP (held for a while, then released)
//  A write goes in while the instruction before it writes back, so the DSP
//  sees it at the next instruction boundary, as MAME does; a reset starts
//  the clock after that write back.
//
//  With -host the events are instead the host's side as dcs_trace.lua's
//  DCS_HOST logs it, by time: "t W xx" (latch write) and "t C xxxx" (I/O
//  control word, bit 4 holds the DSP in reset), t in microseconds from
//  power-on: a reset at that tick, a write when the DSP's own time (ticks
//  less the instruction cycles it owes) gets there. No MAME trace is needed,
//  so long runs with many sounds are quick to get; tools/dcs_trace.py dac
//  then compares the DAC words.
//
//  Usage: Vdcs_audio <image> <events> <out> [-n N] [-samples FILE] [-lat L]
//                    [-raw] [-host [-t S] [-rt]]
//    -n N          stop after N instructions (collapsed; default: when the
//                  events run out, plus 100000)
//    -t S          with -host: stop after S seconds (default: 1 s after the
//                  last event)
//    -samples FILE the DAC words, one per line ("cycle word", cycle in
//                  10 MHz instruction cycles)
//    -lat L        ROM latency in clocks (default 12)
//    -rt           with -host: write at the event's real time, not the DSP's own
//                  (the hardware: a write finds the latch full if the DSP lags)
//    -raw          keep the DAC buffer waits (against dcs_trace.py events -raw)
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
// ============================================================================

#include "Vdcs_audio.h"
#include "Vdcs_audio___024root.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

struct Event { long n; char kind; unsigned v; double t; };

static std::vector<uint8_t> image;
static Vdcs_audio *top;
static uint64_t clocks;

static void tick()
{
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	clocks++;
}

// the main loop's DAC buffer waits (PC, opcode)
static bool poll_op(unsigned pc, unsigned op)
{
	switch (pc) {
	case 0x137: case 0x13D: return op == 0x0D02A3;
	case 0x138: case 0x13E: return op == 0x26E20F;
	case 0x139: return op == 0x181375;
	case 0x13F: return op == 0x1813D4;
	}
	return false;
}

int main(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "usage: %s <image> <events> <out> [-n N] [-samples FILE] [-lat L] [-raw] [-host [-t S] [-rt]]\n", argv[0]);
		return 1;
	}
	long limit = -1;
	int lat = 12;
	FILE *fs = nullptr;
	bool host = false, raw = false, rt = false;
	double tlimit = -1;
	for (int i = 4; i < argc; i++) {
		if (!strcmp(argv[i], "-n") && i + 1 < argc) limit = atol(argv[++i]);
		else if (!strcmp(argv[i], "-samples") && i + 1 < argc) fs = fopen(argv[++i], "w");
		else if (!strcmp(argv[i], "-lat") && i + 1 < argc) lat = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-host")) host = true;
		else if (!strcmp(argv[i], "-rt")) rt = true;
		else if (!strcmp(argv[i], "-raw")) raw = true;
		else if (!strcmp(argv[i], "-t") && i + 1 < argc) tlimit = atof(argv[++i]);
	}

	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 1; }
	fseek(f, 0, SEEK_END);
	image.resize(ftell(f));
	fseek(f, 0, SEEK_SET);
	if (fread(image.data(), 1, image.size(), f) != image.size()) { perror(argv[1]); return 1; }
	fclose(f);
	image.resize(32 << 20, 0xff);

	std::vector<Event> ev;
	f = fopen(argv[2], "r");
	if (!f) { perror(argv[2]); return 1; }
	char line[256];
	while (fgets(line, sizeof line, f)) {
		Event e{};
		char k;
		unsigned v = 0;
		if (host ? sscanf(line, "%lf %c %x", &e.t, &k, &v) == 3 : sscanf(line, "%ld %c %x", &e.n, &k, &v) >= 2) {
			e.kind = k;
			e.v = v;
			ev.push_back(e);
		}
	}
	fclose(f);
	if (host) {
		limit = 1L << 62;
		if (tlimit < 0) tlimit = (ev.empty() ? 0 : ev.back().t * 1e-6) + 1.0;
	}
	if (limit < 0) limit = (ev.empty() ? 0 : ev.back().n) + 100000;

	FILE *out = fopen(argv[3], "w");
	if (!out) { perror(argv[3]); return 1; }

	Verilated::commandArgs(argc, argv);
	top = new Vdcs_audio;
	auto *r = top->rootp;

	top->reset = 1;
	top->dcs_reset = 0;
	top->host_wr = 0;
	top->host_rd = 0;
	top->rom_ack = 0;
	for (int i = 0; i < 20; i++) tick();
	top->reset = 0;

	long n = 0;                 // collapsed instructions started
	size_t ei = 0;              // next event
	int rom_wait = -1;
	unsigned prev_st = 0;
	unsigned snap[34];
	unsigned snap_pc = 0;
	bool have_snap = false;
	int reset_hold = 0;
	bool reset_next = false;
	std::vector<unsigned> pending_wr;   // writes that follow a reset
	uint64_t cycles = 0;        // 10 MHz ticks
	unsigned maxtok = 0, lost = 0;

	while (n < limit) {
		// channel 0
		if (rom_wait < 0 && top->rom_req != top->rom_ack)
			rom_wait = lat;
		if (rom_wait == 0) {
			uint64_t a = (uint64_t)top->rom_addr << 3, d = 0;
			for (int b = 0; b < 8; b++) d |= (uint64_t)image[(a + b) % image.size()] << (8 * b);
			top->rom_data = d;
			top->rom_ack = top->rom_req;
		}
		if (rom_wait >= 0) rom_wait--;

		// host
		top->host_wr = 0;
		if (reset_next) {
			// after the write back of the instruction before
			top->dcs_reset = 1;
			reset_hold = 200;
			reset_next = false;
		}
		else if (reset_hold > 0 && --reset_hold == 0) {
			top->dcs_reset = 0;
			if (!pending_wr.empty()) {
				top->host_wr = 1;
				top->host_data = pending_wr.back();
				pending_wr.clear();
			}
		}
		unsigned st = r->dcs_audio__DOT__dsp__DOT__st;
		if ((unsigned)r->dcs_audio__DOT__dsp__DOT__tok > maxtok) maxtok = r->dcs_audio__DOT__dsp__DOT__tok;
		if (host) {
			// by time: a write when the DSP's own time (ticks less the
			// instruction cycles it owes) gets there, as MAME's scheduler
			// hands it over between two of its instructions; with -rt at the
			// real time, as the hardware gets it
			uint64_t dsp_time = cycles - r->dcs_audio__DOT__dsp__DOT__tok;
			while (ei < ev.size() && ev[ei].t * 10.0 <= (double)(ev[ei].kind == 'W' && !top->dcs_reset && !rt ? dsp_time : cycles)) {
				const Event &e = ev[ei++];
				if (e.kind == 'C')
					top->dcs_reset = (e.v >> 4) & 1;
				else if (e.kind == 'W') {
					top->host_wr = 1;
					top->host_data = e.v;
					if (r->dcs_audio__DOT__in_full) lost++;
					break;                       // one write a clock
				}
			}
			if (cycles >= tlimit * 1e7) break;
		}
		else if (st == 9 && ei < ev.size() && ev[ei].n == n && !top->dcs_reset) {
			// write back of instruction n - 1: the actions before instruction n
			while (ei < ev.size() && ev[ei].n == n) {
				const Event &e = ev[ei++];
				if (e.kind == 'R')
					reset_next = true;
				else if (e.kind == 'W') {
					if (reset_next) pending_wr.push_back(e.v);
					else { top->host_wr = 1; top->host_data = e.v; }
				}
			}
		}

		tick();
		if (r->dcs_audio__DOT__tick) cycles++;
		if (fs && top->sample_strobe)
			fprintf(fs, "%llu %04x\n", (unsigned long long)cycles, top->sample);

		// registers at the start of each instruction (fetch issued: S_TOP -> S_OPW)
		st = r->dcs_audio__DOT__dsp__DOT__st;
		if (prev_st == 3 && st == 4) {
			auto &rf = r->dcs_audio__DOT__dsp__DOT__rf;
			int b = (r->dcs_audio__DOT__dsp__DOT__mstat & 1) ? 32 : 0;
			static const int slot[19] = { 0, 1, 4, 5, 10, 16, 2, 3, 6, 7, 11, 12, 13, 17, 8, 9, 18, 14, 15 };
			for (int i = 0; i < 19; i++) snap[i] = rf[b + slot[i]];
			snap[12] &= 0xff;          // MR2
			snap[15] &= 0xff;          // SE
			snap[16] &= 0x1f;          // SB
			for (int i = 0; i < 8; i++) snap[19 + i] = r->dcs_audio__DOT__dsp__DOT__ir[i];
			snap[27] = r->dcs_audio__DOT__dsp__DOT__cntr;
			snap[28] = r->dcs_audio__DOT__dsp__DOT__astat;
			snap[29] = r->dcs_audio__DOT__dsp__DOT__mstat;
			snap[30] = r->dcs_audio__DOT__dsp__DOT__imask;
			snap[31] = r->dcs_audio__DOT__dsp__DOT__px;
			snap[32] = r->dcs_audio__DOT__in_full;
			snap[33] = r->dcs_audio__DOT__in_data;
			snap_pc = r->dcs_audio__DOT__dsp__DOT__pc;
			have_snap = true;
		}
		prev_st = st;

		if (top->dbg_retire && have_snap) {
			have_snap = false;
			if (top->dbg_pc != snap_pc)
				fprintf(stderr, "snapshot PC %04x, retired %04x\n", snap_pc, top->dbg_pc);
			if (raw || !poll_op(top->dbg_pc, top->dbg_op)) {
				for (int i = 0; i < 34; i++) fprintf(out, "%X ", snap[i]);
				fprintf(out, "%04X: %06X\n", top->dbg_pc, top->dbg_op);
				n++;
			}
		}
		if (!host && clocks > (uint64_t)limit * 400 + 100000000ull) {
			fprintf(stderr, "stuck at instruction %ld (PC %04x)\n", n, top->dbg_pc);
			break;
		}
	}
	fclose(out);
	if (fs) fclose(fs);
	fprintf(stderr, "max owed %u cycles, %u host writes found the latch full\n", maxtok, lost);
	fprintf(stderr, "%ld instructions, %llu clocks, %llu cycles, %zu/%zu events\n", n,
	        (unsigned long long)clocks, (unsigned long long)cycles, ei, ev.size());
	delete top;
	return 0;
}
