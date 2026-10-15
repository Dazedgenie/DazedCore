--[[ Dazed Core -- the Dazed Control window, drawn like Dazed Power's charge board: an olive frame, a cream face,
     lamps along the top, cards in two columns and chunky buttons. Every tab is drawn from the plain view the
     authority sends (DC_Control), so a mod's tab needs no UI code of its own.

     The bottom bar holds the target: yourself, an online player, or a spot picked on the world map. A button marked
     `target` sends it with the request and the authority decides the final spot. A red (danger) button asks for a
     second click. Buttons the viewer's level may not use are drawn but greyed. ]]

require "ISUI/ISPanel"
require "DazedCore/DC_Control"

DazedCore = DazedCore or {}
local C = DazedCore.Control
local U = DazedCore.Util
local Net = DazedCore.Net

DC_ControlWindow = ISPanel:derive("DC_ControlWindow")
local Win = DC_ControlWindow

-- The game has no UI scale: Options > Font Size loads a bigger font set, so the window grows by the same ratio.
local S = math.max(1, getTextManager():getFontHeight(UIFont.CodeSmall) / 16)
local function px(v) return math.floor(v * S + 0.5) end

local BASE_W, BASE_H = 860, 600
local REFRESH_MS = 5000
local PICK_REFRESH_MS = 2000
local CONFIRM_MS = 3000
local TEX = "media/ui/DazedCore/Control/"

-- Dazed Power's board colours (DP_BoardLayout), so the two read as one family.
local K = {
    frame = { 0.235, 0.282, 0.227 }, barText = { 0.925, 0.898, 0.800 }, face = { 0.906, 0.867, 0.765 },
    card = { 0.886, 0.847, 0.749 }, line = { 0.667, 0.620, 0.525 }, ink = { 0.165, 0.153, 0.133 },
    muted = { 0.455, 0.420, 0.361 }, red = { 0.733, 0.169, 0.133 }, green = { 0.290, 0.560, 0.255 },
    amber = { 0.800, 0.540, 0.120 }, paper = { 0.969, 0.941, 0.882 }, tab = { 0.839, 0.796, 0.682 },
    tabOn = { 0.212, 0.255, 0.184 }, btn = { 0.941, 0.910, 0.824 }, sel = { 0.835, 0.788, 0.663 },
    redDark = { 0.478, 0.102, 0.078 }, greenDark = { 0.173, 0.353, 0.153 }, blue = { 0.169, 0.302, 0.647 },
}
local TONE = { green = K.green, red = K.red, amber = K.amber, muted = K.muted, blue = K.blue }

local function font(name) return UIFont[name] or UIFont.Small end
local function fontH(f) return getTextManager():getFontHeight(font(f)) end
local function width(f, s) return getTextManager():MeasureStringX(font(f), s) end

--- Words for a view's text: a translation key, { key, { args } } or plain text.
local function words(v)
    if v == nil then return "" end
    if type(v) == "table" then return U.txtArgs(v[1], v[2]) end
    v = tostring(v)
    if string.find(v, "^IGUI_") then return getText(v) end
    return v
end

local lampTex = {}
local function lamp(state)
    state = (state == "green" or state == "amber" or state == "red") and state or "off"
    if lampTex[state] == nil then lampTex[state] = getTexture(TEX .. "lamp_" .. state .. ".png") or false end
    return lampTex[state] or nil
end

---------------------------------------------------------------- drawing helpers

function Win:fill(x, y, w, h, c, a) self:drawRect(x, y, w, h, a or 1, c[1], c[2], c[3]) end
function Win:edge(x, y, w, h, c, a) self:drawRectBorder(x, y, w, h, a or 1, c[1], c[2], c[3]) end
function Win:text(s, x, y, c, f) self:drawText(s, x, y, c[1], c[2], c[3], 1, font(f or "Small")) end
function Win:textR(s, x, y, c, f) self:drawTextRight(s, x, y, c[1], c[2], c[3], 1, font(f or "Small")) end

-- Cut a string to fit `w` pixels, with an ellipsis.
-- How a view button is drawn: greyed when the viewer's level may not use it, else red, green or plain.
local function kindOf(level, b)
    if not C.atLeast(level, b.need) then return "off" end
    if b.danger then return "danger" end
    if b.go then return "go" end
    return nil
end

local function fit(f, s, w)
    if width(f, s) <= w then return s end
    while #s > 1 and width(f, s .. "...") > w do s = string.sub(s, 1, -2) end
    return s .. "..."
end

-- A chunky board button; records its click region. `kind` is nil, "danger", "go" or "off".
function Win:button(label, x, y, kind, onClick, minW)
    local f = "Small"
    local w = math.max(minW or 0, width(f, label) + px(16))
    local h = fontH(f) + px(6)
    local body, rim, ink = K.btn, K.muted, K.ink
    if kind == "danger" then body, rim, ink = K.red, K.redDark, { 1, 1, 1 }
    elseif kind == "go" then body, rim, ink = K.green, K.greenDark, { 1, 1, 1 }
    elseif kind == "off" then body, rim, ink = K.card, K.line, K.line end
    self:fill(x, y + px(2), w, h, rim)
    self:fill(x, y, w, h, body)
    self:edge(x, y, w, h, rim)
    self:drawTextCentre(label, x + w / 2, y + px(3), ink[1], ink[2], ink[3], 1, font(f))
    if onClick and kind ~= "off" then self.regions[#self.regions + 1] = { x = x, y = y, w = w, h = h + px(2), fn = onClick } end
    return w, h + px(2)
end

---------------------------------------------------------------- state

function Win:currentTab() return self.tab or "overview" end

function Win:request(tab)
    self.tab = tab or self:currentTab()
    self.asked = getTimestampMs()
    Net.send(self.player, C.MODULE, "ctlOpen", { tab = self.tab })
end

function Win:setView(args)
    -- An answer for a tab already left is dropped; one for a tab the server does not have (it sent its first) is kept.
    if self.tab and args.tab ~= self.tab and type(args.tabs) == "table" then
        for _, t in ipairs(args.tabs) do if t.id == self.tab then return end end
    end
    self.tab = args.tab
    self.tabs = type(args.tabs) == "table" and args.tabs or self.tabs or {}
    self.level = args.level
    self.players = type(args.players) == "table" and args.players or {}
    self.spots = type(args.spots) == "table" and args.spots or {}
    self.marks = type(args.marks) == "table" and args.marks or {}
    self.view = type(args.view) == "table" and args.view or {}
end

function Win:status(line, ok)
    self.statusLine = words(line)
    self.statusOk = ok ~= false
    self.statusAt = getTimestampMs()
end

function Win:targetText()
    local t = self.target
    if not t then return getText("IGUI_DazedControl_TargetMe") end
    if t.player then return U.txt("IGUI_DazedControl_TargetPlayer", t.player) end
    return U.txt("IGUI_DazedControl_TargetSpot", t.x, t.y)
end

-- Me, then each online player other than me, then back to me.
function Win:nextTarget()
    local me = self.player and self.player:getUsername()
    local names = {}
    for _, n in ipairs(self.players or {}) do if n ~= me then names[#names + 1] = n end end
    local cur = self.target and self.target.player
    if not cur then
        if names[1] then self.target = { player = names[1] } end
        return
    end
    for i, n in ipairs(names) do
        if n == cur then
            self.target = names[i + 1] and { player = names[i + 1] } or nil
            return
        end
    end
    self.target = nil
end

function Win:press(b)
    if not C.atLeast(self.level, b.need) then
        self:status("IGUI_DazedControl_NotAllowed", false)
        return
    end
    local key = tostring(b.module) .. "." .. tostring(b.command) .. tostring(b.label)
    if b.danger and not (self.armed == key and getTimestampMs() - (self.armedAt or 0) < CONFIRM_MS) then
        self.armed, self.armedAt = key, getTimestampMs()
        self:status("IGUI_DazedControl_ClickAgain", true)
        return
    end
    self.armed = nil
    if b.route then
        self:planRoute(b)
        return
    end
    local req ={ tab = self.tab, module = b.module, command = b.command, args = b.args }
    if b.target then req.target = self.target or {} end
    Net.send(self.player, C.MODULE, "ctlAct", req)
    self:status("IGUI_DazedControl_Sent", true)
end

---------------------------------------------------------------- layout of one card

-- Height of a card at width w, and when `draw` is set, draw it at x, y.
function Win:card(card, x, y, w, draw)
    local pad = px(10)
    local lineF, rowH, itemH, logH = "Small", fontH("Small") + px(4), fontH("Small") + px(14), fontH("CodeSmall") + px(2)
    local cy = y + px(6)
    if draw then
        self:fill(x, y, w, self.cardH or 0, card.log and K.paper or K.card)
        self:edge(x, y, w, self.cardH or 0, K.line)
        self:text(string.upper(words(card.title)), x + pad, cy, K.ink, "Small")
    end
    cy = cy + fontH("Small") + px(4)
    for _, r in ipairs(type(card.rows) == "table" and card.rows or {}) do
        if draw then
            self:text(string.upper(words(r[1])), x + pad, cy, K.muted, "Small")
            self:textR(words(r[2]), x + w - pad, cy, TONE[r[3]] or K.ink, lineF)
        end
        cy = cy + rowH
    end
    for _, it in ipairs(type(card.items) == "table" and card.items or {}) do
        local sub = words(it.sub)
        local ih = sub ~= "" and (fontH("Small") * 2 + px(10)) or itemH     -- a second line for the detail
        if draw then
            self:fill(x + 1, cy, w - 2, 1, K.line, 0.6)
            local bx = x + w - pad
            local by = cy + (ih - (fontH("Small") + px(8))) / 2
            local list = type(it.buttons) == "table" and it.buttons or {}
            for i = #list, 1, -1 do
                local b = list[i]
                local label = string.upper(words(b[1] or b.label))
                local bw = width("Small", label) + px(16)
                bx = bx - bw
                self:button(label, bx, by, kindOf(self.level, b), function() self:press(b) end)
                bx = bx - px(6)
            end
            local tx = x + pad
            local ty = cy + px(5)
            if it.tone and TONE[it.tone] then
                local c = TONE[it.tone]
                self:fill(tx, ty + fontH("Small") / 2 - px(5), px(10), px(10), c)
                self:edge(tx, ty + fontH("Small") / 2 - px(5), px(10), px(10), K.ink)
                tx = tx + px(16)
            end
            local room = bx - tx - px(8)
            self:text(fit("Small", words(it.text), room), tx, ty, K.ink, "Small")
            if sub ~= "" then self:text(fit("Small", sub, room), tx, ty + fontH("Small"), K.muted, "Small") end
        end
        cy = cy + ih
    end
    for _, l in ipairs(type(card.lines) == "table" and card.lines or {}) do
        if draw then self:text(fit("CodeSmall", words(l), w - pad * 2), x + pad, cy, K.ink, "CodeSmall") end
        cy = cy + logH
    end
    local bl = type(card.buttons) == "table" and card.buttons or {}
    if #bl > 0 then
        cy = cy + px(4)
        local bx, bh = x + pad, fontH("Small") + px(8)
        for _, b in ipairs(bl) do
            local label = string.upper(words(b[1] or b.label))
            local bw = width("Small", label) + px(16)
            if bx + bw > x + w - pad and bx > x + pad then bx, cy = x + pad, cy + bh + px(6) end
            if draw then
                self:button(label, bx, cy, kindOf(self.level, b), function() self:press(b) end)
            end
            bx = bx + bw + px(8)
        end
        cy = cy + bh
    end
    return cy - y + px(8)
end

---------------------------------------------------------------- the frame

function Win:prerender()
    self.regions = {}
    local w, h = self:getWidth(), self:getHeight()
    local bar, inset = px(30), px(6)
    self:fill(0, 0, w, h, K.frame)
    -- title bar
    self:text(getText("IGUI_DazedControl_Title"), px(12), (bar - fontH("Medium")) / 2, K.barText, "Medium")
    local xs = px(20)
    local xx, xy = w - inset - xs, (bar - xs) / 2
    self:fill(xx, xy, xs, xs, K.red)
    self:drawTextCentre("X", xx + xs / 2, xy + (xs - fontH("Small")) / 2, 1, 1, 1, 1, UIFont.Small)
    self.regions[#self.regions + 1] = { x = xx, y = xy, w = xs, h = xs, fn = function() self:close() end }
    if self.view and self.view.clock then self:textR(self.view.clock, xx - px(12), (bar - fontH("Code")) / 2, K.barText, "Code") end

    local fx, fy, fw, fh = inset, bar, w - inset * 2, h - bar - inset
    self:fill(fx, fy, fw, fh, K.face)

    -- tabs
    local tx, ty = fx + px(8), fy + px(8)
    local th = fontH("Small") + px(6)
    for _, t in ipairs(self.tabs or {}) do
        local label = string.upper(words(t.title))
        local tw = width("Small", label) + px(18)
        local on = t.id == self:currentTab()
        self:fill(tx, ty, tw, th, on and K.tabOn or K.tab)
        local c = on and K.barText or K.muted
        self:drawTextCentre(label, tx + tw / 2, ty + px(3), c[1], c[2], c[3], 1, UIFont.Small)
        local id = t.id
        self.regions[#self.regions + 1] = { x = tx, y = ty, w = tw, h = th, fn = function()
            self.scroll = 0
            self.view = nil
            self:request(id)
        end }
        tx = tx + tw + px(4)
    end

    -- lamps
    local ly = ty + th + px(8)
    local lx = fx + px(10)
    local ls = px(18)
    local lamps = self.view and type(self.view.lamps) == "table" and self.view.lamps or {}
    for _, l in ipairs(lamps) do
        local tex = lamp(l[2])
        if tex then self:drawTextureScaled(tex, lx, ly, ls, ls, 1, 1, 1, 1) end
        local label = string.upper(words(l[1]))
        self:text(label, lx + ls + px(5), ly + (ls - fontH("Small")) / 2, K.ink, "Small")
        lx = lx + ls + px(5) + width("Small", label) + px(18)
    end
    local top = ly + (#lamps > 0 and ls + px(8) or 0)

    -- bottom bar: the target and the last result
    local bb = fontH("Small") + px(14)
    local by = fy + fh - bb
    self:fill(fx, by, fw, 1, K.line)
    local bx = fx + px(10)
    self:text(getText("IGUI_DazedControl_Target"), bx, by + px(6), K.muted, "Small")
    bx = bx + width("Small", getText("IGUI_DazedControl_Target")) + px(8)
    local tl = string.upper(self:targetText())
    local bw = self:button(tl, bx, by + px(3), nil, function() self:nextTarget() end, px(150))
    bx = bx + bw + px(6)
    bw = self:button(string.upper(getText("IGUI_DazedControl_PickMap")), bx, by + px(3), nil, function() self:pickOnMap() end)
    bx = bx + bw + px(6)
    if self.target then
        self:button(string.upper(getText("IGUI_DazedControl_TargetReset")), bx, by + px(3), nil, function() self.target = nil end)
    end
    if self.statusLine and getTimestampMs() - (self.statusAt or 0) < 8000 then
        self:textR(self.statusLine, fx + fw - px(10), by + px(6), self.statusOk and K.green or K.red, "Small")
    elseif self.level == "mod" then
        self:textR(getText("IGUI_DazedControl_ViewOnly"), fx + fw - px(10), by + px(6), K.muted, "Small")
    end

    -- cards, two columns, each card into the shorter one; scrolled with the wheel
    local cx, cw = fx + px(8), (fw - px(24)) / 2
    local areaY, areaH = top, by - top - px(6)
    self.area = { x = fx, y = areaY, w = fw, h = areaH }
    if not self.view then
        self:text(getText("IGUI_DazedControl_Loading"), cx, areaY + px(4), K.muted, "Small")
        return
    end
    local cards = type(self.view.cards) == "table" and self.view.cards or {}
    local colY = { areaY - (self.scroll or 0), areaY - (self.scroll or 0) }
    self:setStencilRect(fx, areaY, fw, areaH)
    local regionsBefore = #self.regions
    for _, card in ipairs(cards) do
        local col = (card.wide or colY[1] <= colY[2]) and 1 or 2
        local x = cx + (col - 1) * (cw + px(8))
        local y = card.wide and math.max(colY[1], colY[2]) or colY[col]
        local cardW = card.wide and (cw * 2 + px(8)) or cw
        self.cardH = self:card(card, x, y, cardW, false)
        self:card(card, x, y, cardW, true)
        if card.wide then colY[1], colY[2] = y + self.cardH + px(8), y + self.cardH + px(8)
        else colY[col] = y + self.cardH + px(8) end
    end
    self:clearStencilRect()
    -- buttons scrolled out of the area are not clickable
    for i = #self.regions, regionsBefore + 1, -1 do
        local r = self.regions[i]
        if r.y < areaY or r.y + r.h > areaY + areaH then table.remove(self.regions, i) end
    end
    self.contentH = math.max(colY[1], colY[2]) + (self.scroll or 0) - areaY
end

function Win:render() end

function Win:update()
    ISPanel.update(self)
    -- the map was closed without a pick (Esc, the map key): stop waiting for one
    if C.picking == self and getTimestampMs() - (self.pickAt or 0) > 1000
            and not (ISWorldMap_instance and ISWorldMap_instance:isVisible()) then
        C.picking = nil
        if self.routing then
            self.routing = nil
            self:status("IGUI_DazedControl_RouteCancelled", false)
        end
    end
    -- faster while the map is up, so the player marks follow the players
    local every = C.picking == self and PICK_REFRESH_MS or REFRESH_MS
    if getTimestampMs() - (self.asked or 0) > every then self:request() end
end

function Win:onMouseWheel(del)
    local maxS = math.max(0, (self.contentH or 0) - (self.area and self.area.h or 0))
    self.scroll = math.max(0, math.min(maxS, (self.scroll or 0) + del * px(40)))
    return true
end

function Win:onMouseDown(x, y)
    for i = #(self.regions or {}), 1, -1 do
        local r = self.regions[i]
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            r.fn()
            return true
        end
    end
    return ISPanel.onMouseDown(self, x, y)
end

function Win:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if C.window == self then C.window = nil end
    if C.picking == self then C.picking = nil end
end

---------------------------------------------------------------- picking a spot on the world map

-- While the panel holds the map it shows everything: no fog over unvisited areas, and every player marked. What
-- the map showed before is put back when it closes, before vanilla saves its settings.
local REVEAL = { { "hideUnvisitedAreas", "setHideUnvisitedAreas", false }, { "showPlayers", "setShowPlayers", true },
    { "showRemotePlayers", "setShowRemotePlayers", true }, { "showPlayerNames", "setShowPlayerNames", true } }

local function reveal(map)
    if map.dazedRevealed or not map.mapAPI then return end
    map.dazedRevealed = {}
    for _, r in ipairs(REVEAL) do
        map.dazedRevealed[r[1]] = map[r[1]]
        pcall(map[r[2]], map, r[3])
    end
end

local function unreveal(map)
    local was = map.dazedRevealed
    if not was then return end
    map.dazedRevealed = nil
    for _, r in ipairs(REVEAL) do pcall(map[r[2]], map, was[r[1]]) end
end

-- World tile to map pixels; nil when the map cannot say.
local function toUI(map, x, y)
    local okX, ux = pcall(map.mapAPI.worldToUIX, map.mapAPI, x, y)
    local okY, uy = pcall(map.mapAPI.worldToUIY, map.mapAPI, x, y)
    if okX and okY and ux and uy then return ux, uy end
    return nil
end

local function line(map, x1, y1, x2, y2, thick, c, a)
    pcall(map.drawLine, map, nil, x1, y1, x2, y2, thick, a or 1, c[1], c[2], c[3])
end

-- A label on a dark tag, centred under ux, uy.
local function tag(map, s, ux, uy)
    local w = getTextManager():MeasureStringX(UIFont.Small, s) + 8
    map:drawRect(ux - w / 2, uy, w, getTextManager():getFontHeight(UIFont.Small) + 2, 0.8, K.frame[1], K.frame[2], K.frame[3])
    map:drawTextCentre(s, ux, uy + 1, K.barText[1], K.barText[2], K.barText[3], 1, UIFont.Small)
end

-- A square of colour c with a dark rim, and optionally a number on it.
local function dot(map, ux, uy, size, c, num)
    local h = size / 2
    map:drawRect(ux - h - 1, uy - h - 1, size + 2, size + 2, 1, K.ink[1], K.ink[2], K.ink[3])
    map:drawRect(ux - h, uy - h, size, size, 1, c[1], c[2], c[3])
    if num then map:drawTextCentre(tostring(num), ux, uy - getTextManager():getFontHeight(UIFont.Small) / 2, 1, 1, 1, 1, UIFont.Small) end
end

-- A mark and name for each online player the server reported. Your own mark is vanilla's.
local function drawSpots(map, win)
    local me = win.player and win.player:getUsername()
    for _, s in ipairs(win.spots or {}) do
        if s.n ~= me then
            local ux, uy = toUI(map, s.x, s.y)
            if ux then
                dot(map, ux, uy, 8, K.red)
                tag(map, s.n, ux, uy + 7)
            end
        end
    end
end

-- The marks the tabs sent: a ring for the spread, the route as a line (done legs grey), numbered checkpoints.
local function drawMarks(map, win)
    for _, m in ipairs(win.marks or {}) do
        local c = TONE[m.tone] or K.amber
        local ux, uy = toUI(map, m.x, m.y)
        local route = type(m.route) == "table" and m.route or {}
        local nextI = tonumber(m.next) or 1
        local px0, py0 = ux, uy
        for i, p in ipairs(route) do
            local rx, ry = toUI(map, p.x, p.y)
            if rx then
                local done = i < nextI
                if i >= nextI and px0 then line(map, px0, py0, rx, ry, 2, c, 0.9) end
                if done and route[i - 1] then
                    local qx, qy = toUI(map, route[i - 1].x, route[i - 1].y)
                    if qx then line(map, qx, qy, rx, ry, 1, K.muted, 0.7) end
                end
                dot(map, rx, ry, 14, done and K.muted or c, i)
                if i >= nextI then px0, py0 = rx, ry end
            end
        end
        if ux then
            local r = tonumber(m.r) or 0
            if r > 0 then
                local lx, ly
                for k = 0, 24 do
                    local a = k * math.pi / 12
                    local cx, cy = toUI(map, m.x + math.cos(a) * r, m.y + math.sin(a) * r)
                    if cx and lx then line(map, lx, ly, cx, cy, 2, c, 0.8) end
                    lx, ly = cx, cy
                end
            end
            dot(map, ux, uy, 12, c)
            if m.label then tag(map, words(m.label), ux, uy + 9) end
        end
    end
end

-- The route being planned: blue, numbered, joined in order.
local function drawPlan(map, points)
    local lx, ly
    for i, p in ipairs(points) do
        local ux, uy = toUI(map, p.x, p.y)
        if ux then
            if lx then line(map, lx, ly, ux, uy, 2, K.blue) end
            dot(map, ux, uy, 14, K.blue, i)
            lx, ly = ux, uy
        end
    end
end

-- The plan's buttons along the top of the map, under the hint; each records a click region on the map.
local function planBar(map, win)
    map.dazedRegions = {}
    local plan = win.routing
    local f = UIFont.Small
    local h = getTextManager():getFontHeight(f) + 8
    local list = {
        { "IGUI_DazedControl_RouteUndo", K.btn, K.ink, #plan.points > 0, function() table.remove(plan.points) end },
        { "IGUI_DazedControl_RouteClear", K.btn, K.ink, #plan.points > 0, function() plan.points = {} end },
        { "IGUI_DazedControl_RouteSend", K.green, { 1, 1, 1 }, #plan.points > 0, function() win:sendRoute() end },
        { "IGUI_DazedControl_RouteCancel", K.red, { 1, 1, 1 }, true, function() win:cancelRoute() end },
    }
    local total = 0
    for _, b in ipairs(list) do
        b.w = getTextManager():MeasureStringX(f, string.upper(getText(b[1]))) + 20
        total = total + b.w + 8
    end
    local x = (map:getWidth() - total + 8) / 2
    for _, b in ipairs(list) do
        local body, ink = b[2], b[3]
        if not b[4] then body, ink = K.card, K.line end
        map:drawRect(x, 78, b.w, h, 1, body[1], body[2], body[3])
        map:drawRectBorder(x, 78, b.w, h, 1, K.ink[1], K.ink[2], K.ink[3])
        map:drawTextCentre(string.upper(getText(b[1])), x + b.w / 2, 82, ink[1], ink[2], ink[3], 1, f)
        if b[4] then map.dazedRegions[#map.dazedRegions + 1] = { x = x, y = 78, w = b.w, h = h, fn = b[5] } end
        x = x + b.w + 8
    end
end

local function regionAt(map, x, y)
    for _, r in ipairs(map.dazedRegions or {}) do
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r end
    end
    return nil
end

-- Picking a spot, the world map takes the next plain click (not a drag) as the spot and closes, back to the panel
-- under it. Planning a route, each plain click adds a checkpoint until Send or Cancel.
local function patchMap()
    if not ISWorldMap or ISWorldMap.dazedControlPatched then return end
    ISWorldMap.dazedControlPatched = true
    local down, up, rend, close = ISWorldMap.onMouseDown, ISWorldMap.onMouseUp, ISWorldMap.render, ISWorldMap.close
    function ISWorldMap:close()
        unreveal(self)
        return close(self)
    end
    function ISWorldMap:onMouseDown(x, y)
        if C.picking then
            self.dazedDown = { x, y }
            -- a plan button: keep the press from starting a drag of the map
            if C.picking.routing and regionAt(self, x, y) then return true end
        end
        if down then return down(self, x, y) end
        return false
    end
    function ISWorldMap:onMouseUp(x, y)
        local d = self.dazedDown
        self.dazedDown = nil
        if C.picking and d and math.abs(d[1] - x) + math.abs(d[2] - y) < 6 and self.mapAPI then
            local okX, wx = pcall(self.mapAPI.uiToWorldX, self.mapAPI, x, y)
            local okY, wy = pcall(self.mapAPI.uiToWorldY, self.mapAPI, x, y)
            local pick = C.picking
            local plan = pick.routing
            if plan then
                local r = regionAt(self, x, y)
                if r then
                    r.fn()
                elseif okX and okY and wx and wy and #plan.points < C.ROUTE_MAX then
                    plan.points[#plan.points + 1] = { x = math.floor(wx), y = math.floor(wy) }
                end
                return true
            end
            C.picking = nil
            if okX and okY and wx and wy then
                pick.target = { x = math.floor(wx), y = math.floor(wy), z = 0 }
                pick:status(U.txt("IGUI_DazedControl_Picked", math.floor(wx), math.floor(wy)), true)
            else
                print("DazedCore: control map pick failed: " .. tostring(wx) .. " " .. tostring(wy))
                pick:status("IGUI_DazedControl_PickFailed", false)
            end
            pcall(ISWorldMap.HideWorldMap, pick.playerNum)
            return true
        end
        if up then return up(self, x, y) end
        return false
    end
    function ISWorldMap:render()
        if C.picking then reveal(self) else unreveal(self) end
        if rend then rend(self) end
        if C.picking then
            local win = C.picking
            drawMarks(self, win)
            drawSpots(self, win)
            local s = getText("IGUI_DazedControl_PickHint")
            if win.routing then
                drawPlan(self, win.routing.points)
                planBar(self, win)
                s = U.txt("IGUI_DazedControl_RouteHint", #win.routing.points, C.ROUTE_MAX)
            end
            local w = getTextManager():MeasureStringX(UIFont.Medium, s) + 24
            local x = (self:getWidth() - w) / 2
            self:drawRect(x, 40, w, 30, 0.9, 0.235, 0.282, 0.227)
            self:drawTextCentre(s, self:getWidth() / 2, 44, 0.925, 0.898, 0.800, 1, UIFont.Medium)
        end
    end
end

-- Open the map for this window: to pick a spot, or with `routing` set to plan a route.
function Win:openMap(routing)
    patchMap()
    if not (ISWorldMap and ISWorldMap.IsAllowed and ISWorldMap.IsAllowed()) then
        self:status("IGUI_DazedControl_NoMap", false)
        return
    end
    C.picking = self
    self.routing = routing
    self.pickAt = getTimestampMs()
    local ok = pcall(ISWorldMap.ShowWorldMap, self.playerNum)
    if not ok then
        C.picking, self.routing = nil, nil
        self:status("IGUI_DazedControl_NoMap", false)
    end
end

function Win:pickOnMap() self:openMap(nil) end

--- Plan a route for a `route` button: checkpoints are clicked on the map, then sent with the button's command.
function Win:planRoute(b) self:openMap({ button = b, points = {} }) end

local function closePlan(win)
    win.routing = nil
    if C.picking == win then C.picking = nil end
    pcall(ISWorldMap.HideWorldMap, win.playerNum)
end

function Win:sendRoute()
    local plan = self.routing
    if not (plan and #plan.points > 0) then return end
    local b = plan.button
    Net.send(self.player, C.MODULE, "ctlAct", { tab = self.tab, module = b.module, command = b.command, args = b.args, route = plan.points })
    self:status(U.txt("IGUI_DazedControl_RouteSent", #plan.points), true)
    closePlan(self)
end

function Win:cancelRoute()
    self:status("IGUI_DazedControl_RouteCancelled", false)
    closePlan(self)
end

---------------------------------------------------------------- opening

function Win:new(player)
    local w, h = px(BASE_W), px(BASE_H)
    local x = math.max(0, (getCore():getScreenWidth() - w) / 2)
    local y = math.max(0, (getCore():getScreenHeight() - h) / 2)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.moveWithMouse = true
    o.background = false
    o.regions = {}
    o.scroll = 0
    o.tabs = { { id = "overview", title = "IGUI_DazedControl_Overview" } }
    return o
end

--- Open the panel for a local player, or close it when it is open. Staff only; the authority checks again.
function C.toggle(player)
    player = player or getPlayer()
    if not player then return end
    if C.window then
        if C.picking then C.picking = nil end
        C.window:close()
        return
    end
    if not C.level(player) then return end
    local win = Win:new(player)
    win:initialise()
    win:addToUIManager()
    C.window = win
    win:request("overview")
end

Net.onClient(C.MODULE, "ctlView", function(args)
    if C.window then C.window:setView(args) end
end)

Net.onClient(C.MODULE, "ctlResult", function(args)
    if C.window then C.window:status(args.line, args.ok) end
end)

return Win
