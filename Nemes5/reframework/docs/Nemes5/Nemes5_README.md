# Nemes!5: Toil & Trouble

Rival officers, faction wars and a war room for Dragon's Dogma 2.
- Requires REFramework. 
- Can be installed with Fluffy Mod Manager.
Development build 0.1.0 

## Files
entry point: `reframework/autorun/Nemes5.lua` <br>
Entry point loads the modules in `reframework/autorun/Nemes5/`. The  modules run once, through the entry point. Each system gets its own folder as its phase arrives (`World/`, `Factions/`, `Ghost/` and so on), holding its `Sim.lua` (plain Lua, no engine calls) and its `Engine.lua`, `Render.lua` or `UI.lua`.

| Module | Contents |
|---|---|
| `Definitions` | Names, paths, systems, the engine points each system needs, unconfirmed assumptions as variable in capital letters |
| `State` | Settings and runtime state shared by modules |
| `Shared` | Picks the PermadevShared copy to use: the newest installed by any Permadev mod that is compatible with this mod |
| `Adapter` | Startup probes of the engine points, per-system switch-off, guarded hooks |
| `ProbeLog` | Probe events (`reframework/data/Nemes5/probe_events.json`) and a summary of verification data |
| `Panel` | Mod panel ui: switch, system status, some verification data |
