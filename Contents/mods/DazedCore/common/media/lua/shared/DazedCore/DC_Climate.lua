--[[ Dazed Core -- one place every Dazed mod asks how warm it is. A climate mod (Dazed Climate) registers
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

-- Share of normal food ageing by temperature: { °C, share }, straight lines between, flat past the ends.
Cl.SPOIL_CURVE = { { -2, 0.05 }, { 0, 0.3 }, { 4, 0.3 }, { 10, 0.7 }, { 15, 1.0 } }

--- How fast food spoils at `t` °C compared with a warm room (1). A mod may pass its own `curve` in the same shape.
function Cl.spoilShare(t, curve)
    local c = curve or Cl.SPOIL_CURVE
    if t <= c[1][1] then return c[1][2] end
    for i = 2, #c do
        if t <= c[i][1] then
            local a, b = c[i - 1], c[i]
            return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
        end
    end
    return c[#c][2]
end

-- Temperature units. Everything above stays in °C; only text shown to the player converts. The drop-down on the
-- Dazed Core options page (1 Game setting, 2 Celsius, 3 Fahrenheit) wins, and Game setting follows the game's own
-- Display > Temperature option.
Cl.UNITS_OPTION = "TempUnits"

--- True when temperatures should read in Celsius.
function Cl.celsius()
    local O = DazedCore.Options
    local pick = O and O.pick and O.pick("DazedCore", Cl.UNITS_OPTION)
    if pick == 2 then return true elseif pick == 3 then return false end
    local core = getCore and getCore()
    local v = core and try(core, "getOptionDisplayAsCelsius")
    if v ~= nil then return v == true end
    return true
end

--- A °C reading in the player's unit: the number and "C" or "F".
function Cl.display(t)
    if Cl.celsius() then return t, "C" end
    return t * 9 / 5 + 32, "F"
end

--- A °C reading as the player likes to read it: "23 C" or "73 F", with `decimals` places (default none).
function Cl.tempText(t, decimals)
    local v, unit = Cl.display(t)
    if decimals and decimals > 0 then return string.format("%." .. decimals .. "f %s", v, unit) end
    return string.format("%d %s", math.floor(v + 0.5), unit)
end

return Cl
