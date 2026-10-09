--[[ Dazed Core -- schema versions on saved data, so a later release can change what
     it stores without a clean break. A mod stamps its ModData table with `stamp` when it first
     writes it, and runs `upgrade` with its list of steps when it reads it back. ]]

DazedCore = DazedCore or {}
DazedCore.Migrate = DazedCore.Migrate or {}
local M = DazedCore.Migrate

M.KEY = "_v"            -- the version field inside a mod's own ModData table

--- Mark a table as written by schema `version` (only when it has no version yet, or an older one).
function M.stamp(t, version)
    if type(t) ~= "table" then return t end
    if (t[M.KEY] or 0) < version then t[M.KEY] = version end
    return t
end

function M.versionOf(t)
    return type(t) == "table" and tonumber(t[M.KEY]) or 0
end

--- Bring a table up to `latest`. `steps[n]` turns version n-1 data into version n and may return
--  a replacement table. Returns the table and whether anything changed.
function M.upgrade(t, latest, steps)
    if type(t) ~= "table" then return t, false end
    local v = M.versionOf(t)
    if v >= latest then return t, false end
    for n = v + 1, latest do
        local step = steps and steps[n]
        if type(step) == "function" then
            local ok, out = pcall(step, t)
            if ok and type(out) == "table" then t = out end
        end
        t[M.KEY] = n
    end
    return t, true
end

return M
