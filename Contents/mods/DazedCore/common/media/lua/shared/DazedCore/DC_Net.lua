--[[ Dazed Utilities: Core -- one way to ask the authority to change the world, and to answer a player.

     A mod registers server handlers with `on(module, command, fn)` and asks with `send`. On a client the
     request travels as a client command; in single player (or on the server itself) the handler runs at
     once. Handlers must re-check everything: a client's arguments are a request, never a fact. ]]

require "DazedCore/DC_Util"

DazedCore = DazedCore or {}
DazedCore.Net = DazedCore.Net or {}
local N = DazedCore.Net
local U = DazedCore.Util

N.server = N.server or {}       -- module -> command -> { fn, every }
N.client = N.client or {}       -- module -> command -> fn
local lastAt = {}

local function onClient() return isClient ~= nil and isClient() == true end
local function onServer() return isServer ~= nil and isServer() == true end

local function now() return getTimestampMs and getTimestampMs() or 0 end

local function who(player)
    local name = U.try(player, "getUsername")
    return (type(name) == "string" and name ~= "") and name or tostring(player)
end

--- Register a server handler fn(player, args); `every` (ms) drops repeats from one player faster than that.
function N.on(module, command, fn, every)
    if type(module) ~= "string" or type(command) ~= "string" or type(fn) ~= "function" then return end
    N.server[module] = N.server[module] or {}
    N.server[module][command] = { fn = fn, every = every }
end

--- Register a client handler fn(args, player) for a message the authority sends with `reply`.
--  `player` is the one replied to in single player and split screen; over the network it is nil, so use getPlayer().
function N.onClient(module, command, fn)
    if type(module) ~= "string" or type(command) ~= "string" or type(fn) ~= "function" then return end
    N.client[module] = N.client[module] or {}
    N.client[module][command] = fn
end

-- Run one server handler with the rate limit and a guard, so one bad request never breaks the event.
local function dispatch(module, command, player, args)
    local h = N.server[module] and N.server[module][command]
    if not h then return false end
    if h.every then
        local key = who(player) .. "|" .. module .. "|" .. command
        local t = now()
        if lastAt[key] and t - lastAt[key] < h.every then return false end
        lastAt[key] = t
    end
    local ok, err = pcall(h.fn, player, type(args) == "table" and args or {})
    if not ok then print("DazedCore: " .. module .. "." .. command .. " failed: " .. tostring(err)) end
    return ok
end

--- Ask the authority to run module.command for this player.
function N.send(player, module, command, args)
    if not player then return false end
    if onClient() then
        if sendClientCommand then pcall(sendClientCommand, player, module, command, args or {}) end
        return true
    end
    return dispatch(module, command, player, args)
end

--- Answer one player: a server command on a server, the client handler at once in single player.
--  Off a server the handler also gets `player`, so split screen answers the right one.
function N.reply(player, module, command, args)
    if onServer() then
        if sendServerCommand and player then pcall(sendServerCommand, player, module, command, args or {}) end
        return
    end
    local fn = N.client[module] and N.client[module][command]
    if fn then pcall(fn, args or {}, player) end
end

--- Server-side check that a player stands within `max` tiles of x, y on the same floor.
function N.near(player, x, y, z, max)
    if not (player and x and y) then return false end
    local px, py, pz = U.try(player, "getX"), U.try(player, "getY"), U.try(player, "getZ")
    if not (px and py) then return false end
    if z and pz and math.floor(pz) ~= math.floor(z) then return false end
    local dx, dy = px - x, py - y
    return dx * dx + dy * dy <= (max or 2) * (max or 2)
end

if Events and not N.hooked then
    N.hooked = true
    if Events.OnClientCommand then
        Events.OnClientCommand.Add(function(module, command, player, args)
            if N.server[module] then dispatch(module, command, player, args) end
        end)
    end
    if Events.OnServerCommand then
        Events.OnServerCommand.Add(function(module, command, args)
            local fn = N.client[module] and N.client[module][command]
            if fn then pcall(fn, args or {}) end
        end)
    end
end

return N
