#!/bin/sh
# Runs every headless test against the mod's Lua. Needs a Lua 5.3+ interpreter on PATH as `lua`.
cd "$(dirname "$0")" || exit 1
ROOT=../../common/media/lua
rc=0
lua syntax_check.lua $ROOT || rc=1
for t in heavy_test core_test buildings_test preset_test climate_test net_test; do lua $t.lua $ROOT || rc=1; done
exit $rc
