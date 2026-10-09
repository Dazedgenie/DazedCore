-- Checks for the shared climate lookup (DC_Climate). Run from run_all.sh.
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. package.path
require "DazedCore/DC_Boot"
local Cl = DazedCore.Climate
local fails, n = 0, 0
local function check(ok, msg) n = n + 1 if not ok then fails = fails + 1 print("FAIL " .. msg) end end

getClimateManager = function() return { getTemperature = function() return 12 end,
    getAirTemperatureForSquare = function(_, sq) return sq == "inside" and 18 or 12 end } end
check(Cl.outdoor() == 12 and Cl.temperatureAt("inside") == 18, "without a provider the game's figures are used")
check(Cl.forecast(1) == nil, "and there is no forecast")
Cl.register({ outdoor = function() return -7 end, at = function(sq) return sq == "inside" and 4 or nil end,
    forecast = function(d) return { min = -10, max = -2, mean = -6, d = d } end })
check(Cl.outdoor() == -7 and Cl.temperatureAt("inside") == 4, "a provider's answers come first")
check(Cl.temperatureAt("elsewhere") == 12, "a provider with no answer falls back to the game")
check(Cl.forecast(1).d == 1, "forecasts pass the day through")
Cl.register({ outdoor = function() error("boom") end })
check(Cl.outdoor() == 12, "a provider that errors falls back to the game")
-- the shared spoilage curve, matching Dazed Climate's cold storage
check(Cl.spoilShare(-10) == 0.05 and Cl.spoilShare(2) == 0.3 and Cl.spoilShare(15) == 1.0 and Cl.spoilShare(40) == 1.0,
      "spoilShare: flat past the ends and on the fridge plateau")
check(math.abs(Cl.spoilShare(7) - 0.5) < 1e-9 and math.abs(Cl.spoilShare(-1) - 0.175) < 1e-9, "spoilShare: straight lines between points")
check(Cl.spoilShare(30, { { 0, 0 }, { 20, 1 }, { 30, 1.6 } }) == 1.6, "spoilShare: a mod's own curve")
print(string.format("climate_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
