--[[ Dazed Core -- one OnTick hook for the whole suite.

     Every Dazed mod used to add its own OnTick handler that read the clock and returned early most frames.
     Here a mod registers a job once and says how often it wants to run, and Core calls it from a single
     hook with one clock read a frame:

        DazedCore.Tick.every("DazedPower.sounds", 250, function(nowMs) ... end)   -- about every 250 ms
        DazedCore.Tick.everyTicks("DazedDefences.check", 30, function(nowMs) ... end)  -- every 30th frame
        DazedCore.Tick.remove("DazedPower.sounds")

     Ids are strings a mod owns ("<ModId>.<job>"); registering an id again replaces the job. A job that
     errors is reported once and keeps running, so one bad job never stops the others. An `every` job first
     runs on the first frame after registration (not after a full interval); an `everyTicks(n)` job on its nth
     frame. Jobs run on whichever side
     registered them: a server file registers a server job, a client file a client job. ]]

DazedCore = DazedCore or {}
DazedCore.Tick = DazedCore.Tick or {}
local T = DazedCore.Tick

T.jobs = T.jobs or {}        -- id -> job
T.failed = T.failed or {}    -- id -> first error text
local order, dirty = {}, true

local function now()
    return getTimestampMs and getTimestampMs() or 0
end

local function add(id, job)
    if type(id) ~= "string" or id == "" or type(job.fn) ~= "function" then return false end
    job.id = id
    job.runs = 0
    T.jobs[id] = job
    T.failed[id] = nil
    dirty = true
    return true
end

--- Run fn(nowMs) about every `ms` milliseconds of real time.
function T.every(id, ms, fn)
    return add(id, { fn = fn, ms = math.max(0, tonumber(ms) or 0), last = nil })
end

--- Run fn(nowMs) every n-th frame.
function T.everyTicks(id, n, fn)
    return add(id, { fn = fn, n = math.max(1, math.floor(tonumber(n) or 1)), count = 0 })
end

function T.remove(id)
    if T.jobs[id] then T.jobs[id] = nil; dirty = true; return true end
    return false
end

function T.has(id) return T.jobs[id] ~= nil end

--- Every job with its interval and how many times it ran, sorted by id (for the Error Magnifier report).
function T.stats()
    local out = {}
    for id, j in pairs(T.jobs) do
        out[#out + 1] = { id = id, ms = j.ms, ticks = j.n, runs = j.runs, failed = T.failed[id] }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function rebuild()
    order = {}
    for id in pairs(T.jobs) do order[#order + 1] = id end
    table.sort(order)
    dirty = false
end

--- The one frame handler. Public so a test (or a mod with its own frame loop) can drive it.
function T.onTick()
    if dirty then rebuild() end
    local t = now()
    for i = 1, #order do
        local j = T.jobs[order[i]]
        if j then
            local due
            if j.ms then
                due = j.last == nil or (t - j.last) >= j.ms or t < j.last
                if due then j.last = t end
            else
                j.count = j.count + 1
                due = j.count >= j.n
                if due then j.count = 0 end
            end
            if due then
                j.runs = j.runs + 1
                local ok, err = pcall(j.fn, t)
                if not ok and not T.failed[j.id] then
                    T.failed[j.id] = tostring(err)
                    print("DazedCore: tick job " .. j.id .. " failed: " .. tostring(err))
                end
            end
        end
    end
end

if Events and Events.OnTick and not T.hooked then
    T.hooked = true
    -- A wrapper, so a debug Lua reload (which redefines T.onTick) keeps working.
    Events.OnTick.Add(function(n) DazedCore.Tick.onTick(n) end)
end

return T
