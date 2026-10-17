-- Headless check of Tick (shared frame scheduler), Menu (shared right-click dispatcher), Util.clamp/players
-- and Boot.require. Run: lua tick_menu_test.lua <lua root>
local root = arg[1] or "../../Contents/mods/DazedCore/common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end
local function printed(pat)
    for _, line in ipairs(E.printed) do if string.find(line, pat, 1, true) then return true end end
    return false
end

------------------------------------------------------------------ Tick
local t = 1000
getTimestampMs = function() return t end
local T = require "DazedCore/DC_Tick"
local a, b, c = 0, 0, 0
check(T.every("Test.a", 100, function(now) a = a + 1 end), "every registers")
check(T.everyTicks("Test.b", 3, function() b = b + 1 end), "everyTicks registers")
check(not T.every("", 10, function() end) and not T.every("Test.x", 10, nil), "bad ids and fns are refused")
T.onTick()
check(a == 1 and b == 0, "first frame: ms job runs at once, tick job waits: " .. a .. " " .. b)
T.onTick(); T.onTick()
check(a == 1 and b == 1, "no time passed: ms job waits, tick job ran on its 3rd frame: " .. a .. " " .. b)
t = 1150; T.onTick()
check(a == 2, "150 ms later the ms job runs again")
t = 1100; T.onTick()
check(a == 3, "a clock that went backwards still runs the job")
T.every("Test.c", 0, function() c = c + 1; error("boom") end)
T.onTick(); T.onTick()
check(c == 2 and T.failed["Test.c"] and printed("tick job Test.c failed"), "a failing job is reported once and keeps running")
check(T.remove("Test.c") and not T.has("Test.c") and not T.remove("Test.c"), "remove")
local st = T.stats()
check(#st == 2 and st[1].id == "Test.a" and st[1].runs == 3, "stats lists jobs with runs")
check(#Events.OnTick.handlers == 1, "exactly one OnTick hook")

------------------------------------------------------------------ Menu
local M = require "DazedCore/DC_Menu"
local sq = E.square(5, 5, 0)
local o1, o2 = E.object("tile_1", sq), E.object("tile_2", sq)
local ch = E.character(5, 5, 0)
getSpecificPlayer = function(i) if i == 0 then return ch end return nil end
local seen = {}
M.world("Test.second", function(player, context, square, objects, worldobjects, test)
    seen[#seen + 1] = { "second", player, square, #objects, worldobjects, test }
end)
M.world("Test.first", function(player, context, square, objects)
    seen[#seen + 1] = { "first", player, square, #objects }
end, 10)
M.world("Test.bad", function() error("menu boom") end, 5)
local ctx = {}
M.onWorld(0, ctx, { o1 }, false)
check(#seen == 2 and seen[1][1] == "first" and seen[2][1] == "second", "handlers run in order, the failing one is skipped")
check(seen[1][2] == ch and seen[1][3] == sq and seen[1][4] == 2, "player, square and the two objects are handed over")
check(seen[2][5][1] == o1 and seen[2][6] == false, "worldobjects and test flag pass through")
check(M.failed["Test.bad"] and printed("right-click handler Test.bad failed"), "a failing handler is reported once")
E.printed = {}
M.onWorld(0, ctx, { o1 })
check(not printed("Test.bad"), "the failure is not printed again")
M.onWorld(3, ctx, { o1 })
check(#seen == 4, "an unknown player index adds nothing: " .. #seen)
local sq2, objs = M.squareOf({})
check(sq2 == nil and #objs == 0, "no world objects: nil square, empty list")
local inv = {}
M.inventory("Test.inv", function(player, context, items) inv[#inv + 1] = items end)
M.onInventory(0, ctx, { "item" })
check(#inv == 1 and inv[1][1] == "item", "inventory handler gets the items")
check(M.remove("Test.inv") and not M.remove("Test.inv"), "remove")
check(#Events.OnFillWorldObjectContextMenu.handlers == 1 and #Events.OnFillInventoryObjectContextMenu.handlers == 1, "one hook per event")
check(#M.stats() == 3, "stats lists the world handlers")

------------------------------------------------------------------ Util.clamp / players
local U = require "DazedCore/DC_Util"
check(U.clamp(5, 0, 3) == 3 and U.clamp(-1, 0, 3) == 0 and U.clamp(2, 0, 3) == 2 and U.clamp(9, nil, 4) == 4 and U.clamp(-9, 0) == 0, "clamp")
local ps = U.players()
check(#ps == 1 and ps[1] == ch, "players(): the local player")
isServer = function() return true end
local online = { E.character(1, 1), E.character(2, 2) }
getOnlinePlayers = function() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
ps = U.players()
check(#ps == 2 and ps[1] == online[1], "players(): online players on a server")
isServer = nil; getOnlinePlayers = nil
getSpecificPlayer = function() return nil end
getPlayer = function() return ch end
check(#U.players() == 1, "players(): getPlayer fallback")

------------------------------------------------------------------ Boot.require
local B = require "DazedCore/DC_Boot"
check(DazedCore.VERSION == "1.9.0", "Core is 1.9.0")
check(B.atLeast("1.9.0") and B.atLeast("1.8.4") and B.atLeast("1.9") and B.atLeast("0.9.9") and not B.atLeast("1.9.1") and not B.atLeast("1.10.0") and not B.atLeast("2.0.0"), "atLeast compares numerically")
E.printed = {}
check(B.require("DazedTest", "1.9.0") and #E.printed == 0, "a satisfied require is silent")
check(not B.require("DazedTest", "1.12.0") and printed("DazedTest needs Dazed Core 1.12.0, have 1.9.0"), "an old Core warns")
E.printed = {}
B.require("DazedTest", "1.12.0")
check(#E.printed == 0, "warns once per mod")
check(string.find(B.summary(), "DazedTest NEEDS CORE 1.12.0", 1, true), "the ready line names the mod that needs a newer Core")

print(string.format("tick_menu_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
