--[[ Dazed Core -- loads every shared module and prints one line so a console log
     shows the library arrived: DazedCore: ready -- 1.4.1, heavy parts v2, 0 power providers, 0 loads. ]]

require "DazedCore/DC_Util"
require "DazedCore/DC_Preset"
require "DazedCore/DC_Sync"
require "DazedCore/DC_Note"
require "DazedCore/DC_HeavyParts"
require "DazedCore/DC_Power"
require "DazedCore/DC_Migrate"
require "DazedCore/DC_Reach"
require "DazedCore/DC_Buildings"
require "DazedCore/DC_Climate"
require "DazedCore/DC_Detect"
require "DazedCore/DC_Net"
require "DazedCore/DC_DebugSpawn"
require "DazedCore/DC_ClearArea"
require "DazedCore/DC_Control"
require "DazedCore/DC_Tick"
require "DazedCore/DC_Menu"
require "DazedCore/DC_Radio"
require "DazedCore/DC_Heat"

DazedCore.Boot = DazedCore.Boot or {}
local B = DazedCore.Boot

--- A mod says it is here: name and version, for the ready line and the report.
B.mods = B.mods or {}
function B.register(id, version) B.mods[id] = version or "?" end

-- "1.8.4" -> 1, 8, 4 (missing parts are 0; anything that is not a number is 0).
local function parts(v)
    local a, b, c = string.match(tostring(v or ""), "^(%d+)%.?(%d*)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

--- Is Core at least this version? B.atLeast("1.9.0")
function B.atLeast(minVersion)
    local a1, b1, c1 = parts(DazedCore.VERSION)
    local a2, b2, c2 = parts(minVersion)
    if a1 ~= a2 then return a1 > a2 end
    if b1 ~= b2 then return b1 > b2 end
    return c1 >= c2
end

--- A mod says which Core it needs: true when this Core is new enough, else false after one console
--  warning naming the mod, so a Steam copy of Core that lags a mod is found in the log, not by a nil call.
B.tooOld = B.tooOld or {}
function B.require(id, minVersion)
    if B.atLeast(minVersion) then return true end
    if not B.tooOld[id] then
        B.tooOld[id] = minVersion
        print("DazedCore: " .. tostring(id) .. " needs Dazed Core " .. tostring(minVersion) .. ", have " .. tostring(DazedCore.VERSION) .. ": update Dazed Core")
    end
    return false
end

function B.summary()
    local n, loads = 0, 0
    for _ in pairs(DazedCore.Power.providers) do n = n + 1 end
    for _ in pairs(DazedCore.Power.loads) do loads = loads + 1 end
    local mods = {}
    for id, v in pairs(B.mods) do mods[#mods + 1] = id .. " " .. tostring(v) end
    table.sort(mods)
    for id, v in pairs(B.tooOld) do mods[#mods + 1] = id .. " NEEDS CORE " .. v end
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
