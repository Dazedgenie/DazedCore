-- Headless check of ClearArea: what it removes (zombies, vehicles, placed objects, ground items, corpses), what it
-- leaves (floors, walls, trees, the requester's vehicle, anything outside the circle) and who may ask.
-- Run: lua cleararea_test.lua <lua root>
local root = arg[1] or "../../Contents/mods/DazedCore/common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

local function jlist(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end,
             iterator = function()
                 local i = 0
                 return { hasNext = function() return i < #t end, next = function() i = i + 1; return t[i] end }
             end }
end

E.grid(60, 60)
local cx, cy = 30, 30
local classes = {}
instanceof = function(o, cls) return classes[o] and classes[o][cls] or false end

-- squares learn the calls ClearArea makes
local removedFromSquare = {}
for _, sq in pairs(E.squares) do
    sq.worldObjs, sq.bodies = {}, {}
    sq.getFloor = function(s) return s.objs[1] end
    sq.getWorldObjects = function(s) return jlist(s.worldObjs) end
    sq.getDeadBodys = function(s) return jlist(s.bodies) end
    sq.transmitRemoveItemFromSquare = function(s, o) removedFromSquare[o] = true end
    sq.removeCorpse = function(s, b) for i, v in ipairs(s.bodies) do if v == b then table.remove(s.bodies, i) return end end end
end
local function floorAt(x, y)
    local sq = E.square(x, y)
    local f = E.object("floors_interior_01", sq)
    return sq, f
end
local function prop(o, names)
    o.getProperties = function() return { Is = function(_, n) return names[n] == true end } end
end

local zombies, vehicles = {}, {}
getCell = function()
    return { getGridSquare = function(_, x, y, z) return E.squares[x .. "," .. y .. "," .. z] end,
             getZombieList = function() return jlist(zombies) end,
             getVehicles = function() return jlist(vehicles) end }
end

-- a crate 3 tiles away (moveable), a wall and a tree next to it, a generator 25 tiles out (outside r=10)
local sqA = floorAt(cx + 3, cy)
local crate = E.object("furniture_crate_01", sqA); prop(crate, { IsMoveAble = true })
local wall = E.object("walls_01_0", sqA); prop(wall, { WallN = true, IsMoveAble = true })
local tree = E.object("e_tree_01", sqA); prop(tree, {}); classes[tree] = { IsoTree = true }
local thump = E.object("carpentry_02_0", sqA); prop(thump, {}); classes[thump] = { IsoThumpable = true }
local door = E.object("door_01", sqA); prop(door, { doorN = true }); classes[door] = { IsoThumpable = true }
local bare = E.object("decor_01", sqA); prop(bare, {})                       -- plain map decor: stays
local item = { name = "ground item" }
table.insert(sqA.worldObjs, item)
item.removeFromWorld = function() item.gone = true end
item.removeFromSquare = function() item.unlinked = true end
local body = { name = "corpse" }; table.insert(sqA.bodies, body)

local sqFar = floorAt(cx + 25, cy)
local farCrate = E.object("furniture_crate_01", sqFar); prop(farCrate, { IsMoveAble = true })

local sqUp = E.square(cx + 1, cy, 1)                                         -- an upper floor in range
sqUp.worldObjs, sqUp.bodies = {}, {}
sqUp.getFloor = sqA.getFloor; sqUp.getWorldObjects = sqA.getWorldObjects; sqUp.getDeadBodys = sqA.getDeadBodys
sqUp.transmitRemoveItemFromSquare = sqA.transmitRemoveItemFromSquare; sqUp.removeCorpse = sqA.removeCorpse
E.object("floors_interior_01", sqUp)
local shelf = E.object("furniture_shelf", sqUp); prop(shelf, { IsMoveAble = true })

local function zombie(x, y)
    local z = { x = x, y = y, getX = function(s) return s.x end, getY = function(s) return s.y end }
    z.removeFromWorld = function(s) s.gone = true end
    z.removeFromSquare = function(s) s.unlinked = true end
    zombies[#zombies + 1] = z
    return z
end
local zNear, zFar = zombie(cx + 4, cy + 4), zombie(cx + 40, cy)
local function vehicle(x, y)
    local v = { x = x, y = y, getX = function(s) return s.x end, getY = function(s) return s.y end }
    v.permanentlyRemove = function(s) s.gone = true end
    vehicles[#vehicles + 1] = v
    return v
end
local vNear, vFar, vOwn = vehicle(cx - 5, cy), vehicle(cx + 50, cy), vehicle(cx + 1, cy + 1)

local C = require "DazedCore/DC_ClearArea"
local S = require "DazedCore/DC_DebugSpawn"
local ch = E.character(cx, cy, 0)
ch.getVehicle = function() return vOwn end

local n = C.clear(ch, 10)
check(n.zombies == 1 and zNear.gone and zNear.unlinked and not zFar.gone, "a near zombie goes, a far one stays")
check(n.vehicles == 1 and vNear.gone and not vFar.gone, "a near vehicle goes, a far one stays")
check(not vOwn.gone, "the requester's own vehicle stays")
check(n.placed == 3 and removedFromSquare[crate] and removedFromSquare[thump] and removedFromSquare[shelf],
    "moveables, built objects and an upper floor's furniture go: " .. n.placed)
check(#sqA.objs == 5 and not removedFromSquare[wall] and not removedFromSquare[tree] and not removedFromSquare[door]
    and not removedFromSquare[bare], "floor, wall, tree, door and plain decor stay")
check(sqFar.objs[2] == farCrate, "a crate outside the circle stays")
check(n.items == 1 and item.gone and item.unlinked and removedFromSquare[item], "a ground item is removed and synced")
check(n.corpses == 1 and #sqA.bodies == 0, "a corpse is removed")

check(C.clampRadius(99) == 30 and C.clampRadius(0) == 0 and C.clampRadius("x") == 0 and C.clampRadius(7.9) == 7,
    "radius is clamped to 1..30")
check(C.inside(3, 4, 0, 0, 5) and not C.inside(4, 4, 0, 0, 5), "the area is a circle")

------------------------------------------------------------------ the request
local N = require "DazedCore/DC_Net"
getTimestampMs = function() return 100000 end
getDebug = function() return false end
local outsider = E.character(cx, cy, 0)
local z3 = zombie(cx + 2, cy)
N.send(outsider, C.MODULE, C.COMMAND, { radius = 10 })
check(not z3.gone, "the authority refuses a player who may not")
getDebug = function() return true end
getTimestampMs = function() return 200000 end
N.send(ch, C.MODULE, C.COMMAND, { radius = 10 })
check(z3.gone, "debug mode may clear")
local z4 = zombie(cx + 2, cy)
getTimestampMs = function() return 300000 end
N.send(ch, C.MODULE, C.COMMAND, { radius = 0 })
check(not z4.gone, "a zero radius clears nothing")
getTimestampMs = function() return 400000 end
N.send(ch, C.MODULE, C.COMMAND, { radius = 999 })
check(z4.gone, "an oversized radius is clamped, not refused")

print(string.format("cleararea_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
