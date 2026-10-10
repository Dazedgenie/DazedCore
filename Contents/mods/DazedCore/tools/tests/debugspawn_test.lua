-- Headless check of DebugSpawn: the ring order, who may use it, and placing on a stand-in moveable system
-- (blocked squares skipped, a gap kept, a 2-square part, a wall part trying its other facings, loose items kept).
-- Run: lua debugspawn_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

local S = require "DazedCore/DC_DebugSpawn"

------------------------------------------------------------------ ring order
local ring = S.ringOrder(0, 0, 2, 3)
check(#ring == 16 + 24, "rings 2 and 3 hold 8r squares each")
local seen, dup = {}, false
for _, p in ipairs(ring) do
    local k = p[1] .. "," .. p[2]
    if seen[k] then dup = true end
    seen[k] = true
    local r = math.max(math.abs(p[1]), math.abs(p[2]))
    if r < 2 or r > 3 then dup = true end
end
check(not dup, "every square once, at the right distance")
check(ring[1][1] == -2 and ring[1][2] == -2, "the first ring starts at its corner")

------------------------------------------------------------------ allowed
getDebug = function() return false end
local user = E.character(0, 0, 0)
check(not S.allowed(user), "an ordinary player outside debug may not")
getDebug = function() return true end
check(S.allowed(user), "debug mode may")
getDebug = function() return false end
Capability = { UseMovablesCheat = "cheat", BanUnbanUser = "ban" }
local admin = E.character(0, 0, 0)
admin.getRole = function() return { hasCapability = function(_, c) return c == "cheat" end } end
user.getRole = function() return { hasCapability = function() return false end } end
check(S.allowed(admin) and not S.allowed(user), "staff by capability, not by role name")

------------------------------------------------------------------ the moveable system, stood in
E.grid(30, 30)
local cx, cy = 15, 15
E.square(cx + 2, cy - 2).blocked = true            -- the first square of the first ring: a tree, say
E.square(cx - 2, cy - 2).water = true
local placedAt = {}

-- An item knows its world sprite; the inventory grows contains().
local function stubItem(fullType, sprite)
    local it = E.item(fullType)
    it.getWorldSprite = function() return sprite end
    return it
end
local SPRITE = { ["Base.Box"] = "box_S", ["Base.Long"] = "long_S", ["Base.Wall"] = "wall_S", ["Base.Book"] = nil }

ISMoveableSpriteProps = {}
ISMoveableSpriteProps.__index = ISMoveableSpriteProps
function ISMoveableSpriteProps.new(name)
    local p = setmetatable({ spriteName = name, isMoveable = true }, ISMoveableSpriteProps)
    p.isMultiSprite = name:match("^long") ~= nil
    p.facing = name:match("_(%u)$")
    return p
end
function ISMoveableSpriteProps:getFaces()
    local base = self.spriteName:match("^(.-)_%u$")
    return { S = base .. "_S", E = base .. "_E", W = base .. "_W", N = base .. "_N" }
end
function ISMoveableSpriteProps:getSpriteGridInfo(sq)
    local other = E.squares[(sq.x + 1) .. "," .. sq.y .. ",0"]
    return { { square = sq }, { square = other } }
end
local asked = 0
function ISMoveableSpriteProps:canPlaceMoveable(ch, sq, item)
    asked = asked + 1
    return not sq.water
end
function ISMoveableSpriteProps:placeMoveable(ch, sq, orig)
    if sq.water then error("placed on water: the cursor test was skipped") end
    local inv = ch:getInventory()
    local item
    for _, it in ipairs(inv.items) do if it.getWorldSprite and it:getWorldSprite() == orig then item = it end end
    if not item or sq.blocked or #sq.objs > 0 then return false end
    if orig:match("^wall") and self.facing ~= "W" then return false end     -- only a west wall stands here
    if self.isMultiSprite then
        local other = E.squares[(sq.x + 1) .. "," .. sq.y .. ",0"]
        if not other or other.blocked or #other.objs > 0 then return false end
        E.object(self.spriteName .. "_2", other)
    end
    E.object(self.spriteName, sq)
    placedAt[#placedAt + 1] = { sq = sq, sprite = self.spriteName }
    inv:Remove(item)
end

local ch = E.character(cx, cy, 0)
ch.inv.contains = function(self, it) for _, v in ipairs(self.items) do if v == it then return true end end return false end
local add0 = ch.inv.AddItem
ch.inv.AddItem = function(self, ft)
    local it = stubItem(ft, SPRITE[ft])
    add0(self, it)
    return it
end

S.register("test", "Test", function() return { "Base.Box", "Base.Box", "Base.Long", "Base.Wall", "Base.Book" } end)
local placed, kept, missing = S.spawn(ch, "test")
check(placed == 4 and kept == 1 and missing == 0, "four placed, the book kept: " .. placed .. "/" .. kept .. "/" .. missing)
check(E.count(ch, "Base.Book") == 1 and E.count(ch, "Base.Box") == 0, "the loose item stays in the bag, placed ones leave it")
local blockedHit, nearPlayer = false, false
for _, p in ipairs(placedAt) do
    if p.sq.blocked then blockedHit = true end
    if math.max(math.abs(p.sq.x - cx), math.abs(p.sq.y - cy)) < 2 then nearPlayer = true end
end
check(not blockedHit and not nearPlayer, "no blocked square, nothing next to the player")
check(asked > 0, "the cursor's canPlace test is asked before placing")
local gap = true
for i = 1, #placedAt do
    for j = i + 1, #placedAt do
        local a, b = placedAt[i].sq, placedAt[j].sq
        if math.abs(a.x - b.x) <= 1 and math.abs(a.y - b.y) <= 1 then gap = false end
    end
end
check(gap, "a free square between parts")
local wallFace
for _, p in ipairs(placedAt) do if p.sprite:match("^wall") then wallFace = p.sprite end end
check(wallFace == "wall_W", "the wall part tried its other facings: " .. tostring(wallFace))

------------------------------------------------------------------ the request
getDebug = function() return true end
placedAt = {}
local N = require "DazedCore/DC_Net"
check(N.send(ch, S.MODULE, S.COMMAND, { set = "test" }) and #placedAt == 4, "the command spawns in single player")
getDebug = function() return false end
placedAt = {}
getTimestampMs = function() return 999999 end
local outsider = E.character(cx, cy, 0)
N.send(outsider, S.MODULE, S.COMMAND, { set = "test" })
check(#placedAt == 0, "the authority refuses a player who may not")

------------------------------------------------------------------ a set that places itself
local asked
S.register("own", "own parts", nil, { label = "IGUI_Own", place = function(who) asked = who; return 3, 1 end })
local pOwn, kOwn = S.spawn(ch, "own")
check(asked == ch and pOwn == 3 and kOwn == 1, "a set with its own place() is handed the character and its counts")
check(S.sets.own.label == "IGUI_Own", "a set keeps its own menu label")
S.register("broken", "broken", nil, { place = function() error("boom") end })
check(S.spawn(ch, "broken") == 0, "a place() that errors spawns nothing and does not throw")
S.register("nothing", "nothing", nil, nil)
check(S.sets.nothing == nil, "a set with neither items nor place() is refused")

print(string.format("debugspawn_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
