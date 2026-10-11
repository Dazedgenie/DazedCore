--[[ Dazed Core -- debug spawn: every item a Dazed mod names, placed in a ring of open squares around the player.

     A mod registers a set with `register(id, name, items)`, where items() returns full types. The right-click
     menu (DC_DebugSpawnMenu) offers one row per set to anyone `allowed`: the game in debug mode, or staff.
     The authority does the work, so on a server the parts land for everyone.

     Each placeable item is created in the player's inventory and put down through vanilla's own
     ISMoveableSpriteProps:placeMoveable, the same call a player's place action ends in. That runs every mod's
     placing hooks (a controller becomes a generator, a tank gets its fluid state, a heavy part stays whole),
     and its own canPlace check skips walls, trees, water and occupied squares. Squares are tried ring by ring
     from two tiles out, every facing in turn, so a wall-mounted part finds a wall when there is one. A square
     is left empty around each part so every one can be clicked on its own. Whatever finds no room, and every
     item that is not a moveable (books, kits, filters), stays in the player's inventory. ]]

require "DazedCore/DC_Util"
require "DazedCore/DC_Net"
require "DazedCore/DC_Note"

DazedCore = DazedCore or {}
DazedCore.DebugSpawn = DazedCore.DebugSpawn or {}
local S = DazedCore.DebugSpawn
local U = DazedCore.Util
local try = U.try

S.MODULE, S.COMMAND = "DazedCore", "debugSpawn"
S.MIN_RADIUS = 2            -- the ring next to the player stays clear, so they can walk out
S.MAX_RADIUS = 12
S.FACES = { "S", "E", "W", "N" }
S.sets = S.sets or {}
S.order = S.order or {}

--- A mod offers its items: `id` a short key, `name` what the menu calls them ("Dazed Power"), `items` a
--  function returning full types. Asked when the row is used, so it may read tables that load later.
--  `opts` is optional: `label` replaces the row's "Spawn all ... items" text, and `place(character)` puts
--  the set down itself (returning placed, kept) for parts that need a state no item carries.
function S.register(id, name, items, opts)
    opts = type(opts) == "table" and opts or {}
    local place = type(opts.place) == "function" and opts.place or nil
    if type(id) ~= "string" or (type(items) ~= "function" and not place) then return end
    if not S.sets[id] then S.order[#S.order + 1] = id end
    S.sets[id] = { id = id, name = name or id, items = items, label = opts.label, place = place }
end

--- Staff by capability, the way Dazed Power decides it: B42 roles name an ordinary player "user", so the
--  access-level string alone lets everyone through. Admins hold UseMovablesCheat, moderators BanUnbanUser.
function S.isStaff(character)
    if not character then return false end
    local role = try(character, "getRole")
    if role and Capability then
        for _, cap in ipairs({ Capability.UseMovablesCheat, Capability.BanUnbanUser }) do
            if cap ~= nil and try(role, "hasCapability", cap) == true then return true end
        end
        return false
    end
    local lvl = try(character, "getAccessLevel")
    if type(lvl) ~= "string" then return false end
    lvl = string.lower(lvl)
    return lvl == "admin" or lvl == "moderator"
end

--- May this character spawn? The game in debug mode (single player, or a server started with -debug), or staff.
function S.allowed(character)
    if getDebug and getDebug() == true then return true end
    return S.isStaff(character)
end

--- Squares around cx, cy in rings of growing distance: { x, y } from minR out to maxR, each ring walked once.
function S.ringOrder(cx, cy, minR, maxR)
    local out = {}
    for r = minR, maxR do
        if r == 0 then
            out[#out + 1] = { cx, cy }
        else
            for dx = -r, r do out[#out + 1] = { cx + dx, cy - r } end
            for dy = -r + 1, r do out[#out + 1] = { cx + r, cy + dy } end
            for dx = r - 1, -r, -1 do out[#out + 1] = { cx + dx, cy + r } end
            for dy = r - 1, -r + 1, -1 do out[#out + 1] = { cx - r, cy + dy } end
        end
    end
    return out
end

local function key(x, y) return x .. "," .. y end

--- The squares a part would cover with its anchor on `sq`: the sprite grid for a multi-square part.
local function footprint(props, sq)
    if not props.isMultiSprite then return { sq } end
    local ok, grid = pcall(props.getSpriteGridInfo, props, sq, false)
    if not ok or type(grid) ~= "table" or #grid == 0 then return nil end
    local out = {}
    for i, g in ipairs(grid) do
        if not g.square then return nil end
        out[i] = g.square
    end
    return out
end

local function isFree(used, squares)
    for _, s in ipairs(squares) do
        if used[key(s:getX(), s:getY())] then return false end
    end
    return true
end

--- Mark a placed part's squares and the ring of squares around them, so the next part keeps a gap.
local function claim(used, squares)
    for _, s in ipairs(squares) do
        local x, y = s:getX(), s:getY()
        for dx = -1, 1 do for dy = -1, 1 do used[key(x + dx, y + dy)] = true end end
    end
end

--- The props to try for an item, its own facing first: { props, spriteName }.
local function facesOf(sprite)
    local base = ISMoveableSpriteProps.new(sprite)
    if not (base and base.isMoveable) then return {} end
    local out = { { base, sprite } }
    local ok, faces = pcall(base.getFaces, base)
    if ok and type(faces) == "table" then
        for _, f in ipairs(S.FACES) do
            local name = faces[f]
            if name and name ~= sprite then
                local p = ISMoveableSpriteProps.new(name)
                if p and p.isMoveable then out[#out + 1] = { p, name } end
            end
        end
    end
    return out
end

--- Put one item down on the first open square that takes it. True when it left the inventory.
local function placeOne(character, inv, item, squares, used)
    local sprite = try(item, "getWorldSprite")
    if type(sprite) ~= "string" or not ISMoveableSpriteProps then return false end
    local faces = facesOf(sprite)
    if #faces == 0 then return false end
    for _, sq in ipairs(squares) do
        if not used[key(sq:getX(), sq:getY())] then
            for _, face in ipairs(faces) do
                local props = face[1]
                local foot = footprint(props, sq)
                -- The cursor's own test first (water, walls, a full square), so a square that cannot take it never
                -- reaches the place call and the placing hooks' console line.
                local fits = foot and isFree(used, foot)
                if fits and props.canPlaceMoveable then
                    local okC, can = pcall(props.canPlaceMoveable, props, character, sq, item)
                    fits = not okC or (can and true or false)
                end
                if fits then
                    -- placeMoveable finds the item by its own sprite and the props say which way it faces
                    local ok, err = pcall(props.placeMoveable, props, character, sq, sprite)
                    if not ok then print("DazedCore: debug spawn " .. tostring(sprite) .. ": " .. tostring(err)) end
                    if try(inv, "contains", item) ~= true then
                        claim(used, foot)
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Spawn one registered set around the character (authority). Returns placed, kept (in the bag), missing.
function S.spawn(character, id)
    local set = S.sets[id]
    local inv = character and try(character, "getInventory")
    if not (set and inv) then return 0, 0, 0 end
    if set.place then
        local okP, placed, kept = pcall(set.place, character)
        if not okP then print("DazedCore: debug spawn " .. id .. ": " .. tostring(placed)); return 0, 0, 0 end
        print(string.format("DazedCore: debug spawn %s -- %d placed", id, tonumber(placed) or 0))
        return tonumber(placed) or 0, tonumber(kept) or 0, 0
    end
    local ok, list = pcall(set.items)
    if not ok or type(list) ~= "table" then return 0, 0, 0 end

    local cx, cy = math.floor(character:getX()), math.floor(character:getY())
    local z = math.floor(character:getZ())
    local cell = getCell and getCell()
    local squares = {}
    for _, p in ipairs(S.ringOrder(cx, cy, S.MIN_RADIUS, S.MAX_RADIUS)) do
        local sq = cell and cell:getGridSquare(p[1], p[2], z)
        if sq then squares[#squares + 1] = sq end
    end

    local used, placed, kept, missing = {}, 0, 0, 0
    local sm = getScriptManager and getScriptManager()
    for _, fullType in ipairs(list) do
        if sm and not try(sm, "getItem", fullType) then
            missing = missing + 1
        else
            local item = inv:AddItem(fullType)
            if not item then
                missing = missing + 1
            elseif placeOne(character, inv, item, squares, used) then
                placed = placed + 1
            else
                kept = kept + 1
                if isServer and isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
            end
        end
    end
    print(string.format("DazedCore: debug spawn %s at %d,%d,%d -- %d placed, %d in the bag, %d missing",
        id, cx, cy, z, placed, kept, missing))
    return placed, kept, missing
end

DazedCore.Net.on(S.MODULE, S.COMMAND, function(player, args)
    if not S.allowed(player) then return end
    local set = S.sets[args.set]
    if not set then return end
    local placed, kept = S.spawn(player, set.id)
    DazedCore.Note.say(player, "IGUI_DazedCore_DebugSpawned", { placed, set.name, kept })
end, 2000)

return S
