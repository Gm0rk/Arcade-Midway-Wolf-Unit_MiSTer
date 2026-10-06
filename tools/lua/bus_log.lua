-- bus_log.lua - CPU writes to the palette, blitter registers, sound latch
-- and the UMK3 palette ring in MAME 0.289, frame by frame, in the format of
-- the board simulation's -buslog (sim/board/tb_board.cpp), so the two can be
-- diffed when a picture goes wrong in one of them.
--
-- Environment:
--   WU_SET    set name;  WU_OUT  output file
--   WU_FROM / WU_TO     frames to log (the run exits after WU_TO)
--   WU_PRESS            as in ref_trace.lua
--
-- Each line: frame, microseconds since the frame notifier, PC, then the write.
--
-- Run: wtunit <set> -video none -sound none -nothrottle -autoboot_script bus_log.lua
-- (tap handles are kept in globals so Lua does not free them)

local from    = tonumber(os.getenv("WU_FROM") or "0")
local to      = tonumber(os.getenv("WU_TO") or "0")
local log     = assert(io.open(os.getenv("WU_OUT"), "w"))
local machine = manager.machine
local space   = machine.devices[":maincpu"].spaces["program"]

local presses = {}
for fr, port, mask, len in (os.getenv("WU_PRESS") or ""):gmatch("(%d+):([%w_]+):(%x+):(%d+)") do
	presses[#presses + 1] = { frame = tonumber(fr), port = port, mask = tonumber(mask, 16), len = tonumber(len) }
end

local frame = 0
local frame_t = 0                        -- emulated time of the last frame start
local cpu = machine.devices[":maincpu"]
local function on() return frame >= from and frame <= to end
-- the stamp: frame, microseconds since the frame started, the 34010's PC
local function st()
	return string.format("f%05d %8.2f %08x", frame, (machine.time:as_double() - frame_t) * 1e6, cpu.state["PC"].value)
end

-- offsets are bit addresses; the simulator logs word addresses
tap_pal = space:install_write_tap(0x01880000, 0x018fffff, "pal", function(offset, data, mask)
	if on() then log:write(string.format("%s pal %04x %04x\n", st(), (offset - 0x01880000) >> 4, data)) end
end)
tap_dma = space:install_write_tap(0x01a00000, 0x01a000ff, "dma", function(offset, data, mask)
	if on() then log:write(string.format("%s dma %x %04x\n", st(), ((offset - 0x01a00000) >> 4) & 15, data)) end
end)
tap_dma2 = space:install_write_tap(0x01a80000, 0x01a800ff, "dma2", function(offset, data, mask)
	if on() then log:write(string.format("%s dma %x %04x\n", st(), ((offset - 0x01a80000) >> 4) & 15, data)) end
end)
tap_ring = space:install_write_tap(0x0106a060, 0x0106a09f, "ring", function(offset, data, mask)
	if on() then log:write(string.format("%s ring %x %04x\n", st(), (offset - 0x0106a060) >> 4, data)) end
end)
tap_snd = space:install_write_tap(0x01680000, 0x0168001f, "snd", function(offset, data, mask)
	if on() then log:write(string.format("%s snd %04x\n", st(), data)) end
end)

local held = {}
frame_sub = emu.add_machine_frame_notifier(function()
	frame = frame + 1
	frame_t = machine.time:as_double()
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
	if frame > to then
		log:close()
		machine:exit()
	end
end)
