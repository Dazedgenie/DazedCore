--[[ Dazed Core -- the right-click row for DC_DebugSpawn: "Dazed debug" with one "Spawn all ... items" per
     registered set. Shown only to whoever DC_DebugSpawn allows; the authority asks again. ]]

require "DazedCore/DC_DebugSpawn"

local S = DazedCore.DebugSpawn

local function onSpawn(_, playerObj, id)
    DazedCore.Net.send(playerObj, S.MODULE, S.COMMAND, { set = id })
end

local function onFill(player, context, worldobjects, test)
    if test or #S.order == 0 then return end
    local playerObj = getSpecificPlayer(player)
    if not (playerObj and S.allowed(playerObj)) then return end
    local head = context:addOption(getText("IGUI_DazedCore_Debug"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(head, sub)
    for _, id in ipairs(S.order) do
        local set = S.sets[id]
        local label = set.label and getText(set.label) or DazedCore.Util.txt("IGUI_DazedCore_DebugSpawn", set.name)
        sub:addOption(label, worldobjects, onSpawn, playerObj, id)
    end
end

if Events and Events.OnFillWorldObjectContextMenu and not S.menuHooked then
    S.menuHooked = true
    Events.OnFillWorldObjectContextMenu.Add(onFill)
end
