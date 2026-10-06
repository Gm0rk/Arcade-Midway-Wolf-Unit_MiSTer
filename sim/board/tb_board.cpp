// tb_board.cpp - full Wolf Unit board simulation (Verilator)
//
// Runs sim_top (board, sound placeholder, SDRAM controller) with:
//   - an SDRAM chip model on the controller's pins (CAS latency 3, bursts of
//     4 reads, single-word writes with DQM byte masks), loaded with the ROM
//     image tools/wunit_roms.py builds; main RAM (the top 512 KB) starts at 0
//   - a DDR3 bridge model on the Avalon port (fixed read latency, one beat a
//     clock, byte enables)
//   - video capture: the active picture of every frame, written as 32-bit
//     xRGB like MAME's screen:pixels() (tools/lua/ref_trace.lua) so the two
//     compare byte for byte
//
// Usage:
//   tb_board <rom dir> <set> <out dir> <frames to dump, comma list> [options]
//     -exit N         stop after frame N (default: the last dumped frame)
//     -press F:P:M:L  hold port P (in0/in1/in2) bits M (hex) from frame F for
//                     L frames (like WU_PRESS in ref_trace.lua)
//     -dsw HEX        DIP switches instead of the set's default
//     -pctrace FILE   write every retired instruction's PC
//
// Frame numbers count the board's vertical blanks from reset; the first
// complete picture is frame 1.

#include "Vsim_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <set>
#include <string>
#include <vector>

static Vsim_top *top;
static uint64_t cyc = 0;

// ---------------------------------------------------------------- SDRAM ----
static std::vector<uint16_t> sdram(16 * 1024 * 1024);      // 32 MB
static int sd_row[4];
static std::map<uint64_t, uint16_t> sd_sched;              // cycle -> DQ value

static void sdram_after_edge()
{
	int cmd = (top->SDRAM_nRAS << 2) | (top->SDRAM_nCAS << 1) | top->SDRAM_nWE;
	int ba = top->SDRAM_BA;
	int a = top->SDRAM_A;
	if (!top->SDRAM_nCS) {
		if (cmd == 3) sd_row[ba] = a;                         // ACTIVE
		else if (cmd == 5) {                                  // READ, burst of 4
			uint32_t base = ((uint32_t)ba << 22) | ((uint32_t)sd_row[ba] << 9) | (a & 0x1FF);
			for (int k = 0; k < 4; k++)
				sd_sched[cyc + 3 + k] = sdram[(base & ~3u) | ((base + k) & 3)];
		}
		else if (cmd == 4) {                                  // WRITE, one word
			uint32_t w = ((uint32_t)ba << 22) | ((uint32_t)sd_row[ba] << 9) | (a & 0x1FF);
			uint16_t d = top->SDRAM_DQ_O;
			uint16_t &m = sdram[w];
			if (!top->SDRAM_DQML) m = (m & 0xFF00) | (d & 0x00FF);
			if (!top->SDRAM_DQMH) m = (m & 0x00FF) | (d & 0xFF00);
		}
	}
	auto it = sd_sched.find(cyc);
	if (it != sd_sched.end()) {
		top->SDRAM_DQ_I = it->second;
		sd_sched.erase(it);
	}
}

// ----------------------------------------------------------------- DDR3 ----
static const uint32_t DDR_BASE = 0x06000000;               // beat address of the frame store
static std::vector<uint64_t> ddr(0x20000);                  // 1 MB
static int ddr_wr_left = 0;
static uint32_t ddr_wr_addr = 0;
struct DdrRead { uint64_t at; uint32_t addr; int left; };
static std::deque<DdrRead> ddr_rq;
static const int DDR_LATENCY = 18;

static uint64_t &ddr_at(uint32_t beat)
{
	static uint64_t dummy;
	uint32_t i = beat - DDR_BASE;
	if (i >= ddr.size()) { dummy = 0; return dummy; }
	return ddr[i];
}

static void ddr_before_edge()
{
	top->ddr_busy = 0;
	if (top->ddr_we) {
		if (ddr_wr_left == 0) {
			ddr_wr_addr = top->ddr_addr;
			ddr_wr_left = top->ddr_burstcnt;
		}
		uint64_t &m = ddr_at(ddr_wr_addr);
		uint64_t d = top->ddr_din;
		for (int b = 0; b < 8; b++)
			if ((top->ddr_be >> b) & 1)
				m = (m & ~(0xFFull << (8 * b))) | (d & (0xFFull << (8 * b)));
		ddr_wr_addr++;
		ddr_wr_left--;
	}
	if (top->ddr_rd)
		ddr_rq.push_back({cyc + DDR_LATENCY, (uint32_t)top->ddr_addr, (int)top->ddr_burstcnt});

	top->ddr_dout_ready = 0;
	if (!ddr_rq.empty() && ddr_rq.front().at <= cyc) {
		DdrRead &r = ddr_rq.front();
		top->ddr_dout = ddr_at(r.addr);
		top->ddr_dout_ready = 1;
		r.addr++;
		if (--r.left == 0) ddr_rq.pop_front();
	}
}

static void apply_inputs();

// ---------------------------------------------------------------- video ----
static std::vector<uint32_t> frame_px, line_px;
static bool prev_hb = true, prev_vb = true;
static int frame_no = 0;
static std::set<int> dump_frames;
static std::string out_dir, set_name;

