// tb_dma.cpp - random blits through rtl/wunit_dma.sv against MAME's code
//
// Each test fills a 32 MB graphics ROM with random bytes, programs a random
// blit through the CPU register interface (both clip banks, every mode, bpp,
// skip, scale, flip, clip and skip-register form), starts it, and runs the
// blitter with
//   - a graphics ROM that answers line requests after a random delay
//   - a VRAM controller model that reads finished rows out of the blitter's
//     row buffer as the real one does (one beat per clock, data a clock
//     after the address) and applies the byte enables
// until the completion interrupt. The frame store must then equal MAME's
// (mame_dma.h, MAME's dma_w / dma_draw), and the completion must come no
// earlier than MAME's 41 ns per pixel.
//
// Blits stay inside the frame store's columns (right clip below 512): MAME
// stores pixels past column 511 into the next row, which the core drops
// (a known difference, see wunit_dma.sv).
//
// Usage: tb_dma [tests] [seed]

#include "Vwunit_dma.h"
#include "verilated.h"
#include "mame_dma.h"
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>
#include <string>

static Vwunit_dma *top;
static uint64_t clocks = 0;

static std::vector<uint8_t> rom(0x2000000 + 16);
static std::vector<uint16_t> ref_vram(0x80000), dut_vram(0x80000);
static std::mt19937 rng;

static uint32_t rnd(uint32_t n) { return n ? rng() % n : 0; }

// ---- models around the blitter ----
static int gfx_wait = -1;          // clocks until the line request is answered
static int vr_state = 0;           // VRAM model: 0 idle, 1 reading beats
static int vr_i, vr_n, vr_lo, vr_row;

static void tick()
{
	top->clk = 0; top->eval();

	// graphics ROM: answer a new request after 4-24 clocks
	if (top->gfx_req != top->gfx_ack) {
		if (gfx_wait < 0) gfx_wait = 4 + rnd(21);
		else if (gfx_wait == 0) {
			uint32_t line = top->gfx_line;
			uint64_t v = 0;
			for (int b = 0; b < 8; b++) v |= (uint64_t)rom[(line * 8 + b) & 0x1FFFFFF] << (8 * b);
			top->gfx_data = v;
			top->gfx_ack = top->gfx_req;
			gfx_wait = -1;
		}
		else gfx_wait--;
	}

	// VRAM model: on a row request, address beat lo..hi, take data a clock
	// later (the blitter's row buffer output is registered)
	static bool take = false;
	static int take_beat = 0;
	if (take) {
		uint64_t q = top->blt_q;
		uint8_t be = top->blt_be;
		for (int e = 0; e < 4; e++) {
			uint16_t w = (q >> (16 * e)) & 0xFFFF;
			int idx = vr_row * 512 + take_beat * 4 + e;
			if ((be >> (2 * e)) & 1) dut_vram[idx] = (dut_vram[idx] & 0xFF00) | (w & 0xFF);
			if ((be >> (2 * e + 1)) & 1) dut_vram[idx] = (dut_vram[idx] & 0x00FF) | (w & 0xFF00);
		}
		take = false;
	}
	if (vr_state == 0 && top->blt_req != top->blt_ack) {
		vr_state = 1;
		vr_row = top->blt_row;
		vr_lo = top->blt_lo;
		vr_n = top->blt_hi - top->blt_lo + 1;
		vr_i = 0;
	}
	else if (vr_state == 1) {
		if (vr_i < vr_n) {
			top->blt_raddr = (vr_lo + vr_i) & 0x7F;
			take = true;
			take_beat = (vr_lo + vr_i) & 0x7F;
			vr_i++;
		}
		else {
			top->blt_ack = top->blt_req;
			vr_state = 0;
		}
	}

	top->eval();
	top->clk = 1; top->eval();
	clocks++;
}

static void reg_write(int idx, uint16_t v)
{
	top->reg_wr = 1; top->reg_idx = idx; top->reg_wdata = v;
	tick();
	while (top->reg_wr_wait) tick();
	top->reg_wr = 0;
	tick();
}

