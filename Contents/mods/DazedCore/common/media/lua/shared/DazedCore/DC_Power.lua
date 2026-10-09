--[[ Dazed Core -- the power registry the Dazed mods talk through.

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
W.nameMemo = {}                        -- load id -> sprite name -> true | false, for `byName` loads
W.NAME_MEMO_MAX = 2048                 -- names remembered per load before its memo starts over
local memoSize = {}
W.legacyHook = nil                      -- an older add-on's single hook (Dazed Power 0.9 set DazedPlumb.externalPower)

--- A provider: { id = "dazedpower_wire", isPowered = function(obj) ... end }.
function W.registerProvider(p)
    if type(p) ~= "table" or type(p.id) ~= "string" or type(p.isPowered) ~= "function" then return nil end
    W.providers[p.id] = p
    return p
end

--- A load: { id, kind = "waterpump", match(obj), watts(obj) -> rated W, working(obj) -> bool, items = {...} }.
--  `kind` names the LOADS-page label (IGUI_DazedPower_Load_<kind>); `items` lists the item types it is placed from.
--  Optional speed-ups: `prefix` (sprite names must start with it) and `matchName(spriteName)` are tested before `match`,
--  and `byName = true` says `match` depends on the sprite name alone, so its verdict is remembered per name.
function W.registerLoad(l)
    if type(l) ~= "table" or type(l.id) ~= "string" or type(l.match) ~= "function" then return nil end
    if not W.loads[l.id] then W.order[#W.order + 1] = l.id end
    l.kind = l.kind or l.id
    W.loads[l.id] = l
    W.nameMemo[l.id] = nil
    memoSize[l.id] = nil
    return l
end

-- The object's sprite name, or nil.
local function spriteName(obj)
    local n = U.try(U.try(obj, "getSprite"), "getName")
    if type(n) == "string" then return n end
    return nil
end

-- Could load l apply to a sprite named `name`? Loads without name hints always could.
local function nameFits(l, name)
    if l.prefix ~= nil then
        if name == nil or string.sub(name, 1, #l.prefix) ~= l.prefix then return false end
    end
    if l.matchName ~= nil then
        if name == nil then return false end
        local ok, hit = pcall(l.matchName, name)
        if not (ok and hit) then return false end
    end
    return true
end

-- Does load l match obj? A `byName` load's verdict is remembered per sprite name.
local function matches(l, obj, name)
    if not nameFits(l, name) then return false end
    local memo = (l.byName and name ~= nil) and W.nameMemo[l.id] or nil
    if l.byName and name ~= nil and not memo then
        memo = {}
        W.nameMemo[l.id] = memo
        memoSize[l.id] = 0
    end
    if memo then
        local v = memo[name]
        if v ~= nil then return v end
    end
    local ok, hit = pcall(l.match, obj)
    local v = (ok and hit) and true or false
    if memo and ok then
        if (memoSize[l.id] or 0) >= W.NAME_MEMO_MAX then
            memo = {}
            W.nameMemo[l.id] = memo
            memoSize[l.id] = 0
        end
        memo[name] = v
        memoSize[l.id] = (memoSize[l.id] or 0) + 1
    end
    return v
end

--- The load record for an object, or nil. The record is the registered table itself: read it, never change it.
function W.loadOf(obj)
    if not obj then return nil end
    local name, named = nil, false
    for _, id in ipairs(W.order) do
        local l = W.loads[id]
        if l.prefix ~= nil or l.matchName ~= nil or l.byName then
            if not named then name, named = spriteName(obj), true end
            if matches(l, obj, name) then return l end
        else
            local ok, hit = pcall(l.match, obj)
            if ok and hit then return l end
        end
    end
    return nil
end

--- Forget every remembered `byName` verdict, e.g. after a load's rules change at run time.
function W.clearNameMemo()
    W.nameMemo = {}
    memoSize = {}
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