static void video_sample()
{
	bool hb = top->vid_hb, vb = top->vid_vb;
	if (!hb && !vb)
		line_px.push_back(0xFF000000u | (top->vid_r << 16) | (top->vid_g << 8) | top->vid_b);
	if (hb && !prev_hb && !line_px.empty()) {
		frame_px.insert(frame_px.end(), line_px.begin(), line_px.end());
		static size_t width = 0;
		if (width && line_px.size() != width)
			fprintf(stderr, "frame %d: line of %zu pixels (expected %zu)\n", frame_no + 1, line_px.size(), width);
		width = line_px.size();
		line_px.clear();
	}
	if (vb && !prev_vb) {
		frame_no++;
		apply_inputs();          // at the start of vertical blank, as MAME's frame notifier
		if (dump_frames.count(frame_no)) {
			char name[512];
			snprintf(name, sizeof name, "%s/frame_%05d.rgb", out_dir.c_str(), frame_no);
			FILE *f = fopen(name, "wb");
			fwrite(frame_px.data(), 4, frame_px.size(), f);
			fclose(f);
			fprintf(stderr, "frame %d dumped (%zu pixels) at cycle %llu\n", frame_no, frame_px.size(),
			        (unsigned long long)cyc);
		}
		frame_px.clear();
	}
	prev_hb = hb;
	prev_vb = vb;
}

// --------------------------------------------------------------- inputs ----
struct Press { int frame, port; uint16_t mask; int len; };
static std::vector<Press> presses;

static void apply_inputs()
{
	uint16_t in[3] = {0xFFFF, 0xFFFF, 0xFFFF};
	for (auto &p : presses)
		if (frame_no >= p.frame && frame_no < p.frame + p.len)
			in[p.port] &= ~p.mask;
	top->in0 = in[0];
	top->in1 = in[1];
	top->in2 = in[2];
}

// ----------------------------------------------------------------- main ----
int main(int argc, char **argv)
{
	if (argc < 5) {
		fprintf(stderr, "usage: tb_board <rom dir> <set> <out dir> <frames> [options]\n");
		return 1;
	}
	std::string romdir = argv[1];
	set_name = argv[2];
	out_dir = argv[3];
	int last = 0;
	for (char *t = strtok(argv[4], ","); t; t = strtok(nullptr, ",")) {
		dump_frames.insert(atoi(t));
		last = std::max(last, atoi(t));
	}
	int exit_at = last;
	FILE *pct = nullptr;
	int dsw_override = -1;
	for (int i = 5; i < argc; i++) {
		if (!strcmp(argv[i], "-exit")) exit_at = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-dsw")) dsw_override = strtol(argv[++i], nullptr, 16);
		else if (!strcmp(argv[i], "-pctrace")) pct = fopen(argv[++i], "w");
		else if (!strcmp(argv[i], "-press")) {
			Press p; char port[8];
			sscanf(argv[++i], "%d:%7[^:]:%hx:%d", &p.frame, port, &p.mask, &p.len);
			p.port = port[2] - '0';
			presses.push_back(p);
		}
	}
	Verilated::commandArgs(argc, argv);
	top = new Vsim_top;

	// ROM image and configuration
	std::string base = romdir + "/" + set_name;
	FILE *f = fopen((base + ".rom").c_str(), "rb");
	if (!f) { perror("rom"); return 1; }
	std::vector<uint8_t> img;
	uint8_t buf[65536];
	size_t n;
	while ((n = fread(buf, 1, sizeof buf, f)) > 0) img.insert(img.end(), buf, buf + n);
	fclose(f);
	for (size_t i = 0; i + 1 < img.size(); i += 2) sdram[i / 2] = img[i] | (img[i + 1] << 8);

	std::map<std::string, std::string> cfg;
	f = fopen((base + ".cfg").c_str(), "r");
	char line[256];
	while (fgets(line, sizeof line, f)) {
		char k[64], v[192];
		if (sscanf(line, "%63s %191[^\n]", k, v) == 2) cfg[k] = v;
	}
	fclose(f);
	uint64_t slots = 0;
	{
		unsigned s[8];
		sscanf(cfg["slots"].c_str(), "%x %x %x %x %x %x %x %x", &s[0], &s[1], &s[2], &s[3], &s[4], &s[5], &s[6], &s[7]);
		for (int i = 0; i < 8; i++) slots |= (uint64_t)s[i] << (8 * i);
	}
	int game = atoi(cfg["game"].c_str());
	static const int dcs_ver[6] = {0x01, 0x02, 0x01, 0x12, 0x01, 0x01};
	static const int dcs_dly[6] = {584560, 587480, 33690, 584090, 27600, 586860};
	top->gfx_slots = slots;
	top->year = atoi(cfg["year"].c_str());
	top->io_remap = atoi(cfg["io_remap"].c_str());
	top->dcs_version = dcs_ver[game];
	top->dcs_delay = dcs_dly[game];
	top->dsw = dsw_override >= 0 ? dsw_override : strtol(cfg["dsw"].c_str(), nullptr, 16);
	apply_inputs();

	// reset: the SDRAM controller initialises first
	top->reset = 1;
	top->sdram_init = 1;
	top->clk = 0;
	top->eval();
	for (int i = 0; i < 20000; i++) {
		if (i == 100) top->sdram_init = 0;
		ddr_before_edge();
		top->clk = 1; top->eval();
		sdram_after_edge();
		top->clk = 0; top->eval();
		cyc++;
	}
	top->reset = 0;

	while (frame_no < exit_at) {
		ddr_before_edge();
		bool ce = top->ce_pix;
		top->clk = 1; top->eval();
		sdram_after_edge();
		if (ce) video_sample();
		if (pct && top->dbg_retire) fprintf(pct, "%08x\n", top->dbg_pc);
		top->clk = 0; top->eval();
		cyc++;
	}
	if (pct) fclose(pct);
	delete top;
	return 0;
}
