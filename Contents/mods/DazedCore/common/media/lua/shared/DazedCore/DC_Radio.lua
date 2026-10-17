--[[ Dazed Core -- one way to put a line on the radio, shared by Signal's beacons, Air Drops' warnings and
     anything else that wants players with a tuned radio to hear something.

     Server (or single player):
        DazedCore.Radio.air(freq, x, y, range, text, opts)
            freq   the channel number radios are tuned to (the game's own units, e.g. 93200)
            text   a string every listener gets, or fn(player) -> string | nil (nil skips that player)
            opts   { call = "KY-7" (prefix shown as [KY-7]), guid = "DSIG-BEACON", color = {r,g,b}, z = 0,
                     key = true (text is a translation key, resolved on the client), args = {...} }
        Every player within range + MARGIN of x, y is sent the line; a client plays it through vanilla's
        ZomboidRadio.SendTransmission so it shows on every tuned radio and in the radio log, and falls back
        to a halo note when the player holds or stands by a radio tuned to freq. The route is printed once.
     Client:
        DazedCore.Radio.onAir(function(line, freq, x, y, opts) end)   -- a listener (Signal's logger)
     DazedCore.Radio.survivorFreq() is the suite's shared survivor channel (SURVIVOR_FREQ, which a mod may
     set before anything airs). ]]

require "DazedCore/DC_Util"
require "DazedCore/DC_Net"

DazedCore = DazedCore or {}
DazedCore.Radio = DazedCore.Radio or {}
local R = DazedCore.Radio
local U = DazedCore.Util
local Net = DazedCore.Net

R.MODULE = "DazedCore"
R.COMMAND = "radio"
R.MARGIN = 50                       -- tiles past `range` a player still receives the line (the radio decides audibility)
R.GUID = "DAZED-RADIO"
R.COLOR = { 1.0, 0.82, 0.45 }
R.SURVIVOR_FREQ = R.SURVIVOR_FREQ or 101100
R.listeners = R.listeners or {}
local route

function R.survivorFreq() return R.SURVIVOR_FREQ end

--- "[CALL] text" as listeners read it.
function R.lineOf(call, text)
    local line = tostring(text or "")
    if call and call ~= "" then line = "[" .. tostring(call) .. "] " .. line end
    return line
end

local function onServer() return isServer ~= nil and isServer() == true end
local function onClient() return isClient ~= nil and isClient() == true end

--- Put a line on the air from x, y (authority only: a multiplayer client gets 0). Returns how many players were sent it.
function R.air(freq, x, y, range, text, opts)
    if not (freq and x and y) then return 0 end
    if onClient() then return 0 end
    opts = opts or {}
    local sent = 0
    local players = U.players()
    local reach = (tonumber(range) or 100) + R.MARGIN
    for i = 1, #players do
        local p = players[i]
        local line = text
        if type(text) == "function" then
            local ok, v = pcall(text, p)
            line = ok and v or nil
        end
        if line ~= nil and (not onServer() or Net.near(p, x, y, nil, reach)) then
            local args = { x = x, y = y, z = opts.z or 0, f = freq, r = tonumber(range) or 100, t = line,
                           c = opts.call, g = opts.guid, k = opts.key and true or nil, a = opts.args,
                           col = opts.color }
            Net.reply(p, R.MODULE, R.COMMAND, args)
            sent = sent + 1
        end
    end
    return sent
end

--- Client side: fn(line, freq, x, y, args) for every line this machine airs.
function R.onAir(fn)
    if type(fn) == "function" then R.listeners[#R.listeners + 1] = fn end
end

-- A radio the player holds or stands by, on and tuned to f (client).
local function tunedNear(player, f)
    local function tuned(dd)
        return dd and U.try(dd, "getIsTurnedOn") == true and U.try(dd, "getChannel") == f
    end
    for _, it in ipairs({ U.try(player, "getPrimaryHandItem"), U.try(player, "getSecondaryHandItem") }) do
        if it and instanceof and instanceof(it, "Radio") and tuned(U.try(it, "getDeviceData")) then return true end
    end
    local sq = U.try(player, "getCurrentSquare")
    if not sq then return false end
    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    for x = cx - 6, cx + 6 do
        for y = cy - 6, cy + 6 do
            local s2 = U.squareAt(x, y, cz)
            if s2 then
                local objs = s2:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof and instanceof(o, "IsoWaveSignal") and tuned(U.try(o, "getDeviceData")) then return true end
                end
            end
        end
    end
    return false
end

local lastKey, lastAt = nil, -1  -- repeat filter (only with the game's clock)

--- Play one aired line on this machine (public so a test can drive it). The same line reaching one machine
--- twice in a row within a second (split screen: one copy per local player) plays on the radios once.
function R.receive(a, player)
    player = player or (getPlayer and getPlayer())
    local text = a.t
    if a.k then text = U.txtArgs(a.t, a.a) end
    local line = R.lineOf(a.c, text)
    local col = a.col or R.COLOR
    if col.r then col = { col.r, col.g, col.b } end
    local key = tostring(a.f) .. ":" .. tostring(a.x) .. ":" .. tostring(a.y) .. ":" .. line
    local now = getTimestampMs and getTimestampMs()
    local repeated = now ~= nil and key == lastKey and now - lastAt < 1000
    lastKey, lastAt = key, now
    local radio = getZomboidRadio and getZomboidRadio()
    local ok = repeated
    if not repeated and radio and radio.SendTransmission then
        ok = pcall(radio.SendTransmission, radio, math.floor(a.x), math.floor(a.y), math.floor(a.f), line,
            a.g or R.GUID, "", col[1], col[2], col[3], math.floor(a.r or 100), false)
    end
    if not ok and player and tunedNear(player, a.f) then
        U.haloNote(player, line)
    end
    local r = ok and "ZomboidRadio.SendTransmission" or "halo fallback"
    if route ~= r then
        route = r
        print("DazedCore: radio lines reach radios through " .. r)
    end
    for i = 1, #R.listeners do pcall(R.listeners[i], line, a.f, a.x, a.y, a) end
    return ok
end

Net.onClient(R.MODULE, R.COMMAND, R.receive)

return R
