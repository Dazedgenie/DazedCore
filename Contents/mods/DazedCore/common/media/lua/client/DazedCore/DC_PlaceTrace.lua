--[[ Dazed Core -- why the Place cursor shows no ghost for a Dazed item.

     When the moveable cursor in place mode has a Dazed item selected but shows only the white box, one console
     line says what it was looking at, so a placement that silently fails can be traced. ]]

require "DazedCore/DC_HeavyParts"

local H = DazedCore.Heavy

local function isDazed(item)
    local t = item and item.getFullType and item:getFullType()
    -- Anchored find: no substring is made on the per-frame cursor check.
    return type(t) == "string" and string.find(t, "^Base%.Dazed") ~= nil
end

local function hook()
    if not ISMoveableCursor or ISMoveableCursor.dazedTraced then return end
    ISMoveableCursor.dazedTraced = true
    local valid0 = ISMoveableCursor.isValid
    function ISMoveableCursor:isValid(square, ...)
        local ok = valid0(self, square, ...)
        if ISMoveableCursor.mode[self.player] ~= "place" or self.currentMoveProps then return ok end
        local objs = self.objectListCache
        local entry = objs and objs[self.objectIndex or 1]
        local item = entry and entry.object
        if item and isDazed(item) then
            local inv = self.character and self.character:getInventory()
            H.say(string.format("place cursor shows nothing for %s (%s): %d in list, index %s, in inventory %s, sprite %s",
                tostring(item:getFullType()), tostring(item:getName()), #objs, tostring(self.objectIndex),
                tostring(inv and inv:getItemById(item:getID()) ~= nil), tostring(item:getWorldSprite())))
        elseif objs and #objs == 0 and square then
            H.say("place cursor: no placeable items found in the main inventory")
        end
        return ok
    end
end

Events.OnGameStart.Add(hook)
