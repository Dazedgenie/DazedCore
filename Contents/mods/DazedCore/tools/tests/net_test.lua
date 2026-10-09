-- Headless check of Detect (mod lookup, yield cache) and Net (local dispatch, rate limit, client path, near).
-- Run: lua net_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
local E = dofile("engine_stub.lua")
local print = E.realPrint
package.path = root .. "/shared/?.lua;" .. root .. "/client/?.lua;" .. package.path
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

------------------------------------------------------------------ Detect
local mods = { "DazedCore", "\\BB_CommonSense" }
getActivatedMods = function()
    return { size = function() return #mods end, get = function(_, i) return mods[i + 1] end }
end
local D = require "DazedCore/DC_Detect"
check(D.isActive("DazedCore") and D.isActive("BB_CommonSense") and not D.isActive("Nope"), "isActive strips a leading backslash")
D.yieldTo("Test.Pry", { "BB_BreakingIn", "BB_CommonSense" })
D.yieldTo("Test.Prox", { "ProximityInventory" })
check(D.yields("Test.Pry") and D.yieldedTo("Test.Pry") == "BB_CommonSense", "yields to the first active mod")
check(not D.yields("Test.Prox") and D.yieldedTo("Test.Prox") == nil, "no overlap, no yield")
check(not D.yields("Test.Unregistered"), "an unregistered feature never yields")
mods[#mods + 1] = "ProximityInventory"
check(not D.yields("Test.Prox"), "answer is cached until reset")
D.reset()
check(D.yields("Test.Prox"), "reset re-reads the mod list")

------------------------------------------------------------------ Net
local N = require "DazedCore/DC_Net"
local ch = E.character(10, 10, 0)
local got
N.on("DazedTest", "pry", function(p, args) got = { p, args.x } end)
check(N.send(ch, "DazedTest", "pry", { x = 5 }) and got and got[1] == ch and got[2] == 5, "single player runs the handler at once")
check(N.send(ch, "DazedTest", "missing", {}) == false, "unknown command is refused")
N.on("DazedTest", "boom", function() error("bad") end)
check(N.send(ch, "DazedTest", "boom", {}) == false, "a failing handler is caught")
-- rate limit
local count, t = 0, 1000
getTimestampMs = function() return t end
N.on("DazedTest", "spam", function() count = count + 1 end, 500)
N.send(ch, "DazedTest", "spam"); N.send(ch, "DazedTest", "spam")
t = 1600; N.send(ch, "DazedTest", "spam")
check(count == 2, "repeats inside the window are dropped: " .. count)
-- the OnClientCommand path on a server
got = nil
for _, h in ipairs(Events.OnClientCommand.handlers) do h("DazedTest", "pry", ch, { x = 9 }) end
check(got and got[2] == 9, "server receives a client command")
for _, h in ipairs(Events.OnClientCommand.handlers) do h("DazedTest", "pry", ch, nil) end
check(got and got[2] == nil, "nil args arrive as an empty table")
-- on a client the request travels instead
isClient = function() return true end
local sent
sendClientCommand = function(p, m, c, a) sent = { m, c, a.x } end
got = nil
N.send(ch, "DazedTest", "pry", { x = 3 })
check(sent and sent[1] == "DazedTest" and sent[3] == 3 and got == nil, "a client sends, never runs")
isClient = nil
-- reply in single player and on a server
local shown
N.onClient("DazedTest", "done", function(a) shown = a.n end)
N.reply(ch, "DazedTest", "done", { n = 4 })
check(shown == 4, "single player reply runs the client handler")
isServer = function() return true end
local out
sendServerCommand = function(p, m, c, a) out = { m, c, a.n } end
N.reply(ch, "DazedTest", "done", { n = 6 })
check(out and out[2] == "done" and out[3] == 6, "server reply sends a command")
isServer = nil
for _, h in ipairs(Events.OnServerCommand.handlers) do h("DazedTest", "done", { n = 8 }) end
check(shown == 8, "client receives a server command")
local whom
N.onClient("DazedTest", "who", function(a, p) whom = p end)
local ch2 = E.character(3, 3, 0)
N.reply(ch2, "DazedTest", "who", {})
check(whom == ch2, "single player reply hands the handler its split-screen player")
-- near
check(N.near(ch, 11, 11, 0, 2) and not N.near(ch, 15, 10, 0, 2) and not N.near(ch, 10, 10, 1, 2), "near checks range and floor")

print(string.format("net_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
