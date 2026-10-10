--[[ Dazed Core -- small helpers every Dazed mod uses: guarded engine calls, tile
     properties, translated text with {1} placeholders, and halo notes. ]]

DazedCore = DazedCore or {}
DazedCore.VERSION = "1.6.1"
DazedCore.Util = DazedCore.Util or {}
local U = DazedCore.Util

U.NOTE_WARN = { r = 1.0, g = 0.45, b = 0.3 }
U.NOTE_TIME = 300

--- Call a method on an engine object; a missing method or an engine error answers nil.
function U.try(obj, method, ...)
    if not obj or not obj[method] then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end
local try = U.try

-- A property holder's value for key, or nil.
local function holderVal(holder, key)
    if not holder then return nil end
    local v = try(holder, "get", key)
    if v == nil then v = try(holder, "Val", key) end
    return v
end

--- A tile property's value from the object or its sprite, or nil.
function U.prop(obj, key)
    local own = try(obj, "getProperties")
    if not own then return nil end         -- as before: the sprite is asked only when the object has properties
    local v = holderVal(own, key)
    if v ~= nil then return v end
    return holderVal(try(try(obj, "getSprite"), "getProperties"), key)
end

-- Does a property holder carry the flag under any of the engine's three method names?
local function holderIs(holder, key)
    if not holder then return false end
    return try(holder, "has", key) == true or try(holder, "Is", key) == true or try(holder, "is", key) == true
end

--- Does the object or its sprite carry a tile flag?
function U.propIs(obj, key)
    local own = try(obj, "getProperties")
    if not own then return false end       -- as before: the sprite is asked only when the object has properties
    if holderIs(own, key) then return true end
    return holderIs(try(try(obj, "getSprite"), "getProperties"), key)
end

--- Remember a one-argument lookup's answers by that argument (a sprite name, say), up to `max` (default 1024).
--  Returns the remembering function and a clear(); a nil argument is never remembered. Only for answers that never change.
function U.memo1(fn, max)
    local NIL = {}
    local cap = max or 1024
    local memo, size = {}, 0
    local function get(k)
        if k == nil then return fn(k) end
        local v = memo[k]
        if v == nil then
            v = fn(k)
            if size >= cap then memo, size = {}, 0 end
            if v == nil then memo[k] = NIL else memo[k] = v end
            size = size + 1
            return v
        end
        if v == NIL then return nil end
        return v
    end
    local function clear() memo, size = {}, 0 end
    return get, clear
end

--- Translated text with {1}, {2}... filled in. A % in a value is escaped for gsub.
function U.txt(key, ...)
    local s = getText and getText(key) or nil
    if s == nil then return tostring(key) end
    for i = 1, select("#", ...) do
        local v = tostring((select(i, ...)))
        v = string.gsub(v, "%%", "%%%%")
        s = string.gsub(s, "{" .. i .. "}", v)
    end
    return s
end

--- The same with the values in a table (no unpack needed, which the game's Lua lacks).
function U.txtArgs(key, args)
    local s = getText and getText(key) or nil
    if s == nil then return tostring(key) end
    for i, raw in ipairs(args or {}) do
        local v = string.gsub(tostring(raw), "%%", "%%%%")
        s = string.gsub(s, "{" .. i .. "}", v)
    end
    return s
end

--- A counted phrase: the key's "One" twin when n is 1 ("1 floor", "3 floors").
function U.count(key, n, ...)
    local k = (n == 1) and (key .. "One") or key
    if select("#", ...) > 0 then return U.txt(k, ...) end
    return U.txt(k, n)
end

--- A short line above a character's head, in the warning colour if asked.
function U.haloNote(character, text, warn)
    if not character or not character.setHaloNote or text == nil then return end
    if warn then
        local c = U.NOTE_WARN
        pcall(character.setHaloNote, character, tostring(text), c.r, c.g, c.b, U.NOTE_TIME)
    else
        pcall(character.setHaloNote, character, tostring(text))
    end
end

--- In-game hours since the world began.
function U.worldHours()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

--- The square at x, y, z if its chunk is loaded, else nil.
function U.squareAt(x, y, z)
    local cell = getCell and getCell()
    return cell and try(cell, "getGridSquare", x, y, z) or nil
end

--- Iterate a Java list: fn(item) for each.
function U.each(list, fn)
    local n = list and list.size and list:size() or 0
    for i = 0, n - 1 do fn(list:get(i)) end
end

--- A sandbox value by page and name, with a fallback when the page is absent.
function U.sandbox(page, name, fallback)
    local pre = DazedCore.Preset and DazedCore.Preset.override(page, name)
    if pre ~= nil then return pre end
    local sv = SandboxVars and SandboxVars[page]
    local v = sv and sv[name]
    if v == nil then return fallback end
    return v
end

return U
