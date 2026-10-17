--[[ Dazed Core -- debug-mode pcall watch.
     Every engine error a pcall swallows leaks a Kahlua return slot; after enough of them
     vanilla timed actions and context menus die with "Cannot assign field callFrame
     because a is null". In debug mode this wraps the global pcall and logs each failure
     it catches (first few per message, then a count every in-game ten minutes), so
     console.txt names the mod and call that keeps failing. Off outside debug mode. ]]

DazedCore = DazedCore or {}
DazedCore.LeakWatch = DazedCore.LeakWatch or {}
local W = DazedCore.LeakWatch

W.SHOW_EACH = 3      -- lines printed per distinct failure before it is only counted
W.MAX_KEYS = 200     -- distinct failures tracked

local function debugOn()
    return getDebug and getDebug() == true
end

if W.installed or not debugOn() then return end
W.installed = true

local realPcall = pcall
local counts, order, total = {}, {}, 0

local function short(v)
    local s = tostring(v)
    s = string.gsub(s, "[\r\n\t]+", " ")
    if #s > 220 then s = string.sub(s, 1, 220) .. "..." end
    return s
end

local function note(f, ...)
    total = total + 1
    local msg = short((select(1, ...)))
    local label = DazedCore.Util and DazedCore.Util._tryMethod
    local key = (label and ("try:" .. label .. " ") or "") .. short(f) .. " | " .. msg
    local c = counts[key]
    if not c then
        if #order >= W.MAX_KEYS then return end
        c = 0
        order[#order + 1] = key
    end
    c = c + 1
    counts[key] = c
    if c <= W.SHOW_EACH then
        local extra = select("#", ...) >= 2 and short((select(2, ...))) or ""
        print("[DazedCore] LeakWatch #" .. total .. " (x" .. c .. ") " .. key .. (extra ~= "" and (" || " .. extra) or ""))
    end
end

local function after(f, ok, ...)
    if not ok then note(f, ...) end
    return ok, ...
end

function pcall(f, ...)
    return after(f, realPcall(f, ...))
end

--- Print the failures caught so far, most frequent first.
function W.report()
    if total == 0 then return end
    local keys = {}
    for i = 1, #order do keys[i] = order[i] end
    table.sort(keys, function(a, b) return counts[a] > counts[b] end)
    print("[DazedCore] LeakWatch: " .. total .. " pcall failures caught so far")
    for i = 1, math.min(#keys, 15) do
        print("[DazedCore] LeakWatch   " .. counts[keys[i]] .. "x " .. keys[i])
    end
end

if Events and Events.EveryTenMinutes then Events.EveryTenMinutes.Add(W.report) end
print("[DazedCore] LeakWatch on (debug mode): logging every failure pcall catches")
