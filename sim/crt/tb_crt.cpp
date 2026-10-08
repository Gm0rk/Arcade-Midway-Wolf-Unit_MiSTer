// ============================================================================
//  tb_crt.cpp - the analog CRT stage (rtl/video/wunit_crt.sv) on its own
//
//  Feeds wunit_crt the Wolf Unit raster (MAME's set_raw(8000000, 506, 101,
//  501, 289, 20, 274): 506 dots a line, 289 lines, the picture dots 101-500
//  of lines 20-273) on a 96 MHz clock with the 8 MHz dot enable, and a
//  test picture that says where every dot came from:
//      R = picture line (0-253), G = 0x50 | column bit 8, B = column bits 7-0
//  It watches what goes out (sync, and the picture dots: CE_PIXEL samples
//  while the picture area is open) and prints, per output frame:
//      F frame clocks lines vs_lines pic_lines line_min line_max
//  and at the end a summary of the last frames, checked against what the
//  settings should give:
//    - V-Size 0: the frame as the board sends it (-log writes every line's
//      dots, for comparing with another build of the stage)
//    - PVM: 289 - 3n lines a frame in the board's frame time, every picture
//      line once and in order, whole lines
//    - Cabinet: the board's line period and line count, the picture on
//      254 + 3n lines, the line numbers in R rising through 0..253, columns
//      untouched
//
//  Usage: Vwunit_crt [-off] [-vsize n] [-cabinet] [-autow] [-hsize n]
//                    [-hpos n] [-vshift n] [-frames n] [-log file]
//    -off        CRT Adjust off (the module's pass-through path)
//    -vsize n    V-Size step, -7..+7 (+ taller)
//    -cabinet    V-Size Cabinet mode (default PVM)
//    -frames n   frames to run (default 30)
//    -change f n V-Size n from board frame f on (checks use the last setting)
//    -vtot n     board frame length in lines (277, 263: the 57 / 60 Hz Video
//                Timing settings; the checks assume 289)
//    -log file   every output line: frame, line, clocks from VSync, dots,
//                hash of the dots, first and last dot
//  Built with -DNO_VSIZE it drives a stage without the V-Size ports (the
//  build before V-Size), for the -log comparison.
//
//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
// ============================================================================

#include "Vwunit_crt.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <algorithm>

static Vwunit_crt *top;

// board raster (dots, lines)
static const int HTOT = 506, H0 = 101, H1 = 501, HSW = 43;
static int VTOT = 289;                                   // -vtot: 277 / 263 (57 / 60 Hz timings)
static const int V0 = 20, V1 = 274, VSW = 3;

struct Line {
	uint64_t start = 0;          // clock of the HSync rise
	int hs_w = 0;                // HSync width, clocks
	std::vector<uint32_t> dots;  // picture dots (RGB)
};

struct Frame {
	uint64_t start = 0;          // clock of the VSync rise
	int vs_lines = 0;
	std::vector<Line> lines;
};

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	bool off = false, cab = false, autow = false;
	int vsize = 0, hsize = 0, hpos = 0, vshift = 0, frames = 30;
	int change_at = -1, change_to = 0;
	const char *logname = nullptr;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-off")) off = true;
		else if (!strcmp(argv[i], "-cabinet")) cab = true;
		else if (!strcmp(argv[i], "-autow")) autow = true;
		else if (!strcmp(argv[i], "-vsize") && i + 1 < argc) vsize = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-hsize") && i + 1 < argc) hsize = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-hpos") && i + 1 < argc) hpos = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-vshift") && i + 1 < argc) vshift = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-frames") && i + 1 < argc) frames = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-log") && i + 1 < argc) logname = argv[++i];
		else if (!strcmp(argv[i], "-vtot") && i + 1 < argc) VTOT = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-change") && i + 2 < argc) { change_at = atoi(argv[++i]); change_to = atoi(argv[++i]); }
		else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
	}
	FILE *log = logname ? fopen(logname, "w") : nullptr;

	top = new Vwunit_crt;
	top->crt_en = off ? 0 : 1;
	top->autow = autow;
	top->scandoubler = 0;
	top->hsize_osd = hsize & 31;
	top->hpos_osd = hpos >= 0 ? hpos : 97 + hpos;
	top->vshift_osd = vshift & 31;
