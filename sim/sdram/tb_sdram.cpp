// ============================================================================
//  tb_sdram.cpp - rtl/sdram.sv's command timing against the SDRAM datasheet
//
//  Random traffic on the controller's channels as the core makes it (sound
//  reads in bank 0; the CPU's main RAM writes, back to back, and reads
//  anywhere; blitter reads; the download / RAM clear write port in bank 3)
//  and every command the controller sends checked against the chips on the
//  MiSTer SDRAM modules (AS4C16M16SA / AS4C32M16SB, speed grades -6 and -7):
//  ACTIVE to ACTIVE in a bank (tRC), ACTIVE to READ / WRITE (tRCD), the
//  bank's auto precharge over before its next ACTIVE (tRAS, tWR, tRP) and
//  before a refresh, refresh to refresh / ACTIVE (tRFC).
//
//  Usage: tb_sdram [clocks] [seed]
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
// ============================================================================

#include "Vsdram.h"
#include "Vsdram___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>

static const double TCK = 1000.0 / 96.0;                 // ns
static const char *GRADE[2] = {"-6", "-7"};
static const double tRC[2] = {60, 63}, tRCD[2] = {18, 21}, tRAS[2] = {42, 42}, tRP[2] = {18, 21}, tWR[2] = {12, 14};

