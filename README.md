# NG+ Fog 1.0

Map fog of war in NG+ for Dragon's Dogma 2. Works for:
- The full map, 
- the minimap, 
- the cave and interior maps
- Hides icon behind the fog of war

Requires REFramework. Install with Fluffy Mod Manager or manually.

## Settings
REFramework (Insert) → Script Generated UI → **NG+ Fog**.
| Setting | Effect |
|---|---|
| **Fog of war in NG+** | On: fog clears as you explore this playthrough. Off: the vanilla NG+ map (fully revealed). |
| **Show real map progress** | Uses the save's own fog, as it was before NG+ revealed everything, with map icons hidden by that fog. Overrides the other setting while enabled. |

## Buttons 
- **'Save now'**
- **'Reset NG+ fog (this slot)'**
- **'Copy real progress into NG+ fog'** (adds the previous playthrough's exploration to the NG+ fog)
- **'Reload slot file'**

## Files
Entry point: `reframework/autorun/NGPlusFog.lua`; 
| Module | Contents |
|---|---|
| `Definitions` | Constants, game types, unconfirmed (CAPITALS) assumptions |
| `State` | Settings and runtime state shared by every module |
| `Core` | Helpers: protected calls, field access, raw array words, hook install |
| `Scope` | NG+ flag and mask-array swap while map code runs; map scope hooks |
| `Masks` | Game masks, private copies, bitmap helpers; exploration mirror hook |
| `Persistence` | Snapshot ring per save slot; save and load hooks |
| `Backups` | Copy real progress, timestamped backups, revert |
| `Icons` | Icons in fog on the full map; drawing and cursor hooks |
| `Tick` | Safety guards and the per-tick state update |
| `Panel` | Settings panel and diagnostics probe |

## Icons
- Full-map icons keep their map coordinates for drawing. Each icon under fog is switched off. During the game's cursor search only it is temporarliy moved off the map, so the cursot cannot target icons behind fog. 

## Saving
- NG+ fog data is stored per save slot as in a list of the 8 latest snapshots: `reframework/data/NGPlusFog/slot_<n>_h0.json` to `_h7.json`. A snapshot is written whenever the game saves, and holds the fog, a sequence number, the save's play time and its in-game time. If the save is older than every stored snapshot, the oldest snapshot is used.

## QA
- **Tested and confirmed (2026-11-05):** Reverting a savefile also loads the correct fog data
- **Tested and confirmed (2026-11-05):** Vendor stocks keep high-level gear with the mod on, off, and in real-progress mode
- **Tested and confirmed (2026-11-05):** Manual saves, autosaves, inn saves and interim saves each use their own slot number, and all save and load their fog correctly
- **Tested and confirmed (2026-11-05):** The game's own saves cannot be affected by a crash while the map is open. The flag and array changes exist only in memory, and both are restored before the game prepares save data
- **Tested and confirmed (2026-11-05):** General testing regarding fog, all seems to work as expected as far as I can test

## Not yet confirmed 
My own save is not close enough to another ng+ cycle to test this
- The NG+ fog is cleared when `GuiManager.makeLoopSaveData()` runs, which is assumed to be the creation of the next NG+ cycle. The `new_cycle_resets` counter records when it happens.

## Shorthand reminders 
in case things break after an update, I would expect one of these to have changed
- `app.ui040205`: full map
- `app.ui020301`: mini map
- `app.GUIMaskPainter`: fog painters