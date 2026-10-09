-- Headless check of the small core modules: Util text, Sync, Note, Power registry, Migrate.
-- Run: lua core_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

local TEXT = { ["IGUI_X_Hello"] = "Hi {1}, {2}%", ["IGUI_X_Count"] = "{1} things", ["IGUI_X_CountOne"] = "one thing" }
getText = function(k) return TEXT[k] end

local U = require "DazedCore/DC_Util"
check(U.txt("IGUI_X_Hello", "Bob", "100%") == "Hi Bob, 100%%", "txt fills placeholders and escapes %: " .. U.txt("IGUI_X_Hello", "Bob", "100%"))
check(U.txtArgs("IGUI_X_Hello", { "A", "B" }) == "Hi A, B%", "txtArgs")
check(U.txt("IGUI_Missing") == "IGUI_Missing", "missing key echoes the key")
check(U.count("IGUI_X_Count", 1) == "one thing" and U.count("IGUI_X_Count", 3) == "3 things", "count picks the One twin")
local sq = E.square(1, 1, 0)
local o = E.object("x_1", sq)
check(U.try(o, "getSquare") == sq and U.try(o, "nope") == nil and U.try(nil, "x") == nil, "try")
check(U.squareAt(1, 1, 0) == sq and U.squareAt(9, 9, 0) == nil, "squareAt")

-- tile properties: the object's own first, then its sprite's; flags under has, Is or is
local function Props(vals, flags, via) return { get = via == "get" and function(_, k) return vals[k] end or nil,
    Val = via ~= "get" and function(_, k) return vals[k] end or nil, Is = function(_, k) return flags[k] == true end } end
local po = { getProperties = function() return Props({ A = "own" }, { F = true }, "get") end,
             getSprite = function() return { getProperties = function() return Props({ A = "spr", B = "spr" }, { G = true }, "Val") end } end }
