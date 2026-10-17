-- Compiles every Lua file under the given roots without running it. Run: lua syntax_check.lua <dir>...
local bad = 0
for i = 1, #arg do
    local p = io.popen('find "' .. arg[i] .. '" -name "*.lua" | sort')
    for file in p:lines() do
        local f, err = loadfile(file)
        if not f then bad = bad + 1; print("SYNTAX " .. err) end
    end
    p:close()
end
print(string.format("syntax_check: %d bad", bad))
os.exit(bad == 0 and 0 or 1)
