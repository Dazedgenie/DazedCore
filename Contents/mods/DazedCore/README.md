# Dazed Core

Shared library for the Dazed mods for Project Zomboid Build 42. It does nothing on its own.
**Required by** *Dazed Plumbing* 0.10 and later and *Dazed Power*.

- **Mod ID:** `DazedCore` · **Version:** 1.4.1 · **Game:** Build 42 · **Load order:** before any other Dazed mod (`require=DazedCore` in theirs)

## What it holds

| Module | Namespace | For |
|---|---|---|
| `DC_HeavyParts` | `DazedCore.Heavy` (also the global `DazedHeavy`, version 2) | Anything over 30 kg is carried as parts, "(1/2)" and "(2/2)", like a bed or shelving; placing needs every part. A mod registers the item prefixes it owns. Upgrades an older version-1 copy left by Plumbing 0.9 / Dazed Power 0.9 in place. |
| `DC_Power` | `DazedCore.Power` | The registry the mods talk through. A power mod registers a **provider** (`isPowered(obj)`); a mod with a machine that needs power registers a **load** (`match`, `watts`, `working`; optional `prefix`, `matchName`, `byName` let `loadOf` skip or remember `match` by sprite name). `isPowered(obj)` answers for any object: wired, or a powered square. |
| `DC_Buildings`, `DC_Reach` | `DazedCore.Buildings`, `DazedCore.Reach` | Which squares a building is: map houses with their basements and wall shell, and player-built structures read from region data so a dedicated server agrees with its clients. Footprints, rects and their string codecs. |
| `DC_Picker` (client) | `DazedCore.Picker` | The Building Picker window and overlay. A mod opens it with a *spec* saying what its part serves, how far it reaches and what to send on a click. |
| `DC_Sync` | `DazedCore.Sync` | Who is the authority, tracked global ModData tables sent to clients, a `version` counter for caches and `versionOf(key)` per table. |
| `DC_Note` (+ `DC_NoteClient`) | `DazedCore.Note` | A line above a player's head; on a server the translation key travels and the client shows it. `limited` for refusals the cursor asks every frame. |
| `DC_Migrate` | `DazedCore.Migrate` | Schema versions on saved ModData, so a later release can change what it stores. |
| `DC_Detect` | `DazedCore.Detect` | Which mods are loaded. A feature registers the mod IDs that already do it (`yieldTo`); `yields(feature)` says whether to step aside, logged once. |
| `DC_Net` | `DazedCore.Net` | Client asks, authority acts: `on(module, command, fn, every)` server handlers with a per-player rate limit, `send` (runs at once in single player), `reply`/`onClient` for answers, `near` range check. |
| `DC_Options` (client) | `DazedCore.Options` | One "Dazed Core" page in the Mods options tab that every mod adds its tick boxes to. |
| `DC_Report` (client) | `DazedCore.Report` | One Error Magnifier report with a section per mod. |
| `DC_Util` | `DazedCore.Util` | `try`, tile `prop`/`propIs`, `memo1` for one-argument lookups, translated `txt`/`count`, `haloNote`, `worldHours`, `squareAt`. |
| `DC_Boot` | `DazedCore.Boot` | Loads the shared modules and prints `DazedCore: ready -- ...` with the mods that registered. |

## Using it from a mod

```lua
require "DazedCore/DC_Boot"
DazedCore.Boot.register("DazedPlumbing", "0.10.0")
DazedCore.Heavy.register("Base.Dazed")                 -- my heavy items come apart
DazedCore.Sync.track("DazedPlumbNet")                  -- keep this global table in step
DazedCore.Power.registerLoad({ id = "dazed_pump", kind = "waterpump", match = isPump, watts = watts, working = working })
DazedCore.Note.limited(character, "IGUI_DazedPlumb_XLOutdoors")
```

The picker takes a spec; see the header of `DC_Picker.lua` for every field. The caller decodes its own stored
targets with `DazedCore.Buildings.decodeTargets` and `DazedCore.Reach.decodeRects`.

## Tests

`lua run_all.lua` in `tools/tests` runs the headless checks with any Lua 5.3+ on PATH as `lua`
(set `LUA="luatex --luaonly"` to use that instead). `engine_stub.lua` is the shared stand-in for the game engine; the other
Dazed mods' tests use it as well.

## Tools

`tools/pzformat` reads and writes `.pack` and `.tiles` files; `tools/blender/pz_sprite_forge.py` is the render rig
the Dazed mods' sprites are made with; `pack_art.py` and `pack_tiles.py` put rendered cells into a pack and check a
tiledef. All need Python 3 with Pillow (and Blender 4.2+ for the rig).

## Credits and licence

