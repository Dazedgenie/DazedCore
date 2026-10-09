-- Headless check of DC_Reach footprints and DC_Buildings' codec, reach test and map-building resolver
-- against a stand-in metagrid. Run: lua buildings_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

-- A metagrid with one two-room house (rooms 10..19 x 10..14 and 10..19 x 15..19 on z 0, one room upstairs)
-- and its basement, plus a shed far away.
local function List(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local function Rect(x, y, w, h) return { getX = function() return x end, getY = function() return y end, getW = function() return w end, getH = function() return h end } end
local function Room(z, rects, def) return { getZ = function() return z end, getRects = function() return List(rects) end, isUserDefined = function() return false end, getBuilding = function() return def end } end
local function Def(x, y, w, h, basement)
    local d = { rooms = {} }
    d.getX = function() return x end d.getY = function() return y end d.getW = function() return w end d.getH = function() return h end
    d.getRooms = function() return List(d.rooms) end
    d.isUserDefined = function() return false end
    d.isBasement = function() return basement == true end
    d.getMaxLevel = function() return basement and -1 or 1 end
    return d
end
local house = Def(10, 10, 10, 10)
house.rooms = { Room(0, { Rect(10, 10, 10, 5) }, house), Room(0, { Rect(10, 15, 10, 5) }, house), Room(1, { Rect(10, 10, 10, 10) }, house) }
local cellar = Def(12, 12, 4, 4, true)
cellar.rooms = { Room(-1, { Rect(12, 12, 4, 4) }, cellar) }
local shed = Def(60, 60, 4, 4)
shed.rooms = { Room(0, { Rect(60, 60, 4, 4) }, shed) }
local defs = { house, cellar, shed }
local function roomAt(x, y, z)
    for _, d in ipairs(defs) do
        for _, r in ipairs(d.rooms) do
            if r.getZ() == z then
                local rs = r.getRects()
                for i = 0, rs.size() - 1 do
                    local q = rs.get(nil, i)
                    if x >= q.getX() and x < q.getX() + q.getW() and y >= q.getY() and y < q.getY() + q.getH() then return r end
                end
            end
        end
    end
    return nil
end
getWorld = function()
    return { getMetaGrid = function() return {
        getRoomAt = function(_, x, y, z) return roomAt(x, y, z) end,
        getBuildingsIntersecting = function(_, x, y, w, h, list)
            for _, d in ipairs(defs) do
                if d.getX() < x + w and d.getX() + d.getW() > x and d.getY() < y + h and d.getY() + d.getH() > y then list:add(d) end
            end
        end,
    } end }
end
ArrayList = { new = function() local t = {} return { add = function(_, v) t[#t + 1] = v end, size = function() return #t end, get = function(_, i) return t[i + 1] end } end }
IsoRegions = nil

local R = require "DazedCore/DC_Reach"
local B = require "DazedCore/DC_Buildings"

-- footprints and rects
local fp = R.fpNew()
check(R.fpAdd(fp, 1, 1, 0) and not R.fpAdd(fp, 1, 1, 0), "fpAdd once")
R.fpAdd(fp, 2, 1, 0); R.fpAdd(fp, 1, 2, 0); R.fpAdd(fp, 2, 2, 0); R.fpAdd(fp, 5, 5, 1)
check(R.fpCount(fp) == 5 and R.fpHas(fp, 2, 2, 0) and not R.fpHas(fp, 3, 3, 0), "fp count/has")
local rects = R.rectsOf(fp)
local back = R.fpOfRects(R.decodeRects(R.encodeRects(rects)))
check(R.fpCount(back) == 5 and R.fpHas(back, 5, 5, 1), "rects round-trip through the codec")
local x0, y0, x1, y1, z0, z1 = R.fpBounds(fp)
check(x0 == 1 and y0 == 1 and x1 == 5 and y1 == 5 and z0 == 0 and z1 == 1, "fpBounds")

-- billing owners: the first shape holding a square owns it
local shapes = { R.circleShape(4, 4, 0, 3, 1), R.circleShape(6, 4, 0, 3, 1) }
local ix = R.chunkIndex(shapes)
check(R.owner(shapes, ix, 1, 5, 4, 0) and not R.owner(shapes, ix, 2, 5, 4, 0) and R.owner(shapes, ix, 2, 8, 4, 0), "owner")
local cl = ix["0,0"]
check(R.ownerIn(shapes, cl, 1, 5, 4, 0) and not R.ownerIn(shapes, cl, 2, 5, 4, 0) and R.ownerIn(shapes, cl, 2, 8, 4, 0)
      and not R.ownerIn(shapes, cl, 1, 9, 4, 0) and R.ownerIn(shapes, nil, 2, 5, 4, 0), "ownerIn matches owner with the chunk list in hand")

-- map buildings
local t = B.targetAt(15, 12, 0)
check(t and t.k == "b" and t.def == house, "click in a room picks the house")
local hf = B.footprintOf(t)
check(R.fpHas(hf, 10, 10, 0) and R.fpHas(hf, 19, 19, 0) and R.fpHas(hf, 15, 15, 1), "house footprint covers both floors")
check(R.fpHas(hf, 20, 15, 0) and R.fpHas(hf, 15, 20, 0), "south and east wall shell included")
check(R.fpHas(hf, 13, 13, -1), "basement under the house included")
local tc = B.targetAt(13, 13, -1)
check(tc and tc.def == house, "clicking the basement answers for the house above")
check(B.targetAt(20, 15, 0) and B.targetAt(20, 15, 0).def == house, "a wall-row click (outside the rects) still picks the house")
check(B.targetAt(40, 40, 0) == nil, "nothing in the open")
check(B.reaches(hf, 25, 15, 0, 6, 3) and not B.reaches(hf, 30, 15, 0, 6, 3), "reach: 6 squares from the shell")
check(not B.reaches(hf, 15, 15, 5, 6, 3), "reach: too many floors up")
local near = B.nearestDef(24, 15, 0, 6, 3)
check(near == house, "nearest def within 6")
check(B.nearestDef(66, 66, 0, 6, 3) == shed and B.nearestDef(70, 70, 0, 6, 3) == nil, "nearest def: the shed, and none past 6")
local dt = B.defaultTarget(24, 15, 0, 6, 3)
check(dt and dt.def == house, "default target: nearest reached house")
local list = B.decodeTargets(B.encodeTargets({ t, { k = "s", x = 1, y = 2, z = 0, id = "1,2,0:9" } }))
check(#list == 2 and list[1].k == "b" and list[1].id == t.id and list[2].k == "s" and list[2].id == "1,2,0:9", "targets codec")
local rt = B.resolve("b", t.x, t.y, t.z)
check(rt and rt.id == t.id, "resolve a stored building target")
check(B.predefinedRoomAt(15, 15, 0) and not B.predefinedRoomAt(40, 40, 0), "predefinedRoomAt")

-- player-built structures, against stand-in region data: A (x 20..22, y 10..12) next to B (x 24..26), D above A,
-- O an open lean-to beside B, and M a region that runs into the house's rooms.
local regions, owners = {}, {}
local function Region(name, enclosed, roofed)
    local r = { name = name, crs = {}, nbs = {} }
    r.isEnclosed = function() return enclosed end
    r.getRoofedPercentage = function() return roofed end
    r.getDebugIsoChunkRegionCopy = function() return List(r.crs) end
    r.getNeighbors = function() return List(r.nbs) end
    regions[#regions + 1] = r
    return r
end
local function claim(r, x0, y0, x1, y1, z)
    local cr = { z = z }
    cr.getzLayer = function() return z end
    cr.getDataChunk = function()
        local kx, ky = math.floor(x0 / 8), math.floor(y0 / 8)
        return { getChunkX = function() return kx end, getChunkY = function() return ky end,
                 getSquare = function(_, lx, ly, lz) return owners[(kx * 8 + lx) .. "," .. (ky * 8 + ly) .. "," .. lz] and 1 or 0 end,
                 getIsoChunkRegion = function(_, lx, ly, lz) local o = owners[(kx * 8 + lx) .. "," .. (ky * 8 + ly) .. "," .. lz] return o and o.cr end }
    end
    r.crs[#r.crs + 1] = cr
    for x = x0, x1 do for y = y0, y1 do owners[x .. "," .. y .. "," .. z] = { r = r, cr = cr } end end
end
local A, Bq, D, O, M = Region("A", true, 1), Region("B", true, 0.6), Region("D", true, 1), Region("O", true, 0.2), Region("M", true, 1)
claim(A, 20, 10, 22, 12, 0); claim(Bq, 24, 10, 26, 12, 0); claim(D, 21, 11, 21, 11, 1); claim(O, 24, 13, 26, 13, 0)
claim(M, 18, 2, 21, 3, 0); claim(M, 18, 1, 19, 1, 0)
A.nbs = { Bq }; Bq.nbs = { A, O }; O.nbs = { Bq }
IsoRegions = { getIsoWorldRegion = function(x, y, z) local o = owners[x .. "," .. y .. "," .. z] return o and o.r end }
local sf = B.structureAt(21, 11, 0)
check(sf and R.fpCount(sf) == 19 and R.fpHas(sf, 25, 12, 0) and R.fpHas(sf, 21, 11, 1) and not R.fpHas(sf, 25, 13, 0),
      "structure: two rooms and the floor above, not the open lean-to: " .. tostring(sf and R.fpCount(sf)))
local _, why1 = B.structureAt(15, 15, 0)
local _, why2 = B.structureAt(25, 13, 0)
local _, why3 = B.structureAt(40, 40, 0)
check(why1 == "map" and why2 == "open" and why3 == "none", "structure: map, open and none answers")
house.rooms[#house.rooms + 1] = Room(0, { Rect(18, 1, 2, 1) }, house)
local mf = B.structureAt(20, 2, 0)
check(mf and R.fpCount(mf) == 8 and not R.fpHas(mf, 18, 1, 0), "structure: map-room squares left out")
IsoRegions = nil

print(string.format("buildings_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
