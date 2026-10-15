-- Headless check of the Dazed Control window (DC_ControlWindow): every kind of view block draws without an error,
-- buttons get click regions (greyed ones none), a danger button needs a second click, a stale tab answer is dropped,
-- and the target cycles me -> other players -> me. Run: lua controlwindow_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

UIFont = { Small = "Small", Medium = "Medium", Code = "Code", CodeSmall = "CodeSmall" }
getTextManager = function() return { getFontHeight = function() return 16 end, MeasureStringX = function(_, _, s) return #s * 7 end } end
local now = 1000
getTimestampMs = function() return now end
getTexture = function(p) return p end
getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
ISPanel = { derive = function(self) local c = {} c.__index = c setmetatable(c, { __index = self }) return c end,
    new = function(self, x, y, w, h) return setmetatable({ x = x, y = y, w = w, h = h }, self) end,
    getWidth = function(s) return s.w end, getHeight = function(s) return s.h end, update = function() end,
    onMouseDown = function() return false end }
package.preload["ISUI/ISPanel"] = function() return ISPanel end
local sent = {}
local Win = require "DazedCore/DC_ControlWindow"
DazedCore.Net.send = function(_, module, command, args) sent[#sent + 1] = { module, command, args } return true end
for _, f in ipairs({ "drawRect", "drawRectBorder", "drawText", "drawTextRight", "drawTextCentre", "drawTextureScaled",
    "setStencilRect", "clearStencilRect" }) do Win[f] = function() end end

local me = { getPlayerNum = function() return 0 end, getUsername = function() return "Kyle" end }
local w = Win:new(me)
w.tab = "t"
local view = { clock = "D1 08:00", lamps = { { "A", "green" }, { "B", "off" } }, cards = {
    { title = { "IGUI_X", { 3 } }, rows = { { "k", "v", "red" }, { "k2", "v2" } } },
    { title = "Items", items = { { text = "one", sub = "detail", tone = "green",
        buttons = { { label = "Remove", module = "M", command = "rm", need = "admin", danger = true } } }, { text = "two" } } },
    { title = "Log", log = true, lines = { "a", "b" } },
    { title = "Buttons", wide = true, buttons = { { label = "Go", module = "M", command = "go", need = "admin", target = true, go = true },
        { label = "Peek", module = "M", command = "peek", need = "mod" } } } } }
local tabs = { { id = "overview", title = "Overview" }, { id = "t", title = "T" } }
w:setView({ tab = "t", tabs = tabs, level = "mod", players = { "Kyle", "Pete", "Ash" }, view = view })
local ok, err = pcall(w.prerender, w)
check(ok, "a full view draws: " .. tostring(err))
-- count clickable regions: close, 2 tabs, 3 target-bar buttons (me, pick; no reset yet) + Peek only (moderator)
check(#w.regions == 1 + 2 + 2 + 1, "a moderator gets regions only for the buttons a moderator may use, got " .. #w.regions)
w.level = "admin"
w:prerender()
check(#w.regions == 1 + 2 + 2 + 3, "an admin gets every button, got " .. #w.regions)

-- the danger button: first click arms, second sends
local function click(i) local r = w.regions[i] w:onMouseDown(r.x + 1, r.y + 1) end
local rm
for i, r in ipairs(w.regions) do if r.y > 100 and r.x > w.w / 2 and r.y < 300 then rm = i end end
sent = {}
click(rm)
check(#sent == 0 and w.statusLine == "IGUI_DazedControl_ClickAgain", "a danger button asks for a second click")
click(rm)
check(#sent == 1 and sent[1][2] == "ctlAct" and sent[1][3].command == "rm", "the second click sends")

-- a target button sends the target
w.target = { player = "Pete" }
sent = {}
w:press(view.cards[4].buttons[1])
check(sent[1] and sent[1][3].target.player == "Pete", "a target button carries the target")
w.target = nil
sent = {}
w:press(view.cards[4].buttons[1])
check(sent[1] and type(sent[1][3].target) == "table" and sent[1][3].target.player == nil, "no target means me")
w:press(view.cards[4].buttons[2])
check(sent[2] and sent[2][3].target == nil, "a plain button sends no target")

-- target cycling skips me
w.target = nil
w:nextTarget() check(w.target and w.target.player == "Pete", "first other player")
w:nextTarget() check(w.target and w.target.player == "Ash", "next player")
w:nextTarget() check(w.target == nil, "back to me")

-- a stale answer for the tab just left is dropped; one for a tab the server lacks is kept
w.tab = "overview"
w:setView({ tab = "t", tabs = tabs, level = "admin", view = { cards = {} } })
check(w.tab == "overview", "stale answer dropped")
w.tab = "gone"
w:setView({ tab = "overview", tabs = tabs, level = "admin", view = { cards = {} } })
check(w.tab == "overview", "missing tab falls back to the server's first")

print(string.format("controlwindow_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
