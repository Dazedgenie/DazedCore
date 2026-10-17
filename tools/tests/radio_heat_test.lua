-- Headless check of Radio (air, receive, listeners), Heat (dispatcher) and Net.broadcast.
-- Run: lua radio_heat_test.lua <lua root>
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
getTimestampMs = function() return 1000 end

------------------------------------------------------------------ Net.broadcast
local N = require "DazedCore/DC_Net"
local ch = E.character(10, 10, 0)
getSpecificPlayer = function(i) if i == 0 then return ch end return nil end
getPlayer = function() return ch end
local got
N.onClient("DazedTest", "all", function(a, p) got = { a.n, p } end)
check(N.broadcast("DazedTest", "all", { n = 7 }) and got and got[1] == 7 and got[2] == ch, "single player: the client handler runs for the local player")
isServer = function() return true end
local sent
sendServerCommand = function(...) sent = { ... } end
N.broadcast("DazedTest", "all", { n = 8 })
check(sent and sent[1] == "DazedTest" and sent[2] == "all" and sent[3].n == 8, "server: one server command with no player")
isServer = nil; sendServerCommand = nil
isClient = function() return true end
check(N.broadcast("DazedTest", "all", {}) == false, "a client never broadcasts")
isClient = nil

------------------------------------------------------------------ Radio
local R = require "DazedCore/DC_Radio"
local heard = {}
R.onAir(function(line, f, x, y) heard[#heard + 1] = { line, f, x, y } end)
local tx
getZomboidRadio = function() return { SendTransmission = function(self, x, y, f, line, guid, _, r, g, b, range, flag) tx = { x, y, f, line, guid, range } end } end
local n = R.air(93200, 100.4, 200.6, 60, "Crate inbound", { call = "ARMY" })
check(n == 1 and tx and tx[1] == 100 and tx[3] == 93200 and tx[4] == "[ARMY] Crate inbound" and tx[5] == R.GUID and tx[6] == 60, "single player: aired at once through ZomboidRadio: " .. tostring(tx and tx[4]))
check(#heard == 1 and heard[1][1] == "[ARMY] Crate inbound" and heard[1][2] == 93200, "listeners hear the line")
check(printed("radio lines reach radios through ZomboidRadio.SendTransmission"), "route printed")
E.printed = {}
R.air(93200, 1, 1, 10, "again")
check(#E.printed == 0, "route printed once")
-- per-player text and the server distance filter
isServer = function() return true end
local far, near = E.character(500, 500, 0), E.character(110, 200, 0)
local online = { far, near }
getOnlinePlayers = function() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
local replies = {}
sendServerCommand = function(p, m, c, a) replies[#replies + 1] = { p, m, c, a } end
n = R.air(93200, 100, 200, 60, function(p) if p == near then return "for you" end return "for anyone" end)
check(n == 1 and #replies == 1 and replies[1][1] == near and replies[1][4].t == "for you" and replies[1][3] == "radio", "server: only players within range + margin get a reply, with their own text")
n = R.air(93200, 100, 200, 60, function(p) return nil end)
check(n == 0, "a nil text skips the player")
isServer = nil; sendServerCommand = nil; getOnlinePlayers = nil
-- the halo fallback when the radio API is missing and a tuned radio is in hand
getZomboidRadio = nil
local dd = { getIsTurnedOn = function() return true end, getChannel = function() return 93200 end }
local radioItem = { getDeviceData = function() return dd end }
instanceof = function(o, cls) return o == radioItem and cls == "Radio" end
function ch:getPrimaryHandItem() return radioItem end
function ch:getSecondaryHandItem() return nil end
function ch:getCurrentSquare() return E.square(10, 10, 0) end
local before = #ch.notes
R.receive({ x = 1, y = 1, f = 93200, r = 10, t = "IGUI_Test_Key", k = true, c = "KY" }, ch)
check(#ch.notes == before + 1 and ch.notes[#ch.notes] == "[KY] IGUI_Test_Key", "halo fallback with a tuned radio in hand, key resolved: " .. tostring(ch.notes[#ch.notes]))
dd.getChannel = function() return 1 end
R.receive({ x = 1, y = 1, f = 93200, r = 10, t = "x" }, ch)
check(#ch.notes == before + 1, "no tuned radio, no halo")
check(R.survivorFreq() == R.SURVIVOR_FREQ, "survivor frequency")

------------------------------------------------------------------ Heat
local H = require "DazedCore/DC_Heat"
check(H.add(1, 2, 40, "airdrop_land") == 0 and not H.any(), "no consumer: nothing happens")
local calls = {}
check(H.register("DazedHordes", function(x, y, a, s, o) calls[#calls + 1] = { x, y, a, s, o.sustained } end), "register")
H.register("Bad", function() error("heat boom") end)
check(H.add(1, 2, 40, "airdrop_land") == 1 and #calls == 1 and calls[1][3] == 40 and calls[1][4] == "airdrop_land" and calls[1][5] == nil, "a pulse reaches the consumer, the failing one is counted out")
check(H.failed["Bad"] and printed("heat consumer Bad failed"), "failure printed once")
E.printed = {}
H.add(1, 2, 5, "generator", { sustained = true })
check(#calls == 2 and calls[2][5] == true and #E.printed == 0, "sustained flag passes, no second print")
isClient = function() return true end
check(H.add(1, 2, 9, "x") == 0 and #calls == 2, "clients never dispatch")
isClient = nil
check(H.unregister("Bad") and not H.unregister("Bad") and H.sent == 2, "unregister and count")

print(string.format("radio_heat_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
