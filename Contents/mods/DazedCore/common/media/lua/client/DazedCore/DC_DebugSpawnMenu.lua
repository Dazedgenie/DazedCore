--[[ Dazed Core -- the right-click row for DC_DebugSpawn: "Dazed debug" with one "Spawn all ... items" per
     registered set. Shown only to whoever DC_DebugSpawn allows; the authority asks again. ]]

require "DazedCore/DC_DebugSpawn"
require "DazedCore/DC_ClearArea"
require "ISUI/ISModalDialog"

local S = DazedCore.DebugSpawn

local function onSpawn(_, playerObj, id)
    DazedCore.Net.send(playerObj, S.MODULE, S.COMMAND, { set = id })
end

local CA = DazedCore.ClearArea

-- Ask first: the removal can't be undone.
local function onClear(_, playerObj, radius)
    local text = DazedCore.Util.txt("IGUI_DazedCore_ClearAsk", radius)
    local core = getCore()
    local modal = ISModalDialog:new(core:getScreenWidth() / 2 - 175, core:getScreenHeight() / 2 - 75, 350, 150, text, true, nil,
        function(_, button)
            if button.internal == "YES" then DazedCore.Net.send(playerObj, CA.MODULE, CA.COMMAND, { radius = radius }) end
        end, playerObj:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
end

local function onFill(player, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(player)
    if not (playerObj and S.allowed(playerObj)) then return end
    local head = context:addOption(getText("IGUI_DazedCore_Debug"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(head, sub)
    local clearHead = sub:addOption(getText("IGUI_DazedCore_Clear"), worldobjects, nil)
    local clearSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(clearHead, clearSub)
    for _, r in ipairs(CA.RADII) do
        clearSub:addOption(DazedCore.Util.txt("IGUI_DazedCore_ClearRadius", r), worldobjects, onClear, playerObj, r)
    end
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
