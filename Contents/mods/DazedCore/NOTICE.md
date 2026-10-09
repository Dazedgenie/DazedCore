# Notice of modification

Parts of this mod are adapted from **Off-Grid: Solar Power** (mod id `OffGrid`, version 3.0.0) by cakcan,
https://github.com/turret001/OffGrid, Steam Workshop item 3789425624, licensed under
Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (https://creativecommons.org/licenses/by-nc-sa/4.0/).

| File here | Taken from | What changed |
|---|---|---|
| `common/media/lua/shared/DazedCore/DC_Reach.lua` | `OffGrid/common/media/lua/shared/OffGrid/OG_Reach.lua` | Namespace `OffGrid.Reach` → `DazedCore.Reach`; comments reworded. Logic unchanged. |
| `common/media/lua/shared/DazedCore/DC_Buildings.lua` | `OffGrid/common/media/lua/shared/OffGrid/OG_Buildings.lua` | Namespace `OffGrid.Buildings` → `DazedCore.Buildings`; requires `DC_Reach`; comments reworded. Logic unchanged. |
| `common/media/lua/client/DazedCore/DC_Picker.lua` | `OffGrid/common/media/lua/client/OffGrid/OG_Picker.lua` | Rewritten to take a caller-supplied spec (reach, served targets, status, lock, pick, clear, text keys) instead of reading Off-Grid's parts, model and grid directly; window class renamed; `single` mode added; translation keys moved to `IGUI_DazedCore_*`. Drawing, hover resolution and window layout are as in the original. |

Everything else in this mod is original work of the Dazed authors. This mod as a whole is distributed under
the same licence, CC BY-NC-SA 4.0 (see `LICENSE`).