`DC_Buildings`, `DC_Reach` and `DC_Picker` are adapted from **Off-Grid: Solar Power** by cakcan
(https://github.com/turret001/OffGrid, Steam Workshop 3789425624), CC BY-NC-SA 4.0, with namespace and API changes
so other mods can use them; see `NOTICE.md` for what changed. The whole mod is therefore licensed
**CC BY-NC-SA 4.0** (`LICENSE`). `tools/pzformat` and `tools/blender/pz_sprite_forge.py` are from pz-sprite-forge (MIT);
its licence ships in those folders.

## Changes

- **1.4.1.** Renamed to **Dazed Core** everywhere players see it: mod list, sandbox page, Mods options page, Error Magnifier report and the guide. The options page keeps its internal ID (`DazedUtilities`) so saved tick boxes carry over. Filled in `workshop.txt` with the Workshop description. The test runner is now `tools/tests/run_all.lua` (was `run_all.sh`) because the Steam Workshop refuses `.sh` files in an upload. Guide text brought up to date: Power's first-system steps use the real menu names, the monitor page describes the charge board, rain is clean water, and the Dank pages use the grow room dashboard and vanilla sheets instead of blackout curtains.
  - **Fix:** the Building Picker no longer errors as it opens when a mod passes a `clear` callback (Dazed Plumbing's water main and Dazed Power's picker both do). Only text keys that are strings are used as labels.

- **1.4.0.**
  - **Sync:** `S.versions[key]` and `S.versionOf(key)` count changes per tracked table (on touch and on a client's receive); `S.version` is unchanged.
  - **Power:** a load may declare `prefix`, `matchName(spriteName)` and `byName = true` so `loadOf` skips or remembers `match` by sprite name; `W.clearNameMemo()`.
  - **Reach:** `R.ownerIn(shapes, list, i, x, y, z, inside)` for callers holding the chunk's list from `R.chunkIndex`.
  - **Net:** client handlers get `(args, player)`, the local player replied to, on the direct and the networked path (split screen included; nil only when it cannot be told).
  - **Climate:** `Cl.spoilShare(t, curve)` and `Cl.SPOIL_CURVE`, the cold-storage spoilage curve in one place.
  - **Util:** `U.memo1(fn, max)` remembers a one-argument lookup (returns the function and a clear).
  - Performance: the heavy-parts sweep runs every ten game minutes (pick-up still splits at once); the Guide button
    no longer re-attaches every minute; the picker remembers targets and footprints per session and does nothing per
    frame while closed; `structureAt` fetches the metagrid once; `prop`/`propIs` build no tables.
  - Removed, unused by any Dazed mod: `R.chunkKey`, `R.shapeSquares`, `D.yieldedTo`, `B.enclosedAt`.
  - **Fixes:**
    - **Picker hover:** with the cursor still, the hover now follows a new served list at once (it compares the served version itself), and is looked at again every second (`K.HOVER_RECHECK_MS`) so a building another part takes turns red without moving the mouse. Test: `picker_test.lua`.
    - **Net replies in split screen:** a server reply carries its target's online ID (`N.TO`, stripped before the handler runs), so the client hands the handler the right split-screen player instead of nil.
- **1.3.0.**
  - **Detect:** `DazedCore.Detect` finds loaded mods (a leading backslash in B42 server lists is ignored) so a feature can yield to another mod that already does it.
  - **Net:** `DazedCore.Net` routes requests to the authority and answers back, with per-player rate limits and a `near` check for handlers. Test: `net_test.lua`.
- **1.2.0.**
  - **Guide window:** a book button at the foot of the left sidebar opens the Dazed Mod Suite Guide, with tabs for
    Basics, Power and Plumbing (only the mods you have). Pages live in `IG_UI.json` (`IGUI_DazedGuide_*`); the button
    can be hidden on the Dazed Core options page.
  - **Translation kit:** `tools/translation_kit.py start|check` and `TRANSLATING.md`.
  - **Place trace:** when the Place cursor shows nothing for a Dazed item, one `DazedCore: place cursor shows nothing
    for ...` console line says why.
  - Performance: the heavy-parts minute sweep remembers which item types are a mod's own and only opens those items,
    instead of reading the ModData of every item (and bag) every player carries; it no longer copies each container.
  - Performance: while the place cursor shows a heavy part, the all-parts check is reused for up to 250 ms unless the
    inventory changes size (placing still checks afresh). The picker's hover and the place-trace check build no strings
    per frame. Tests: new checks in `heavy_test.lua`.
- **1.1.1.** Heavy parts v3: a 2x2 piece of furniture carried as parts can be placed (the game looks it up as
  "Name (1/1)"; the first part of a complete set now answers). A refused placement because a part is missing writes
  `DazedCore: can't place ...` to the console.
- **1.1.0.** Sandbox presets: `DazedCore.Preset` (Custom, Easy, Standard, Realistic, Hardcore) lets any Dazed mod
  register `{ easy, standard, realistic, hardcore }` values per option (`DazedCore.Preset.register`); `DazedCore.Util.sandbox`
  reads through them. Custom changes nothing. Test: `preset_test.lua`.
- **1.0.0.** First release. Heavy parts v2 (both engine argument orders, upgrades a v1 copy in place), power registry,
  building resolver and picker, sync, notes, migrate, shared options page and report.
