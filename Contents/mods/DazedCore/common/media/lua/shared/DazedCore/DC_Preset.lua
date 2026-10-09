--[[ Dazed Core -- sandbox presets for the whole Dazed family.

     The Core's one option, DazedCore.Preset, picks Custom, Easy, Standard, Realistic or Hardcore. Each mod
     registers its page's values for the four named presets; while one is picked, those values replace what the
     page's own options say, and Custom leaves every option alone. Mods read options through Util.sandbox. ]]

require "DazedCore/DC_Util"

DazedCore = DazedCore or {}
DazedCore.Preset = DazedCore.Preset or {}
local R = DazedCore.Preset

R.NAMES = { "custom", "easy", "standard", "realistic", "hardcore" }   -- the enum's 1-based values
R.pages = R.pages or {}

--- A mod registers its page: { Option = { easy, standard, realistic, hardcore }, ... }.
function R.register(page, table_)
    if type(page) == "string" and type(table_) == "table" then R.pages[page] = table_ end
end

--- Which preset is picked, 1 (Custom) to 5.
function R.current()
    local sv = SandboxVars and SandboxVars.DazedCore
    local v = sv and tonumber(sv.Preset)
    if not v or v < 1 or v > #R.NAMES then return 1 end
    return math.floor(v)
end

--- The picked preset's value for one option, or nil when Custom is picked or the preset leaves it alone.
function R.override(page, name)
    local cur = R.current()
    if cur <= 1 then return nil end
    local opts = R.pages[page]
    local row = opts and opts[name]
    if type(row) ~= "table" then return nil end
    return row[cur - 1]
end

return R