check(U.prop(po, "A") == "own" and U.prop(po, "B") == "spr" and U.prop(po, "C") == nil and U.prop(nil, "A") == nil, "prop: own, then sprite")
check(U.propIs(po, "F") and U.propIs(po, "G") and not U.propIs(po, "H") and not U.propIs(nil, "F"), "propIs: own, then sprite")
local asked = 0
local look, forget = U.memo1(function(k) asked = asked + 1 if k == nil or k == "none" then return nil end return k .. "!" end, 2)
check(look("a") == "a!" and look("a") == "a!" and asked == 1, "memo1 remembers an answer")
check(look("none") == nil and look("none") == nil and asked == 2, "memo1 remembers a nil answer")
look("b"); look("a")
check(asked == 4, "memo1 starts over past its cap: " .. asked)
forget(); look("a")
check(asked == 5 and look(nil) == nil, "memo1 clear forgets; a nil argument is passed through")
------------------------------------------------------------------ Sync
local S = require "DazedCore/DC_Sync"
check(S.authority() == true, "single player is the authority")
S.track("DazedTestNet"); S.track("DazedTestNet")
check(#S.keys == 1, "track is idempotent")
local v0 = S.version
S.touch("DazedTestNet")
check(S.version == v0 + 1 and S.dirty["DazedTestNet"], "touch bumps version and marks dirty")
S.flush()
check(not S.dirty["DazedTestNet"], "flush clears dirty")
-- a received copy on the authority is ignored
for _, h in ipairs(Events.OnReceiveGlobalModData.handlers) do h("DazedTestNet", { x = 1 }) end
check(ModData._t["DazedTestNet"] == nil, "authority ignores received tables")
check(S.versionOf("DazedTestNet") == 1 and S.versionOf("Nope") == 0, "versionOf counts one key's changes")
S.touch("DazedOther")
check(S.versionOf("DazedTestNet") == 1 and S.versionOf("DazedOther") == 1, "touch bumps only its own key")
isClient = function() return true end
for _, h in ipairs(Events.OnReceiveGlobalModData.handlers) do h("DazedTestNet", { x = 2 }) end
check(S.versionOf("DazedTestNet") == 2 and ModData._t["DazedTestNet"].x == 2, "client bumps the key's version on receive")
isClient = nil

------------------------------------------------------------------ Note
local N = require "DazedCore/DC_Note"
local ch = E.character(0, 0, 0)
N.say(ch, "IGUI_X_Count", { 3 })
check(ch.notes[1] == "3 things", "note shown with args in single player: " .. tostring(ch.notes[1]))
getTimestampMs = function() return 1000 end
N.limited(ch, "IGUI_X_Count", { 1 }); N.limited(ch, "IGUI_X_Count", { 2 })
check(#ch.notes == 2, "limited note said once per window: " .. #ch.notes)
-- on a server the key travels as a command
isServer = function() return true end
local sent
sendServerCommand = function(c, mod, cmd, args) sent = { mod, cmd, args } end
N.say(ch, "IGUI_X_Count", { 5 }, true)
check(sent and sent[1] == "DazedCore" and sent[2] == "note" and sent[3].key == "IGUI_X_Count" and sent[3].warn == true, "server sends the key")
isServer = nil
-- the client end translates it
require "DazedCore/DC_NoteClient"
getPlayer = function() return ch end
for _, h in ipairs(Events.OnServerCommand.handlers) do h("DazedCore", "note", { key = "IGUI_X_Count", args = { 7 } }) end
check(ch.notes[#ch.notes] == "7 things", "client shows a received note")

------------------------------------------------------------------ Power
local W = require "DazedCore/DC_Power"
local pump = E.object("pump_1", E.square(2, 2, 0))
local lamp = E.object("lamp_1", E.square(3, 3, 0))
check(W.isPowered(pump) == false, "unpowered square")
E.square(2, 2, 0).power = true
check(W.isPowered(pump) == true and W.wired(pump) == false, "powered square is not wired")
E.square(2, 2, 0).power = false
check(W.registerProvider({ id = "bad" }) == nil, "provider needs isPowered")
W.registerProvider({ id = "wire", isPowered = function(obj) if obj == pump then return true end return nil end })
check(W.wired(pump) and W.isPowered(pump) and not W.wired(lamp), "provider powers only its object")
local working = false
W.registerLoad({ id = "testpump", kind = "waterpump", match = function(obj) return obj.sprite == "pump_1" end,
                 watts = function() return 400 end, working = function() return working end })
check(W.loadOf(pump) and W.loadOf(pump).kind == "waterpump" and W.loadOf(lamp) == nil, "loadOf matches by sprite")
check(W.rated(pump) == 400 and W.draw(pump) == 0, "idle load draws nothing")
working = true
check(W.draw(pump) == 400, "working load draws its rating")
W.legacyHook = function(obj) return obj == lamp end
check(W.wired(lamp), "an older add-on's hook still counts")
-- name hints: prefix and matchName skip match, byName remembers the verdict per sprite name
local calls = 0
W.registerLoad({ id = "heater", kind = "heater", prefix = "heat_", matchName = function(n) return n ~= "heat_cold" end, byName = true,
                 match = function(obj) calls = calls + 1 return obj.sprite == "heat_1" end,
                 watts = function() return 50 end, working = function() return true end })
local h1 = E.object("heat_1", E.square(4, 4, 0))
local h1b = E.object("heat_1", E.square(5, 4, 0))
local hc = E.object("heat_cold", E.square(6, 4, 0))
check(W.loadOf(h1) and W.loadOf(h1).id == "heater" and calls == 1, "byName load matched once: " .. calls)
check(W.loadOf(h1b) == W.loadOf(h1) and calls == 1, "same sprite name answered from the memo")
check(W.loadOf(lamp) == nil and W.loadOf(hc) == nil and calls == 1, "prefix and matchName skip match")
check(W.loadOf(pump).id == "testpump", "loads without hints still match as before")
W.clearNameMemo()
W.loadOf(h1)
check(calls == 2, "clearNameMemo forgets verdicts")

------------------------------------------------------------------ Migrate
local M = require "DazedCore/DC_Migrate"
local d = M.stamp({ amount = 5 }, 1)
check(M.versionOf(d) == 1, "stamp")
local out, changed = M.upgrade(d, 3, { [2] = function(t) t.litres = t.amount; t.amount = nil end,
                                       [3] = function(t) return { v3 = t.litres } end })
check(changed and M.versionOf(out) == 3 and out.v3 == 5 and out.litres == nil, "upgrade runs each step in order")
local same, ch2 = M.upgrade(out, 3, {})
check(same == out and not ch2, "already current: untouched")

print(string.format("core_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