int main(int argc, char **argv)
{
	bool replay = argc > 1 && std::string(argv[1]) == "replay";
	int tests = (argc > 1 && !replay) ? atoi(argv[1]) : 2000;
	unsigned seed = argc > 2 ? atoi(argv[2]) : 1;
	rng.seed(seed);
	Verilated::commandArgs(argc, argv);
	top = new Vwunit_dma;

	MameDma ref;
	ref.m_local_videoram = ref_vram.data();
	ref.m_dma_state.gfxrom = rom.data();

	top->reset = 1;
	for (int i = 0; i < 8; i++) tick();
	top->reset = 0;
	tick();

	for (auto &b : rom) b = rng();

	// replay one blit: tb_dma replay <seed> <the 18 registers in hex, as a
	// failure prints them>
	if (argc > 3 && std::string(argv[1]) == "replay") {
		uint16_t r[18];
		for (int i = 0; i < 18; i++) r[i] = strtoul(argv[3 + i], nullptr, 16);
		auto both = [&](int idx, uint16_t v) { reg_write(idx, v); ref.dma_w(idx, v); };
		both(15, 0x0000); both(12, r[16]); both(13, r[17]);
		both(15, 0x0020); both(12, r[12]); both(13, r[13]);
		both(15, r[15]);
		for (int i : {0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}) both(i, r[i]);
		both(1, r[1]);
		while (!top->irq) tick();
		int bad = 0;
		for (int i = 0; i < 0x40000; i++)
			if (ref_vram[i] != dut_vram[i]) {
				if (bad < 40) printf("row %d col %d: MAME %04x core %04x\n", i / 512, i % 512, ref_vram[i], dut_vram[i]);
				bad++;
			}
		printf("%d entries differ\n", bad);
		return bad != 0;
	}

	int fails = 0, slow = 0;
	long changed = 0;                    // entries the blits changed (MAME side)
	uint64_t total_clk = 0, total_mame = 0;
	for (int t = 0; t < tests; t++) {
		// ---- a random blit ----
		uint16_t r[18] = {};
		int bpp = rnd(8);
		bool scaled = rnd(2);
		uint16_t cmd = 0x8000 | (bpp << 12) | (rnd(4) << 10) | (rnd(4) << 8) |
		               (rnd(2) << 7) | (rnd(2) << 6) | (rnd(2) << 5) | (rnd(2) << 4) | rnd(16);
		int w = rnd(10) == 0 ? rnd(1024) : rnd(200);
		int h = rnd(10) == 0 ? rnd(300) : rnd(60);
		r[0]  = rnd(3) == 0 ? rnd(0x10000) : (rnd(32) << 8) | rnd(32);
		r[2]  = rng(); r[3] = rnd(0x0E00);                      // offset below 0x0E000000 bits
		if (rnd(40) == 0) r[3] = 0x1000 + rnd(0xE000);          // out of range: no blit
		if (rnd(40) == 0) r[3] = 0xF800 + rnd(0x0E00);          // the F8000000 alias
		r[4]  = rng(); r[5] = rng();
		r[6]  = w | (rnd(4) == 0 ? (rng() & 0xFC00) : 0);
		r[7]  = h | (rnd(4) == 0 ? (rng() & 0xFC00) : 0);
		r[8]  = rng(); r[9] = rng();
		r[10] = scaled ? (rnd(3) == 0 ? 0 : 0x20 + rnd(0x600)) : 0;
		r[11] = scaled ? (rnd(3) == 0 ? 0 : 0x20 + rnd(0x600)) : 0;
		int lc = rnd(512), rc = lc + rnd(512 - lc);
		int tc = rnd(512), bc = rnd(512);
		if (rnd(3)) { tc = rnd(100); bc = 400 + rnd(112); }
		if (rnd(3)) { lc = rnd(64); rc = 400 + rnd(112); }
		r[16] = lc | (rnd(4) == 0 ? (rng() & 0xFC00) : 0) ;
		r[17] = rc;
		r[12] = tc | (rng() & 0xFE00);
		r[13] = bc | (rng() & 0xFE00);
		if (r[16] & 0x200) r[16] &= 0x1FF;                      // keep left clip below 512 too

		// ---- the same register writes to both ----
		auto both = [&](int idx, uint16_t v) { reg_write(idx, v); ref.dma_w(idx, v); };
		both(15, 0x0000);                    // bank 0: 12/13 are left/right clip
		both(12, r[16]); both(13, r[17]);
		both(15, 0x0020);                    // bank 1: top/bottom clip
		both(12, r[12]); both(13, r[13]);
		both(15, rng() & 0xFF20 & ~0x0020 | (rnd(2) << 5));
		for (int i : {0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}) both(i, r[i]);

		// start
		uint64_t c0 = clocks;
		both(1, cmd);
		int guard = 0;
		while (!top->irq) {
			tick();
			if (++guard > 50000000) { printf("test %d: no completion\n", t); return 1; }
		}
		uint64_t took = clocks - c0;
		uint64_t mame_clk = (uint64_t)ref.last_pixels * 41 * 96 / 1000;
		total_clk += took;
		total_mame += mame_clk;
		if (took + 8 < mame_clk) {
			printf("test %d: completion after %llu clocks, MAME %llu\n", t, (unsigned long long)took, (unsigned long long)mame_clk);
			fails++;
		}
		if (took > mame_clk + 200) slow++;

		// ---- compare the frame store (rows 0-511, columns 0-511) ----
		static std::vector<uint16_t> prev(0x40000);
		for (int i = 0; i < 0x40000; i++) {
			if (ref_vram[i] != prev[i]) changed++;
			prev[i] = ref_vram[i];
		}
		int bad = 0;
		for (int i = 0; i < 0x40000; i++) {
			if (ref_vram[i] != dut_vram[i]) {
				if (bad < 5)
					printf("test %d: entry row %d col %d: MAME %04x core %04x\n", t, i / 512, i % 512, ref_vram[i], dut_vram[i]);
				bad++;
			}
		}
		if (bad) {
			printf("test %d FAILED (%d entries) cmd %04x regs", t, bad, cmd);
			for (int i = 0; i < 18; i++) printf(" %04x", ref.m_dma_register[i]);
			printf("\n");
			fails++;
			if (fails > 10) break;
			// resynchronise for the next test
			dut_vram = ref_vram;
		}
	}
	printf("%d tests, %d failures; %ld entries changed; %d blits slower than MAME's completion time; clocks %llu vs MAME %llu\n",
	       tests, fails, changed, slow, (unsigned long long)total_clk, (unsigned long long)total_mame);
	delete top;
	return fails ? 1 : 0;
}
