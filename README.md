# Dragon's Dogma 2 mods (Permadev)

Mods for Dragon's Dogma 2 by https://github.com/AbsenceGameDev. <br>
The REFramework mods are pure Lua with no native plugins, and install with Fluffy Mod Manager.

## Projects

| Folder | Mod | Status | Summary |
|---|---|---|---|
| `NGPlusFog/` | Rediscovery (NG+ Fog) | 1.6.5 | Restores the map's fog of war in NG+ without turning NG+ features off. The full map, minimap, cave, and interior maps clear only where you explore in the current playthrough. Includes a fog data selector window for loading any stored fog snapshot or backup. |
| `Nemes5/` | Nemes!5: Toil & Trouble | 0.1.0, foundation only | Rival officers who remember the Arisen, 14 factions at war over territory, a Keep to claim for base of operations, a war room with scouts and captives, and a ghost-form revival. No gameplay yet. |

Each project has its own README under the path `reframework/autorun/docs/<Mod>/`

## Requirements

- Dragon's Dogma 2 with [REFramework](https://github.com/praydog/REFramework) (REFramework mods only).
- Fluffy Mod Manager, or a manual copy of each mod's `reframework/` folder into the game folder.

## Layout of a REFramework mod

```
<Mod>/                         repository root, also the Fluffy package root
├─ modinfo.ini                 name, version, description, author
├─ <Mod>_README.md
├─ Tools/                      not shipped: stub runtime, dump verifier, offline tests
└─ reframework/
   ├─ autorun/
   │  ├─ <Mod>.lua             entry point; REFramework runs only top-level files
   │  └─ <Mod>/                modules, loaded with require("<Mod>.<Module>")
   └─ data/<Mod>/              settings, per-save data, probe log
```

All REFramework scripts share one Lua state, so every module name carries its mod's prefix.

## Shared library (PermadevShared)
Code used by more than one mod: protected calls, hooks, the per-save-slot snapshot store and the probe log.

- Mod ships their own copy at `autorun/PermadevShared/v<N>/<Mod>/`, with a marker file `data/PermadevShared/versions/v<N>_<Mod>.json`. Different mods never install the same file, so uninstalling one never breaks another. 
- At startup each mod's `Shared.lua` picks the newest copy installed by **any** Permadev mod.
- Shared modules hold no state; a mod passes its own state in. 

## Testing
- **Offline:** each mod's `Tools/` runs its modules under a REFramework stub (Lua 5.4 through Python's lupa) and checks hooked types, methods, and fields against a REFramework type dump of the game
- **In game:** install, play the listed steps, then read the panel's Verification section or send `probe_events.json`.

## Notes
- **Save slots** (`app.GameSystem`): 3 characters, 3 slots each;  slot[0 + (5×CharIdx), 1 + (5×CharIdx) , 4 + (5×CharIdx)], which resolves to Char0 = [0,1,4]  Char1 = [5,6,9], Char2 = [10,11,14]
- **`fs.glob`** searches only `reframework/data` and returns backslash paths.
- **`draw.*`** paints behind every ImGui window; drawing inside a window goes through `imgui.get_window_draw_list()`.