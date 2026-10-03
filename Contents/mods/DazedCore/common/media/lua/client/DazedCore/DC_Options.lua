--[[ Dazed Utilities: Core -- one "Dazed Utilities" page in the Mods options tab that every Dazed
     mod adds its own tick boxes to. Client-side player preferences only; world rules are sandbox
     options. Registered at file load: MainOptions builds its Mods page when the main screen is
     constructed and only if PZAPI.ModOptions.Data is non-empty then, and mods load after this file. ]]

DazedCore = DazedCore or {}
DazedCore.Options = DazedCore.Options or {}
local O = DazedCore.Options

O.ID = "DazedUtilities"

--- The shared page, made on first use; nil when the engine has no ModOptions.
function O.page()
    if not (PZAPI and PZAPI.ModOptions) then return nil end
    local page = PZAPI.ModOptions:getOptions(O.ID)
    if page then return page end
    return PZAPI.ModOptions:create(O.ID, "IGUI_DazedCore_Options")
end

--- A tick box: O.tick("DazedPower", "Sidebar", "IGUI_...", true, "IGUI_...Tip", onApply). The id is prefixed
--  by the mod so two mods never share one. Returns the option, or nil.
function O.tick(mod, id, labelKey, default, tipKey, onApply)
    local page = O.page()
    if not page then return nil end
    local full = mod .. "_" .. id
    local opt = page:getOption(full)
    if opt then return opt end
    opt = page:addTickBox(full, labelKey, default, tipKey)
    if onApply then
        opt.onChangeApply = function(self, value)
            if value ~= nil then self.value = value end
            pcall(onApply, value)
        end
    end
    return opt
end

--- A tick box's value: true unless the option exists and is unticked, so a missing page changes nothing.
function O.on(mod, id)
    if not (PZAPI and PZAPI.ModOptions) then return true end
    local page = PZAPI.ModOptions:getOptions(O.ID)
    local opt = page and page:getOption(mod .. "_" .. id)
    if not opt then return true end
    return opt:getValue() ~= false
end

return O
