--[[ Dazed Utilities: Core -- anything over LIMIT kg is carried as parts like a bed or shelving
     ("Propane Generator (1/2)"), and placing it needs every part on you.

     Version 2 of the DazedHeavy library that Plumbing 0.9 and Dazed Power 0.9 each shipped a copy
     of. The newest copy loaded wins and upgrades an older one in place, so a mod still carrying
     version 1 keeps working alongside this one. ]]

local VERSION = 3
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

-- Item type -> owned or not, so the sweep asks each type once rather than per item and per prefix.
local ownedMemo, memoPrefixes, memoCount = {}, nil, -1

--- Drop the remembered answers when the registered prefixes are not the ones they were made from.
local function checkOwnedMemo()
    local n = 0
    for _ in pairs(H.prefixes) do n = n + 1 end
    if n ~= memoCount or memoPrefixes ~= H.prefixes then
        ownedMemo, memoPrefixes, memoCount = {}, H.prefixes, n
    end
end

--- A mod names the item types it owns (a prefix such as "Base.Dazed"); only those are ever split.
function H.register(prefix)
    H.prefixes[prefix] = true
    ownedMemo, memoCount = {}, -1
end

local function ownedUncached(fullType)
    for p in pairs(H.prefixes) do
        if string.sub(fullType, 1, #p) == p then return true end
    end
    return false
end

local function owned(fullType)
    if type(fullType) ~= "string" then return false end
    local hit = ownedMemo[fullType]
    if hit == nil then
        hit = ownedUncached(fullType)
        ownedMemo[fullType] = hit
    end
    return hit
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
--  Only items of a registered type are touched; the lists are made only when a container has something to do.
local function walkSplit(cont)
    local items = cont:getItems()
    local bags, todo = nil, nil
    for k = 0, items:size() - 1 do
        local it = items:get(k)
        if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then
            bags = bags or {}
            bags[#bags + 1] = it
        elseif owned(it:getFullType()) then
            todo = todo or {}
            todo[#todo + 1] = it
        end
    end
    -- Collected before any split, so the parts a split adds are not walked again (the old copy-the-list rule).
    if bags then for i = 1, #bags do walkSplit(bags[i]:getInventory()) end end
    if todo then for i = 1, #todo do H.split(todo[i], cont) end end
end

function H.splitAll(character)
    local inv = character and character.getInventory and character:getInventory()
    if not inv then return end
    checkOwnedMemo()
    walkSplit(inv)
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

-- The place cursor asks H.complete every frame; its answer is kept briefly and dropped when the main inventory changes size.
H.COMPLETE_TTL_MS = 250
local completeMemo = nil         -- the last answer: { item, ch, at, size, yes }; the cursor only ever asks about one item

--- H.complete for the per-frame cursor check. Placing itself always asks H.complete afresh.
function H.completeCached(character, item)
    local now = getTimestampMs and getTimestampMs()
    if type(now) ~= "number" or now <= 0 then return H.complete(character, item) end
    local inv = character.getInventory and character:getInventory()
    local items = inv and inv.getItems and inv:getItems()
    local size = items and items:size() or -1
    local c = completeMemo
    if c and c.item == item and c.ch == character and c.size == size and now >= c.at and now - c.at < H.COMPLETE_TTL_MS then
        return c.yes
    end
    local yes = H.complete(character, item)
    completeMemo = { item = item, ch = character, at = now, size = size, yes = yes }
    return yes
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

-- One console line per message every few seconds, so a refusal shows in console.txt without flooding it.
local said = {}
function H.say(msg)
    local now = getTimestampMs and getTimestampMs() or 0
    if said[msg] and now - said[msg] < 5000 then return end
    said[msg] = now
    print("DazedCore: " .. msg)
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

    -- After a pick-up, the new item comes apart at once (the ten-minute sweep below catches crafting and loot).
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
        if item and H.partsOf(item) and character and not H.completeCached(character, item) then
            H.say("can't place " .. tostring(item.getFullType and item:getFullType()) .. ": not every part is on you")
            return false
        end
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

-- A 2x2 piece of furniture (ForceSingleItem) is looked up by its whole name, "Name (1/1)"; a part set
-- carries "Name (1/2)", so the first part of a complete set stands in for the whole item.
if ISMoveableSpriteProps and ISMoveableSpriteProps.findInInventoryMultiSprite and not H.wrapped3 then
    H.wrapped3 = true
    local find0 = ISMoveableSpriteProps.findInInventoryMultiSprite
    function ISMoveableSpriteProps:findInInventoryMultiSprite(character, name, ...)
        local a, b = find0(self, character, name, ...)
        if a or not (character and self.customItem and type(name) == "string") then return a, b end
        if string.sub(name, -6) ~= " (1/1)" then return a, b end
        local inv = character:getInventory()
        local items = inv and inv:getItems()
        for k = 0, (items and items:size() or 0) - 1 do
            local it = items:get(k)
            local p = it:getFullType() == self.customItem and H.partsOf(it)
            if p and p.i == 1 and character:getPrimaryHandItem() ~= it and character:getSecondaryHandItem() ~= it
                    and H.complete(character, it) then
                return it, inv
            end
        end
        return a, b
    end
end

-- Whatever reached an inventory whole (crafted, looted, an older save) comes apart within ten game minutes.
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
if Events and Events.EveryTenMinutes and not H.swept then
    H.swept = true
    Events.EveryTenMinutes.Add(sweep)
end

return H
