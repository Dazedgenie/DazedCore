-- Headless check of Dazed Control (DC_Control): tab order, staff levels, the act path (only named commands, the level
-- each needs, the target resolved by the authority), buttons a tab does not name dropped from its view, and the log.
-- Run: lua control_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

local t = 1000
getTimestampMs = function() t = t + 1000 return t end
local md = {}
ModData = { getOrCreate = function(k) md[k] = md[k] or {} return md[k] end }
getDebug = function() return false end
local C = require "DazedCore/DC_Control"
local N = DazedCore.Net

------------------------------------------------------------------ levels
Capability = { UseMovablesCheat = "cheat", BanUnbanUser = "ban" }
local function person(name, caps, x, y)
    local p = E.character(x or 0, y or 0, 0)
    p.getUsername = function() return name end
    p.getRole = function() return { hasCapability = function(_, c) return caps[c] == true end } end
    return p
end
local admin = person("Kyle", { cheat = true, ban = true }, 10, 20)
local mod = person("Ash", { ban = true }, 30, 40)
local user = person("Pete", {}, 50, 60)
check(C.level(admin) == "admin" and C.level(mod) == "mod" and C.level(user) == nil, "levels by capability")
getDebug = function() return true end
check(C.level(user) == "admin", "debug mode counts as admin")
getDebug = function() return false end
Capability = nil
local old = E.character(0, 0, 0)
old.getAccessLevel = function() return "Moderator" end
check(C.level(old) == "mod", "no roles: the access-level string")
Capability = { UseMovablesCheat = "cheat", BanUnbanUser = "ban" }
check(C.atLeast("admin", "mod") and C.atLeast("mod", "mod") and not C.atLeast("mod", "admin") and not C.atLeast(nil, "mod"),
    "atLeast ranks admin over mod")

------------------------------------------------------------------ tabs
C.register("zeta", { title = "Z", order = 30, view = function() return {} end })
C.register("alpha", { title = "A", order = 30, view = function() return {} end })
C.register("early", { title = "E", order = 5, view = function() return {} end })
check(C.register("broken", { title = "B" }) == nil, "a tab without a view is refused")
check(C.order[1] == "overview" and C.order[2] == "early" and C.order[3] == "alpha" and C.order[4] == "zeta",
    "tabs sort by order, then id")

