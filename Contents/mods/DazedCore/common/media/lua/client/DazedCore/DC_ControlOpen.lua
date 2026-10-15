--[[ Dazed Core -- the two ways staff open Dazed Control: an icon at the foot of the sidebar, shown only to staff
     (and in debug mode), and a "Dazed Control" button added under the vanilla admin panel's own buttons.
     Neither decides anything: the authority checks every request again (DC_Control). ]]

require "ISUI/ISButton"
require "DazedCore/DC_Control"
require "DazedCore/DC_ControlWindow"

DazedCore = DazedCore or {}
local C = DazedCore.Control

---------------------------------------------------------------- the sidebar icon

local ANCHORS = { "warManagerBtn", "adminBtn", "clientBtn", "safetyBtn", "arfBtn", "debugBtn", "mapBtn", "zoneBtn",
                  "searchBtn", "movableBtn", "buildBtn", "craftingBtn", "healthBtn", "invBtn" }
local SIZES = { 48, 64, 80, 96, 128 }

local function anchorBottom(panel)
    local b = 0
    for _, name in ipairs(ANCHORS) do
        local btn = panel[name]
        if btn and btn.Type == "ISButton" then b = math.max(b, btn:getBottom()) end
    end
    return b
end

local function texture(width)
    local best = SIZES[1]
    for _, s in ipairs(SIZES) do if math.abs(s - width) < math.abs(best - width) then best = s end end
    return getTexture("media/ui/DazedCore/Sidebar/" .. best .. "/Control_" .. best .. ".png")
end

local function detach(panel)
    local btn = panel and panel.dazedControlBtn
    if not btn then return end
    panel:removeChild(btn)
    if panel.mouseOverList then
        for i = #panel.mouseOverList, 1, -1 do
            if panel.mouseOverList[i].object == btn then table.remove(panel.mouseOverList, i) end
        end
    end
    panel.dazedControlBtn = nil
end

local function attach(panel)
    if not (panel and panel.invBtn and panel.chr) then return end
    if not C.level(panel.chr) then detach(panel) return end
    local size = panel.invBtn:getWidth()
    local base = anchorBottom(panel)
    local btn = panel.dazedControlBtn
    if not btn then
        local low = base
        for _, child in pairs(panel:getChildren()) do
            if child.Type == "ISButton" then low = math.max(low, child:getBottom()) end
        end
        local y = low + 15
        local chr = panel.chr
        btn = ISButton:new(0, y, size, size * 0.75, "", panel, function() C.toggle(chr) end)
        btn.dazedOffset = y - base
        btn:initialise()
        btn:instantiate()
        btn:setImage(texture(size))
        btn:setDisplayBackground(false)
        btn:ignoreWidthChange()
        btn:ignoreHeightChange()
        panel:addChild(btn)
        panel:addMouseOverToolTipItem(btn, getText("IGUI_DazedControl_Title"))
        panel.dazedControlBtn = btn
    else
        local y = base + (btn.dazedOffset or 15)
        if btn:getY() ~= y then btn:setY(y) end
    end
    if btn:getBottom() > panel:getHeight() then panel:setHeight(btn:getBottom()) end
    if btn:getRight() > panel:getWidth() then panel:setWidth(btn:getRight()) end
end

local function current()
    local pd = getPlayerData and getPlayerData(0)
    attach(pd and pd.equipped or nil)
end

local function patchSidebar()
    if not ISEquippedItem or ISEquippedItem.dazedControlPatched then return end
    ISEquippedItem.dazedControlPatched = true
    local original = ISEquippedItem.initialise
    function ISEquippedItem:initialise()
        original(self)
        if self.chr and self.chr:getPlayerNum() == 0 then attach(self) end
    end
end

---------------------------------------------------------------- the vanilla admin panel button

-- Added below the lowest button the admin panel made, as wide as it, and the panel grows to hold it.
local function patchAdminPanel()
    if not ISAdminPanelUI or ISAdminPanelUI.dazedControlPatched then return end
    ISAdminPanelUI.dazedControlPatched = true
    local original = ISAdminPanelUI.create
    function ISAdminPanelUI:create(...)
        original(self, ...)
        local ok, err = pcall(function()
            local low, w, x, h = 0, nil, 10, nil
            for _, child in pairs(self:getChildren()) do
                if child.Type == "ISButton" and child:getBottom() > low then
                    low, w, x, h = child:getBottom(), child:getWidth(), child:getX(), child:getHeight()
                end
            end
            local btn = ISButton:new(x, low + 5, w or 150, h or 25, getText("IGUI_DazedControl_Title"), self,
                function() C.toggle(getPlayer()) end)
            btn:initialise()
            btn:instantiate()
            btn.borderColor = { r = 0.80, g = 0.54, b = 0.12, a = 0.9 }
            self:addChild(btn)
            self.dazedControlBtn = btn
            if btn:getBottom() + 10 > self:getHeight() then self:setHeight(btn:getBottom() + 10) end
        end)
        if not ok then print("DazedCore: could not add the Dazed Control button to the admin panel: " .. tostring(err)) end
    end
end

if Events then
    Events.OnGameStart.Add(function()
        patchSidebar()
        patchAdminPanel()
    end)
    Events.OnCreatePlayer.Add(current)
    -- Roles reach the client after the player is made and can change mid-game, so look again now and then.
    Events.EveryTenMinutes.Add(current)
end
