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
local OverworldMaskKey <const>     = Definitions.OverworldMaskKey;

--
-- Snapshot files

local function SlotFileBase(Slot) return DataDirectory .. "slot_" .. tostring(Slot) end
local function ReadValidFile(Path)
  local Content = TryCall(json.load_file, Path)
  if type(Content) == "table" and type(Content.masks) == "table" then return Content end
end

-- Set bits per hex digit, indexed by the digit's byte value ('0'-'9', 'a'-'f', 'A'-'F')
local HexDigitBitCounts <const> = {};
for DigitValue = 0, 15 do
  local DigitBitCount = (DigitValue & 1) + (DigitValue >> 1 & 1) + (DigitValue >> 2 & 1) + (DigitValue >> 3 & 1);
  HexDigitBitCounts[string.byte(string.format("%x", DigitValue))] = DigitBitCount;
  HexDigitBitCounts[string.byte(string.format("%X", DigitValue))] = DigitBitCount;
end

--- @brief Revealed cell counts of a set of fog bitmaps (mask key -> hex): the overworld's revealed and total cells,
--- and the number of local maps (caves, interiors) with their revealed cells
local function CountRevealed(MaskHex)
  local Revealed = { overworld = 0, overworld_total = 0, local_maps = 0, local_cells = 0 };
  for MaskKey, Hex in pairs(MaskHex) do
    local CellCount = 0;
    for CharIndex = 1, #Hex do CellCount = CellCount + (HexDigitBitCounts[string.byte(Hex, CharIndex)] or 0) end;

    if MaskKey == OverworldMaskKey then
      Revealed.overworld, Revealed.overworld_total = CellCount, #Hex * 4;
    else
      Revealed.local_maps, Revealed.local_cells = Revealed.local_maps + 1, Revealed.local_cells + CellCount;
    end
  end

  return Revealed;
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

--
-- Slot index

-- slot_<n>_index.json lists every snapshot of the slot as { file, ring, seq, play, saved, revealed }, so a load reads the
-- index and one snapshot. Each snapshot also records its own seq: a snapshot whose seq differs from its index entry 
-- (a crash between the two writes) makes the load fall back to a full scan, which rewrites the index.

local function SlotIndexPath(Slot) return SlotFileBase(Slot) .. "_index.json" end;
local function RingFilePath(Slot, RingIndex) return SlotFileBase(Slot) .. "_h" .. RingIndex .. ".json" end;

--- @brief Sorts index entries by sequence and sets the slot's ring position from the newest ring entry
local function SetSlotEntries(Slot, Entries)
  table.sort(Entries, function(Lhs, Rhs) return (Lhs.seq or 0) < (Rhs.seq or 0) end);

  local FileState = { Sequence = 0, NextRingIndex = 0, Entries = Entries };
  for _, Entry in ipairs(Entries) do
    if Entry.ring ~= nil and Entry.seq > FileState.Sequence then
      FileState.Sequence, FileState.NextRingIndex = Entry.seq, (Entry.ring + 1) % SnapshotHistorySize;
    end
  end

  InstanceState.SlotFileState[Slot] = FileState;
  return Entries;
end

local function WriteSlotIndex(Slot, Entries) pcall(json.dump_file, SlotIndexPath(Slot), { version = 1, entries = Entries }) end;

