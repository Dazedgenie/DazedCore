--[[ Dazed Core -- a short line to a player. A server sends the translation KEY (it has
     no translations); the client shows it (DC_NoteClient). Single player shows it at once. ]]

require "DazedCore/DC_Util"

DazedCore.Note = DazedCore.Note or {}
local N = DazedCore.Note
local U = DazedCore.Util

N.MODULE = "DazedCore"
N.EVERY_MS = 3000
local saidAt = {}

local function who(character)
    local name = U.try(character, "getUsername")
    return (type(name) == "string" and name ~= "") and name or tostring(character)
end

--- Say the translated key, with {1}... args, in the warning colour if `warn`.
function N.say(character, key, args, warn)
    if not (character and key) then return end
    if isServer and isServer() then
        if sendServerCommand then
            pcall(sendServerCommand, character, N.MODULE, "note", { key = key, args = args, warn = warn })
        end
    else
        U.haloNote(character, U.txtArgs(key, args), warn)
    end
end

--- The same, but at most once every EVERY_MS per player: for refusals the cursor asks every frame.
function N.limited(character, key, args, warn)
    if not character then return end
    local now = getTimestampMs and getTimestampMs() or 0
    local id = who(character)
    local last = saidAt[id]
    if last and now - last <= N.EVERY_MS then return end
    saidAt[id] = now
    N.say(character, key, args, warn)
end

return N
