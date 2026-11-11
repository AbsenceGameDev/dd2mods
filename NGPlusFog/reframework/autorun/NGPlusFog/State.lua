--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - State
  - InstanceSettings: persisted user choices 
  - InstanceState: runtime data.
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")

--
-- Loaded intance settings
local InstanceSettings = {}
do
  local bLoaded, SavedSettings = pcall(json.load_file, Definitions.SettingsPath)
  for SettingName, DefaultValue in pairs(Definitions.SettingsDefaults) do
    InstanceSettings[SettingName] = DefaultValue
    if bLoaded == true and type(SavedSettings) == "table" then
      local SavedValue = SavedSettings[SettingName]
      if SavedValue == nil then SavedValue = SavedSettings[Definitions.PrototypeSettingsKeys[SettingName]] end
      if type(SavedValue) == type(DefaultValue) then InstanceSettings[SettingName] = SavedValue end
    end
  end
end

--- @brief Writes the current settings to the settings file
local function SaveSettings() pcall(json.dump_file, Definitions.SettingsPath, InstanceSettings) end

--
-- Instance state  hashmaps, key -> value
local InstanceState = {
  GameMasks = {},               -- data address -> { Key, Object }: the game's own MapMaskInfo objects
  PrivateMasks = {},            -- mask key -> private mask copy (see Masks.GetPrivateMask)
  PrivateMaskAddresses = {},    -- data address -> true for every private MapMaskInfo
  SavedMaskHex = {},            -- mask key -> hex bitmap of the snapshot in use
  FullMapPainters = {},         -- data address -> true for painters set up through setupMenu
  PainterRedrawGeneration = {}, -- data address -> exploration generation it last redrew for
  PinnedGameArrays = {},        -- data address -> true for game arrays kept alive with add_ref while swapped out
  HiddenIcons = {},             -- data address -> { WorldX, WorldZ } where the mod hid it
  RealProgressViews = {},       -- mask key -> read-only view of the game's own bitmap
  CellFogCache = {},            -- mask key -> {cell key -> bFogged}
  SlotFileState = {},           -- slot -> { Sequence, NextRingIndex }
  CopyBackups = {},             -- slot key -> list of { name, file }
  AllFogFiles = nil,            -- list of { name, file }: every fog file of every slot (cached fs.glob result)
  AllFogFileNames = nil,        -- dropdown labels for AllFogFiles, same order
  Selector =                    -- fog data selector: selection, grouped slots, per-slot row cache
    { 
      RowsBySlot = {}, 
      RowIndexBySlot = {}, 
      ScannedSlots = {} 
    }, 
  ProbeEvents = nil,            -- list of { time, event, details }: probe_events.json, loaded on first use (see ProbeLog)
  LoadMenu = {EnumNames = {}},  -- load menu rows (slots.json, loaded on first use), enum names, open menu, last slot calculation
  Counters = {},
  HookResults = {},
  RevealedCellCounts = {},
  Status = "waiting for game",
  ScopeDepth = 0,
  CursorSearchDepth = 0,
  ExplorationGeneration = 0,
  CellFogCacheGeneration = -1,
  FrameCounter = 0,
  LastIndexTime = -math.huge,
}

return {
  Settings     = InstanceSettings,
  Instance     = InstanceState,
  SaveSettings = SaveSettings,
}
