--[[ Dazed Utilities: Core -- one Error Magnifier report for every Dazed mod. A mod adds a section
     with R.add(id, fn); fn returns a table and runs only when the player presses Copy. Registered
     on OnGameStart, and only when Error Magnifier is among the activated mods. ]]

require "DazedCore/DC_Util"

DazedCore.Report = DazedCore.Report or {}
local R = DazedCore.Report

R.MOD_ID = "DazedCore"
R.DISPLAY = "Dazed Utilities"
R.sections = R.sections or {}
R.order = R.order or {}

function R.add(id, fn)
    if type(id) ~= "string" or type(fn) ~= "function" then return end
    if not R.sections[id] then R.order[#R.order + 1] = id end
    R.sections[id] = fn
end

function R.magnifierActive()
    if not getActivatedMods then return false end
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods then return false end
    local n = 0
    local ok2 = pcall(function() n = mods:size() end)
    if not ok2 then return false end
    for i = 0, n - 1 do
        local id
        pcall(function() id = mods:get(i) end)
        if id == "errorMagnifier" then return true end
    end
    return false
end

function R.build()
    local out = { coreVersion = DazedCore.VERSION, multiplayer = isClient() and true or false }
    for _, id in ipairs(R.order) do
        local ok, section = pcall(R.sections[id])
        out[id] = ok and section or ("report failed: " .. tostring(section))
    end
    return out
end

function R.attach()
    if not R.magnifierActive() then return end
    local ok, em = pcall(require, "errorMagnifier_Main")
    if not ok or type(em) ~= "table" or type(em.registerDebugReport) ~= "function" then return end
    pcall(em.registerDebugReport, R.MOD_ID, R.build, R.DISPLAY)
end

if Events and Events.OnGameStart and not R.hooked then
    R.hooked = true
    Events.OnGameStart.Add(R.attach)
end

return R
