-- Headless check of DC_HeavyParts: splitting, the all-parts rule, consuming a set on placing,
-- both engine argument orders, and upgrading a version-1 copy left by an older mod.
-- Run: lua heavy_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end
local WEIGHT = { ["Base.DazedPropaneGen"] = 60, ["Base.DazedPedalGen"] = 30, ["Base.DazedXL"] = 95, ["Base.Other"] = 90 }
local function Item(ft)
    local it = { ft = ft, md = {}, w = WEIGHT[ft], name = ft }
    function it:getFullType() return self.ft end
    function it:getModData() return self.md end
    function it:getScriptItem() local w = WEIGHT[self.ft] return { getActualWeight = function() return w end, getDisplayName = function() return "Gen" end } end
    function it:getActualWeight() return self.w end
    function it:setActualWeight(v) self.w = v end
    function it:setWeight(v) end
    function it:setName(n) self.name = n end
    function it:setCustomName() end
    function it:setCustomWeight() end
    function it:getDisplayName() return self.name end
    function it:getContainer() return self.cont end
    return it
end
local function Inv()
    local inv = { list = {} }
    function inv:getItems() local l = self.list return { size = function() return #l end, get = function(_, k) return l[k + 1] end } end
    function inv:AddItem(it) self.list[#self.list + 1] = it; it.cont = self end
    function inv:Remove(it) for k, v in ipairs(self.list) do if v == it then table.remove(self.list, k) return end end end
    return inv
end
instanceItem = function(ft) return Item(ft) end
instanceof = function(o, cls) return type(o) == "table" and o.__class == cls end
local placed = {}
package.preload["Moveables/ISMoveableSpriteProps"] = function()
    ISMoveableSpriteProps = {
        pickUpMoveable = function(self, ch) return "picked" end,
        canPlaceMoveableInternal = function(self, ...) return true end,
        placeMoveableInternal = function(self, ...) placed[#placed + 1] = { ... } return "obj" end,
    }
    return true
end
Events = setmetatable({}, { __index = function(t, k) local ev = { handlers = {} } ev.Add = function(f) ev.handlers[#ev.handlers + 1] = f end t[k] = ev return ev end })
package.path = root .. "/shared/?.lua;" .. package.path

-- An older mod's version-1 copy is already loaded: the core must upgrade it in place.
DazedHeavy = { VERSION = 1, prefixes = { ["Base.OffGrid"] = true }, wrapped = true, swept = true }
local H = require "DazedCore/DC_HeavyParts"
check(H == DazedHeavy and H.VERSION == 3, "upgrades the v1 table in place")
check(H.prefixes["Base.OffGrid"], "keeps the old mod's registered prefix")
check(DazedCore.Heavy == H, "exposed as DazedCore.Heavy")
check(H.wrapped2 == true, "installs its own wrappers even when v1 wrapped")
check(package.loaded["DazedCore/DC_HeavyParts"] == H, "require returns the library")

H.register("Base.Dazed")
check(H.count(60) == 2 and H.count(30) == 1 and H.count(95) == 4 and H.count(0) == 1, "part count")

local inv = Inv()
local gen = Item("Base.DazedPropaneGen"); gen.md.fuel = 7; inv:AddItem(gen)
local ped = Item("Base.DazedPedalGen"); inv:AddItem(ped)
local other = Item("Base.Other"); inv:AddItem(other)
local ch = { getInventory = function() return inv end }
H.splitAll(ch)
check(#inv.list == 4, "60 kg splits into 2, 30 kg and a foreign 90 kg stay whole: " .. #inv.list)
check(H.partsOf(gen) and H.partsOf(gen).i == 1 and H.partsOf(gen).n == 2, "first part marked")
check(gen.w == 30, "part weighs half: " .. tostring(gen.w))
check(gen.name == "Gen (1/2)", "name: " .. gen.name)
local second = inv.list[4]
check(second.md.fuel == 7 and H.partsOf(second).i == 2, "second part carries the state")
check(not H.partsOf(ped) and not H.partsOf(other), "whole items untouched")
check(H.complete(ch, gen), "set complete with both parts")
inv:Remove(second)
check(not H.complete(ch, gen), "incomplete without the second part")
inv:AddItem(second)

-- Placing in the 42.21 order (character, square, item): consumes the other part.
local sq = { __class = "IsoGridSquare" }
local n0 = #inv.list
local r = ISMoveableSpriteProps:placeMoveableInternal(ch, sq, gen, "sprite")
check(r == "obj" and #placed == 1, "placed through to vanilla")
check(#inv.list == n0 - 1 and not H.partsOf(gen), "other part consumed, placed one whole again")
inv:Remove(gen)                             -- the game takes the placed item out of the inventory

-- The older order (square, item, name): the character comes from getSpecificPlayer.
getSpecificPlayer = function() return ch end
local gen2 = Item("Base.DazedPropaneGen"); inv:AddItem(gen2)
H.splitAll(ch)
check(H.partsOf(gen2) and H.partsOf(gen2).n == 2, "second generator split")
local n1 = #inv.list
check(ISMoveableSpriteProps:canPlaceMoveableInternal(sq, gen2, "sprite") == true, "can place with the set (old order)")
inv:Remove(inv.list[#inv.list])            -- lose the other part
check(ISMoveableSpriteProps:canPlaceMoveableInternal(sq, gen2, "sprite") == false, "refused without the set (old order)")
check(ISMoveableSpriteProps:placeMoveableInternal(sq, gen2, "sprite") == nil, "placing refused too")

-- Performance: the sweep leaves foreign items alone, the type memo follows new prefixes, the cursor memo lets go.
local touched = 0
local plain = Item("Base.Other")
function plain:getModData() touched = touched + 1 return self.md end
local inv3 = Inv()
inv3:AddItem(plain)
local ch3 = { getInventory = function() return inv3 end }
H.splitAll(ch3)
H.splitAll(ch3)
check(touched == 0, "the sweep never opens a foreign item's ModData")
H.register("Base.Other")
H.splitAll(ch3)
check(#inv3.list == 3 and H.partsOf(plain) and H.partsOf(plain).n == 3, "a prefix registered later is honoured at once")
H.prefixes["Base.Other"] = nil
local late = Item("Base.Other"); inv3:AddItem(late)
H.splitAll(ch3)
check(not H.partsOf(late), "a prefix taken out of the table directly is noticed by the next sweep")

local clock = 1000
getTimestampMs = function() return clock end
local inv4 = Inv()
local g4 = Item("Base.DazedPropaneGen"); inv4:AddItem(g4)
local ch4 = { getInventory = function() return inv4 end }
H.splitAll(ch4)
local asks, complete0 = 0, H.complete
H.complete = function(...) asks = asks + 1 return complete0(...) end
check(H.completeCached(ch4, g4) and H.completeCached(ch4, g4) and asks == 1, "cursor memo: one inventory walk serves the next frames")
inv4:Remove(inv4.list[2])
check(not H.completeCached(ch4, g4) and asks == 2, "cursor memo: a part leaving the inventory is seen at once")
clock = clock + H.COMPLETE_TTL_MS
H.completeCached(ch4, g4)
check(asks == 3, "cursor memo: an old answer is asked again")
getTimestampMs = nil

H.completeCached(ch4, g4)
H.completeCached(ch4, g4)
check(asks == 5, "cursor memo: without a clock every call walks")
H.complete = complete0

-- The whole-item sweep runs every ten game minutes, not every minute (the v1 copy above had set `swept`).
H.swept, H.VERSION = nil, 2
package.loaded["DazedCore/DC_HeavyParts"] = nil
require "DazedCore/DC_HeavyParts"
check(#Events.EveryTenMinutes.handlers >= 1 and #Events.EveryOneMinute.handlers == 0, "sweep hooked on EveryTenMinutes")
local inv5 = Inv()
local g5 = Item("Base.DazedPropaneGen"); inv5:AddItem(g5)
local ch5 = { getInventory = function() return inv5 end }
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return ch5 end
for _, h in ipairs(Events.EveryTenMinutes.handlers) do h() end
check(H.partsOf(g5) and #inv5.list == 2, "the ten-minute sweep splits a whole item")

print(string.format("heavy_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
