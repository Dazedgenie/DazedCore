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
