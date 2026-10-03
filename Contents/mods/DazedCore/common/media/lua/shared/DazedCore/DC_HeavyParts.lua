--[[ Dazed Utilities: Core -- anything over LIMIT kg is carried as parts like a bed or shelving
     ("Propane Generator (1/2)"), and placing it needs every part on you.

     Version 2 of the DazedHeavy library that Plumbing 0.9 and Dazed Power 0.9 each shipped a copy
     of. The newest copy loaded wins and upgrades an older one in place, so a mod still carrying
     version 1 keeps working alongside this one. ]]

local VERSION = 2
if DazedHeavy and (DazedHeavy.VERSION or 0) >= VERSION then
    DazedCore = DazedCore or {}
    DazedCore.Heavy = DazedHeavy
    return DazedHeavy
end
DazedHeavy = DazedHeavy or {}
DazedCore = DazedCore or {}
DazedCore.Heavy = DazedHeavy
local H = DazedHeavy
H.VERSION = VERSION
H.LIMIT = 30                                -- most one part may weigh, in kg
H.KEY = "dazedParts"                        -- item ModData: { i = this part, n = how many }
H.prefixes = H.prefixes or {}

--- A mod names the item types it owns (a prefix such as "Base.Dazed"); only those are ever split.
function H.register(prefix) H.prefixes[prefix] = true end

