--[[ Dazed Utilities: Core -- the client end of DC_Note: a key sent by the server is translated here. ]]

require "DazedCore/DC_Note"

local N, U = DazedCore.Note, DazedCore.Util

local function onServerCommand(module, command, args)
    if module ~= N.MODULE or command ~= "note" or type(args) ~= "table" or not args.key then return end
    local player = getPlayer and getPlayer()
    if not player then return end
    U.haloNote(player, U.txtArgs(args.key, args.args), args.warn)
end

if Events and Events.OnServerCommand and not N.clientHooked then
    N.clientHooked = true
    Events.OnServerCommand.Add(onServerCommand)
end
