--[[ Dazed Core -- one right-click hook for the whole suite.

     Every right-click on the world runs every mod's OnFillWorldObjectContextMenu handler, and each of
     them reads the clicked square's objects again. Here Core adds one handler per event, collects the
     square and its objects once, and calls each registered mod in turn inside a guard, so one failing
     handler is reported once and never breaks the menu for the others (the Defences 0.2.0 bug class).

        DazedCore.Menu.world("DazedPlumbing.pipes", function(player, context, square, objects, worldobjects) ... end)
        DazedCore.Menu.inventory("DazedCooking.cuts", function(player, context, items) ... end)
        DazedCore.Menu.remove("DazedPlumbing.pipes")

     `player` is the IsoPlayer (not the index), `square` the clicked square (or nil when the click found
     none), `objects` a plain Lua array of the square's IsoObjects, `worldobjects` the engine's own list.
     Handlers run in id order; pass `order` (a number, default 100) as a fourth argument to come earlier or
     later. A handler may return nothing; it adds its options to `context` as before. The engine's `test`
     flag (the controller asking whether any option exists) is passed as a sixth argument. ]]

DazedCore = DazedCore or {}
DazedCore.Menu = DazedCore.Menu or {}
local M = DazedCore.Menu

M.worldHandlers = M.worldHandlers or {}          -- id -> { fn, order }
M.inventoryHandlers = M.inventoryHandlers or {}  -- id -> { fn, order }
M.failed = M.failed or {}                        -- id -> first error text
local worldOrder, invOrder, dirty = {}, {}, true

local function add(tbl, id, fn, order)
    if type(id) ~= "string" or id == "" or type(fn) ~= "function" then return false end
    tbl[id] = { fn = fn, order = tonumber(order) or 100 }
    M.failed[id] = nil
    dirty = true
    return true
end

--- Register a world right-click handler fn(player, context, square, objects, worldobjects, test).
function M.world(id, fn, order) return add(M.worldHandlers, id, fn, order) end

--- Register an inventory right-click handler fn(player, context, items).
function M.inventory(id, fn, order) return add(M.inventoryHandlers, id, fn, order) end

function M.remove(id)
    local had = M.worldHandlers[id] or M.inventoryHandlers[id]
    M.worldHandlers[id] = nil
    M.inventoryHandlers[id] = nil
    dirty = true
    return had ~= nil
end

local function sorted(tbl)
    local ids = {}
    for id in pairs(tbl) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local oa, ob = tbl[a].order, tbl[b].order
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return ids
end

local function rebuild()
    worldOrder, invOrder = sorted(M.worldHandlers), sorted(M.inventoryHandlers)
    dirty = false
end

local function playerOf(playerNum)
    if type(playerNum) ~= "number" then return playerNum end
    return getSpecificPlayer and getSpecificPlayer(playerNum) or nil
end

--- The clicked square and its objects as a Lua array, read once per click.
function M.squareOf(worldobjects)
    local square
    if worldobjects then
        local first = worldobjects[1]
        if first == nil and worldobjects.get then
            local ok, v = pcall(worldobjects.get, worldobjects, 0)
            if ok then first = v end
        end
        if first and first.getSquare then
            local ok, sq = pcall(first.getSquare, first)
            if ok then square = sq end
        end
    end
    local objects = {}
    if square and square.getObjects then
        local ok, list = pcall(square.getObjects, square)
        if ok and list then
            local n = list.size and list:size() or 0
            for i = 0, n - 1 do objects[#objects + 1] = list:get(i) end
        end
    end
    return square, objects
end

local function guarded(id, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not M.failed[id] then
        M.failed[id] = tostring(err)
        print("DazedCore: right-click handler " .. id .. " failed: " .. tostring(err))
    end
end

--- The world event, public so a test can drive it: (playerNum, context, worldobjects, test).
function M.onWorld(playerNum, context, worldobjects, test)
    if dirty then rebuild() end
    if #worldOrder == 0 then return end
    local player = playerOf(playerNum)
    if not player then return end
    local square, objects = M.squareOf(worldobjects)
    for i = 1, #worldOrder do
        local h = M.worldHandlers[worldOrder[i]]
        if h then guarded(worldOrder[i], h.fn, player, context, square, objects, worldobjects, test) end
    end
end

--- The inventory event: (playerNum, context, items).
function M.onInventory(playerNum, context, items)
    if dirty then rebuild() end
    if #invOrder == 0 then return end
    local player = playerOf(playerNum)
    if not player then return end
    for i = 1, #invOrder do
        local h = M.inventoryHandlers[invOrder[i]]
        if h then guarded(invOrder[i], h.fn, player, context, items) end
    end
end

--- Every handler with its order and first failure, for the report.
function M.stats()
    local out = {}
    for id, h in pairs(M.worldHandlers) do out[#out + 1] = { id = id, kind = "world", order = h.order, failed = M.failed[id] } end
    for id, h in pairs(M.inventoryHandlers) do out[#out + 1] = { id = id, kind = "inventory", order = h.order, failed = M.failed[id] } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

if Events and not M.hooked then
    M.hooked = true
    -- Wrappers, so a debug Lua reload (which redefines the handlers) keeps working.
    if Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(function(p, c, w, t) DazedCore.Menu.onWorld(p, c, w, t) end)
    end
    if Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(function(p, c, i) DazedCore.Menu.onInventory(p, c, i) end)
    end
end

return M
