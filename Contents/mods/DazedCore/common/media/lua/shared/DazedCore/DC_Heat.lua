--[[ Dazed Core -- "heat": how much attention a spot has drawn, so a mod that makes noise or light
     (an air drop landing, a generator running, a still's thumper) can tell a mod that answers it (Dazed
     Hordes) without either requiring the other. Core keeps no pools and no decay: it is a plain dispatcher
     that does nothing until a consumer registers, on the authority only.

        DazedCore.Heat.add(x, y, 40, "airdrop_land")                      -- a pulse
        DazedCore.Heat.add(x, y, 5, "generator", { sustained = true })    -- a steady source, sent each tick it runs
        DazedCore.Heat.register("DazedHordes", function(x, y, amount, source, opts) ... end)
        DazedCore.Heat.unregister("DazedHordes")

     Amounts are relative (a crate landing is +40, opening it +20). Each consumer is called inside a guard;
     the first failure per consumer is printed once. `Heat.get(x, y)` is not here yet: the consumer owns
     the numbers. ]]

DazedCore = DazedCore or {}
DazedCore.Heat = DazedCore.Heat or {}
local H = DazedCore.Heat

H.consumers = H.consumers or {}      -- name -> fn
H.failed = H.failed or {}
H.sent = H.sent or 0
local order, dirty = {}, true

local function onClient() return isClient ~= nil and isClient() == true end

function H.register(name, fn)
    if type(name) ~= "string" or name == "" or type(fn) ~= "function" then return false end
    H.consumers[name] = fn
    H.failed[name] = nil
    dirty = true
    return true
end

function H.unregister(name)
    if H.consumers[name] then H.consumers[name] = nil; dirty = true; return true end
    return false
end

function H.any()
    for _ in pairs(H.consumers) do return true end
    return false
end

--- Tell every consumer about heat at x, y. Returns how many consumers heard it (0 on a client, or with none).
function H.add(x, y, amount, source, opts)
    if onClient() then return 0 end
    if not (x and y) then return 0 end
    if dirty then
        order = {}
        for name in pairs(H.consumers) do order[#order + 1] = name end
        table.sort(order)
        dirty = false
    end
    if #order == 0 then return 0 end
    amount = tonumber(amount) or 0
    source = tostring(source or "unknown")
    opts = opts or {}
    local heard = 0
    for i = 1, #order do
        local name = order[i]
        local fn = H.consumers[name]
        if fn then
            local ok, err = pcall(fn, x, y, amount, source, opts)
            if ok then
                heard = heard + 1
            elseif not H.failed[name] then
                H.failed[name] = tostring(err)
                print("DazedCore: heat consumer " .. name .. " failed: " .. tostring(err))
            end
        end
    end
    H.sent = H.sent + 1
    return heard
end

return H
