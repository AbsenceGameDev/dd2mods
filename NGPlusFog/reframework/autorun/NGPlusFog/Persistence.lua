--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Persistence
  NG+ fog per save slot, stored as a ring of 8 snapshots (slot_<n>_h0..h7.json) with sequence, play time, and in-game time.
  A crash can only damage the snapshot being written. On load, the snapshot matching the save's play time is used, or closest below it if none match
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")
local Masks       = require("NGPlusFog.Masks")

local InstanceState = State.Instance
local TryCall, Now, Increment, InstallHook = Core.TryCall, Core.Now, Core.Increment, Core.InstallHook
local ApplyHex, ClearBits, HexOf = Masks.ApplyHex, Masks.ClearBits, Masks.HexOf
local DataDirectory <const>        = Definitions.DataDirectory
local SnapshotHistorySize <const>  = Definitions.SnapshotHistorySize
local PlayTimeMatchSeconds <const> = Definitions.PlayTimeMatchSeconds
local SaveDataManagerType <const>  = Definitions.SaveDataManagerType
local GuiManagerType <const>       = Definitions.GuiManagerType

--
-- Snapshot files

local function SlotFileBase(Slot) return DataDirectory .. "slot_" .. tostring(Slot) end
local function ReadValidFile(Path)
  local Content = TryCall(json.load_file, Path)
  if type(Content) == "table" and type(Content.masks) == "table" then return Content end
end

--- @brief Play time (TimeManager.WholePlayTime) and in-game time (day * InGameDaySeconds + seconds)
local function ReadTimes()
  local TimeManager = sdk.get_managed_singleton("app.TimeManager")
  if TimeManager == nil then return nil, nil end

  local PlayTime = TryCall(function() return TimeManager:call(Definitions.PlayTimeGetter) end)
  local InGameDay = TryCall(function() return TimeManager:call("get_InGameDay") end)
  local DaySeconds = TryCall(function() return TimeManager:call("get_InGameElapsedDaySeconds") end)
  local SecondsPerDay = TryCall(function() return sdk.find_type_definition("app.TimeManager"):get_field("InGameDaySeconds"):get_data(nil) end)
  local bHasGameTime = InGameDay ~= nil and DaySeconds ~= nil and SecondsPerDay ~= nil

  return PlayTime, bHasGameTime and InGameDay * SecondsPerDay + DaySeconds or nil
end

