-- ref_trace.lua - reference run of a Wolf Unit set in MAME 0.289
--
-- Writes, for comparison with the core in simulation:
--   <out>/<set>/frame_NNNNN.rgb   screen pixels (MAME's visible area, 32-bit
--                                 xRGB little endian) at the frames in WU_FRAMES
--   <out>/<set>/trace.log         34010 CRT controller writes, sound latch
--                                 traffic, the first WU_BLITS blitter starts
--                                 with their registers, frame by frame
--
-- Environment:
--   WU_SET     set name (also the output folder)
--   WU_OUT     output root (default "ref")
--   WU_FRAMES  comma list of frames to dump
--   WU_EXIT    frame to exit at (default: last of WU_FRAMES + 1)
--   WU_BLITS   blits to log (default 200)
--   WU_PRESS   "frame:port:mask:frames,..." - hold input bits (active low
--              ports, mask in hex) from that frame for that many frames
--
-- Run: wtunit <set> -video none -sound none -nothrottle -autoboot_script ref_trace.lua
--
-- Tap handles are kept in globals: Lua frees an unreferenced handle and the
-- tap goes with it.

local set    = os.getenv("WU_SET")
local out    = (os.getenv("WU_OUT") or "ref") .. "/" .. set
local frames = {}
local last   = 0
for f in (os.getenv("WU_FRAMES") or ""):gmatch("%d+") do
	frames[tonumber(f)] = true
	if tonumber(f) > last then last = tonumber(f) end
end
local exit_at   = tonumber(os.getenv("WU_EXIT") or (last + 1))
local max_blits = tonumber(os.getenv("WU_BLITS") or "200")

local presses = {}
for fr, port, mask, len in (os.getenv("WU_PRESS") or ""):gmatch("(%d+):([%w_]+):(%x+):(%d+)") do
	presses[#presses + 1] = { frame = tonumber(fr), port = port, mask = tonumber(mask, 16), len = tonumber(len) }
end

os.execute("mkdir -p " .. out)
local log = assert(io.open(out .. "/trace.log", "w"))

local machine = manager.machine
local cpu     = machine.devices[":maincpu"]
local space   = cpu.spaces["program"]
local screen  = machine.screens[":screen"]

-- the stamp of a logged event: the frame it fell in and the emulated time
-- in microseconds (MAME's Lua has no beam position)
local frame = 0
local function stamp()
	return string.format("f%05d t%012.3f", frame, machine.time:as_double() * 1e6)
end

-- 34010 I/O register names (bit address 0xC0000000 + 16 * index)
local ioname = { [0]="HESYNC","HEBLNK","HSBLNK","HTOTAL","VESYNC","VEBLNK","VSBLNK","VTOTAL",
	"DPYCTL","DPYSTRT","DPYINT","CONTROL","HSTDATA","HSTADRL","HSTADRH","HSTCTLL",
	"HSTCTLH","INTENB","INTPEND","CONVSP","CONVDP","PSIZE","PMASK","R23","R24","R25",
	"R26","DPYTAP","HCOUNT","VCOUNT","DPYADR","REFCNT" }

tap_io = space:install_write_tap(0xc0000000, 0xc00001ff, "crtc", function(offset, data, mask)
	local idx = (offset - 0xc0000000) // 16
	if idx <= 11 or idx == 27 then
		log:write(string.format("%s io %-8s %04x\n", stamp(), ioname[idx], data))
	end
end)

tap_snd_w = space:install_write_tap(0x01680000, 0x0168001f, "snd_w", function(offset, data, mask)
	log:write(string.format("%s snd_w %04x\n", stamp(), data))
end)

tap_snd_r = space:install_read_tap(0x01680000, 0x0168001f, "snd_r", function(offset, data, mask)
	log:write(string.format("%s snd_r %04x\n", stamp(), data))
end)

-- I/O word 4 (status, at 4 or 12 of the 16-word window before any WWF
-- reordering) reads, logged when the value changes
local last_status = -1
tap_io_r = space:install_read_tap(0x01800000, 0x0187ffff, "io_r", function(offset, data, mask)
	local w = ((offset - 0x01800000) // 16) % 16
	if w % 8 == 4 and data ~= last_status then
		log:write(string.format("%s status %x %04x\n", stamp(), w, data))
		last_status = data
	end
end)

-- I/O writes, except the watchdog (word 3, mirrored at 11)
tap_io_w = space:install_write_tap(0x01800000, 0x0187ffff, "io_w", function(offset, data, mask)
	local w = ((offset - 0x01800000) // 16) % 16
	if w % 8 ~= 3 then
		log:write(string.format("%s io_w %x %04x\n", stamp(), w, data))
	end
end)

-- blitter: keep the register file, log each start
local dma = {}
for i = 0, 15 do dma[i] = 0 end
local blits = 0
tap_dma = space:install_write_tap(0x01a00000, 0x01a000ff, "dma", function(offset, data, mask)
	local i = ((offset - 0x01a00000) // 16) % 16
	dma[i] = data
	if i == 1 and (data & 0x8000) ~= 0 and blits < max_blits then
		blits = blits + 1
		local t = {}
		for k = 0, 15 do t[#t + 1] = string.format("%04x", dma[k]) end
		log:write(string.format("%s blit %s\n", stamp(), table.concat(t, " ")))
	end
end)

tap_ctrl = space:install_write_tap(0x01b00000, 0x01b0001f, "ctrl", function(offset, data, mask)
	log:write(string.format("%s ctrl %04x\n", stamp(), data))
end)

-- held input bits: pressed through the port's field values
local held = {}
local function apply_presses()
	for _, p in ipairs(presses) do
		if frame == p.frame then
			for _, field in pairs(machine.ioport.ports[":" .. p.port].fields) do
				if (field.mask & p.mask) ~= 0 then
					field:set_value(1)
					held[#held + 1] = { field = field, until_frame = frame + p.len }
				end
			end
		end
	end
	for i = #held, 1, -1 do
		if frame >= held[i].until_frame then
			held[i].field:set_value(0)
			table.remove(held, i)
		end
	end
end

frame_sub = emu.add_machine_frame_notifier(function()
	frame = frame + 1
	apply_presses()
	if frames[frame] then
		local pixels, w, h = screen:pixels()
		local f = assert(io.open(string.format("%s/frame_%05d.rgb", out, frame), "wb"))
		f:write(pixels)
		f:close()
		log:write(string.format("f%05d frame dumped %dx%d\n", frame, w, h))
	end
	if frame >= exit_at then
		log:close()
		machine:exit()
	end
end)
