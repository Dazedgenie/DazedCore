-- Dazed Core 1.9.0 moved the shared test engine stub to <repo>/tools/tests/engine_stub.lua.
-- This forwarder keeps the other Dazed mods' tests working until they point at the new path.
-- It is never uploaded: steam_upload.py leaves out every tools/ folder.
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
return dofile(here .. "/../../../../../tools/tests/engine_stub.lua")
