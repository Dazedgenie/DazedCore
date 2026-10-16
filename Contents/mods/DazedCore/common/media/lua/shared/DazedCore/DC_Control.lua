--[[ Dazed Core -- Dazed Control, the staff panel every Dazed mod can hang a tab on.

     A mod registers a tab with `register(id, def)` in shared code:
       def.title     what the tab is called (a translation key or plain text)
       def.order     where it sits (lower first); Overview is 0
       def.view      fn(viewer) run by the authority, returning what the tab shows (below)
       def.commands  { ["Module.command"] = "admin" | "mod" }: the Net commands its buttons may run, and the level
                     each needs. A button can only run a command its tab names here.
       def.marks     optional fn(viewer) run by the authority, returning marks for the panel's map, whichever tab is
                     open: { { x, y, label, tone, r = radius in tiles, route = { { x, y } }, next = index } }.
                     `route` is drawn as a line from the mark through its checkpoints; those before `next` are done.

     A view is plain data, so the window draws every tab the same way and mods write no UI code:
       { lamps = { { label, "green"|"amber"|"red"|"off" } },
         cards = { { title, rows = { { label, value, tone } }, items = { { text, sub, tone, buttons } },
                     lines = { "log line" }, buttons = { button } } } }
       button = { label, module, command, args, danger = true, target = true, route = true }
     A `route` button opens the map for checkpoints instead of running at once; the command gets them as
     args.route = { { x = , y = } }, at most C.ROUTE_MAX.
     Any text may be a translation key, { key, { args } } or plain text: the server has no translations, so the
     client turns keys into words. A `target` button gets the spot the staff member picked (x, y, z) added to its
     args, resolved again by the authority from the target's name when the target is a player.

     Who may use it: admins every button, moderators look only (a command can lower its level to "mod"). The game in
     debug mode counts as admin, so single player can test it. Every request is checked again here, on the
     authority; the client only hides what it may not use. Every action is logged to the console, to
     Zomboid/Lua/DazedControl.log and to a short list the Overview tab shows. ]]

require "DazedCore/DC_Util"
require "DazedCore/DC_Net"

DazedCore = DazedCore or {}
DazedCore.Control = DazedCore.Control or {}
local C = DazedCore.Control
local U = DazedCore.Util
local Net = DazedCore.Net
local try = U.try

C.MODULE = "DazedCore"
C.LOG_KEY = "DazedControlLog"
C.LOG_KEEP = 40
C.LOG_FILE = "DazedControl.log"
C.ROUTE_MAX = 16
C.tabs = C.tabs or {}
C.order = C.order or {}

local RANK = { admin = 2, mod = 1 }