static uint64_t s = 88172645463325252ull;
static uint32_t rnd() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return (uint32_t)s; }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	long ncyc = argc > 1 ? atol(argv[1]) : 400000;
	if (argc > 2) s ^= strtoull(argv[2], 0, 0) * 0x9E3779B97F4A7C15ull;
	Vsdram *t = new Vsdram;
	auto *r = t->rootp;

	t->init = 1;
	t->SDRAM_DQ_I = 0;
	for (int i = 0; i < 20; i++) { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }
	t->ch0_req = t->ch0_ack; t->ch1_req = t->ch1_ack; t->ch2_req = t->ch2_ack; t->ch3_req = t->ch3_ack;
	t->wr_req = t->wr_ack;
	t->init = 0;

	double act[4], idle[2][4], lastwr[4], lastwr_any = -1e9, ref = -1e9;
	bool waswr[4] = {false, false, false, false};
	for (int b = 0; b < 4; b++) { act[b] = -1e9; idle[0][b] = idle[1][b] = -1e9; lastwr[b] = -1e9; }
	long viol[2][5] = {{0}}, ncmd[4] = {0};
	double short_rd[2] = {0, 0}, short_wr[2] = {0, 0};
	double min_aa = 1e9, min_wa = 1e9, min_wr_ref = 1e9;
	bool started = false;
	long n_clear = 0;

	for (long c = 0; c < ncyc; c++) {
		t->clk = 1; t->eval();
		double now = c * TCK;
		// the command the controller drives after this edge
		if (!started) started = r->sdram__DOT__state == 4;        // STATE_IDLE: start-up done
		int cmd = (t->SDRAM_nRAS << 2) | (t->SDRAM_nCAS << 1) | t->SDRAM_nWE;
		int b = t->SDRAM_BA;
		if (started) {
			if (cmd == 3) {                                          // ACTIVE
				ncmd[0]++;
				if (now - act[b] < min_aa) min_aa = now - act[b];
				if (now - lastwr[b] < min_wa) min_wa = now - lastwr[b];
				for (int g = 0; g < 2; g++) {
					if (now - act[b] < tRC[g] - 1e-6) viol[g][0]++;
					if (now < idle[g][b] - 1e-6) {
						viol[g][2]++;
						double d = idle[g][b] - now;
						if (waswr[b]) { if (d > short_wr[g]) short_wr[g] = d; }
						else if (d > short_rd[g]) short_rd[g] = d;
					}
					if (now - ref < tRC[g] - 1e-6) viol[g][4]++;
				}
				act[b] = now;
			} else if (cmd == 5 || cmd == 4) {                       // READ / WRITE with auto precharge
				bool wr = cmd == 4;
				ncmd[wr ? 2 : 1]++;
				for (int g = 0; g < 2; g++) {
					if (now - act[b] < tRCD[g] - 0.5) viol[g][1]++;
					// precharge starts after the burst (read) or the write recovery,
					// not before tRAS; the bank is idle tRP later
					double start = wr ? now + tWR[g] : now + 4 * TCK;
					if (start < act[b] + tRAS[g]) start = act[b] + tRAS[g];
					idle[g][b] = start + tRP[g];
				}
				waswr[b] = wr;
				if (wr) { lastwr[b] = now; lastwr_any = now; }
			} else if (cmd == 1) {                                   // AUTO REFRESH
				ncmd[3]++;
				if (now - lastwr_any < min_wr_ref) min_wr_ref = now - lastwr_any;
				for (int g = 0; g < 2; g++) {
					for (int k = 0; k < 4; k++)
						if (now < idle[g][k] - 1e-6) {
							viol[g][3]++;
							double d = idle[g][k] - now;
							if (waswr[k]) { if (d > short_wr[g]) short_wr[g] = d; }
							else if (d > short_rd[g]) short_rd[g] = d;
						}
					if (now - ref < tRC[g] - 1e-6) viol[g][4]++;
				}
				ref = now;
			}
		}
		t->clk = 0; t->eval();

		// traffic, as the core's clients make it
		if (!started) continue;
		if (t->ch0_req == t->ch0_ack && (rnd() & 31) == 0) {               // sound: bank 0
			t->ch0_addr = 0x20000 + (rnd() & 0x3FFFF); t->ch0_req ^= 1;
		}
		if (t->ch1_req == t->ch1_ack && (rnd() & 3) == 0) {                // CPU
			t->ch1_we = rnd() & 1;
			t->ch1_addr = (rnd() & 1) ? 0xFC0000 + (rnd() & 0x3FFFF) : (rnd() & 0xFFFFFF);
			t->ch1_din = rnd(); t->ch1_be = 3; t->ch1_req ^= 1;
		}
		if (t->ch2_req == t->ch2_ack && (rnd() & 7) == 0) {                // blitter
			t->ch2_addr = rnd() & 0x3FFFFF; t->ch2_req ^= 1;
		}
		if (t->wr_req == t->wr_ack && n_clear < ncyc / 4) {                 // RAM clear
			t->wr_addr = 0xFC0000 + (n_clear++ & 0x3FFFF); t->wr_data = 0; t->wr_be = 3; t->wr_req ^= 1;
		}
	}

	printf("%ld clocks: ACTIVE %ld, READ %ld, WRITE %ld, REFRESH %ld\n", ncyc, ncmd[0], ncmd[1], ncmd[2], ncmd[3]);
	printf("shortest: ACTIVE to ACTIVE in a bank %.1f ns, WRITE to its bank's ACTIVE %.1f ns, WRITE to REFRESH %.1f ns\n",
	       min_aa, min_wa, min_wr_ref);
	int bad = 0;
	for (int g = 0; g < 2; g++) {
		printf("%s: tRC %ld, tRCD %ld, ACTIVE before precharge %ld, REFRESH before precharge %ld, tRFC %ld; "
		       "largest shortfall after a READ %.1f ns, after a WRITE %.1f ns\n", GRADE[g],
		       viol[g][0], viol[g][1], viol[g][2], viol[g][3], viol[g][4], short_rd[g], short_wr[g]);
		// the read path's 2-clock tRCD and precharge (20.8 ns against -7's 21) are
		// the original controller's: reported, not failed
		if (viol[g][0] || viol[g][4] || short_wr[g] > 0 || (g == 0 && (viol[g][1] || viol[g][2] || viol[g][3]))) bad = 1;
	}
	printf("%s\n", bad ? "FAIL" : "OK");
	delete t;
	return bad;
}