#ifndef NO_VSIZE
	top->vsize_osd = vsize >= 0 ? vsize : 15 + vsize;   // the OSD's index: -7..-1 = 8..14
	top->vsize_mode = cab;
#endif

	std::vector<Frame> out;
	Frame cur;
	Line *ln = nullptr;
	bool have_frame = false;
	int hs_d = 0, vs_d = 0;
	uint64_t clk = 0;
	int ph = 0, h = 0, v = 0;
	int in_frames = 0;

	while (in_frames < frames) {
		// board side: a dot every 12 clocks; signals change with the dot enable
		bool ce = (ph == 0);
		if (ce) {
			bool act = h >= H0 && h < H1 && v >= V0 && v < V1;
			int col = h - H0, row = v - V0;
			top->hs_in = h < HSW;
			top->vs_in = v < VSW;
			top->hb_in = !(h >= H0 && h < H1);
			top->vb_in = !(v >= V0 && v < V1);
			top->r_in = act ? row & 0xFF : 0;
			top->g_in = act ? 0x50 | ((col >> 8) & 1) : 0;
			top->b_in = act ? col & 0xFF : 0;
		}
		top->ce_pix = ce;
		top->clk = 0; top->eval();
		top->clk = 1; top->eval();
		clk++;

		// output side
		int hs = top->hs_out, vs = top->vs_out;
		if (off) { hs = top->c_hs; vs = top->c_vs; }
		if (vs && !vs_d) {
			if (have_frame) out.push_back(cur);
			cur = Frame();
			cur.start = clk;
			have_frame = true;
			ln = nullptr;
		}
		if (hs && !hs_d && have_frame) {
			cur.lines.push_back(Line());
			ln = &cur.lines.back();
			ln->start = clk;
			if (vs) cur.vs_lines++;
		}
		if (hs && ln) ln->hs_w++;
		if (!off && ln && top->rd_ce && top->str_act)
			ln->dots.push_back((top->r_out << 16) | (top->g_out << 8) | top->b_out);
		hs_d = hs; vs_d = vs;

		if (ce) {
			if (++h == HTOT) { h = 0; if (++v == VTOT) { v = 0; in_frames++; } }
		}
		if (in_frames == change_at) {             // a new V-Size from this board frame on
			vsize = change_to;
#ifndef NO_VSIZE
			top->vsize_osd = vsize >= 0 ? vsize : 15 + vsize;
#endif
			change_at = -1;
		}
		ph = (ph + 1) % 12;
	}
	if (have_frame) out.push_back(cur);       // incomplete: not counted below
	top->final();

	// per frame
	int nf = (int)out.size() - 1;
	for (int f = 0; f < nf; f++) {
		Frame &F = out[f];
		uint64_t len = out[f + 1].start - F.start;
		int pic = 0, lmin = 1 << 30, lmax = 0;
		for (size_t i = 0; i < F.lines.size(); i++) {
			uint64_t end = i + 1 < F.lines.size() ? F.lines[i + 1].start : out[f + 1].start;
			int l = (int)(end - F.lines[i].start);
			if (i + 1 < F.lines.size()) { lmin = std::min(lmin, l); lmax = std::max(lmax, l); }
			if (!F.lines[i].dots.empty()) pic++;
			if (log) {
				uint32_t hsh = 2166136261u;
				for (uint32_t d : F.lines[i].dots) { hsh ^= d; hsh *= 16777619u; }
				Line &L = F.lines[i];
				fprintf(log, "%d %zu %llu %d %zu %08x %06x %06x\n", f, i,
				        (unsigned long long)(L.start - F.start), L.hs_w, L.dots.size(), hsh,
				        L.dots.empty() ? 0 : L.dots.front(), L.dots.empty() ? 0 : L.dots.back());
			}
		}
		printf("F %d %llu %zu %d %d %d %d\n", f, (unsigned long long)len, F.lines.size(),
		       F.vs_lines, pic, lmin, lmax);
	}
	if (log) fclose(log);
	if (off || nf < 4) return 0;

	// checks over the last 3 whole frames
	const int64_t frame_clk = (int64_t)HTOT * VTOT * 12;
	int bad = 0;
	auto fail = [&](const char *what, int f, long a, long b) {
		if (bad++ < 20) printf("FAIL frame %d: %s (%ld, expected %ld)\n", f, what, a, b);
	};
	int want_lines = (vsize == 0 || cab) ? VTOT : VTOT - 3 * vsize;
	int want_pic = cab ? 254 + 3 * vsize : 254;
	for (int f = nf - 3; f < nf; f++) {
		Frame &F = out[f];
		long len = (long)(out[f + 1].start - F.start);
		if (len != frame_clk) fail("frame clocks", f, len, frame_clk);
		if ((int)F.lines.size() != want_lines) fail("lines", f, F.lines.size(), want_lines);
		if (F.vs_lines != VSW) fail("VSync lines", f, F.vs_lines, VSW);
		int prev = -1, pic = 0, lmin = 1 << 30, lmax = 0;
		for (size_t i = 0; i < F.lines.size(); i++) {
			uint64_t end = i + 1 < F.lines.size() ? F.lines[i + 1].start : out[f + 1].start;
			int l = (int)(end - F.lines[i].start);
			lmin = std::min(lmin, l); lmax = std::max(lmax, l);
			std::vector<uint32_t> &D = F.lines[i].dots;
			if (D.empty()) continue;
			pic++;
			// columns: consecutive, the whole picture unless H-Size or Auto-Width change it
			int c0 = ((D.front() >> 8) & 1) << 8 | (D.front() & 0xFF);
			for (size_t k = 1; k < D.size(); k++) {
				int c = ((D[k] >> 8) & 1) << 8 | (D[k] & 0xFF);
				if (c != c0 + (int)k) { fail("column", f, c, c0 + (long)k); break; }
				if (((D[k] >> 16) & 0xFF) != ((D[0] >> 16) & 0xFF)) { fail("line number inside a line", f, (D[k] >> 16) & 0xFF, (D[0] >> 16) & 0xFF); break; }
			}
			if (!hsize && !hpos && !autow && (D.size() != 400 || c0 != 0)) fail("dots in a line", f, D.size(), 400);
			int r = (D[0] >> 16) & 0xFF;
			if (prev < 0 && r > (cab ? 1 : 0)) fail("first picture line", f, r, 0);
			if (!cab) {
				if (r != prev + 1) fail("picture line", f, r, prev + 1);
			} else {
				if (r < prev || r > prev + 2) fail("picture line (rising)", f, r, prev + 1);
			}
			prev = r;
		}
		if (pic != want_pic) fail("picture lines", f, pic, want_pic);
		// Cabinet blends neighbouring lines: the last output line can land
		// just short of line 253 (a mostly-253 blend that rounds to 252)
		if (cab ? prev < 252 : prev != 253) fail("last picture line", f, prev, 253);
		if (cab && (lmin != HTOT * 12 || lmax != HTOT * 12)) fail("line period (Cabinet)", f, lmin, HTOT * 12);
		if (!cab && vsize) {
			long want = frame_clk / want_lines;
			if (lmin < want - 1 || lmax > want + 1) fail("line period (PVM)", f, lmin, want);
		}
	}
	printf(bad ? "%d checks failed\n" : "checks: OK\n", bad);
	return bad ? 1 : 0;
}
