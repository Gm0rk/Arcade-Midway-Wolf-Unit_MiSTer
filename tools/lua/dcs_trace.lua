-- dcs_trace.lua - the DCS sound board in MAME 0.289, for sim/dcs
--
-- Writes (each optional, by environment):
--   DCS_TRACE  the sound DSP's trace from power-on: per instruction the
--              registers before it, then "PC: disassembly". Fields (hex):
--              AX0 AX1 AY0 AY1 AR AF MX0 MX1 MY0 MY1 MR0 MR1 MR2 MF SI SE SB
--              SR0 SR1 I0-I7 CNTR ASTAT MSTAT IMASK PX IRQ2 LATCH (the input
--              latch's IRQ line and data). Before frame DCS_FULL only IRQ2
--              and LATCH are given (the others "*"), which runs about five
--              times faster. Ends with a line "END". Can be a pipe
--              (sim/dcs/run_ref.sh filters it on the way): set DCS_PIPE then.
--   DCS_HOST   the host's side, one line each, time in microseconds:
--                t W xx     write to the sound data latch
--                t C xxxx   write to the I/O control word (bit 4: sound
--                           CPU held in reset)
--   DCS_DAC    the words MAME's DCS takes from the DAC buffer, as
--              "t address word" (MAME moves half a buffer at a time, so they
--              come in runs with the same time; reads by the DSP itself are
--              in the log too, one at a time). DCS_DAC_AT: the buffer's
--              ranges, comma list, default 0c00-0ddf
--   DCS_END    frame to exit at (default 60)
--   WU_PRESS   "frame:port:mask:frames,..." held input bits, as
--              ref_trace.lua
--
-- Run: wtunit <set> -debug -debugger none -video none -sound none
--      -nothrottle -autoboot_script dcs_trace.lua
--
-- The debugger's register symbols and tracelog work on its visible CPU,
-- which only a stop changes, so a breakpoint on the DSP's first
-- instruction (no action to go on: the null debugger resumes by itself)
-- starts the trace. It hits again at each DSP reset and reopens the trace
-- for appending; the first instruction after power-on is not in it.

local machine = manager.machine
local dbg     = machine.debugger
local dcs     = machine.devices[":dcs:dcs"]
local main    = machine.devices[":maincpu"].spaces["program"]
local endf    = tonumber(os.getenv("DCS_END") or "60")
local fullf   = tonumber(os.getenv("DCS_FULL") or "0")
local trace   = os.getenv("DCS_TRACE")
local pipe    = os.getenv("DCS_PIPE")       -- DCS_TRACE is a pipe: no appending (no seeks)

local FULL = "AX0,AX1,AY0,AY1,AR,AF,MX0,MX1,MY0,MY1,MR0,MR1,MR2&0xff,MF,SI,SE&0xff,SB&0x1f,SR0,SR1," ..
             "I0,I1,I2,I3,I4,I5,I6,I7,CNTR,ASTAT,MSTAT,IMASK,PX,IRQ2,dw@3400"
local function trace_cmd(full)
	if full then
		return "trace " .. (pipe and "" or ">>") .. trace .. ",:dcs:dcs,noloop,{tracelog \"" .. string.rep("%X ", 34) .. "\"," .. FULL .. "}"
	end
	return "trace " .. (pipe and "" or ">>") .. trace .. ",:dcs:dcs,noloop,{tracelog \"" .. string.rep("* ", 32) .. "%X %X \",IRQ2,dw@3400}"
end

local bp
if trace then
	io.open(trace, "w"):close()
	bp = dcs.debug:bpset(0, "1", trace_cmd(fullf == 0))
end

local function us() return string.format("%.3f", machine.time:as_double() * 1e6) end

local host = os.getenv("DCS_HOST") and assert(io.open(os.getenv("DCS_HOST"), "w"))
if host then
	tap_snd = main:install_write_tap(0x01680000, 0x0168001f, "snd_w", function(offset, data, mask)
		host:write(string.format("%s W %02x\n", us(), data & 0xff))
	end)
	-- the I/O control word is word 1 of the I/O window, after WWF's order
	-- shuffle (MAME midwunit_m.cpp wwfmania_io_0_w: a write to word 0
	-- itself picks one of five orders)
	local sys = machine.system
	local wwf = (sys.name == "wwfmania" or sys.parent == "wwfmania")
	local orders = { [0] = {}, { [4]=0, [8]=1, [1]=2, [9]=3, [2]=4 }, { [8]=0, [2]=1, [4]=2, [6]=3, [1]=4 },
	                 { [1]=0, [8]=1, [2]=2, [10]=3, [5]=4 }, { [2]=0, [4]=1, [1]=2, [7]=3, [8]=4 } }
	local order = orders[0]
	tap_ioc = main:install_write_tap(0x01800000, 0x0187ffff, "io_w", function(offset, data, mask)
		local w = (offset - 0x01800000) // 16
		if wwf and w == 0 then
			order = orders[data] or orders[0]
			return
		end
		local i = w % 16
		if (order[i] or (i % 8)) % 8 == 1 then
			host:write(string.format("%s C %04x\n", us(), data))
		end
	end)
end

local dac = os.getenv("DCS_DAC") and assert(io.open(os.getenv("DCS_DAC"), "w"))
if dac then
	-- reads of the DAC buffer (DCS_DAC_AT, hex ranges; default the main
	-- program's 0C00-0DDF, the boot loader's test tone uses 3800-39DF):
	-- MAME's half-buffer moves come as runs with one time stamp, the DSP's
	-- own reads one at a time
	tap_dac = {}
	for lo, hi in (os.getenv("DCS_DAC_AT") or "0c00-0ddf"):gmatch("(%x+)-(%x+)") do
		tap_dac[#tap_dac + 1] = dcs.spaces["data"]:install_read_tap(tonumber(lo, 16), tonumber(hi, 16), "dac" .. lo,
			function(offset, data, mask)
				dac:write(string.format("%s %04x %04x\n", us(), offset, data))
			end)
	end
end

local presses = {}
for fr, port, mask, len in (os.getenv("WU_PRESS") or ""):gmatch("(%d+):([%w_]+):(%x+):(%d+)") do
	presses[#presses + 1] = { frame = tonumber(fr), port = port, mask = tonumber(mask, 16), len = tonumber(len) }
end
local held = {}
local frame = 0
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
	if trace and frame == fullf and fullf > 0 then
		dcs.debug:bpclear(bp)
		bp = dcs.debug:bpset(0, "1", trace_cmd(true))
		dbg:command(trace_cmd(true))
	end
	if frame >= endf then
		if trace then
			dbg:command("trace off,:dcs:dcs")
			local f = io.open(trace, "a")
			f:write("END\n")       -- for a reader on a pipe
			f:close()
		end
		if host then host:close() end
		if dac then dac:close() end
		machine:exit()
	end
end)
