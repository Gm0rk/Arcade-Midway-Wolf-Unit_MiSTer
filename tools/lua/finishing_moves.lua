-- finishing_moves.lua - the core's finishing moves played in MAME 0.289 (MK3, UMK3)
--
-- tools/finishing_moves.py --mame runs this once per character. From
-- power-on it inserts coins, starts a two-player game, picks the fighters
-- (FM_P1, FM_P2: the game's character numbers, written into the player
-- blocks until the first fight starts; the stage, FM_STAGE, all along), wins the
-- rounds for the winner (FM_WINNER) by setting the loser's energy to 1 and
-- walking in to punch, and saves a state at the FINISH HIM. Each test then
-- loads that state, waits for the FINISH HIM state (3), puts the winner the
-- given distance from the loser (the loser first moved FM_EDGE pixels off
-- the stage edge it was knocked to: some moves want room behind the loser),
-- enters the move and watches the game's finishing move type (1 Fatality,
-- 2 Stage Fatality, 3 Animality, 4 Friendship, 5 Babality) or, for the
-- Mercy, the loser's energy coming back.
--
-- FM_TESTS: one test a line, "id kind distances program":
--   kind f   at the FINISH HIM of a 2-0 match
--        m   at the FINISH HIM of round 3 (both players won a round)
--        a   after a Mercy (FM_MERCY at FM_MDIST) in round 3, at the
--            second FINISH HIM
--   distances  comma list, pixels between the fighters' X positions
--   program    as rtl/wunit_finish_moves.vh lists them (U D F B HP LP HK LK
--              BL RN, a+b together, hold:x, rel:x, w:frames, t:on/off; tapped
--              4 frames, 4 apart), or one token a frame, r:IN0.IN1 in hex, as
--              sim/finish prints what the core's player holds
-- FM_OUT/results.txt: "id distance measured outcome" a line, "done" at the
-- end; measured is the distance when the move's last input went in.
--
-- Other settings: FM_UMK3 (1: UMK3's RAM layout, else MK3's), FM_KSTATE (the
-- state variable's main RAM word, hex), FM_LEAD (frames before a move,
-- default 10).
--
-- Run: wtunit <set> -rompath ROMS -state_directory DIR -video none
--      -sound none -nothrottle -autoboot_script finishing_moves.lua

local machine = manager.machine
local ram = machine.memory.shares[":mainram"]
local env = os.getenv
local out = env("FM_OUT") or "."
local kst = tonumber(env("FM_KSTATE") or "6096", 16)
local umk3 = env("FM_UMK3") == "1"
-- offsets from the state variable: player 1's block (player 2's BBh on),
-- finishing move type, stage, FINISH HIM state
local pb = { kst + (umk3 and 7 or 5) }
pb[2] = pb[1] + 0xBB
local ftv = kst + (umk3 and 0x17D or 0x17B)
local stv = kst + (umk3 and 0x190 or 0x18B)
local fhv = kst + (umk3 and 0x194 or 0x18F)
local pc = { tonumber(env("FM_P1") or "-1"), tonumber(env("FM_P2") or "0") }
local stage = env("FM_STAGE") and tonumber(env("FM_STAGE"), 16)
local winner = tonumber(env("FM_WINNER") or "1")
local edge = tonumber(env("FM_EDGE") or "160")
local lead = tonumber(env("FM_LEAD") or "10")
local tag = env("FM_TAG") or "fm"

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

-- the winner d from the loser, the loser moved off the stage edge first
local function place(d)
	local l = 3 - winner
	local s = xpos(l) > xpos(winner) and 1 or -1
	local xl = xpos(l) - s * edge
	wr(obj(l) + 9, xl)
	wr(obj(winner) + 9, xl - s * d)
end

local function win_round(w)
	local l = 3 - w
	while rd(kst) ~= 2 do wait(1) end
	wait(10)
	wr(pb[l] + 9, 1)
	local n = 0
	while energy(l) > 0 and n < 900 do
		local dx = xpos(l) - xpos(w)
		if math.abs(dx) > 60 then
			local k = dx > 0 and "R" or "L"
			set(w, k, true) wait(1) set(w, k, false)
		else
			tap(w, {"HP"})
		end
		if energy(l) > 1 and energy(l) < 0x100 then wr(pb[l] + 9, 1) end
		n = n + 1
	end
	release_all()
	return energy(l) == 0
