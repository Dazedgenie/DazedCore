--[[ Dazed Utilities: Core -- who is in charge, and keeping clients in step.

     The AUTHORITY (single player, or the server) owns every change to the world. A client never
     writes it. Global ModData tables a mod registers here with `track` are sent to clients by the
     authority after a change and asked for by a client when it joins. `version` goes up on every
     change seen on this side, so a cache keyed on it knows when to rebuild. ]]

DazedCore = DazedCore or {}
DazedCore.Sync = DazedCore.Sync or {}
local S = DazedCore.Sync

S.keys = S.keys or {}            -- tracked global ModData tags, in registration order
S.version = S.version or 0
S.dirty = S.dirty or {}

--- A client of someone else's world. Single player and a server are not.
function S.isClient() return isClient ~= nil and isClient() == true end

--- May this machine change the world?
function S.authority() return not S.isClient() end

--- Register a global ModData tag to keep in step across the network.
function S.track(key)
    for _, k in ipairs(S.keys) do if k == key then return end end
    S.keys[#S.keys + 1] = key
    if S.isClient() and ModData and ModData.request then pcall(ModData.request, key) end
end

--- Note that a synced table changed; the authority sends it at the next flush, or at once with `now`.
function S.touch(key, now)
    S.version = S.version + 1
    if S.authority() and key then S.dirty[key] = true end
    if now then S.flush() end
end

--- Send every changed table to the clients. Called once a minute.
function S.flush()
    if not S.authority() then return end
    for key in pairs(S.dirty) do
        S.dirty[key] = nil
        if isServer and isServer() and ModData and ModData.transmit then pcall(ModData.transmit, key) end
    end
end

local function request()
    if not S.isClient() or not (ModData and ModData.request) then return end
    for _, key in ipairs(S.keys) do pcall(ModData.request, key) end
end

local function receive(key, tbl)
    if S.authority() then return end        -- a copy arriving on the server is never adopted
    for _, k in ipairs(S.keys) do
        if k == key and tbl and ModData and ModData.add then
            ModData.add(key, tbl)
            S.version = S.version + 1
        end
    end
end

if Events and not S.hooked then
    S.hooked = true
    if Events.OnReceiveGlobalModData then Events.OnReceiveGlobalModData.Add(receive) end
    if Events.OnGameStart then Events.OnGameStart.Add(request) end
    if Events.OnConnected then Events.OnConnected.Add(request) end
    if Events.EveryOneMinute then Events.EveryOneMinute.Add(S.flush) end
end

return S
