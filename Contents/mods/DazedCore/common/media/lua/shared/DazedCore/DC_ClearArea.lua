--[[ Dazed Core -- clear area: a debug action that empties a circle around the player.

     It removes, on the authority, every zombie (and corpse), every vehicle, every placed or moveable world
     object (furniture, crates, generators, built items) and every loose item lying on the ground within a
     radius the user picks. Walls, floors, doors, windows, stairs and trees are map structure and stay. A
     vehicle the requester sits in stays too. The right-click menu (DC_DebugSpawnMenu) asks for a yes first;
     the authority checks DebugSpawn.allowed again, so only debug mode or staff get through. ]]

require "DazedCore/DC_Util"
require "DazedCore/DC_Net"
require "DazedCore/DC_Note"
require "DazedCore/DC_DebugSpawn"

DazedCore = DazedCore or {}
DazedCore.ClearArea = DazedCore.ClearArea or {}
local C = DazedCore.ClearArea
local U = DazedCore.Util
local try = U.try

C.MODULE, C.COMMAND = "DazedCore", "clearArea"
C.RADII = { 5, 10, 20, 30 }     -- what the menu offers
C.MAX_RADIUS = 30
C.MAX_Z = 7

-- Properties of map structure, never removed.
local STRUCTURE = {
    "WallN", "WallW", "WallNW", "WallSE", "WallNTrans", "WallWTrans", "DoorWallN", "DoorWallW",
    "windowN", "windowW", "doorN", "doorW", "StairsTW", "StairsMW", "StairsBW", "StairsTN", "StairsMN", "StairsBN",
}
local STRUCTURE_CLASSES = { "IsoWall", "IsoDoor", "IsoWindow", "IsoStairs", "IsoTree", "IsoCurtain", "IsoBarricade", "IsoZombie", "IsoPlayer" }

local function props(o)
    local p = try(o, "getProperties")
    return p
end

local function isStructure(o, floor)
    if o == floor then return true end
    local sprite = try(o, "getSpriteName")
    if type(sprite) == "string" and (sprite:find("^floors_") or sprite:find("^blends_")) then return true end
    if instanceof then
        for _, cls in ipairs(STRUCTURE_CLASSES) do
            if instanceof(o, cls) then return true end
        end
    end
    local p = props(o)
    if p and p.Is then
        for _, name in ipairs(STRUCTURE) do
            if try(p, "Is", name) == true then return true end
        end
    end
    return false
end

--- Is this square object something a player put there: furniture and other moveables, built (thumpable)
--  objects and generators, once map structure is ruled out?
function C.isPlaced(o, floor)
    if not o or isStructure(o, floor) then return false end
    if instanceof and (instanceof(o, "IsoThumpable") or instanceof(o, "IsoGenerator")) then return true end
    local p = props(o)
    return p ~= nil and p.Is ~= nil and try(p, "Is", "IsMoveAble") == true
end

--- Square distance test: inside a circle of `r` tiles around cx, cy (square centres).
function C.inside(x, y, cx, cy, r)
    local dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r
end

local function clampRadius(r)
    r = math.floor(tonumber(r) or 0)
    if r < 1 then return 0 end
    return math.min(r, C.MAX_RADIUS)
end
C.clampRadius = clampRadius

-- Every item of a java list into a Lua table, so the list can change while we work on the copy.
local function snapshot(list)
    local out = {}
    if not list then return out end
    local n = try(list, "size") or 0
    for i = 0, n - 1 do out[#out + 1] = list:get(i) end
    return out
end

local function removeObject(sq, o)
    pcall(function()
        if sq.transmitRemoveItemFromSquare then sq:transmitRemoveItemFromSquare(o) end
        if sq.RemoveTileObject then sq:RemoveTileObject(o) end
    end)
end

local function removeWorldItem(sq, w)
    pcall(function()
        if sq.transmitRemoveItemFromSquare then sq:transmitRemoveItemFromSquare(w) end
        if w.removeFromWorld then w:removeFromWorld() end
        if w.removeFromSquare then w:removeFromSquare() end
    end)
end

local function removeCorpse(sq, body)
    pcall(function()
        if sq.removeCorpse then sq:removeCorpse(body, false)
        else removeObject(sq, body) end
    end)
end

--- Clear the area (authority). Returns { zombies, corpses, vehicles, placed, items }.
function C.clear(character, radius)
    local out = { zombies = 0, corpses = 0, vehicles = 0, placed = 0, items = 0 }
    local r = clampRadius(radius)
    local cell = getCell and getCell()
    if not (character and cell and r > 0) then return out end
    local cx, cy = try(character, "getX") or 0, try(character, "getY") or 0

    -- zombies: collect, then remove
    local doomed = {}
    for _, z in ipairs(snapshot(try(cell, "getZombieList"))) do
        if C.inside(try(z, "getX") or 1e9, try(z, "getY") or 1e9, cx, cy, r) then doomed[#doomed + 1] = z end
    end
    for _, z in ipairs(doomed) do
        pcall(function()
            if z.removeFromWorld then z:removeFromWorld() end
            if z.removeFromSquare then z:removeFromSquare() end
        end)
        out.zombies = out.zombies + 1
    end

    -- vehicles: B42's list is a HashSet, so walk its iterator, and never remove the one the requester drives
    local own = try(character, "getVehicle")
    local vlist = try(cell, "getVehicles")
    local cars = {}
    if vlist and vlist.iterator then
        local it = vlist:iterator()
        while it:hasNext() do
            local v = it:next()
            if v ~= own and C.inside(try(v, "getX") or 1e9, try(v, "getY") or 1e9, cx, cy, r) then cars[#cars + 1] = v end
        end
    end
    for _, v in ipairs(cars) do
        if pcall(function() v:permanentlyRemove() end) then out.vehicles = out.vehicles + 1 end
    end

    -- squares: placed objects, loose items, corpses
    local x0, y0 = math.floor(cx), math.floor(cy)
    for x = x0 - r, x0 + r do
        for y = y0 - r, y0 + r do
            if C.inside(x + 0.5, y + 0.5, cx, cy, r) then
                for z = 0, C.MAX_Z do
                    local sq = cell:getGridSquare(x, y, z)
                    if sq then
                        local floor = try(sq, "getFloor")
                        for _, o in ipairs(snapshot(try(sq, "getObjects"))) do
                            if C.isPlaced(o, floor) then removeObject(sq, o); out.placed = out.placed + 1 end
                        end
                        for _, w in ipairs(snapshot(try(sq, "getWorldObjects"))) do
                            removeWorldItem(sq, w); out.items = out.items + 1
                        end
                        for _, b in ipairs(snapshot(try(sq, "getDeadBodys"))) do
                            removeCorpse(sq, b); out.corpses = out.corpses + 1
                        end
                    end
                end
            end
        end
    end
    return out
end

DazedCore.Net.on(C.MODULE, C.COMMAND, function(player, args)
    if not DazedCore.DebugSpawn.allowed(player) then return end
    local r = clampRadius(args.radius)
    if r == 0 then return end
    local n = C.clear(player, r)
    local name = try(player, "getUsername")
    print(string.format("DazedCore: clear area by %s r=%d at %d,%d -- %d zombies, %d corpses, %d vehicles, %d placed, %d items",
        tostring(name), r, math.floor(try(player, "getX") or 0), math.floor(try(player, "getY") or 0),
        n.zombies, n.corpses, n.vehicles, n.placed, n.items))
    DazedCore.Note.say(player, "IGUI_DazedCore_ClearDone", { n.zombies + n.corpses, n.vehicles, n.placed, n.items, r })
end, 3000)

return C
