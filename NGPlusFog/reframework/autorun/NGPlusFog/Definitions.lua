--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Definitions
  - Constants shared by every NG+ Fog module.
  - Names written in CAPITALS are for behaviours not yet confirmed in game.
]]

local Definitions = {}

--
-- Paths and game types
Definitions.SettingsPath        = "NGPlusFog/config.json"
Definitions.DataDirectory       = "NGPlusFog/"
Definitions.GuiManagerType      = "app.GuiManager"
Definitions.MaskInfoType        = "app.GuiManager.MapMaskInfo"
Definitions.MaskPainterType     = "app.GUIMaskPainter"
Definitions.SaveDataManagerType = "app.SaveDataManager"
Definitions.FullMapType         = "app.ui040205"
Definitions.MinimapType         = "app.ui020301"
Definitions.SetMaskOffSignature = "setMaskOff(via.vec3)"
Definitions.IsMaskOffSignature  = "isMaskOff(via.vec3)"
Definitions.PlayTimeGetter      = "get_WholePlayTime" -- app.TimeManager; @todo: check if restored from the save on load
Definitions.OverworldMaskKey    = "F" -- GuiManager.MapMaskField; local area masks are "L<index>"

-- layout for MaskBit access
Definitions.ManagedArrayByteDataOffset = 0x20
Definitions.ManagedArrayByteLengthFieldOffset = 0x1C

--
-- Unconfirmed behaviour
Definitions.RESET_FOG_WHEN_MAKELOOPSAVEDATA_RUNS_ASSUMED_NEW_CYCLE_CREATION = true -- @todo: need to test on a save that passes NG+ during the session

-- Save slot { character index, save type }.
-- @todo: confirm against SaveSlotNo and SaveDataType of the load menu rows (app.ui030901.MainListInfo).
-- @note The game calls the manual save "Last interim save"
Definitions.ASSUMED_SAVE_SLOT_LAYOUT_PER_CHARACTER = {
  [-1] = { 0, "Autosave" }, [0] = { 0, "Last interim save" }, [4] = { 0, "Inn save" },
  [-2] = { 1, "Autosave" }, [1] = { 1, "Last interim save" }, [5] = { 1, "Inn save" },
  [-3] = { 2, "Autosave" }, [2] = { 2, "Last interim save" }, [6] = { 2, "Inn save" },
};

--
-- Tuning
Definitions.SnapshotHistorySize   = 16    -- snapshot files (per save slot). In case save files are reverted, the previous last save states are kept
Definitions.PlayTimeMatchSeconds  = 2.0   -- slack for snapshot playtime check when matching correct snapshot 
Definitions.LoadPickDelaySeconds  = 0.5   -- time to delay the slot pick when loadGameSaveData runs
Definitions.TickIntervalSeconds   = 0.25  -- update/refresh interval for fog reveal
Definitions.StuckFrameLimit       = 3     -- if a scope is open for longer than this amount of frames gets force-closed
Definitions.IconRevealRadiusCells = 2     -- an icon shows if any 16 m cell within 2 cells (32 m) is revealed; the fog edge is soft
Definitions.ParkedCoordinate      = 1.0e6 -- coord on map where 'hidden' icons are moved
Definitions.CellKeyStride         = 8192  --

--
-- Field lists
Definitions.GeometryFields = { "BasePos", "EdgePos", "DispRange", "MaskNum", "Interval", "IntervalHalf", "IntervalShift" }
Definitions.IconListFields = { "MapIconInfoList", "OriginAreaMapIconInfoList", "NRDAreaMapIconInfoList" }

--
-- Settings
Definitions.SettingsDefaults   = { bFogOfWar = true, bShowRealMapProgress = false }
-- Settings file keys left from prototyping, some of my local save dta is stored it in this format
Definitions.PrototypeSettingsKeys = { bFogOfWar = "enabled", bShowRealMapProgress = "show_real_map_progress" }

return Definitions
