--[[ Dazed Utilities: Core -- loads every shared module and prints one line so a console log
     shows the library arrived: DazedCore: ready -- 1.1.0, heavy parts v2, 0 power providers, 0 loads. ]]

require "DazedCore/DC_Util"
require "DazedCore/DC_Preset"
require "DazedCore/DC_Sync"
require "DazedCore/DC_Note"
require "DazedCore/DC_HeavyParts"
require "DazedCore/DC_Power"
require "DazedCore/DC_Migrate"
require "DazedCore/DC_Reach"
require "DazedCore/DC_Buildings"

DazedCore.Boot = DazedCore.Boot or {}
local B = DazedCore.Boot

--- A mod says it is here: name and version, for the ready line and the report.
B.mods = B.mods or {}
function B.register(id, version) B.mods[id] = version or "?" end

function B.summary()
    local n, loads = 0, 0
    for _ in pairs(DazedCore.Power.providers) do n = n + 1 end
    for _ in pairs(DazedCore.Power.loads) do loads = loads + 1 end
    local mods = {}
    for id, v in pairs(B.mods) do mods[#mods + 1] = id .. " " .. tostring(v) end
    table.sort(mods)
    return string.format("DazedCore: ready -- %s, heavy parts v%d, %d power provider%s, %d load%s, mods: %s",
        DazedCore.VERSION, DazedCore.Heavy.VERSION, n, n == 1 and "" or "s", loads, loads == 1 and "" or "s",
        #mods > 0 and table.concat(mods, ", ") or "none")
end

local function ready()
    B.done = true
    print(B.summary())
end

if Events and Events.OnGameStart and not B.hooked then
    B.hooked = true
    Events.OnGameStart.Add(ready)
    if Events.OnServerStarted then Events.OnServerStarted.Add(ready) end
end

return B