end

local function wait_finish()
	local n = 0
	while rd(fhv) ~= 3 and n < 300 do wait(1) n = n + 1 end
end

-- the finishing move type, or the loser's energy back (Mercy)
local function outcome(l)
	for i = 1, 300 do
		if rd(ftv) ~= 0 then return "type" .. rd(ftv) end
		if energy(l) > 0 and energy(l) < 0x100 then return "revived" end
		if rd(kst) ~= 2 and i > 30 then return "none" end
		wait(1)
	end
	return "none"
end

local fought = true             -- until the fighter select: nothing forced
local function setup(plan, name)
	machine:load("sel") wait(2)
	fought = false
	for i = 1, #plan do
		if not win_round(tonumber(plan:sub(i, i))) then say("setup failed " .. plan) return false end
	end
	wait(3)
	machine:save(name) wait(2)
	return true
end

local tests = {}
for line in io.lines(env("FM_TESTS")) do
	local id, kind, dists, prog = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(.+)$")
	if id then
		local ds = {}
		for d in dists:gmatch("%d+") do ds[#ds + 1] = tonumber(d) end
		tests[#tests + 1] = { id = id, kind = kind, dists = ds, prog = prog }
	end
end

local function run(t, st)
	for _, d in ipairs(t.dists) do
		machine:load(st) wait(2)
		release_all()
		wait_finish()
		place(d)
		wait(lead)
		local dist = do_move(winner, t.prog)
		local o = outcome(3 - winner)
		release_all()
		say(string.format("%s %d %d %s", t.id, d, dist or -1, o))
	end
end

local function main()
	-- power-on to the fighter select (frames as MAME's frame notifier
	-- counts them): two credits each, both players in, both pick
	local function push(f, field)
		upto(f) field:set_value(1) upto(f + 5) field:set_value(0)
	end
	push(150, fields[1].HP)
	for _, f in ipairs({ 400, 430, 460, 490 }) do push(f, coin[0x0001]) end
	push(550, coin[0x0004])
	push(700, coin[0x0020])
	push(760, coin[0x0020])
	upto(850) set(1, "HP", true) set(2, "HP", true)
	upto(852) machine:save("sel")
	upto(855) release_all()
	local need = {}
	for _, t in ipairs(tests) do need[t.kind] = true end
	local w = winner
	if need.f and setup(w == 1 and "11" or "22", tag .. "f") then
		for _, t in ipairs(tests) do if t.kind == "f" then run(t, tag .. "f") end end
	end
	if (need.m or need.a) and setup(w == 1 and "121" or "212", tag .. "m") then
		for _, t in ipairs(tests) do if t.kind == "m" then run(t, tag .. "m") end end
		if need.a then
			machine:load(tag .. "m") wait(2)
			wait_finish()
			place(tonumber(env("FM_MDIST") or "220"))
			wait(lead)
			do_move(w, env("FM_MERCY") or "hold:RN w:66 D D rel:RN")
			local o = outcome(3 - w)
			if o ~= "revived" then
				say("mercy " .. o)
			else
				wait(60)
				if win_round(w) then
					wait(3) machine:save(tag .. "a") wait(2)
					for _, t in ipairs(tests) do if t.kind == "a" then run(t, tag .. "a") end end
				else
					say("animality setup failed")
				end
			end
		end
	end
	say("done")
end

local co = coroutine.create(main)
sub = emu.add_machine_frame_notifier(function()
	frame = frame + 1
	if not fought then
		for p = 1, 2 do if pc[p] >= 0 then wr(pb[p] + 6, pc[p]) end end
		if rd(kst) == 2 then fought = true end
	end
	-- the stage all along (MK3 sets its own stage for Smoke)
	if stage and frame > 855 then wr(stv, stage) end
	if coroutine.status(co) ~= "dead" then
		local ok, err = coroutine.resume(co)
		if not ok then say("error " .. tostring(err)) end
	end
	if coroutine.status(co) == "dead" then res:close() machine:exit() end
end)