--- @brief Reads every snapshot of a slot (ring files plus legacy files), sorted by sequence, and refreshes the slot's ring position
local function ScanSlot(Slot)
  local Snapshots, FileBase = {}, SlotFileBase(Slot)
  for RingIndex = 0, SnapshotHistorySize - 1 do
    local Snapshot = ReadValidFile(FileBase .. "_h" .. RingIndex .. ".json")
    if Snapshot ~= nil then Snapshot.RingIndex = RingIndex; Snapshots[#Snapshots + 1] = Snapshot end
  end

  for LegacyIndex, LegacyPath in ipairs({ FileBase .. "_a.json", FileBase .. "_b.json", FileBase .. ".json" }) do
    local Snapshot = ReadValidFile(LegacyPath)
    if Snapshot ~= nil then Snapshot.seq = -10 + (Snapshot.seq or 0) + LegacyIndex * 0.001; Snapshots[#Snapshots + 1] = Snapshot end
  end
  table.sort(Snapshots, function(Lhs, Rhs) return (Lhs.seq or 0) < (Rhs.seq or 0) end)

  local FileState = { Sequence = 0, NextRingIndex = 0 }
  for _, Snapshot in ipairs(Snapshots) do
    if Snapshot.RingIndex ~= nil and Snapshot.seq > FileState.Sequence then
      FileState.Sequence, FileState.NextRingIndex = Snapshot.seq, (Snapshot.RingIndex + 1) % SnapshotHistorySize
    end
  end

  InstanceState.SlotFileState[Slot] = FileState
  return Snapshots
end

local function FormatPlayTime(Seconds)
  if Seconds == nil then return "?" end
  local WholeSeconds = math.floor(Seconds)
  return string.format("%d:%02d:%02d", WholeSeconds // 3600, WholeSeconds // 60 % 60, WholeSeconds % 60)
end

--- @brief Chooses the snapshot for the loaded save. Returns the snapshot (or nil) and a note for the status line.
local function PickSnapshot(Snapshots, PlayTime)
  if #Snapshots == 0 then return nil, "no NG+ fog stored for this slot yet" end

  local Newest = Snapshots[#Snapshots]
  if PlayTime == nil then return Newest, "play time unreadable: newest NG+ fog used" end

  local ExactMatch, NewestNotAfter
  for _, Snapshot in ipairs(Snapshots) do
    local Distance = Snapshot.play ~= nil and math.abs(Snapshot.play - PlayTime) or nil
    if Distance ~= nil and Distance <= PlayTimeMatchSeconds then
      local BestDistance = ExactMatch ~= nil and math.abs(ExactMatch.play - PlayTime) or math.huge
      if Distance < BestDistance or (Distance == BestDistance and Snapshot.play < ExactMatch.play) then ExactMatch = Snapshot end
    end
    if Snapshot.play ~= nil and Snapshot.play <= PlayTime + PlayTimeMatchSeconds
      and (NewestNotAfter == nil or Snapshot.play >= NewestNotAfter.play) then NewestNotAfter = Snapshot end
  end

  if ExactMatch ~= nil then return ExactMatch, "NG+ fog matches this save (" .. FormatPlayTime(PlayTime) .. ")" end
  
  if Newest.play ~= nil and PlayTime < Newest.play then
    if NewestNotAfter ~= nil 
      then return NewestNotAfter, "older or reverted save: NG+ fog from " .. FormatPlayTime(NewestNotAfter.play) .. " used" end
    
    local Oldest
    for _, Snapshot in ipairs(Snapshots) do
      if Snapshot.play ~= nil and (Oldest == nil or Snapshot.play < Oldest.play) then Oldest = Snapshot end
    end

    return Oldest or Newest, "save is older than all stored NG+ fog: oldest kept fog used"
  end

  return Newest, "newest NG+ fog used"
end

--
-- Load, save and reset

local function ApplySavedMasks()
  for MaskKey, Private in pairs(InstanceState.PrivateMasks) do
    if ApplyHex(Private, InstanceState.SavedMaskHex[MaskKey]) == false then ClearBits(Private) end
  end

  InstanceState.bRedrawRequested = true
end

--- @brief Starts a slot load; the snapshot is chosen about half a second later, once the game has restored its own play time
local function LoadSlot(Slot)
  InstanceState.SavedMaskHex, InstanceState.PendingPickSlot, InstanceState.PendingPickTime = {}, Slot, Now() + Definitions.LoadPickDelaySeconds
  ApplySavedMasks()
end

local function PickPendingSnapshot()
  local Slot = InstanceState.PendingPickSlot
  InstanceState.PendingPickSlot = nil
  if Slot == nil then return end
  
  local Snapshots, PlayTime = ScanSlot(Slot), ReadTimes()
  local Snapshot, Note = PickSnapshot(Snapshots, PlayTime)
  InstanceState.SavedMaskHex = Snapshot ~= nil and Snapshot.masks or {}
  InstanceState.LoadedFogNote, InstanceState.PlayTimeAtLoad = Note, PlayTime

  ApplySavedMasks()
end

--- @brief Writes the current NG+ fog as the next snapshot in the slot's ring
local function SaveSlot(Slot)
  if Slot == nil then return end

  if InstanceState.PendingPickSlot ~= nil then PickPendingSnapshot() end -- a save right after a load must not store the still-empty fog

  for MaskKey, Private in pairs(InstanceState.PrivateMasks) do InstanceState.SavedMaskHex[MaskKey] = HexOf(Private) end
  if InstanceState.SlotFileState[Slot] == nil then ScanSlot(Slot) end

  local FileState = InstanceState.SlotFileState[Slot]
  local PlayTime, GameTime = ReadTimes()
  local Snapshot = { version = 3, seq = FileState.Sequence + 1, play = PlayTime, game = GameTime, masks = InstanceState.SavedMaskHex }

  local bDidWriteSnapshot = pcall(json.dump_file, SlotFileBase(Slot) .. "_h" .. FileState.NextRingIndex .. ".json", Snapshot) == true;
  if bDidWriteSnapshot == true then
    FileState.Sequence, FileState.NextRingIndex = FileState.Sequence + 1, (FileState.NextRingIndex + 1) % SnapshotHistorySize
  end
end

local function ResetNgPlusFog()
  InstanceState.SavedMaskHex = {}
  for _, Private in pairs(InstanceState.PrivateMasks) do ClearBits(Private) end
  InstanceState.bRedrawRequested = true
end

--
-- Save and load hooks

local function ReadSlotArgument(Argument) return TryCall(function() return sdk.to_int64(Argument) & 0xFFFFFFFF end) end
local SlotRequestParameters <const> = "(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])"

local function InstallHooks()
  InstallHook(SaveDataManagerType, "requestSaveSlot" .. SlotRequestParameters, function(Args)
    local Slot = ReadSlotArgument(Args[3])
    if Slot ~= nil and InstanceState.bActive == true then InstanceState.CurrentSlot = Slot; SaveSlot(Slot) end
  end, nil)

  InstallHook(SaveDataManagerType, "requestLoadSlot" .. SlotRequestParameters, function(Args)
    InstanceState.RequestedLoadSlot = ReadSlotArgument(Args[3])
  end, nil)

  InstallHook(GuiManagerType, "loadGameSaveData(app.SaveDataBase)", nil, function(ReturnValue)
    local SaveDataManager = sdk.get_managed_singleton(SaveDataManagerType)
    InstanceState.CurrentSlot = TryCall(function() return SaveDataManager:call("getLoadingGameSlotId") end) or InstanceState.RequestedLoadSlot
    InstanceState.GameMasks, InstanceState.LastIndexTime = {}, -math.huge
    LoadSlot(InstanceState.CurrentSlot)

    return ReturnValue
  end)

  InstallHook(GuiManagerType, "makeLoopSaveData()", nil, function(ReturnValue)
    local bResetOnNewCycle = Definitions.RESET_FOG_WHEN_MAKELOOPSAVEDATA_RUNS_ASSUMED_NEW_CYCLE_CREATION == true
    if bResetOnNewCycle == true then ResetNgPlusFog(); Increment("new_cycle_resets") end
    
    return ReturnValue
  end)
end

return {
  ReadValidFile       = ReadValidFile,
  ReadTimes           = ReadTimes,
  FormatPlayTime      = FormatPlayTime,
  ApplySavedMasks     = ApplySavedMasks,
  LoadSlot            = LoadSlot,
  PickPendingSnapshot = PickPendingSnapshot,
  SaveSlot            = SaveSlot,
  ResetNgPlusFog      = ResetNgPlusFog,
  InstallHooks        = InstallHooks,

  -- Exposed for tests
  PickSnapshot        = PickSnapshot,
}
