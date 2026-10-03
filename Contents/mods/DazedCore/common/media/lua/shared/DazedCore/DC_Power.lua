--[[ Dazed Utilities: Core -- the power registry the Dazed mods talk through.

     Two sides never name each other. A mod that MAKES power (Dazed Power's controllers) registers
     a PROVIDER: asked about an object, it answers true when it feeds that object by wire, nil when
     the object is none of its business. A mod with a machine that NEEDS power (Plumbing's electric
     pump and purifier, a grow light) registers a LOAD: how to recognise the machine, its rated
     watts, and whether it is working right now. The power mod bills loads it is wired to; anything
     else runs off a powered square, as vanilla appliances do. ]]

require "DazedCore/DC_Util"

DazedCore.Power = DazedCore.Power or {}
local W = DazedCore.Power
local U = DazedCore.Util

W.providers = W.providers or {}        -- id -> { id, isPowered(obj) -> true | false | nil }
W.loads = W.loads or {}                -- id -> { id, kind, match(obj), watts(obj), working(obj), items }
W.order = W.order or {}                -- load ids in registration order
W.legacyHook = nil                      -- an older add-on's single hook (Dazed Power 0.9 set DazedPlumb.externalPower)

--- A provider: { id = "dazedpower_wire", isPowered = function(obj) ... end }.
function W.registerProvider(p)
    if type(p) ~= "table" or type(p.id) ~= "string" or type(p.isPowered) ~= "function" then return nil end
    W.providers[p.id] = p
    return p
end

--- A load: { id, kind = "waterpump", match(obj), watts(obj) -> rated W, working(obj) -> bool, items = {...} }.
--  `kind` names the LOADS-page label (IGUI_DazedPower_Load_<kind>); `items` lists the item types it is placed from.
function W.registerLoad(l)
    if type(l) ~= "table" or type(l.id) ~= "string" or type(l.match) ~= "function" then return nil end
    if not W.loads[l.id] then W.order[#W.order + 1] = l.id end
    l.kind = l.kind or l.id
    W.loads[l.id] = l
    return l
end

--- The load record for an object, or nil.
function W.loadOf(obj)
    if not obj then return nil end
    for _, id in ipairs(W.order) do
        local l = W.loads[id]
        local ok, hit = pcall(l.match, obj)
        if ok and hit then return l end
    end
    return nil
end

--- Does a provider feed this object by wire? (The square is not asked.)
function W.wired(obj)
    if not obj then return false end
    for _, p in pairs(W.providers) do
        local ok, on = pcall(p.isPowered, obj)
        if ok and on == true then return true end
    end
    if W.legacyHook then
        local ok, on = pcall(W.legacyHook, obj)
        if ok and on == true then return true end
    end
    return false
end

--- Has this object power: by wire, or from the square it stands on (town grid or a generator)?
function W.isPowered(obj)
    if W.wired(obj) then return true end
    local sq = U.try(obj, "getSquare")
    return sq ~= nil and U.try(sq, "haveElectricity") == true
end

--- Rated watts of a registered load, or 0.
function W.rated(obj, l)
    l = l or W.loadOf(obj)
    if not l then return 0 end
    local ok, w = pcall(l.watts, obj)
    return (ok and tonumber(w)) or 0
end

--- Watts a registered load draws right now: its rating while working, else 0.
function W.draw(obj, l)
    l = l or W.loadOf(obj)
    if not l then return 0 end
    local ok, on = pcall(l.working, obj)
    if ok and on then return W.rated(obj, l) end
    return 0
end

return W
