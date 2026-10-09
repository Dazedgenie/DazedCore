-- Headless check of the Building Picker's hover: a still cursor sees a new served list, and the recheck timer.
-- Run: lua picker_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

-- just enough UI and rendering for DC_Picker to load and draw into a log
package.preload["ISUI/ISCollapsableWindow"] = function()
    ISCollapsableWindow = { derive = function(self, name) local c = { name = name } c.__index = c setmetatable(c, { __index = self }) return c end,
        new = function(self) return setmetatable({ getHeight = function() return 100 end, setResizable = function() end,
            titleBarHeight = function() return 10 end, setHeight = function() end }, self) end,
        initialise = function() end, addToUIManager = function() end, removeFromUIManager = function() end,
        createChildren = function() end, prerender = function() end }
    return ISCollapsableWindow
end
package.preload["ISUI/ISButton"] = function() ISButton = {} return ISButton end
getTextManager = function() return { getFontHeight = function() return 16 end, MeasureStringX = function() return 10 end } end
UIFont = { Small = 1, Medium = 2 }
local drawn = {}
SpriteRenderer = { instance = { renderPoly = function(_, ...) drawn[#drawn + 1] = { ... } end, renderlinef = function() end } }
IsoUtils = { XToScreenExact = function(x) return x end, YToScreenExact = function(_, y) return y end }
local MX, MY = 5, 5
getMouseX = function() return MX end
getMouseY = function() return MY end
screenToIsoX = function(_, mx) return mx end
screenToIsoY = function(_, _, my) return my end
local NOW = 0
getTimestampMs = function() return NOW end

local player = E.character(5, 5, 0)
function player:isDead() return false end
function player:getPlayerNum() return 0 end
getSpecificPlayer = function() return player end
IsoPlayer = { getPlayerIndex = function() return 0 end }
getSquare = function(x, y, z) return E.square(x, y, z) end

local R = require "DazedCore/DC_Reach"
local B = require "DazedCore/DC_Buildings"
local K = require "DazedCore/DC_Picker"

-- one building over squares 4..6 x 4..6, found by the resolver
local house = { k = "b", id = 7, x = 4, y = 4, z = 0 }
local houseRects = { { x = 4, y = 4, w = 3, h = 3, z = 0 } }
local lookups = 0
B.targetAt = function(x, y, z) lookups = lookups + 1 return (x >= 4 and x <= 6 and y >= 4 and y <= 6 and z == 0) and house or nil end
B.footprintOf = function() return R.fpOfRects(houseRects) end
B.reaches = function() return true end

local servedList, version, taken = {}, 1, false
local spec = {
    textVersion = function() return version end,
    served = function() return servedList end,
    status = function() return taken and "taken" or nil end,
    pick = function() end,
}
local part = E.object("part", E.square(5, 6))
local st = K.open(player, part, spec)
check(st ~= nil, "the picker opens")

local function hoverMode() K.render() return st.hover and st.hover.mode end
check(hoverMode() == "add", "a building in reach under the cursor would be added")
-- the server now serves it; the cursor has not moved
servedList = { { k = "b", x = 4, y = 4, z = 0, id = 7, rects = houseRects } }
version = 2
check(hoverMode() == "take", "a new served list turns the still hover to take")
-- moved within the same building with no change: the footprint shortcut keeps the hover, no lookup
local before = lookups
MX = 6
check(hoverMode() == "take" and lookups == before, "moving inside the hovered footprint reuses it")
-- the server drops it again, cursor moved inside the old footprint in the same frame
servedList = {}
version = 3
MX = 4
check(hoverMode() == "add", "a changed list is not hidden by the footprint shortcut")
-- another part takes the building: no served change, so only the recheck timer sees it
taken = true
check(hoverMode() == "add", "a still cursor keeps its hover between rechecks")
NOW = NOW + K.HOVER_RECHECK_MS
check(hoverMode() == "taken", "after the recheck interval the hover is resolved again")
K.close(0)

print(string.format("picker_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
