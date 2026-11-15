--[[ @author: https://github.com/AbsenceGameDev. Permadev shared module v1. - Persistence
  per save slots for mods, stored as a ring of N snapshots (slot_<n>_h0..hN.json) with sequence, play time, and in-game time.
  On load the snapshot matching the save's play time is used, or closest below it if none match
]]


local SharedPrefix <const> = (...):match("^(.*%.)[^.]+$");
local Core = require(SharedPrefix .. "Core");

local TryCall = Core.TryCall;

--
-- Slots and times

--- @brief TODO REMOVE, from furhter looking at it -1 seems to be some shared save data file which is not relevant to us, need to ignore it
--- unsigned 32-bit (autosave -1 -> 4294967295).
--- Accepts an integer or an integral float, signed or unsigned; anything else is nil.
local function NormalizeSlot(Slot)
  local IntegerSlot = type(Slot) == "number" and math.tointeger(Slot) or nil;
  if IntegerSlot == nil then return nil end;
  return IntegerSlot & 0xFFFFFFFF;
end

--- @brief Slot as the game numbers it (autosaves negative), for display only. 
--- @Note will just remove this, turns out negative saves are some mumbo jumbo shared by all saves, so no touching it!
local function SignedSlot(Slot)
  if Slot == nil or Slot <= -1 then return nil end;
  -- local UnsignedSlot = NormalizeSlot(Slot);
  -- if UnsignedSlot == nil then return nil end;
  -- return UnsignedSlot - ((UnsignedSlot >> 31) & 1) * 0x100000000;
  return Slot;
end


