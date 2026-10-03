-- Checks for the sandbox preset switch (DC_Preset). Run from run_all.sh.
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
require "DazedCore/DC_Boot"
local R = DazedCore.Preset
local fails, n = 0, 0
local function check(ok, msg) n = n + 1 if not ok then fails = fails + 1 print("FAIL " .. msg) end end

R.register("Test", { Scale = { 150, 100, 80, 60 }, Flag = { false, true, true, true } })
SandboxVars = { Test = { Scale = 77, Flag = true }, DazedCore = { Preset = 1 } }
check(DazedCore.Util.sandbox("Test", "Scale", 1) == 77, "Custom leaves the option's own value")
SandboxVars.DazedCore.Preset = 2
check(DazedCore.Util.sandbox("Test", "Scale", 1) == 150 and DazedCore.Util.sandbox("Test", "Flag", true) == false, "Easy replaces the option, false included")
SandboxVars.DazedCore.Preset = 5
check(DazedCore.Util.sandbox("Test", "Scale", 1) == 60, "Hardcore is the fourth column")
check(DazedCore.Util.sandbox("Test", "Other", 9) == 9, "an option a preset does not list keeps its own value")
SandboxVars.DazedCore.Preset = 99
check(R.current() == 1 and R.override("Test", "Scale") == nil, "an out-of-range value reads as Custom")
SandboxVars = nil
check(R.current() == 1 and DazedCore.Util.sandbox("Test", "Scale", 5) == 5, "no SandboxVars at all reads as Custom")
print(string.format("preset_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
