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
Definitions.LoadMenuType        = "app.ui030901"; -- the game's load menu: one MainListInfo row per save
Definitions.SaveDataTypeEnum    = "app.ui030901.SaveDataType";
Definitions.JobEnum             = "app.Character.JobEnum";

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

-- Job enum name -> vocation. @todo: confirm against the job shown in the load menu (load_menu_row events record job_enum).
Definitions.ASSUMED_JOB_NAMES = {
  Job01 = "Fighter", Job02 = "Archer", Job03 = "Mage", Job04 = "Thief", Job05 = "Warrior",
  Job06 = "Sorcerer", Job07 = "Mystic Spearhand", Job08 = "Magick Archer", Job09 = "Trickster", Job10 = "Warfarer",
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
-- Fog preview (selector details). Colours are ABGR (0xAABBGGRR), per imgui draw expectations.
Definitions.OverworldColumns      = 512;  -- overworld mask columns (measured 2026-11-05: 512 x 516 cells of 16 m)
Definitions.PreviewBlockCells     = 4;    -- overlay: one preview block per 4 x 4 cells (128 x 129 blocks)
Definitions.PreviewPixelsPerBlock = 2;    -- overlay: 256 x 258 pixels
Definitions.PreviewTextBlockCells = 8;    -- text mode: one character per 8 x 8 cells (64 x 65 characters)
Definitions.PreviewRebuildSeconds = 2.0;  -- while exploring with the preview open, it is rebuilt at maximum this frequently
Definitions.PreviewColors = { Both = 0xFFC9A37A, OnlyCurrent = 0xFF4FB0E0, OnlySelected = 0xFF6AB34F, Fog = 0xFF312D2A };
Definitions.PreviewCharacters = { Both = "#", OnlyCurrent = "-", OnlySelected = "+", Fog = "." };

--
-- Field lists
Definitions.GeometryFields = { "BasePos", "EdgePos", "DispRange", "MaskNum", "Interval", "IntervalHalf", "IntervalShift" }
Definitions.IconListFields = { "MapIconInfoList", "OriginAreaMapIconInfoList", "NRDAreaMapIconInfoList" }

--
-- Settings
Definitions.SettingsDefaults   = {
  bFogOfWar = true, bShowRealMapProgress = false,
  PreviewMode = "Overlay",      -- @todo confirm draw paints over the panel. "Overlay" (draw.filled_rect over the panel) or "Text"
  bPreviewFlipVertical = false, -- @todo confirm that mask row 0 is the top of the game's map
}
-- Settings file keys left from prototyping, some of my local save dta is stored it in this format
Definitions.PrototypeSettingsKeys = { bFogOfWar = "enabled", bShowRealMapProgress = "show_real_map_progress" }

return Definitions
