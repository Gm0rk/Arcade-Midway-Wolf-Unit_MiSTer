// ============================================================================
//  tb_vram.cpp - rtl/wunit_vram.sv against the DDRAM port's Avalon rules,
//  through resets
//
//  A model of the DDR3 port (Avalon-MM slave: random waitrequest, read
//  latency and gaps between read beats), the four clients making random
//  requests (display rows, shift-register loads / stores, blitter rows, CPU
//  reads / writes; in reset each sets its request to its acknowledge, as the
//  board's do) and random resets of 1-400 clocks, many in the middle of a
//  burst. Checked:
//    - a command waiting on waitrequest stays as it is (read, a write's
//      first beat)
//    - a write burst gets all its beats, back to back, before anything
//      else; no read while one is open; never read and write at once
//    - every read beat the port returns is taken
//    - a display row, a CPU read, a blitter row, a CPU write (with no reset
//      during it) move the right data to / from the right place
//    - no client waits forever outside reset
//
//  Usage: tb_vram [clocks] [one reset in about this many clocks]
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
// ============================================================================

#include "Vwunit_vram.h"
#include "Vwunit_vram___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <deque>
#include <map>
#include <vector>

static Vwunit_vram *t;
static uint64_t cyc = 0;
static int fails = 0;
#define FAIL(...) do { if (fails++ < 20) { printf("FAIL @%llu: ", (unsigned long long)cyc); printf(__VA_ARGS__); printf("\n"); } } while (0)

static std::map<uint32_t, uint64_t> mem;
static uint64_t rd(uint32_t a) { auto it = mem.find(a); return it == mem.end() ? (0x1111111111111111ull * (a & 15)) ^ a : it->second; }

