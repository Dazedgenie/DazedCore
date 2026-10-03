--[[ Dazed Utilities: Core -- (from Dazed Power by cakcan, CC BY-NC-SA 4.0) the Building Picker.

     A part that serves whole buildings (a Dazed Power controller, a Plumbing water main) opens a
     small window and an overlay. Every building and player-built structure the part serves is
     shaded green on the floor the player stands on. The one under the cursor is yellow when a
     click would add it, blue when a click would take it away, green when the part's own system
     already serves it, and red when the part does not reach it or another part serves it. A click
     is sent to the authority, which decides: the client never writes a part's ModData.

     The calling mod hands K.open a SPEC saying how its part works; the picker owns only the
     drawing, the hover resolution and the window. The preview under the cursor is resolved here
     with the same resolver the server uses (DC_Buildings), so what lights up is what a click will
     pick. The green is what the server stored on the part, decoded by the spec, so every client
     draws what the server did.

     One window per player, closed by Done, by Escape, by walking out of reach, or by the part
     leaving the world. The world click reaches Lua only when no window took it. ]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "DazedCore/DC_Util"
require "DazedCore/DC_Reach"
require "DazedCore/DC_Buildings"

DazedCore = DazedCore or {}
DazedCore.Picker = DazedCore.Picker or {}
local K = DazedCore.Picker
local U = DazedCore.Util
local R = DazedCore.Reach
local B = DazedCore.Buildings

local floor = math.floor

local FH_S = getTextManager():getFontHeight(UIFont.Small)
local SCALE = math.max(1, FH_S / 16)
local function px(v) return floor(v * SCALE + 0.5) end
local W, PAD, BTN = px(300), px(10), px(24)
local LIST_MAX = 8

local GREEN = { 0.20, 0.80, 0.40 }
local ADD   = { 0.95, 0.80, 0.20 }
local TAKE  = { 0.35, 0.60, 0.95 }
local FAR   = { 0.90, 0.30, 0.25 }

local states = {}          -- player number -> picker state

--[[ THE SPEC. Every field but `served` and `pick` is optional.
       range(st)            -> r, v     reach in squares and floors (default 20, 3)
       served(st)           -> list of { k, x, y, z, id, rects }  what the part serves now, decoded
                               from the part's data; `rects` as DC_Reach.decodeRects gives them
       status(st, t, fp)    -> "wired" | "taken" | nil   already served by this system / by another
       lock(st)             -> a translation key saying why this player may not change it, or nil
       pick(st, sx, sy, sz)            the click, to send to the authority
       clear(st)                       Remove all, to send to the authority
       single = true                   one building at most: a click on another replaces it; the count line says so
       title, help, legend, clear, clearTip, done, building, structure   translation keys
       textVersion(st)      -> any value; when it changes the served list is decoded again ]]

--------------------------------------------------------------------- basics

local function refused(st)
    local why = st.spec.lock and st.spec.lock(st)
    if not why then return false end
    U.haloNote(st.player, getText(why), true)
    return true
end

local function range(st)
    if st.spec.range then
        local r, v = st.spec.range(st)
        return r or 20, v or 3
    end
    return 20, 3
end

local function key(st, name, fallback)
    return st.spec[name] or fallback
end

--- What the part serves, with every footprint decoded. Cached until the spec says its data changed.
local function served(st)
    local ver = st.spec.textVersion and st.spec.textVersion(st) or 0
    if st.cacheVer == ver and st.cacheList then return st.cacheList end
    local list = st.spec.served(st) or {}
    for n = 1, #list do
        local t = list[n]
        t.rects = t.rects or {}
        t.fp = R.fpOfRects(t.rects)
        local _, _, _, _, z0, z1 = R.fpBounds(t.fp)
        t.floors = z0 and (z1 - z0 + 1) or 0
    end
    st.cacheVer, st.cacheList = ver, list
    st.hoverKey, st.hover = nil, nil
    return list
end
K.served = served

--- The square under the mouse, on the floor the player is looking at.
function K.mouseSquare(pn, z)
    if not (getMouseX and screenToIsoX and screenToIsoY) then return nil end
    local mx, my = getMouseX(), getMouseY()
    local ok1, wx = pcall(screenToIsoX, pn, mx, my, z)
    local ok2, wy = pcall(screenToIsoY, pn, mx, my, z)
    if not (ok1 and ok2 and wx and wy) then return nil end
    return floor(wx), floor(wy)
end

--- The target under the cursor, resolved only when the square changes.
local function hover(st, pn, z)
    local sx, sy = K.mouseSquare(pn, z)
    if not sx then
        st.hover, st.hoverKey = nil, nil
        return
    end
    local hk = sx .. "," .. sy .. "," .. z
    if st.hoverKey == hk then return end
    st.hoverKey = hk
    if st.hover and st.hover.fp and R.fpHas(st.hover.fp, sx, sy, z) then return end
    st.hover = nil
    local list = served(st)
    for n = 1, #list do
        local w = list[n]
        if R.fpHas(w.fp, sx, sy, z) then
            st.hover = { rects = w.rects, mode = "take", fp = w.fp }
            return
        end
    end
    local t = B.targetAt(sx, sy, z)
    if not t then return end
    for n = 1, #list do
        if list[n].k == "b" and t.k == "b" and list[n].id == t.id then
            st.hover = { rects = list[n].rects, mode = "take", fp = list[n].fp }
            return
        end
    end
    local fp = B.footprintOf(t)
    if not fp then return end
    local mode = st.spec.status and st.spec.status(st, t, fp) or nil
    if mode ~= "wired" and mode ~= "taken" then
        local r, v = range(st)
        mode = B.reaches(fp, st.x, st.y, st.z, r, v) and "add" or "far"
    end
    st.hover = { rects = R.rectsOf(fp), fp = fp, mode = mode }
end

----------------------------------------------------------------- the overlay

local function screen(x, y, z)
    return IsoUtils.XToScreenExact(x, y, z, 0), IsoUtils.YToScreenExact(x, y, z, 0)
end

local function drawRect(rc, z, col, fill)
    local renderer = SpriteRenderer.instance
    local x1, y1 = screen(rc.x, rc.y, z)
    local x2, y2 = screen(rc.x + rc.w, rc.y, z)
    local x3, y3 = screen(rc.x + rc.w, rc.y + rc.h, z)
    local x4, y4 = screen(rc.x, rc.y + rc.h, z)
    renderer:renderPoly(x1, y1, x2, y2, x3, y3, x4, y4, col[1], col[2], col[3], fill)
end

--- The outline of a footprint on one floor, as straight runs of edge, worked out once per
--  target and floor and kept on its rects list.
local function edgesOf(rects, z)
    local cache = rects.edges
    if not cache then
        cache = {}
        rects.edges = cache
    end
    if cache[z] then return cache[z] end
    local set = {}
    local x0, y0, x1, y1
    for _, rc in ipairs(rects) do
        if rc.z == z then
            for x = rc.x, rc.x + rc.w - 1 do
                for y = rc.y, rc.y + rc.h - 1 do set[R.sqKey(x, y)] = true end
            end
            local rx1, ry1 = rc.x + rc.w - 1, rc.y + rc.h - 1
            if not x0 then
                x0, y0, x1, y1 = rc.x, rc.y, rx1, ry1
            else
                x0, y0 = math.min(x0, rc.x), math.min(y0, rc.y)
                x1, y1 = math.max(x1, rx1), math.max(y1, ry1)
            end
        end
    end
    local runs = {}
    if x0 then
        for y = y0, y1 do
            local top, bottom = nil, nil
            for x = x0, x1 + 1 do
                local inside = x <= x1 and set[R.sqKey(x, y)]
                local t = inside and not set[R.sqKey(x, y - 1)]
                local b = inside and not set[R.sqKey(x, y + 1)]
                if t and not top then top = x end
                if not t and top then
                    runs[#runs + 1] = { top, y, x, y }
                    top = nil
                end
                if b and not bottom then bottom = x end
                if not b and bottom then
                    runs[#runs + 1] = { bottom, y + 1, x, y + 1 }
                    bottom = nil
                end
            end
        end
        for x = x0, x1 do
            local left, right = nil, nil
            for y = y0, y1 + 1 do
                local inside = y <= y1 and set[R.sqKey(x, y)]
                local l = inside and not set[R.sqKey(x - 1, y)]
                local rt = inside and not set[R.sqKey(x + 1, y)]
                if l and not left then left = y end
                if not l and left then
                    runs[#runs + 1] = { x, left, x, y }
                    left = nil
                end
                if rt and not right then right = y end
                if not rt and right then
                    runs[#runs + 1] = { x + 1, right, x + 1, y }
                    right = nil
                end
            end
        end
    end
    cache[z] = runs
    return runs
end

local function outline(rects, z, col)
    local renderer = SpriteRenderer.instance
    local runs = edgesOf(rects, z)
    for i = 1, #runs do
        local e = runs[i]
        local ax, ay = screen(e[1], e[2], z)
        local bx, by = screen(e[3], e[4], z)
        renderer:renderlinef(nil, ax, ay, bx, by, col[1], col[2], col[3], 0.85, 2)
    end
end

local function drawFootprint(rects, z, col, fill)
    for _, rc in ipairs(rects) do
        if rc.z == z then drawRect(rc, z, col, fill) end
    end
    outline(rects, z, col)
end

--- The part's own reach on this floor, as its outer edge only: the thing the red means.
local function reachEdge(st, z)
    local r, v = range(st)
    if z < st.z - v or z > st.z + v then return end
    local k = r .. ":" .. z
    if st.edgeKey ~= k then
        st.edgeKey = k
        local edges = {}
        local function inside(x, y)
            local dx, dy = x - st.x, y - st.y
            return dx * dx + dy * dy <= r * r
        end
        for y = st.y - r, st.y + r do
            for x = st.x - r, st.x + r do
                if inside(x, y) then
                    if not inside(x, y - 1) then edges[#edges + 1] = { x, y, x + 1, y } end
                    if not inside(x, y + 1) then edges[#edges + 1] = { x, y + 1, x + 1, y + 1 } end
                    if not inside(x - 1, y) then edges[#edges + 1] = { x, y, x, y + 1 } end
                    if not inside(x + 1, y) then edges[#edges + 1] = { x + 1, y, x + 1, y + 1 } end
                end
            end
        end
        st.edges = edges
    end
    local renderer = SpriteRenderer.instance
    for _, e in ipairs(st.edges or {}) do
        local ax, ay = screen(e[1], e[2], z)
        local bx, by = screen(e[3], e[4], z)
        renderer:renderlinef(nil, ax, ay, bx, by, 1, 1, 1, 0.45, 1)
    end
end

local function stillValid(st, player)
    if not player or player:isDead() then return false end
    local part = st.part
    if not part or part:getObjectIndex() < 0 then return false end
    local sq = part:getSquare()
    if not sq or getSquare(sq:getX(), sq:getY(), sq:getZ()) ~= sq then return false end
    local r = range(st)
    local dx, dy = player:getX() - st.x, player:getY() - st.y
    return dx * dx + dy * dy <= (r + 2) * (r + 2)
end

function K.render()
    local viewport = IsoPlayer.getPlayerIndex()
    for pn, st in pairs(states) do
        local player = getSpecificPlayer(pn)
        if not stillValid(st, player) then
            K.close(pn)
        elseif pn == viewport then
            local z = floor(player:getZ())
            reachEdge(st, z)
            local list = served(st)
            for n = 1, #list do drawFootprint(list[n].rects, z, GREEN, 0.28) end
            hover(st, pn, z)
            local h = st.hover
            if h then
                local col = (h.mode == "take" and TAKE) or (h.mode == "add" and ADD)
                            or (h.mode == "wired" and GREEN) or FAR
                drawFootprint(h.rects, z, col, 0.22)
            end
        end
    end
end

------------------------------------------------------------------- clicks

function K.onMouseDown()
    for pn, st in pairs(states) do
        local player = getSpecificPlayer(pn)
        if player and stillValid(st, player) then
            local z = floor(player:getZ())
            local sx, sy = K.mouseSquare(pn, z)
            if sx and not refused(st) then
                st.spec.pick(st, sx, sy, z)
                st.hoverKey = nil
            end
        end
    end
end

function K.onUI()
    if isKeyDown and isKeyDown(Keyboard.KEY_ESCAPE) then K.closeAll() end
end

------------------------------------------------------------------- window

DC_PickerWindow = ISCollapsableWindow:derive("DC_PickerWindow")

local function wrap(text, width)
    local out, line = {}, ""
    local tm = getTextManager()
    for word in string.gmatch(text or "", "%S+") do
        local try = (line == "") and word or (line .. " " .. word)
        if tm:MeasureStringX(UIFont.Small, try) > width and line ~= "" then
            out[#out + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

function DC_PickerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local st = self.state
    local half = floor((W - PAD * 3) / 2)
    local y = self:getHeight() - PAD - BTN
    self.bClear = ISButton:new(PAD, y, half, BTN, getText(key(st, "clear", "IGUI_DazedCore_PickClear")),
                               self, DC_PickerWindow.onClear)
    self.bClear:initialise()
    self.bClear:instantiate()
    self.bClear.tooltip = getText(key(st, "clearTip", "Tooltip_DazedCore_PickClear"))
    self:addChild(self.bClear)
    self.bDone = ISButton:new(PAD * 2 + half, y, half, BTN, getText(key(st, "done", "IGUI_DazedCore_PickDone")),
                              self, DC_PickerWindow.onDone)
    self.bDone:initialise()
    self.bDone:instantiate()
    self:addChild(self.bDone)
end

function DC_PickerWindow:onClear()
    local st = self.state
    if st and st.player and st.spec.clear and not refused(st) then st.spec.clear(st) end
end

function DC_PickerWindow:onDone()
    if self.state then K.close(self.state.pn) end
end

function DC_PickerWindow:close()
    self:onDone()
end

--- One line per served target: what it is and how big.
local function describe(st, t)
    local k = (t.k == "b") and key(st, "building", "IGUI_DazedCore_PickBuilding")
                           or key(st, "structure", "IGUI_DazedCore_PickStructure")
    return U.txt(k, U.count("IGUI_DazedCore_TileCount", R.fpCount(t.fp)),
                 U.count("IGUI_DazedCore_FloorCount", t.floors))
end

function DC_PickerWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local st = self.state
    if not st then return end
    local list = served(st)
    local y = self:titleBarHeight() + PAD
    local lh = FH_S + px(3)
    for i = 1, #self.help do
        self:drawText(self.help[i], PAD, y, 0.90, 0.90, 0.90, 1, UIFont.Small)
        y = y + lh
    end
    for i = 1, #self.legend do
        self:drawText(self.legend[i], PAD, y, 0.65, 0.70, 0.75, 1, UIFont.Small)
        y = y + lh
    end
    y = y + px(4)
    local countKey = st.spec.single and "IGUI_DazedCore_PickOne" or "IGUI_DazedCore_PickCount"
    self:drawText(U.txt(countKey, #list), PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
    y = y + lh
    for n = 1, math.min(#list, self.listMax) do
        self:drawText("  " .. describe(st, list[n]), PAD, y, GREEN[1], GREEN[2], GREEN[3], 1, UIFont.Small)
        y = y + lh
    end
    if self.bClear then
        local why = st.spec.lock and st.spec.lock(st)
        self.bClear:setEnable(#list > 0 and not why and st.spec.clear ~= nil)
        self.bClear.tooltip = getText(why or key(st, "clearTip", "Tooltip_DazedCore_PickClear"))
    end
end

function DC_PickerWindow:new(st)
    local lh = FH_S + px(3)
    local sw = (getCore and getCore() and getCore():getScreenWidth()) or 1920
    local o = ISCollapsableWindow.new(self, sw - W - px(24), px(110), W, 10)
    o:setResizable(false)
    o.state = st
    o.title = getText(key(st, "title", "IGUI_DazedCore_PickTitle"))
    o.pin = true
    o.help = wrap(getText(key(st, "help", "IGUI_DazedCore_PickHelp")), W - PAD * 2)
    o.legend = wrap(getText(key(st, "legend", "IGUI_DazedCore_PickLegend")), W - PAD * 2)
    o.listMax = st.spec.single and 1 or LIST_MAX
    o:setHeight(o:titleBarHeight() + PAD + lh * (#o.help + #o.legend + 1 + o.listMax)
                + px(4) + PAD + BTN + PAD)
    return o
end

-------------------------------------------------------------------- the API

function K.stateFor(playerObj)
    return playerObj and states[playerObj:getPlayerNum()] or nil
end

function K.isOpen(playerObj)
    return K.stateFor(playerObj) ~= nil
end

function K.close(pn)
    local st = states[pn]
    if not st then return end
    states[pn] = nil
    if st.window then st.window:removeFromUIManager() end
end

function K.closeAll()
    for pn in pairs(states) do K.close(pn) end
end

--- Open the picker on `part` for `playerObj`, with the calling mod's spec. Returns the state.
function K.open(playerObj, part, spec)
    if not (playerObj and part and type(spec) == "table" and spec.served and spec.pick) then return nil end
    local sq = part:getSquare()
    if not sq then return nil end
    local pn = playerObj:getPlayerNum()
    K.close(pn)
    local st = { part = part, spec = spec, x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                 player = playerObj, pn = pn }
    states[pn] = st
    local win = DC_PickerWindow:new(st)
    win:initialise()
    win:addToUIManager()
    st.window = win
    return st
end

if not K.hooked then
    K.hooked = true
    Events.OnPostRender.Add(K.render)
    Events.OnPreUIDraw.Add(K.onUI)
    Events.OnMouseDown.Add(K.onMouseDown)
    Events.OnGameStart.Add(K.closeAll)
end

return K
