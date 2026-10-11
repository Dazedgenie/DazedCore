--[[ Dazed Core -- ids the game must know before scripts load.

     B42 runs every mod's media/registries.lua before it reads item and recipe scripts, and a script naming an
     unregistered tag stops script loading. Registering the shared part tags here, in the Core every Dazed mod
     already requires, means any Dazed mod can name them in a recipe (tags[dazedcore:compressor]) whether or not
     Dazed Salvage, which makes the items that carry them, is installed. With Salvage missing, the tag matches
     no item and the recipe simply can't be made. ]]

DazedCore = DazedCore or {}
DazedCore.PartTags = DazedCore.PartTags or {}
local T = DazedCore.PartTags

for _, name in ipairs({
    "motor_small", "motor_large", "compressor", "copper_tubing", "condenser_coil", "fan_motor",
    "thermostat", "heating_element", "transformer_small", "circuit_board", "timer_switch", "drive_belt",
    "steel_tank", "small_engine", "pull_starter", "coin_mech", "alternator", "starter_motor",
    "wiring_harness", "copper_wire",
}) do
    T[name] = ItemTag.register("dazedcore:" .. name)
end