static uint32_t rnd() { static uint64_t s = 88172645463325252ull; s ^= s << 13; s ^= s >> 7; s ^= s << 17; return (uint32_t)s; }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	long ncyc = argc > 1 ? atol(argv[1]) : 2000000;
	int reset_rate = argc > 2 ? atoi(argv[2]) : 3000;     // one reset in about this many clocks
	t = new Vwunit_vram;
	auto *r = t->rootp;

	// slave state
	bool wr_open = false; int wr_left = 0, wr_n = 0; uint32_t wr_addr = 0;
	std::deque<std::pair<uint32_t, int>> rq;     // read bursts accepted: (address, beats)
	int rq_done = 0;                             // beats of the head already returned
	int rd_latency = 0;
	uint32_t lastb_addr = 0; std::vector<uint64_t> lastb(256); int lastb_n = 0;
	int want_row = 0; uint32_t want_q = 0; int want_half = 0;
	bool prev_cmd_wait = false; int prev_rd = 0, prev_we = 0; uint32_t prev_addr = 0; int prev_bc = 0;

	// clients
	uint8_t blt_row[128][8];
	for (int i = 0; i < 128; i++) for (int j = 0; j < 8; j++) blt_row[i][j] = rnd();
	int blt_raddr_q = 0;
	uint64_t req_since[4] = {0, 0, 0, 0};
	bool tainted[4] = {false, false, false, false};  // a reset came during the operation
	uint64_t lb[128]; int lb_n = 0;
	bool cpu_rd_pending = false;
	int blt_r = 0, blt_l = 0, blt_h = 0, blt_b = 0;     // the blitter row being written
	uint32_t cpu_w = 0; int cpu_b = 0;
	int reset_left = 0;
	long n_ops[4] = {0, 0, 0, 0}, n_checked[4] = {0, 0, 0, 0}, n_resets = 0, n_reset_mid = 0;

	t->clk = 0; t->reset = 1; t->ddr_busy = 0; t->ddr_dout_ready = 0;
	t->disp_req = 0; t->srt_req = 0; t->blt_req = 0; t->cpu_req = 0;
	for (int i = 0; i < 4; i++) { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }
	t->disp_req = t->disp_ack; t->srt_req = t->srt_ack; t->blt_req = t->blt_ack; t->cpu_req = t->cpu_ack;
	reset_left = 2;

	for (cyc = 0; cyc < (uint64_t)ncyc; cyc++) {
		// ---- inputs for this clock
		if (reset_left == 0 && (rnd() % reset_rate) == 0) {
			reset_left = 1 + (rnd() % 400);
			n_resets++;
			if (r->wunit_vram__DOT__vstate != 0) n_reset_mid++;
			for (int i = 0; i < 4; i++) tainted[i] = true;
		}
		t->reset = reset_left > 0;
		t->ddr_busy = (rnd() % 4) == 0;
		t->blt_q = 0; for (int j = 0; j < 8; j++) t->blt_q |= (uint64_t)blt_row[blt_raddr_q][j] << (8 * j);
		// a read beat back?
		bool beat = false;
		if (!rq.empty()) {
			if (rd_latency > 0) rd_latency--;
			else if (rnd() % 3) beat = true;
		}
		t->ddr_dout_ready = beat;
		if (beat) t->ddr_dout = rd(rq.front().first + rq_done);
		t->eval();

		// ---- the master's outputs, checked
		int rdc = t->ddr_rd, wec = t->ddr_we;
		uint32_t addr = t->ddr_addr; int bc = t->ddr_burstcnt;
		if (prev_cmd_wait) {
			// a command not yet taken must stay as it was
			if (prev_rd && !(rdc && addr == prev_addr && bc == prev_bc)) FAIL("read dropped or changed while waitrequest");
			if (prev_we && !wr_open && !(wec && addr == prev_addr && bc == prev_bc)) FAIL("write dropped or changed while waitrequest");
		}
		if (wr_open && !wec) FAIL("write burst gap or cut short: %d of %d beats", wr_n - wr_left, wr_n);
		if (wr_open && rdc) FAIL("read during a write burst");
		if (rdc && wec) FAIL("read and write at once");
		if (beat && r->wunit_vram__DOT__vstate != 2) FAIL("read beat not taken (state %d)", r->wunit_vram__DOT__vstate);
		if (rdc && !rq.empty()) FAIL("new read before the last one's beats are in");

		bool busy = t->ddr_busy;
		if (rdc && !busy) {
			rq.push_back({addr, bc});
			if (rq.size() == 1) { rq_done = 0; rd_latency = 2 + rnd() % 20; }
		}
		if (wec && !busy) {
			if (!wr_open) { wr_open = true; wr_n = wr_left = bc; wr_addr = addr; }
			// the beat: byte enables
			uint64_t m = rd(wr_addr + (wr_n - wr_left)), d = t->ddr_din;
			for (int j = 0; j < 8; j++) if (t->ddr_be >> j & 1) m = (m & ~(0xFFull << (8 * j))) | (d & (0xFFull << (8 * j)));
			mem[wr_addr + (wr_n - wr_left)] = m;
			if (--wr_left == 0) wr_open = false;
		}
		if (beat) {
			if (rq_done == 0) { lastb_addr = rq.front().first; lastb_n = 0; }
			lastb[lastb_n++ & 255] = t->ddr_dout;
			if (++rq_done == rq.front().second) { rq.pop_front(); rq_done = 0; rd_latency = 2 + rnd() % 20; }
		}
		prev_cmd_wait = busy && (rdc || wec);
		prev_rd = rdc; prev_we = wec; prev_addr = addr; prev_bc = bc;

		// display row capture
		if (t->lb_we) { lb[t->lb_addr] = t->lb_data; lb_n++; }

		// ---- the clock
		int ack0[4] = {t->disp_ack, t->srt_ack, t->blt_ack, t->cpu_ack};
		blt_raddr_q = t->blt_raddr;
		t->clk = 1; t->eval();
		t->clk = 0; t->eval();
		int ack1[4] = {t->disp_ack, t->srt_ack, t->blt_ack, t->cpu_ack};
		if (reset_left > 0) reset_left--;

		// ---- completions
		if (ack1[0] != ack0[0] && !tainted[0]) {
			n_checked[0]++;
			if (lb_n != 128) FAIL("display row: %d beats into the line buffer", lb_n);
			if (lastb_addr != 0x06000000u + want_row * 128 || lastb_n != 128) FAIL("display row read %08X x %d", lastb_addr, lastb_n);
			for (int i = 0; i < 128; i++) if (lb[i] != lastb[i]) { FAIL("display row data, beat %d", i); break; }
		}
		if (ack1[2] != ack0[2] && !tainted[2]) {
			n_checked[2]++;
			for (int i = blt_l; i <= blt_h; i++) {
				uint64_t m = rd(0x06000000 + blt_r * 128 + i);
				bool ok = true;
				for (int j = 0; j < 8; j++) if ((blt_b >> j & 1) && ((m >> (8 * j)) & 0xFF) != blt_row[i][j]) ok = false;
				if (!ok) { FAIL("blitter row %d beat %d", blt_r, i); break; }
			}
		}
		if (ack1[3] != ack0[3] && !cpu_rd_pending && !tainted[3]) {
			n_checked[3]++;
			uint32_t m = (uint32_t)(rd(0x06000000 + want_q) >> (want_half ? 32 : 0));
			for (int j = 0; j < 4; j++)
				if ((cpu_b >> j & 1) && ((m >> (8 * j)) & 0xFF) != ((cpu_w >> (8 * j)) & 0xFF)) { FAIL("CPU write byte %d", j); break; }
		}
		if (ack1[3] != ack0[3] && cpu_rd_pending && !tainted[3]) {
			n_checked[3]++;
			uint32_t e = (uint32_t)(lastb[0] >> (want_half ? 32 : 0));
			if (lastb_addr != 0x06000000u + want_q || lastb_n != 1) FAIL("CPU read address %08X x %d", lastb_addr, lastb_n);
			if (t->cpu_rdata != e) FAIL("CPU read %08X, returned %08X", t->cpu_rdata, e);
		}

		// ---- clients: in reset each sets its request to its acknowledge
		bool rs = t->reset;
		int reqs[4] = {t->disp_req, t->srt_req, t->blt_req, t->cpu_req};
		int acks[4] = {t->disp_ack, t->srt_ack, t->blt_ack, t->cpu_ack};
		for (int i = 0; i < 4; i++) {
			if (rs) { reqs[i] = acks[i]; continue; }
			if (reqs[i] != acks[i]) {
				if (cyc - req_since[i] > 20000) { FAIL("client %d waits forever", i); req_since[i] = cyc; }
				continue;
			}
			if (rnd() % (i == 0 ? 300 : i == 1 ? 3000 : i == 2 ? 200 : 100)) continue;
			// a new request
			reqs[i] ^= 1; req_since[i] = cyc; tainted[i] = false; n_ops[i]++;
			if (i == 0) {
				int row = rnd() % 512;
				t->disp_row = row; lb_n = 0; want_row = row;
			} else if (i == 1) {
				t->srt_wr = rnd() & 1; t->srt_entry = rnd() & 0x7FFFC;
			} else if (i == 2) {
				int lo = rnd() % 128, hi = lo + rnd() % (128 - lo);
				t->blt_row = blt_r = rnd() % 512; t->blt_lo = blt_l = lo; t->blt_hi = blt_h = hi; t->blt_be = blt_b = (rnd() | 1) & 0xFF;
				for (int a = 0; a < 128; a++) for (int j = 0; j < 8; j++) blt_row[a][j] = rnd();
			} else {
				bool w = rnd() & 1;
				uint32_t q = rnd() & 0x1FFFF; int half = rnd() & 1;
				t->cpu_wr = w; t->cpu_qaddr = q; t->cpu_half = half; t->cpu_be = cpu_b = rnd() & 15; t->cpu_wdata = cpu_w = rnd();
				cpu_rd_pending = !w; want_q = q; want_half = half;
			}
		}
		t->disp_req = reqs[0]; t->srt_req = reqs[1]; t->blt_req = reqs[2]; t->cpu_req = reqs[3];
	}
	printf("%llu clocks, %ld resets (%ld during an operation); requests: display %ld, shift register %ld, "
	       "blitter %ld, CPU %ld; checked: display %ld, blitter %ld, CPU %ld; %s\n",
	       (unsigned long long)cyc, n_resets, n_reset_mid, n_ops[0], n_ops[1], n_ops[2], n_ops[3],
	       n_checked[0], n_checked[2], n_checked[3], fails ? "FAIL" : "OK");
	delete t;
	return fails ? 1 : 0;
}
