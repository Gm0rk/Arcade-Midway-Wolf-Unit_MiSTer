-- dump_regions.lua - write every ROM region MAME loaded to <outdir>/<set>/<tag>.bin
--
-- Run with the set's name and the output folder in the environment:
--   WU_SET=umk3 WU_OUT=regions wtunit umk3 -video none -sound none \
--       -nothrottle -autoboot_script dump_regions.lua
-- The ':' of a device tag becomes '_' in the file name. mra_gen.py --regions
-- compares the MRA images with these files, which come from MAME's own
-- loader rather than from the generator's reading of the driver source.
--
-- The autoboot script runs once the machine has started, after the ROMs are
-- loaded, so the regions are dumped straight away and MAME is told to exit.

local set = os.getenv("WU_SET")
local out = os.getenv("WU_OUT") or "regions"

os.execute("mkdir -p " .. out .. "/" .. set)
for tag, region in pairs(manager.machine.memory.regions) do
	local name = tag:gsub("^:", ""):gsub(":", "_")
	local f = assert(io.open(out .. "/" .. set .. "/" .. name .. ".bin", "wb"))
	f:write(region:read(0, region.size))      -- the bytes as MAME holds them
	f:close()
end
manager.machine:exit()