--- Add or replace a tab. Returns the tab's def, or nil when the def is unusable.
function C.register(id, def)
    if type(id) ~= "string" or type(def) ~= "table" or type(def.view) ~= "function" then return nil end
    def.id = id
    def.order = tonumber(def.order) or 50
    def.commands = type(def.commands) == "table" and def.commands or {}
    if not C.tabs[id] then C.order[#C.order + 1] = id end
    C.tabs[id] = def
    table.sort(C.order, function(a, b)
        local ta, tb = C.tabs[a], C.tabs[b]
        if ta.order ~= tb.order then return ta.order < tb.order end
        return a < b
    end)
    return def
end

-- A role's capability, guarded: older builds have no roles, and a missing capability answers false.
local function hasCap(role, name)
    local cap = Capability and Capability[name]
    if cap == nil then return false end
    return try(role, "hasCapability", cap) == true
end

--- "admin", "mod" or nil. Admins hold UseMovablesCheat and moderators BanUnbanUser, the way DC_DebugSpawn tells
--  staff apart: B42 roles call an ordinary player "user", so the access-level string alone is not enough.
function C.level(character)
    if not character then return nil end
    if getDebug and getDebug() == true then return "admin" end
    local role = try(character, "getRole")
    if role and Capability then
        if hasCap(role, "UseMovablesCheat") then return "admin" end
        if hasCap(role, "BanUnbanUser") then return "mod" end
        return nil
    end
    local lvl = try(character, "getAccessLevel")
    lvl = type(lvl) == "string" and string.lower(lvl) or ""
    if lvl == "admin" then return "admin" end
    if lvl == "moderator" or lvl == "overseer" or lvl == "gm" then return "mod" end
    return nil
end

--- May a character at `level` use something that needs `need`?
function C.atLeast(level, need)
    return (RANK[level] or 0) >= (RANK[need] or RANK.admin)
end

---------------------------------------------------------------- the log

local function stamp()
    local gt = getGameTime and getGameTime()
    if not gt then return "" end
    local day = (try(gt, "getNightsSurvived") or 0) + 1
    return string.format("D%d %02d:%02d", day, try(gt, "getHour") or 0, try(gt, "getMinutes") or 0)
end

local function logStore()
    if not (ModData and ModData.getOrCreate) then return nil end
    local md = ModData.getOrCreate(C.LOG_KEY)
    md.lines = md.lines or {}
    return md
end

--- Write one staff action everywhere it is kept. `who` is a name, `what` plain text.
function C.log(who, what)
    local line = string.format("%s  %s  %s", stamp(), tostring(who), tostring(what))
    print("DazedControl: " .. line)
    local md = logStore()
    if md then
        table.insert(md.lines, 1, line)
        while #md.lines > C.LOG_KEEP do table.remove(md.lines) end
    end
    if getFileWriter then
        local ok, w = pcall(getFileWriter, C.LOG_FILE, true, true)
        if ok and w then
            local okD, real = pcall(function() return os.date("%Y-%m-%d %H:%M:%S  ") end)
            pcall(w.write, w, (okD and type(real) == "string" and real or "") .. line .. "\n")
            pcall(w.close, w)
        end
    end
end

--- The newest `n` log lines.
function C.recent(n)
    local md = logStore()
    local out = {}
    if not md then return out end
    for i = 1, math.min(n or 10, #md.lines) do out[i] = md.lines[i] end
    return out
end

---------------------------------------------------------------- players and targets

local function nameOf(p)
    local n = try(p, "getUsername")
    return (type(n) == "string" and n ~= "") and n or nil
end

--- Every player the authority knows: the online list on a server, the local players otherwise.
function C.players()
    local out = {}
    local list = getOnlinePlayers and getOnlinePlayers()
    local n = list and try(list, "size") or 0
    if n > 0 then
        for i = 0, n - 1 do out[#out + 1] = list:get(i) end
        return out
    end
    for i = 0, 3 do
        local p = getSpecificPlayer and getSpecificPlayer(i)
        if p then out[#out + 1] = p end
    end
    return out
end

function C.findPlayer(name)
    if type(name) ~= "string" then return nil end
    for _, p in ipairs(C.players()) do
        if nameOf(p) == name then return p end
    end
    return nil
end

-- The spot a target button aims at, decided here: a named player where they stand now, a picked map spot as sent
-- (clamped to whole tiles on the ground floor range), or the staff member's own square.
local function resolveTarget(staff, t)
    t = type(t) == "table" and t or {}
    if t.player then
        local p = C.findPlayer(t.player)
        if not p then return nil end
        return math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), nameOf(p)
    end
    local x, y = tonumber(t.x), tonumber(t.y)
    if x and y then
        local z = math.max(0, math.min(7, math.floor(tonumber(t.z) or 0)))
        return math.floor(x), math.floor(y), z, nil
    end
    return math.floor(staff:getX()), math.floor(staff:getY()), math.floor(staff:getZ()), nil
end

---------------------------------------------------------------- the authority's handlers

local function viewOf(tab, player)
    local ok, view = pcall(tab.view, player)
    if not ok then
        print("DazedCore: control tab " .. tab.id .. " view failed: " .. tostring(view))
        return { cards = { { title = "IGUI_DazedControl_ViewFailed", lines = { tostring(view) } } } }
    end
    return type(view) == "table" and view or {}
end

-- Mark each button with the level it needs, and drop any whose command the tab does not name, so the client never
-- shows a button the authority would refuse.
local function markButtons(tab, list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, b in ipairs(list) do
        local need = type(b) == "table" and type(b.module) == "string" and tab.commands[b.module .. "." .. tostring(b.command)]
        if need then
            b.need = need
            out[#out + 1] = b
        end
    end
    return out
end

local function markView(tab, view)
    for _, card in ipairs(type(view.cards) == "table" and view.cards or {}) do
        card.buttons = markButtons(tab, card.buttons)
        for _, item in ipairs(type(card.items) == "table" and card.items or {}) do item.buttons = markButtons(tab, item.buttons) end
    end
    return view
end

-- Every tab's map marks, so the map shows them whichever tab is open.
local function marksOf(player)
    local out = {}
    for _, id in ipairs(C.order) do
        local tab = C.tabs[id]
        if tab.marks then
            local ok, list = pcall(tab.marks, player)
            if not ok then
                print("DazedCore: control tab " .. id .. " marks failed: " .. tostring(list))
            elseif type(list) == "table" then
                for _, m in ipairs(list) do
                    if type(m) == "table" and tonumber(m.x) and tonumber(m.y) then out[#out + 1] = m end
                end
            end
        end
    end
    return out
end

-- Checkpoints as sent by a client: whole tiles, at most C.ROUTE_MAX, anything else dropped.
local function cleanRoute(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, p in ipairs(list) do
        local x, y = type(p) == "table" and tonumber(p.x), type(p) == "table" and tonumber(p.y)
        if x and y then out[#out + 1] = { x = math.floor(x), y = math.floor(y) } end
        if #out >= C.ROUTE_MAX then break end
    end
    return #out > 0 and out or nil
end

local function tabList()
    local out = {}
    for _, id in ipairs(C.order) do out[#out + 1] = { id = id, title = C.tabs[id].title or id } end
    return out
end

--- Send one tab's view (and the tab list, and the viewer's level) to the staff member who asked.
function C.sendView(player, id)
    local level = C.level(player)
    if not level then return end
    local tab = C.tabs[id] or C.tabs[C.order[1]]
    if not tab then return end
    -- names for the target button, and where each one stands for the map: a client only knows the players near it
    local names, spots = {}, {}
    for _, p in ipairs(C.players()) do
        local n = nameOf(p)
        names[#names + 1] = n
        if n then spots[#spots + 1] = { n = n, x = math.floor(p:getX()), y = math.floor(p:getY()) } end
    end
    local view = markView(tab, viewOf(tab, player))
    view.clock = stamp()
    Net.reply(player, C.MODULE, "ctlView", { tab = tab.id, tabs = tabList(), level = level, players = names, spots = spots,
        marks = marksOf(player), view = view })
end

Net.on(C.MODULE, "ctlOpen", function(player, args)
    if not C.level(player) then return end
    C.sendView(player, args.tab)
end, 250)

-- Run a button's command through its own Net handler, after checking the tab names it and the level allows it.
Net.on(C.MODULE, "ctlAct", function(player, args)
    local level = C.level(player)
    if not level then return end
    local tab = C.tabs[args.tab]
    local module, command = args.module, args.command
    if not (tab and type(module) == "string" and type(command) == "string") then return end
    local need = tab.commands[module .. "." .. command]
    if not need then
        C.log(nameOf(player), "refused " .. module .. "." .. command .. ": not a command of tab " .. tab.id)
        return
    end
    if not C.atLeast(level, need) then
        Net.reply(player, C.MODULE, "ctlResult", { ok = false, line = "IGUI_DazedControl_NotAllowed" })
        return
    end
    local h = Net.server[module] and Net.server[module][command]
    if not h then return end
    local cargs = {}
    for k, v in pairs(type(args.args) == "table" and args.args or {}) do cargs[k] = v end
    local where = ""
    if args.target ~= nil then
        local x, y, z, who = resolveTarget(player, args.target)
        if not x then
            Net.reply(player, C.MODULE, "ctlResult", { ok = false, line = "IGUI_DazedControl_NoTarget" })
            return
        end
        cargs.x, cargs.y, cargs.z, cargs.targetName = x, y, z, who
        where = string.format(" at %d,%d,%d%s", x, y, z, who and (" (" .. who .. ")") or "")
    end
    if args.route ~= nil then
        local route = cleanRoute(args.route)
        if not route then
            Net.reply(player, C.MODULE, "ctlResult", { ok = false, line = "IGUI_DazedControl_NoRoute" })
            return
        end
        cargs.route = route
        local last = route[#route]
        where = where .. string.format(" via %d checkpoints to %d,%d", #route, last.x, last.y)
    end
    local ok, err = pcall(h.fn, player, cargs)
    C.log(nameOf(player), string.format("%s %s.%s%s%s", ok and "ran" or "FAILED", module, command, where,
        ok and "" or (": " .. tostring(err))))
    Net.reply(player, C.MODULE, "ctlResult", { ok = ok, line = ok and "IGUI_DazedControl_Done" or "IGUI_DazedControl_Failed" })
    C.sendView(player, tab.id)
end, 300)

---------------------------------------------------------------- Overview, Core's own tab

local function dazedMods()
    local out = {}
    local list = getActivatedMods and getActivatedMods()
    local n = list and try(list, "size") or 0
    for i = 0, n - 1 do
        local id = string.gsub(tostring(list:get(i)), "^\\", "")
        if string.find(id, "^Dazed") then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

C.register("overview", {
    title = "IGUI_DazedControl_Overview",
    order = 0,
    view = function(viewer)
        local players = C.players()
        local rows = {
            { "IGUI_DazedControl_Time", stamp() },
            { "IGUI_DazedControl_Online", tostring(#players) },
            { "IGUI_DazedControl_YourLevel", C.level(viewer) == "admin" and "IGUI_DazedControl_LevelAdmin" or "IGUI_DazedControl_LevelMod" },
        }
        local mods = dazedMods()
        local who = {}
        for _, p in ipairs(players) do
            who[#who + 1] = { text = nameOf(p) or "?", sub = string.format("%d, %d, %d", math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())) }
        end
        return {
            lamps = {
                { "IGUI_DazedControl_LampServer", (isServer and isServer()) and "green" or "off" },
                { "IGUI_DazedControl_LampDebug", (getDebug and getDebug()) and "amber" or "off" },
            },
            cards = {
                { title = "IGUI_DazedControl_World", rows = rows },
                { title = { "IGUI_DazedControl_Mods", { #mods } }, lines = mods },
                { title = "IGUI_DazedControl_Players", items = who },
                { title = "IGUI_DazedControl_StaffLog", lines = C.recent(15), log = true },
            },
        }
    end,
})

---------------------------------------------------------------- Fixes, one-off repairs any mod can add

--[[ A mod adds a fix with `registerFix(id, def)`:
       def.title  def.desc   plain text or a translation key
       def.mod    the mod's name, shown after the description
       def.scope  "player" (runs on the target player) or "world" (runs at the target spot)
       def.run    fn(staff, info) on the authority; info = { x, y, z, player = IsoPlayer or nil, name = string or nil }.
                  Returns true (or true, "what it did"), or false, "why not": a false answer shows as failed.
     The Fixes tab lists them under the two scopes with a Run button that aims at the panel's target. Admins only:
     a fix changes a player or the world, so moderators only look. ]]

C.fixes = C.fixes or {}
C.fixOrder = C.fixOrder or {}

function C.registerFix(id, def)
    if type(id) ~= "string" or type(def) ~= "table" or type(def.run) ~= "function" then return nil end
    def.id = id
    def.scope = def.scope == "player" and "player" or "world"
    if not C.fixes[id] then C.fixOrder[#C.fixOrder + 1] = id end
    C.fixes[id] = def
    table.sort(C.fixOrder, function(a, b)
        local fa, fb = C.fixes[a], C.fixes[b]
        if fa.scope ~= fb.scope then return fa.scope == "player" end
        local ta, tb = tostring(fa.title or a), tostring(fb.title or b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return def
end

Net.on(C.MODULE, "ctlFix", function(player, args)
    if C.level(player) ~= "admin" then return end
    local fix = type(args.id) == "string" and C.fixes[args.id]
    if not fix then return end
    local info = { x = args.x, y = args.y, z = args.z, name = args.targetName }
    if fix.scope == "player" then
        info.player = args.targetName and C.findPlayer(args.targetName) or player
        info.name = info.name or nameOf(player)
        if not info.player then error("player not found") end
    end
    local ok, done, msg = pcall(fix.run, player, info)
    if not ok then error(tostring(done)) end
    if done == false then error(tostring(msg or "the fix did not apply")) end
    if type(msg) == "string" then C.log(nameOf(player), "fix " .. fix.id .. ": " .. msg) end
end, 500)

C.register("fixes", {
    title = "IGUI_DazedControl_Fixes",
    order = 90,
    commands = { ["DazedCore.ctlFix"] = "admin" },
    view = function()
        local groups = { player = {}, world = {} }
        for _, id in ipairs(C.fixOrder) do
            local f = C.fixes[id]
            local sub = tostring(f.desc or "")
            if f.mod then sub = sub .. (sub ~= "" and " (" or "(") .. tostring(f.mod) .. ")" end
            local list = groups[f.scope]
            list[#list + 1] = { text = f.title or id, sub = sub,
                buttons = { { label = "IGUI_DazedControl_Run", module = C.MODULE, command = "ctlFix", args = { id = id }, target = true } } }
        end
        local cards = {}
        if #groups.player > 0 then cards[#cards + 1] = { title = "IGUI_DazedControl_FixesPlayer", items = groups.player } end
        if #groups.world > 0 then cards[#cards + 1] = { title = "IGUI_DazedControl_FixesWorld", items = groups.world } end
        if #cards == 0 then cards[1] = { title = "IGUI_DazedControl_Fixes", lines = { "IGUI_DazedControl_FixesNone" } } end
        local n = #C.fixOrder
        return { lamps = { { { "IGUI_DazedControl_FixesCount", { n } }, n > 0 and "green" or "off" } }, cards = cards }
    end,
})

return C
