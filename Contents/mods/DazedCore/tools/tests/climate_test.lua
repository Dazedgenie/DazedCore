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
-- temperature units: the game's option unless the Dazed Core drop-down picks one
local celsius = true
getCore = function() return { getOptionDisplayAsCelsius = function() return celsius end } end
check(Cl.tempText(21.6) == "22 C" and Cl.tempText(21.64, 1) == "21.6 C", "tempText: Celsius by the game's option")
celsius = false
check(Cl.tempText(20) == "68 F" and Cl.tempText(-40) == "-40 F" and Cl.tempText(21, 1) == "69.8 F", "tempText: Fahrenheit by the game's option")
local v, u = Cl.display(100)
check(v == 212 and u == "F", "display: the number and unit")
local pick
DazedCore.Options = { pick = function(mod, id) return mod == "DazedCore" and id == Cl.UNITS_OPTION and pick or nil end }
pick = 2
check(Cl.tempText(20) == "20 C", "the drop-down's Celsius beats the game's Fahrenheit")
celsius, pick = true, 3
check(Cl.tempText(20) == "68 F", "the drop-down's Fahrenheit beats the game's Celsius")
pick = 1
check(Cl.tempText(20) == "20 C", "Game setting follows the game")
getCore, DazedCore.Options = nil, nil
check(Cl.tempText(20) == "20 C", "no game core reads Celsius")
-- the Temperatures drop-down on the shared options page, against a stand-in for the game's ModOptions
local pages = {}
local function newPage()
    local pg = { dict = {} }
    function pg:getOption(id) return self.dict[id] end
    function pg:addTickBox(id) local o = { value = true, getValue = function(o) return o.value end } self.dict[id] = o return o end
    function pg:addComboBox(id, name, tip)
        local o = { values = {}, selected = 1, name = name, tip = tip }
        function o:addItem(key, sel) table.insert(self.values, key) if sel then self.selected = #self.values end end
        function o:getValue() return self.selected end
        self.dict[id] = o
        return o
    end
    return pg
end
PZAPI = { ModOptions = { getOptions = function(_, id) return pages[id] end,
    create = function(_, id) pages[id] = newPage() return pages[id] end } }
dofile(root .. "/client/DazedCore/DC_Options.lua")
local O = DazedCore.Options
local units = pages[O.ID] and pages[O.ID]:getOption("DazedCore_" .. Cl.UNITS_OPTION)
check(units and #units.values == 3 and units.selected == 1 and O.pick("DazedCore", Cl.UNITS_OPTION) == 1,
      "options: the Temperatures drop-down is on the page and starts on Game setting")
getCore = function() return { getOptionDisplayAsCelsius = function() return true end } end
units.selected = 3
check(Cl.tempText(0) == "32 F", "options: picking Fahrenheit changes the text")
check(O.combo("DazedCore", Cl.UNITS_OPTION, "x", { "a" }, 1) == units and O.pick("Nope", "x") == nil,
      "options: a second combo call returns the same option; a missing one picks nothing")
PZAPI, getCore, DazedCore.Options = nil, nil, nil
print(string.format("climate_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
