-- Runs every headless test against the mod's Lua: `lua run_all.lua` from this folder (set LUA to name another interpreter).
-- It is a .lua file because the Steam Workshop refuses .sh files in an upload.
local lua = os.getenv("LUA") or "lua"
local root = "../../common/media/lua"
local ok = true
local function run(script)
    local r1, _, r3 = os.execute(lua .. " " .. script .. " " .. root)
    if r1 ~= true and r1 ~= 0 then ok = false end
end
run("syntax_check.lua")
for _, t in ipairs({ "heavy", "core", "buildings", "preset", "climate", "net", "picker", "debugspawn" }) do run(t .. "_test.lua") end
os.exit(ok and 0 or 1)
