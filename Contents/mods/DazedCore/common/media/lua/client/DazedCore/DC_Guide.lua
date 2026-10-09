--[[ Dazed Core -- the in-game guide for the whole Dazed suite.

     A window with one tab per Dazed mod that is loaded and a list of short pages in each, opened from a
     button at the foot of the vanilla sidebar. The text lives in the translation files
     (IGUI_DazedGuide_<page>_Title / _Text), so it can be translated like anything else. ]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "DazedCore/DC_Options"

DazedCore = DazedCore or {}
DazedCore.Guide = DazedCore.Guide or {}
local G = DazedCore.Guide

--- Books: { id, titleKey, present = function, pages = { page ids } }. Another mod may add its own with G.add.
G.books = G.books or {}

function G.add(book)
    for _, b in ipairs(G.books) do if b.id == book.id then return end end
    G.books[#G.books + 1] = book
end

G.add({ id = "core", titleKey = "IGUI_DazedGuide_Book_core", present = function() return true end,
        pages = { "CoreStart", "CoreHeavy", "CorePresets", "CorePicker" } })
G.add({ id = "power", titleKey = "IGUI_DazedGuide_Book_power",
        present = function() return DazedPower ~= nil and DazedPower.Parts ~= nil end,
        pages = { "PowerStart", "PowerWiring", "PowerMonitor", "PowerBatteries", "PowerSources", "PowerLoads",
                  "PowerCharging", "PowerHazards" } })
G.add({ id = "plumbing", titleKey = "IGUI_DazedGuide_Book_plumbing",
        present = function() return DazedPlumb ~= nil end,
        pages = { "PlumbStart", "PlumbPumps", "PlumbQuality", "PlumbRain", "PlumbMain", "PlumbFuel",
                  "PlumbDigester", "PlumbSprinkler" } })
-- The rest of the Dazed suite: each tab shows only while its mod is enabled.
G.add({ id = "butchery", titleKey = "IGUI_DazedGuide_Book_butchery",
        present = function() return DazedButchery ~= nil end,
        pages = { "ButchStart", "ButchCut", "ButchGrades", "ButchField", "ButchEdge" } })
G.add({ id = "cooking", titleKey = "IGUI_DazedGuide_Book_cooking",
        present = function() return DazedCooking ~= nil end,
        pages = { "CookStart", "CookMood", "CookPortion" } })
G.add({ id = "dank", titleKey = "IGUI_DazedGuide_Book_dank",
        present = function() return CannabisMod ~= nil end,
        pages = { "DankStart", "DankLights", "DankBags", "DankHydro", "DankRooms", "DankClimate", "DankDrying", "DankSmoking" } })

local function txt(key)
    local t = getText(key)
    if t == key then return "" end
    return t
end

---------------------------------------------------------------- the window

DC_GuideWindow = ISCollapsableWindow:derive("DC_GuideWindow")

function DC_GuideWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    local fh = getTextManager():getFontHeight(UIFont.Small)
    local x, y = 8, th + 6
    self.tabs = {}
    for _, b in ipairs(G.books) do
        if b.present() then
            local w = getTextManager():MeasureStringX(UIFont.Small, getText(b.titleKey)) + 20
            local btn = ISButton:new(x, y, w, fh + 6, getText(b.titleKey), self, DC_GuideWindow.onTab)
            btn.book = b
            btn:initialise()
            self:addChild(btn)
            self.tabs[#self.tabs + 1] = btn
            x = x + w + 6
        end
    end
    local top = y + fh + 14
    local listW = 170
    self.list = ISScrollingListBox:new(8, top, listW, self.height - top - 10)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = fh + 8
    self.list.font = UIFont.Small
    self.list:setOnMouseDownFunction(self, DC_GuideWindow.onPage)
    self.list:setAnchorBottom(true)
    self:addChild(self.list)
    self.text = ISRichTextPanel:new(listW + 16, top, self.width - listW - 24, self.height - top - 10)
    self.text:initialise()
    self.text.autosetheight = false
    self.text.clip = true
    self.text:addScrollBars()
    self.text:setAnchorRight(true)
    self.text:setAnchorBottom(true)
    self:addChild(self.text)
    if self.tabs[1] then self:showBook(self.tabs[1].book) end
end

function DC_GuideWindow:onTab(button)
    self:showBook(button.book)
end

function DC_GuideWindow:showBook(book)
    self.book = book
    for _, t in ipairs(self.tabs) do
        t.backgroundColor = (t.book == book) and { r = 0.35, g = 0.3, b = 0.1, a = 0.9 } or { r = 0, g = 0, b = 0, a = 0.7 }
    end
    self.list:clear()
    for _, id in ipairs(book.pages) do
        local title = txt("IGUI_DazedGuide_" .. id .. "_Title")
        if title ~= "" then self.list:addItem(title, id) end
    end
    self.list.selected = 1
    local first = self.list.items[1]
    self:showPage(first and first.item)
end

function DC_GuideWindow:onPage(id)
    self:showPage(id)
end

function DC_GuideWindow:showPage(id)
    if not id then self.text.text = "" self.text:paginate() return end
    self.text.text = " <H1> " .. txt("IGUI_DazedGuide_" .. id .. "_Title") .. " <LINE> <TEXT> "
        .. txt("IGUI_DazedGuide_" .. id .. "_Text")
    self.text:paginate()
    self.text:setYScroll(0)
end

function DC_GuideWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    G.window = nil
end

function DC_GuideWindow:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = getText("IGUI_DazedGuide_Title")
    o.resizable = true
    o.minimumWidth, o.minimumHeight = 520, 320
    return o
end

--- Open the guide, or bring it to the front; a second call closes it.
function G.toggle()
    if G.window then G.window:close() return end
    local core = getCore()
    local w, h = 760, 520
    local win = DC_GuideWindow:new((core:getScreenWidth() - w) / 2, (core:getScreenHeight() - h) / 2, w, h)
    win:initialise()
    win:addToUIManager()
    G.window = win
end

---------------------------------------------------------------- the sidebar button

-- Placed under the lowest vanilla button plus any Dazed button already there, measured once like DazedPower's
-- almanac button, so two mods hanging buttons there never chase each other down the screen.
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
    return getTexture("media/ui/DazedCore/Sidebar/" .. best .. "/Guide_" .. best .. ".png")
end

local function detach(panel)
    local btn = panel and panel.dazedGuideBtn
    if not btn then return end
    panel:removeChild(btn)
    if panel.mouseOverList then
        for i = #panel.mouseOverList, 1, -1 do
            if panel.mouseOverList[i].object == btn then table.remove(panel.mouseOverList, i) end
        end
    end
    panel.dazedGuideBtn = nil
end

function G.attach(panel)
    if not panel or not panel.invBtn then return end
    if not DazedCore.Options.on("DazedCore", "GuideButton") then detach(panel) return end
    local size = panel.invBtn:getWidth()
    local base = anchorBottom(panel)
    local btn = panel.dazedGuideBtn
    if not btn then
        local low = base
        for _, child in pairs(panel:getChildren()) do
            if child.Type == "ISButton" then low = math.max(low, child:getBottom()) end
        end
        local y = low + 15
        btn = ISButton:new(0, y, size, size * 0.75, "", panel, function() G.toggle() end)
        btn.dazedOffset = y - base
        btn:initialise()
        btn:instantiate()
        btn:setImage(texture(size))
        btn:setDisplayBackground(false)
        btn:ignoreWidthChange()
        btn:ignoreHeightChange()
        panel:addChild(btn)
        panel:addMouseOverToolTipItem(btn, getText("IGUI_DazedGuide_Title"))
        panel.dazedGuideBtn = btn
    else
        local y = base + (btn.dazedOffset or 15)
        if btn:getY() ~= y then btn:setY(y) end
    end
    if btn:getBottom() > panel:getHeight() then panel:setHeight(btn:getBottom()) end
    if btn:getRight() > panel:getWidth() then panel:setWidth(btn:getRight()) end
end

local function current()
    local pd = getPlayerData and getPlayerData(0)
    G.attach(pd and pd.equipped or nil)
end

DazedCore.Options.tick("DazedCore", "GuideButton", "IGUI_DazedGuide_Option", true, "IGUI_DazedGuide_OptionTip", current)

local function patch()
    if not ISEquippedItem or ISEquippedItem.dazedGuidePatched then return end
    ISEquippedItem.dazedGuidePatched = true
    local original = ISEquippedItem.initialise
    function ISEquippedItem:initialise()
        original(self)
        if self.chr and self.chr:getPlayerNum() == 0 then G.attach(self) end
    end
end

-- No minute re-check: the button is unconditional, the initialise patch covers every rebuilt sidebar, OnCreatePlayer
-- covers the first one and split-screen rebuilds, and the option applies itself through its callback.
if Events then
    Events.OnGameStart.Add(patch)
    Events.OnCreatePlayer.Add(current)
end

return G
