-- fight_sound.lua - the sound commands of a move in a real fight, in MAME 0.289 (UMK3)
--
-- From power-on it inserts coins, starts a two-player game and picks the fighters (FS_P1,
-- FS_P2: the game's character numbers, see tools/finishing_moves.py), waits for the first
-- fight, puts the fighters FS_DIST pixels apart and has player 1 play FS_MOVE (the tokens of
-- finishing_moves.lua: F B U D HP LP BL HK LK RN, a+b together, w:frames).
--
--   FS_OUT   directory for host.txt (the host's side, as dcs_trace.lua: "t W xx", with the
--            frame in a third column) and dac.txt (MAME's DAC words, as DCS_DAC)
--   FS_SECS  frames to run after the move (default 240)
--   FS_P1 FS_P2 FS_DIST FS_MOVE FS_UMK3 FS_KSTATE   as above / finishing_moves.lua
--   FS_PATCH "byte offset:value,..." (hex): bytes of the program ROM (the maincpu region, as
--            the .rom image's first MB) written before the game runs
--   FS_WTAP  "lo-hi": the same for the 34010's writes (taps.txt, "w" in the second column)
--   FS_TAP   "lo-hi" (hex bit addresses): log the 34010's reads there to taps.txt as
--            "frame pc address data" (who reads a table)
--
-- Run: wtunit umk3 -rompath ROMS -video none -sound none -nothrottle -debug -debugger none
--      -autoboot_script fight_sound.lua   (-debug for the DAC read tap)

local machine = manager.machine
local ram = machine.memory.shares[":mainram"]
local env = os.getenv
local out = env("FS_OUT") or "."
local kst = tonumber(env("FS_KSTATE") or "6096", 16)
local umk3 = env("FS_UMK3") == "1"
-- offsets from the state variable: player 1's block (player 2's BBh on),
-- finishing move type, stage, FINISH HIM state
local pb = { kst + (umk3 and 7 or 5) }
pb[2] = pb[1] + 0xBB
local ftv = kst + (umk3 and 0x17D or 0x17B)
local stv = kst + (umk3 and 0x190 or 0x18B)
local fhv = kst + (umk3 and 0x194 or 0x18F)
local fought = false
local pc = { tonumber(env("FS_P1") or "-1"), tonumber(env("FS_P2") or "0") }
local stage = env("FS_STAGE") and tonumber(env("FS_STAGE"), 16)
local winner = tonumber(env("FS_WINNER") or "1")
local edge = tonumber(env("FS_EDGE") or "160")
local lead = tonumber(env("FS_LEAD") or "10")
local tag = env("FS_TAG") or "fm"

local function rd(w) return ram:read_u16(w * 2) end
local function wr(w, v) ram:write_u16(w * 2, v & 0xFFFF) end
local function obj(p)
	local v = rd(pb[p]) | (rd(pb[p] + 1) << 16)
	if v < 0x01000000 or v >= 0x01400000 then return nil end
	return (v - 0x01000000) >> 4
end
local function xpos(p)
	local o = obj(p)
	if not o then return 0 end
	local v = rd(o + 9)
	return v >= 0x8000 and v - 0x10000 or v
end
local function energy(p) return rd(pb[p] + 9) end

local res = assert(io.open(out .. "/results.txt", "w"))
local function say(s) res:write(s .. "\n") res:flush() end

-- MAME's midwunit.cpp MK3 ports
local map = {
	{ U = {"IN0", 0x0001}, D = {"IN0", 0x0002}, L = {"IN0", 0x0004}, R = {"IN0", 0x0008}, HP = {"IN0", 0x0010},
	  BL = {"IN0", 0x0020}, HK = {"IN0", 0x0040}, LP = {"IN1", 0x0001}, LK = {"IN1", 0x0002}, RN = {"IN1", 0x0004} },
	{ U = {"IN0", 0x0100}, D = {"IN0", 0x0200}, L = {"IN0", 0x0400}, R = {"IN0", 0x0800}, HP = {"IN0", 0x1000},
	  BL = {"IN0", 0x2000}, HK = {"IN0", 0x4000}, LP = {"IN1", 0x0010}, LK = {"IN1", 0x0020}, RN = {"IN1", 0x0040} } }
local fields = {}
for p = 1, 2 do
	fields[p] = {}
	for k, m in pairs(map[p]) do
		for _, f in pairs(machine.ioport.ports[":" .. m[1]].fields) do
			if (f.mask & m[2]) ~= 0 then fields[p][k] = f end
		end
	end
end
local coin = {}
for _, f in pairs(machine.ioport.ports[":IN2"].fields) do coin[f.mask] = f end

local frame = 0
local function set(p, k, on) fields[p][k]:set_value(on and 1 or 0) end
local function release_all() for p = 1, 2 do for _, f in pairs(fields[p]) do f:set_value(0) end end end
local function wait(n) for _ = 1, n do coroutine.yield() end end
local t_on, t_off = 4, 4
local function tap(p, keys)
	for _, k in ipairs(keys) do set(p, k, true) end
	wait(t_on)
	for _, k in ipairs(keys) do set(p, k, false) end
	wait(t_off)
end
local function upto(f) while frame < f do coroutine.yield() end end

-- a program, for player p (F and B by the side the opponent is on)
local function do_move(p, prog)
	local fwd = xpos(3 - p) > xpos(p) and "R" or "L"
	local function key(k)
		if k == "F" then return fwd end
		if k == "B" then return fwd == "R" and "L" or "R" end
		return k
	end
	local toks = {}
	for t in prog:gmatch("%S+") do toks[#toks + 1] = t end
	local dist
	t_on, t_off = 4, 4
	for i, tok in ipairs(toks) do
		if i == #toks then dist = math.abs(xpos(1) - xpos(2)) end
		local r0, r1 = tok:match("^r:(%x+)%.(%x+)$")
		local h, r, w = tok:match("^hold:(.+)$"), tok:match("^rel:(.+)$"), tok:match("^w:(%d+)$")
		local tn, tf = tok:match("^t:(%d+)/(%d+)$")
		if tn then
			t_on, t_off = tonumber(tn), tonumber(tf)
			wait(1)
		elseif r0 then
			local v = { IN0 = tonumber(r0, 16), IN1 = tonumber(r1, 16) }
			for pp = 1, 2 do
				for k, m in pairs(map[pp]) do set(pp, k, (v[m[1]] & m[2]) ~= 0) end
			end
			wait(1)
		elseif w then
			wait(tonumber(w))
		elseif h or r then
			for k in (h or r):gmatch("[^+]+") do set(p, key(k), h ~= nil) end
			wait(t_off)
		else
			local keys = {}
			for k in tok:gmatch("[^+]+") do keys[#keys + 1] = key(k) end
			tap(p, keys)
		end
	end
	return dist
end


local main_sp = machine.devices[":maincpu"].spaces["program"]
local dcs = machine.devices[":dcs:dcs"]
local host = assert(io.open(out .. "/host.txt", "w"))
local dac = assert(io.open(out .. "/dac.txt", "w"))
local function us() return string.format("%.3f", machine.time:as_double() * 1e6) end
tap_snd = main_sp:install_write_tap(0x01680000, 0x0168001f, "snd_w", function(offset, data, mask)
	host:write(string.format("%s W %02x %d\n", us(), data & 0xff, frame))
end)
tap_dac = dcs.spaces["data"]:install_read_tap(0x0c00, 0x0ddf, "dac", function(offset, data, mask)
	dac:write(string.format("%s %04x %04x\n", us(), offset, data))
end)

if env("FS_PATCH") then
	local rgn = machine.memory.regions[":maincpu"]
	for off, val in env("FS_PATCH"):gmatch("(%x+):(%x+)") do rgn:write_u8(tonumber(off, 16), tonumber(val, 16)) end
end

if env("FS_TAP") then
	local taps = assert(io.open(out .. "/taps.txt", "w"))
	local lo, hi = env("FS_TAP"):match("(%x+)-(%x+)")
	tap_rd = main_sp:install_read_tap(tonumber(lo, 16), tonumber(hi, 16), "tap", function(offset, data, mask)
		taps:write(string.format("%d %08x %08x %04x\n", frame, machine.devices[":maincpu"].state["PC"].value, offset, data))
		taps:flush()
	end)
end

if env("FS_WTAP") then
	local wt = assert(io.open(out .. "/wtaps.txt", "w"))
	local lo, hi = env("FS_WTAP"):match("(%x+)-(%x+)")
	tap_wr = main_sp:install_write_tap(tonumber(lo, 16), tonumber(hi, 16), "wtap", function(offset, data, mask)
		wt:write(string.format("%d %08x %08x %04x\n", frame, machine.devices[":maincpu"].state["PC"].value, offset, data))
		wt:flush()
	end)
end

local function main()
	local function push(f, field)
		upto(f) field:set_value(1) upto(f + 5) field:set_value(0)
	end
	push(150, fields[1].HP)
	for _, f in ipairs({ 400, 430, 460, 490 }) do push(f, coin[0x0001]) end
	push(550, coin[0x0004])
	push(700, coin[0x0020])
	push(760, coin[0x0020])
	upto(850) set(1, "HP", true) set(2, "HP", true)
	upto(855) release_all()
	while rd(kst) ~= 2 do wait(1) end
	wait(tonumber(env("FS_LEAD") or "120"))
	local d = tonumber(env("FS_DIST") or "120")
	local s = xpos(2) > xpos(1) and 1 or -1
	wr(obj(2) + 9, xpos(1) + s * d)
	wait(5)
	say(string.format("move at frame %d, distance %d", frame, math.abs(xpos(1) - xpos(2))))
	do_move(1, env("FS_MOVE") or "B B LP")
	say(string.format("move done at frame %d, opponent energy %x", frame, energy(2)))
	wait(tonumber(env("FS_SECS") or "240"))
	release_all()
	say("done")
end

local co = coroutine.create(main)
sub = emu.add_machine_frame_notifier(function()
	frame = frame + 1
	if not fought then
		for p = 1, 2 do if pc[p] >= 0 then wr(pb[p] + 6, pc[p]) end end
		if rd(kst) == 2 then fought = true end
	end
	if coroutine.status(co) ~= "dead" then
		local ok, err = coroutine.resume(co)
		if not ok then say("error " .. tostring(err)) end
	end
	if coroutine.status(co) == "dead" then res:close() host:close() dac:close() machine:exit() end
end)