------------------------------------------------------------------ the act path
getOnlinePlayers = function()
    local l = { admin, mod, user }
    return { size = function() return #l end, get = function(_, i) return l[i + 1] end }
end
local ran = {}
N.on("DazedTest", "drop", function(p, args) ran[#ran + 1] = { p = p, args = args } end)
N.on("DazedTest", "peek", function(p) ran[#ran + 1] = { p = p, peek = true } end)
N.on("DazedTest", "secret", function(p) ran[#ran + 1] = { p = p, secret = true } end)
C.register("test", {
    title = "Test", order = 20,
    commands = { ["DazedTest.drop"] = "admin", ["DazedTest.peek"] = "mod" },
    view = function()
        return { cards = { { title = "x",
            buttons = { { label = "Drop", module = "DazedTest", command = "drop" }, { label = "Secret", module = "DazedTest", command = "secret" } },
            items = { { text = "i", buttons = { { label = "Peek", module = "DazedTest", command = "peek" } } } } } } }
    end,
})
local views, results = {}, {}
N.onClient(C.MODULE, "ctlView", function(args) views[#views + 1] = args end)
N.onClient(C.MODULE, "ctlResult", function(args) results[#results + 1] = args end)

N.send(admin, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "drop", args = { theme = "food" } })
check(#ran == 1 and ran[1].args.theme == "food" and ran[1].args.x == nil, "admin runs a named command, args passed, no target")
N.send(admin, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "secret" })
check(#ran == 1, "a command the tab does not name never runs")
N.send(mod, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "drop" })
check(#ran == 1 and results[#results].ok == false, "a moderator cannot use an admin command")
N.send(mod, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "peek" })
check(#ran == 2 and ran[2].peek, "a moderator may use a command lowered to mod")
N.send(user, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "peek" })
check(#ran == 2, "an ordinary player is ignored")

N.send(admin, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "drop", target = {} })
check(ran[3].args.x == 10 and ran[3].args.y == 20, "an empty target is the staff member's own square")
N.send(admin, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "drop", target = { player = "Pete" } })
check(ran[4].args.x == 50 and ran[4].args.y == 60 and ran[4].args.targetName == "Pete", "a player target is where they stand")
N.send(admin, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "drop", target = { x = 123.7, y = 456.2, z = 99 } })
check(ran[5].args.x == 123 and ran[5].args.y == 456 and ran[5].args.z == 7, "a map spot is floored and the floor clamped")
local before = #ran
N.send(admin, C.MODULE, "ctlAct", { tab = "test", module = "DazedTest", command = "drop", target = { player = "Nobody" } })
check(#ran == before and results[#results].line == "IGUI_DazedControl_NoTarget", "an offline player target is refused")

------------------------------------------------------------------ views
views = {}
N.send(mod, C.MODULE, "ctlOpen", { tab = "test" })
local v = views[1]
check(v and v.level == "mod" and v.tab == "test", "the view says the viewer's level")
local card = v and v.view.cards[1]
check(card and #card.buttons == 1 and card.buttons[1].need == "admin", "an unnamed button is dropped, the rest marked")
check(card and card.items[1].buttons[1].need == "mod", "item buttons are marked too")
check(v and #v.players == 3 and #v.tabs >= 5, "the view carries players and tabs")
views = {}
N.send(user, C.MODULE, "ctlOpen", { tab = "test" })
check(#views == 0, "an ordinary player gets no view")
C.register("bad", { title = "Bad", view = function() error("boom") end })
N.send(admin, C.MODULE, "ctlOpen", { tab = "bad" })
check(views[1] and views[1].view.cards[1].title == "IGUI_DazedControl_ViewFailed", "a failing view is shown, not thrown")

------------------------------------------------------------------ fixes
local fixed = {}
check(C.registerFix("bad", { title = "no run" }) == nil, "a fix without run is refused")
C.registerFix("frost", { title = "Clear frostbite", desc = "heal it", mod = "Climate", scope = "player",
    run = function(staff, info) fixed[#fixed + 1] = { who = info.name, player = info.player, staff = staff } return true, "cleared" end })
C.registerFix("claims", { title = "Release claims", desc = "stuck claims", mod = "Butchery", scope = "world",
    run = function(staff, info) fixed[#fixed + 1] = { x = info.x, y = info.y } return true end })
C.registerFix("nope", { title = "Always fails", scope = "world", run = function() return false, "nothing to do" end })
C.registerFix("boom", { title = "Throws", scope = "world", run = function() error("x") end })
check(C.fixOrder[1] == "frost", "player fixes sort before world fixes")
views = {}
N.send(admin, C.MODULE, "ctlOpen", { tab = "fixes" })
local fv = views[1] and views[1].view
check(fv and #fv.cards == 2 and #fv.cards[1].items == 1 and #fv.cards[2].items == 3, "the Fixes tab groups fixes by scope")
check(fv and fv.cards[1].items[1].sub == "heal it (Climate)" and fv.cards[1].items[1].buttons[1].need == "admin", "a fix shows its mod and needs admin")
N.send(admin, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "frost" }, target = { player = "Pete" } })
check(#fixed == 1 and fixed[1].who == "Pete" and fixed[1].player == user, "a player fix runs on the target player")
N.send(admin, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "frost" }, target = {} })
check(#fixed == 2 and fixed[2].player == admin, "with no target a player fix runs on the staff member")
N.send(admin, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "claims" }, target = { x = 100, y = 200 } })
check(#fixed == 3 and fixed[3].x == 100 and fixed[3].y == 200, "a world fix runs at the target spot")
N.send(admin, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "nope" } })
check(results[#results].ok == false and results[#results].line == "IGUI_DazedControl_Failed", "a fix that answers false shows as failed")
N.send(admin, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "boom" } })
check(results[#results].ok == false, "a fix that throws shows as failed")
N.send(admin, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "missing" } })
local n = #fixed
N.send(mod, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "claims" } })
N.send(user, C.MODULE, "ctlAct", { tab = "fixes", module = C.MODULE, command = "ctlFix", args = { id = "claims" } })
check(#fixed == n, "moderators and players cannot run a fix")

------------------------------------------------------------------ log
local log = md[C.LOG_KEY].lines
check(log and #log >= 5 and string.find(log[1], "Kyle", 1, true), "actions are logged, newest first")
for _ = 1, 50 do C.log("x", "y") end
check(#md[C.LOG_KEY].lines == C.LOG_KEEP, "the log keeps only the newest")
check(#C.recent(15) == 15, "recent gives the newest n")

print(string.format("control_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