local function owned(fullType)
    if type(fullType) ~= "string" then return false end
    for p in pairs(H.prefixes) do
        if string.sub(fullType, 1, #p) == p then return true end
    end
    return false
end

--- The weight a whole one of this item has (its script weight), or nil.
local function wholeWeight(item)
    local ok, s = pcall(function() return item:getScriptItem() end)
    local w = ok and s and select(2, pcall(function() return s:getActualWeight() end))
    if type(w) ~= "number" then w = item.getActualWeight and item:getActualWeight() end
    return type(w) == "number" and w or nil
end

function H.partsOf(item)
    local md = item and item.getModData and item:getModData()
    return md and md[H.KEY] or nil
end

--- How many parts a whole item of this weight comes in (1 means it is carried whole).
function H.count(weight) return math.max(1, math.ceil((weight or 0) / H.LIMIT - 1e-6)) end

local function sync(item)
    if item.syncItemFields then pcall(item.syncItemFields, item) end
    if sendItemStats then pcall(sendItemStats, item) end
end

local function label(item, i, n)
    local ok, s = pcall(function() return item:getScriptItem():getDisplayName() end)
    local base = ok and s or item:getDisplayName()
    return string.format("%s (%d/%d)", tostring(base), i, n)
end

--- Make an item part i of n: its name and its share of the weight.
local function mark(item, i, n, whole)
    item:getModData()[H.KEY] = { i = i, n = n }
    pcall(item.setName, item, label(item, i, n))
    pcall(item.setCustomName, item, true)
    pcall(item.setActualWeight, item, whole / n)
    pcall(item.setWeight, item, whole / n)
    pcall(item.setCustomWeight, item, true)
end

--- Split one whole heavy item in `inv` into parts (authority). The parts share its ModData, so its state rides along.
function H.split(item, inv)
    if not (item and inv) or H.partsOf(item) or not owned(item:getFullType()) then return false end
    local whole = wholeWeight(item)
    local n = H.count(whole)
    if n < 2 then return false end
    mark(item, 1, n, whole)
    sync(item)
    for i = 2, n do
        local extra = instanceItem and instanceItem(item:getFullType())
        if extra then
            local src, dst = item:getModData(), extra:getModData()
            for k, v in pairs(src) do if k ~= H.KEY then dst[k] = v end end
            if extra.setCondition and item.getCondition then pcall(extra.setCondition, extra, item:getCondition()) end
            mark(extra, i, n, whole)
            inv:AddItem(extra)
            if sendAddItemToContainer then sendAddItemToContainer(inv, extra) end
        end
    end
    return true
end

--- Every whole heavy item a character carries, split (bags included).
function H.splitAll(character)
    local inv = character and character.getInventory and character:getInventory()
    if not inv then return end
    local function walk(cont)
        local items = cont:getItems()
        local list = {}
        for k = 0, items:size() - 1 do list[#list + 1] = items:get(k) end
        for _, it in ipairs(list) do
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then walk(it:getInventory())
            else H.split(it, cont) end
        end
    end
    walk(inv)
end

--- The parts of a set a character has on them: { [i] = item } for items of `fullType` with `n` parts.
function H.gather(character, fullType, n)
    local found = {}
    local function walk(cont)
        local items = cont:getItems()
        for k = 0, items:size() - 1 do
            local it = items:get(k)
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then walk(it:getInventory())
            elseif it:getFullType() == fullType then
                local p = H.partsOf(it)
                if p and p.n == n and not found[p.i] then found[p.i] = it end
            end
        end
    end
    walk(character:getInventory())
    return found
end

--- Has the character every part of this item's set?
function H.complete(character, item)
    local p = H.partsOf(item)
    if not p then return true end
    local found = H.gather(character, item:getFullType(), p.n)
    for i = 1, p.n do if not found[i] then return false end end
    return true
end

--- Placing: take the other parts away, and leave the placed one whole again.
function H.consume(character, item)
    local p = H.partsOf(item)
    if not p then return end
    local found = H.gather(character, item:getFullType(), p.n)
    for i = 1, p.n do
        local it = found[i]
        if it and it ~= item then
            local cont = it:getContainer()
            if cont then
                cont:Remove(it)
                if sendRemoveItemFromContainer then sendRemoveItemFromContainer(cont, it) end
            end
        end
    end
    item:getModData()[H.KEY] = nil
end

------------------------------------------------------------ the game's pick-up and placing
pcall(require, "Moveables/ISMoveableSpriteProps")       -- absent in a headless test

--- Up to 42.20 the place calls are handed (square, item, ...); from 42.21 the character comes first.
local function placeArgs(a1, a2, a3)
    if instanceof and instanceof(a2, "IsoGridSquare") then return a1, a2, a3 end
    return nil, a1, a2
end

--- The character placing, when the engine does not pass one: the local player on this side.
local function placer(character)
    if character then return character end
    return getSpecificPlayer and getSpecificPlayer(0) or nil
end

if ISMoveableSpriteProps and not H.wrapped2 then
    H.wrapped2 = true

    -- After a pick-up, the new item comes apart at once (the minute check below catches crafting and loot).
    local pick0 = ISMoveableSpriteProps.pickUpMoveable
    function ISMoveableSpriteProps:pickUpMoveable(character, ...)
        local a, b = pick0(self, character, ...)
        if character and (not isClient or not isClient()) then pcall(H.splitAll, character) end
        return a, b
    end

    -- A part can only go down with all its fellows on you.
    local canPlace0 = ISMoveableSpriteProps.canPlaceMoveableInternal
    function ISMoveableSpriteProps:canPlaceMoveableInternal(...)
        local character, _, item = placeArgs(...)
        character = placer(character)
        if item and H.partsOf(item) and character and not H.complete(character, item) then return false end
        return canPlace0(self, ...)
    end

    local place0 = ISMoveableSpriteProps.placeMoveableInternal
    function ISMoveableSpriteProps:placeMoveableInternal(...)
        local character, _, item = placeArgs(...)
        character = placer(character)
        if item and H.partsOf(item) and character then
            if not H.complete(character, item) then return end
            H.consume(character, item)
        end
        return place0(self, ...)
    end
end

-- Whatever reached an inventory whole (crafted, looted, an older save) comes apart within a minute.
local function sweep()
    if isClient and isClient() then return end
    local players = {}
    if getOnlinePlayers and isServer and isServer() then
        local list = getOnlinePlayers()
        for k = 0, list:size() - 1 do players[#players + 1] = list:get(k) end
    else
        for k = 0, (getNumActivePlayers and getNumActivePlayers() or 1) - 1 do
            local p = getSpecificPlayer(k)
            if p then players[#players + 1] = p end
        end
    end
    for _, p in ipairs(players) do pcall(H.splitAll, p) end
end
if Events and Events.EveryOneMinute and not H.swept then
    H.swept = true
    Events.EveryOneMinute.Add(sweep)
end

return H
