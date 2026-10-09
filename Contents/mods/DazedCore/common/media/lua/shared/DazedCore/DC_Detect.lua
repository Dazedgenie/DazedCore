--[[ Dazed Utilities: Core -- which other mods are loaded, so a Dazed feature can step aside.

     A mod registers a feature with the mod IDs that already do it (`yieldTo`). `yields(feature)` answers
     whether any of them is active; the answer is cached, and one console line names each feature that yielded. ]]

DazedCore = DazedCore or {}
DazedCore.Detect = DazedCore.Detect or {}
local D = DazedCore.Detect

D.features = D.features or {}
D.cache = D.cache or {}
local active

-- Build the set of active mod IDs once; B42 server lists may carry a leading backslash.
local function activeSet()
    if active then return active end
    active = {}
    local list = getActivatedMods and getActivatedMods()
    local n = list and list.size and list:size() or 0
    for i = 0, n - 1 do
        local id = tostring(list:get(i))
        active[id] = true
        active[(string.gsub(id, "^\\", ""))] = true
    end
    return active
end

--- Is this mod ID loaded?
function D.isActive(id)
    if type(id) ~= "string" or id == "" then return false end
    return activeSet()[id] == true
end

--- The first loaded mod from a list of IDs, or nil.
function D.firstActive(ids)
    for _, id in ipairs(ids or {}) do
        if D.isActive(id) then return id end
    end
    return nil
end

--- Register a feature: D.yieldTo("DazedEssentials.Pry", { "BB_CommonSense", "BB_BreakingIn" }).
function D.yieldTo(feature, ids)
    if type(feature) ~= "string" or type(ids) ~= "table" then return end
    D.features[feature] = ids
    D.cache[feature] = nil
end

--- Should this feature stay off because another mod already does it?
function D.yields(feature)
    local c = D.cache[feature]
    if c ~= nil then return c ~= false end
    local hit = D.firstActive(D.features[feature])
    D.cache[feature] = hit or false
    if hit then print("DazedCore: " .. feature .. " yields to " .. hit) end
    return hit ~= nil
end

--- Forget cached answers; tests and a mod list change use it.
function D.reset()
    active = nil
    D.cache = {}
end

return D
