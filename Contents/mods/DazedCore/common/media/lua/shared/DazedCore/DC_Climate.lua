--[[ Dazed Utilities: Core -- one place every Dazed mod asks how warm it is. A climate mod (Dazed Climate) registers
     itself as the provider; without one the answers come from the game, so no mod needs Dazed Climate to run. ]]

require "DazedCore/DC_Util"

DazedCore = DazedCore or {}
DazedCore.Climate = DazedCore.Climate or {}
local Cl = DazedCore.Climate
local try = DazedCore.Util.try

Cl.provider = Cl.provider or nil   -- { outdoor = fn() -> °C, at = fn(square) -> °C, forecast = fn(offset) -> {min, max, mean} }

--- A climate mod takes over the answers below.
function Cl.register(provider)
    if type(provider) == "table" then Cl.provider = provider end
end

local function ask(name, ...)
    local p = Cl.provider
    local fn = p and p[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

--- The outdoor air temperature in °C.
function Cl.outdoor()
    local v = ask("outdoor")
    if v ~= nil then return v end
    local cm = getClimateManager and getClimateManager()
    return cm and try(cm, "getTemperature") or nil
end

--- The air temperature in °C at a square: its room's when indoors and a climate mod tracks rooms.
function Cl.temperatureAt(square)
    local v = ask("at", square)
    if v ~= nil then return v end
    local cm = getClimateManager and getClimateManager()
    v = square and cm and try(cm, "getAirTemperatureForSquare", square)
    if v ~= nil then return v end
    return Cl.outdoor()
end

--- Low, high and mean for the day `offset` days from today, or nil when no climate mod forecasts.
function Cl.forecast(offset) return ask("forecast", offset or 0) end

return Cl