--- @brief Index entries of a slot (no fog data), or nil if the index is missing or unreadable
local function ReadSlotIndex(Slot)
  local Index = TryCall(json.load_file, SlotIndexPath(Slot));
  if type(Index) ~= "table" or type(Index.entries) ~= "table" then return nil end;

  local Entries = {};
  for _, Entry in ipairs(Index.entries) do
    local bIsValidEntry = type(Entry) == "table" and type(Entry.file) == "string" and type(Entry.seq) == "number";
    if bIsValidEntry == true then Entries[#Entries + 1] = Entry end;
  end

  return SetSlotEntries(Slot, Entries);
end

--- @brief Full scan: reads every snapshot of a slot (ring files plus legacy files) and updates the slot's index
local function ScanSlot(Slot)
  local Entries, FileBase = {}, SlotFileBase(Slot);
  for RingIndex = 0, SnapshotHistorySize - 1 do
    local Path = RingFilePath(Slot, RingIndex);
    local Snapshot = ReadValidFile(Path);
    if Snapshot ~= nil then
      Entries[#Entries + 1] = { file = Path, ring = RingIndex, seq = Snapshot.seq or 0, play = Snapshot.play, saved = Snapshot.saved, revealed = Snapshot.revealed or CountRevealed(Snapshot.masks) };
    end
  end

  for LegacyIndex, LegacyPath in ipairs({ FileBase .. "_a.json", FileBase .. "_b.json", FileBase .. ".json" }) do
    local Snapshot = ReadValidFile(LegacyPath);
    if Snapshot ~= nil then
      Entries[#Entries + 1] = { file = LegacyPath, seq = -10 + (Snapshot.seq or 0) + LegacyIndex * 0.001, play = Snapshot.play, revealed = Snapshot.revealed or CountRevealed(Snapshot.masks) };
    end
  end

  SetSlotEntries(Slot, Entries);
  WriteSlotIndex(Slot, Entries);
  return Entries;
end

--- @brief Index entries of a slot
local function GetSlotEntries(Slot, bAllowScan)
  local FileState = InstanceState.SlotFileState[Slot];
  if FileState ~= nil and FileState.Entries ~= nil then return FileState.Entries end;
  return ReadSlotIndex(Slot) or (bAllowScan == true and ScanSlot(Slot) or nil);
end

--- @brief The fog data of an index entry, or nil if the file is unreadable or holds another snapshot than the index says
local function ReadEntrySnapshot(Entry)
  local Snapshot = ReadValidFile(Entry.file);
  local bIsStale = Snapshot == nil or (Entry.ring ~= nil and Snapshot.seq ~= Entry.seq);
  if bIsStale == true then return nil end;
  return Snapshot;
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
  
  local PlayTime = ReadTimes();
  local Entries = ReadSlotIndex(Slot) or ScanSlot(Slot);
  local Entry, Note = PickSnapshot(Entries, PlayTime);
  local Snapshot = Entry ~= nil and ReadEntrySnapshot(Entry) or nil;
  
  -- index out of date: full scan, then pick again
  if Entry ~= nil and Snapshot == nil then 
    Entry, Note = PickSnapshot(ScanSlot(Slot), PlayTime);
    Snapshot = Entry ~= nil and ReadEntrySnapshot(Entry) or nil;
  end

  InstanceState.SavedMaskHex = Snapshot ~= nil and Snapshot.masks or {}
  InstanceState.LoadedFogNote, InstanceState.PlayTimeAtLoad = Note, PlayTime

  ApplySavedMasks()
end

--- @brief Writes the current NG+ fog as the next snapshot in the slot's ring
local function SaveSlot(Slot)
  if Slot == nil then return end

  if InstanceState.PendingPickSlot ~= nil then PickPendingSnapshot() end -- a save right after a load must not store the still-empty fog

  for MaskKey, Private in pairs(InstanceState.PrivateMasks) do InstanceState.SavedMaskHex[MaskKey] = HexOf(Private) end
  if InstanceState.SlotFileState[Slot] == nil and ReadSlotIndex(Slot) == nil then ScanSlot(Slot) end;

  local FileState = InstanceState.SlotFileState[Slot]
  local PlayTime, GameTime = ReadTimes()
  local RingIndex, Sequence = FileState.NextRingIndex, FileState.Sequence + 1;
  local Snapshot = {
    version = 4, seq = Sequence, play = PlayTime, game = GameTime,
    saved = os.date("%Y-%m-%d %H:%M:%S"), revealed = CountRevealed(InstanceState.SavedMaskHex), masks = InstanceState.SavedMaskHex,
  };

  -- Writing the index first; 
  -- @note An index ahead of its file is caught on load (seq mismatch)
  local Entries = {};
  for _, Entry in ipairs(FileState.Entries) do if Entry.ring ~= RingIndex then Entries[#Entries + 1] = Entry end end;
  Entries[#Entries + 1] = { file = RingFilePath(Slot, RingIndex), ring = RingIndex, seq = Sequence, play = PlayTime, saved = Snapshot.saved, revealed = Snapshot.revealed };
  WriteSlotIndex(Slot, Entries);

  -- dump_file reports a failed write by returning false; nil (no return value) counts as written
  local bCallSucceeded, WriteResult = pcall(json.dump_file, RingFilePath(Slot, RingIndex), Snapshot);
  local bDidWriteSnapshot = bCallSucceeded == true and WriteResult ~= false;
  if bDidWriteSnapshot == true then SetSlotEntries(Slot, Entries) end;
end

local function ResetNgPlusFog()
  InstanceState.SavedMaskHex = {}
  for _, Private in pairs(InstanceState.PrivateMasks) do ClearBits(Private) end
  InstanceState.bRedrawRequested = true
end

--
-- Save and load hooks

--- @brief The one form slots are stored and compared in: unsigned 32-bit (autosave -1 -> 4294967295).
--- Accepts an integer or an integral float, signed or unsigned; anything else is nil.
local function NormalizeSlot(Slot)
  local IntegerSlot = type(Slot) == "number" and math.tointeger(Slot) or nil;
  if IntegerSlot == nil then return nil end;
  return IntegerSlot & 0xFFFFFFFF;
end

--- @brief Slot as the game numbers it (autosaves negative), for display only
local function SignedSlot(Slot)
  local UnsignedSlot = NormalizeSlot(Slot);
  if UnsignedSlot == nil then return nil end;
  return UnsignedSlot - ((UnsignedSlot >> 31) & 1) * 0x100000000;
end

local function ReadSlotArgument(Argument) return NormalizeSlot(TryCall(sdk.to_int64, Argument)) end;
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
    local LoadingSlot = NormalizeSlot(TryCall(function() return SaveDataManager:call("getLoadingGameSlotId") end));
    local RequestedSlot = InstanceState.RequestedLoadSlot;
    local bSlotSourcesDisagree = LoadingSlot ~= nil and RequestedSlot ~= nil and LoadingSlot ~= RequestedSlot;
    if bSlotSourcesDisagree == true then Increment("load_slot_sources_disagree") end;

    InstanceState.CurrentSlot = LoadingSlot or RequestedSlot;
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
  SignedSlot          = SignedSlot,
  GetSlotEntries      = GetSlotEntries,
  InstallHooks        = InstallHooks,

  -- Exposed for tests
  PickSnapshot        = PickSnapshot,
}