local function FormatPlayTime(Seconds)
  if Seconds == nil then return "?" end;
  local WholeSeconds = math.floor(Seconds);
  return string.format("%d:%02d:%02d", WholeSeconds // 3600, WholeSeconds // 60 % 60, WholeSeconds % 60);
end

--- @brief Play time (TimeManager.WholePlayTime) and in-game time (day * InGameDaySeconds + seconds)
local function ReadTimes(PlayTimeGetter)
  local TimeManager = sdk.get_managed_singleton("app.TimeManager");
  if TimeManager == nil then return nil, nil end;

  local PlayTime = TryCall(function() return TimeManager:call(PlayTimeGetter) end);
  local InGameDay = TryCall(function() return TimeManager:call("get_InGameDay") end);
  local DaySeconds = TryCall(function() return TimeManager:call("get_InGameElapsedDaySeconds") end);
  local SecondsPerDay = TryCall(function() return sdk.find_type_definition("app.TimeManager"):get_field("InGameDaySeconds"):get_data(nil) end);
  local bHasGameTime = InGameDay ~= nil and DaySeconds ~= nil and SecondsPerDay ~= nil;

  return PlayTime, bHasGameTime and InGameDay * SecondsPerDay + DaySeconds or nil;
end

local DefaultNouns <const> = { Long = "snapshot", Short = "snapshot" };

--- @brief Chooses the snapshot for the loaded save. Returns the snapshot (or nil) and a note for the status line.
--- @note Nouns name the stored data in the notes: { Long = "NG+ fog", Short = "fog" }; snapshot if nil.
local function PickSnapshot(Snapshots, PlayTime, PlayTimeMatchSeconds, Nouns)
  local LongNoun, ShortNoun = (Nouns or DefaultNouns).Long, (Nouns or DefaultNouns).Short;
  if #Snapshots == 0 then return nil, "no " .. LongNoun .. " stored for this slot yet" end;

  local Newest = Snapshots[#Snapshots];
  if PlayTime == nil then return Newest, "play time unreadable: newest " .. LongNoun .. " used" end;

  local ExactMatch, NewestNotAfter;
  for _, Snapshot in ipairs(Snapshots) do
    local Distance = Snapshot.play ~= nil and math.abs(Snapshot.play - PlayTime) or nil;
    if Distance ~= nil and Distance <= PlayTimeMatchSeconds then
      local BestDistance = ExactMatch ~= nil and math.abs(ExactMatch.play - PlayTime) or math.huge;
      if Distance < BestDistance or (Distance == BestDistance and Snapshot.play < ExactMatch.play) then ExactMatch = Snapshot end;
    end
    if Snapshot.play ~= nil and Snapshot.play <= PlayTime + PlayTimeMatchSeconds
      and (NewestNotAfter == nil or Snapshot.play >= NewestNotAfter.play) then NewestNotAfter = Snapshot end;
  end

  if ExactMatch ~= nil then return ExactMatch, LongNoun .. " matches this save (" .. FormatPlayTime(PlayTime) .. ")" end;

  if Newest.play ~= nil and PlayTime < Newest.play then
    if NewestNotAfter ~= nil
      then return NewestNotAfter, "older or reverted save: " .. LongNoun .. " from " .. FormatPlayTime(NewestNotAfter.play) .. " used" end;

    local Oldest;
    for _, Snapshot in ipairs(Snapshots) do
      if Snapshot.play ~= nil and (Oldest == nil or Snapshot.play < Oldest.play) then Oldest = Snapshot end;
    end

    return Oldest or Newest, "save is older than all stored " .. LongNoun .. ": oldest kept " .. ShortNoun .. " used";
  end

  return Newest, "newest " .. LongNoun .. " used";
end

--
-- Snapshot store

--- @brief A snapshot store. Options:
--- DataDirectory (path under reframework/data, ending in "/"), HistorySize, PlayTimeMatchSeconds,
--- SlotFileState (the mod's table: (key -> value) slot -> { Sequence, NextRingIndex, Entries }), IsValidSnapshot(Content),
--- SummaryField and Summarize(Snapshot) (a per-snapshot summary copied into index entries), LegacySuffixes (older file names),
--- Nouns (see PickSnapshot).
local function New(Options)
  local DataDirectory, HistorySize, SlotFileState = Options.DataDirectory, Options.HistorySize, Options.SlotFileState;
  local IsValidSnapshot, SummaryField, Summarize = Options.IsValidSnapshot, Options.SummaryField, Options.Summarize;
  local LegacySuffixes = Options.LegacySuffixes or {};

  local function SlotFileBase(Slot) return DataDirectory .. "slot_" .. tostring(Slot) end;
  local function SlotIndexPath(Slot) return SlotFileBase(Slot) .. "_index.json" end;
  local function RingFilePath(Slot, RingIndex) return SlotFileBase(Slot) .. "_h" .. RingIndex .. ".json" end;

  local function ReadValidFile(Path)
    local Content = TryCall(json.load_file, Path);
    if type(Content) == "table" and IsValidSnapshot(Content) == true then return Content end;
  end

  --- @brief Summary of a snapshot for its index entry: the stored one, or computed for older snapshots without it
  local function SummaryOf(Snapshot)
    if SummaryField == nil then return nil end;
    return Snapshot[SummaryField] or Summarize(Snapshot);
  end

  --
  -- Slot index

  -- slot_<n>_index.json lists every snapshot of the slot as { file, ring, seq, play, saved, revealed }, so a load reads the
  -- index and one snapshot. Each snapshot also records its own seq: a snapshot whose seq differs from its index entry 
  -- (a crash between the two writes) makes the load fall back to a full scan, which rewrites the index.
  --- @brief Sorts index entries by sequence and sets the slot's ring position from the newest ring entry
  local function SetSlotEntries(Slot, Entries)
    table.sort(Entries, function(Lhs, Rhs) return (Lhs.seq or 0) < (Rhs.seq or 0) end);

    local FileState = { Sequence = 0, NextRingIndex = 0, Entries = Entries };
    for _, Entry in ipairs(Entries) do
      if Entry.ring ~= nil and Entry.seq > FileState.Sequence then
        FileState.Sequence, FileState.NextRingIndex = Entry.seq, (Entry.ring + 1) % HistorySize;
      end
    end

    SlotFileState[Slot] = FileState;
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
    for RingIndex = 0, HistorySize - 1 do
      local Path = RingFilePath(Slot, RingIndex);
      local Snapshot = ReadValidFile(Path);
      if Snapshot ~= nil then
        local Entry = { file = Path, ring = RingIndex, seq = Snapshot.seq or 0, play = Snapshot.play, saved = Snapshot.saved };
        if SummaryField ~= nil then Entry[SummaryField] = SummaryOf(Snapshot) end;
        Entries[#Entries + 1] = Entry;
      end
    end

    for LegacyIndex, LegacySuffix in ipairs(LegacySuffixes) do
      local LegacyPath = FileBase .. LegacySuffix;
      local Snapshot = ReadValidFile(LegacyPath);
      if Snapshot ~= nil then
        local Entry = { file = LegacyPath, seq = -10 + (Snapshot.seq or 0) + LegacyIndex * 0.001, play = Snapshot.play };
        if SummaryField ~= nil then Entry[SummaryField] = SummaryOf(Snapshot) end;
        Entries[#Entries + 1] = Entry;
      end
    end

    SetSlotEntries(Slot, Entries);
    WriteSlotIndex(Slot, Entries);
    return Entries;
  end

  --- @brief Index entries of a slot
  local function GetSlotEntries(Slot, bAllowScan)
    local FileState = SlotFileState[Slot];
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

  --- @brief Writes a snapshot as the next one in the slot's ring; sets its seq. 
  --- @return true if snapshot write succeeded.
  local function WriteSnapshot(Slot, Snapshot)
    if SlotFileState[Slot] == nil and ReadSlotIndex(Slot) == nil then ScanSlot(Slot) end;

    local FileState = SlotFileState[Slot];
    local RingIndex, Sequence = FileState.NextRingIndex, FileState.Sequence + 1;
    Snapshot.seq = Sequence;

  -- Writing the index first
  -- @note An index ahead of its file is caught on load (seq mismatch)
    local Entries = {};
    for _, Entry in ipairs(FileState.Entries) do if Entry.ring ~= RingIndex then Entries[#Entries + 1] = Entry end end;
    local NewEntry = { file = RingFilePath(Slot, RingIndex), ring = RingIndex, seq = Sequence, play = Snapshot.play, saved = Snapshot.saved };
    if SummaryField ~= nil then NewEntry[SummaryField] = Snapshot[SummaryField] end;
    Entries[#Entries + 1] = NewEntry;
    WriteSlotIndex(Slot, Entries);

    -- dump_file reports a failed write by returning false; 
    -- @note nil (no return value) counts as written
    local bCallSucceeded, WriteResult = pcall(json.dump_file, RingFilePath(Slot, RingIndex), Snapshot);
    local bDidWriteSnapshot = bCallSucceeded == true and WriteResult ~= false;
    if bDidWriteSnapshot == true then SetSlotEntries(Slot, Entries) end;
    return bDidWriteSnapshot;
  end

  return {
    ReadValidFile     = ReadValidFile,
    ReadSlotIndex     = ReadSlotIndex,
    ScanSlot          = ScanSlot,
    GetSlotEntries    = GetSlotEntries,
    ReadEntrySnapshot = ReadEntrySnapshot,
    WriteSnapshot     = WriteSnapshot,
    PickSnapshot      = function(Snapshots, PlayTime) return PickSnapshot(Snapshots, PlayTime, Options.PlayTimeMatchSeconds, Options.Nouns) end,
  };
end

return {
  NormalizeSlot  = NormalizeSlot,
  SignedSlot     = SignedSlot,
  FormatPlayTime = FormatPlayTime,
  ReadTimes      = ReadTimes,
  PickSnapshot   = PickSnapshot,
  New            = New,
};
