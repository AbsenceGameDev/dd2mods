--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Selector
  Fog data selector: pick a character, then one of its saves, then the fog data to load into the current NG+ fog.
]]  

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Persistence = require("NGPlusFog.Persistence");
local Backups     = require("NGPlusFog.Backups");
local LoadMenu    = require("NGPlusFog.LoadMenu");

local InstanceState                 = State.Instance;
local FormatPlayTime, SignedSlot    = Persistence.FormatPlayTime, Persistence.SignedSlot;
local SlotLayout <const>            = Definitions.ASSUMED_SAVE_SLOT_LAYOUT_PER_CHARACTER;
local PlayTimeMatchSeconds <const>  = Definitions.PlayTimeMatchSeconds;
local UnrecognisedCharacter <const> = -1; -- character key for slots outside the layout
local CharacterOrder <const>        = { 0, 1, 2, UnrecognisedCharacter };

--
-- Slots and characters

--- @brief Character key and save type label of a stored slot; Slots outside the layout gets UnrecognisedCharacter
local function DescribeSlot(Slot)
  local Layout = SlotLayout[SignedSlot(Slot)];
  if Layout == nil then return UnrecognisedCharacter, "Slot " .. tostring(SignedSlot(Slot)) end;

  return Layout[1], Layout[2];
end

--- @brief Returns label using Name, level, vocation  from the character's recorded load menu rows, after loadmenu has been opened; 
--- @note "##" suffix to keep the button unique if two characters read the same label
local function CharacterLabel(CharacterKey, Slots)
  local IdSuffix = "##character" .. CharacterKey;
  if CharacterKey == UnrecognisedCharacter then return "Other slots" .. IdSuffix end;

  for _, Slot in ipairs(Slots) do
    local Row = LoadMenu.GetRow(SignedSlot(Slot));
    local Arisen, Pawn = Row ~= nil and Row.arisen or nil, Row ~= nil and Row.pawn or nil;
    if Arisen ~= nil and Arisen.name ~= nil then
      local PawnText = (Pawn ~= nil and Pawn.name ~= nil) and string.format(" · pawn %s Lv %s", Pawn.name, tostring(Pawn.level)) or "";
      return string.format("%s · Lv %s %s%s", Arisen.name, tostring(Arisen.level), Arisen.job_name or Arisen.job_enum or "", PawnText) .. IdSuffix;
    end
  end

  return "Character " .. (CharacterKey + 1) .. IdSuffix;
end

--- @brief Stored slots with snapshot files, grouped by character (character key -> slots, autosave first).
--- Regrouped whenever the cached fog file list changes (not per frame)
local function GroupSlotsByCharacter()
  local Selector, FogFiles = InstanceState.Selector, Backups.GetAllFogFiles();
  if Selector.GroupedFogFiles == FogFiles then return Selector.Characters end;

  local Characters, SeenSlots = {}, {};
  for _, FogFile in ipairs(FogFiles) do
    local Slot = math.tointeger(tonumber(FogFile.name:match("^slot_(%-?%d+)[_%.]") or ""));
    if Slot ~= nil and SeenSlots[Slot] == nil then
      local CharacterKey = DescribeSlot(Slot);
      SeenSlots[Slot], Characters[CharacterKey] = true, Characters[CharacterKey] or {};
      table.insert(Characters[CharacterKey], Slot);
      Persistence.GetSlotEntries(Slot, false);
    end
  end

  for _, Slots in pairs(Characters) do table.sort(Slots, function(Lhs, Rhs) return SignedSlot(Lhs) < SignedSlot(Rhs) end) end;
  Selector.GroupedFogFiles, Selector.Characters = FogFiles, Characters;
  return Characters;
end

--- @brief Unlike a full scan, this indexes at most one not yet indexed slot
local function IndexOneSlot(Characters)
  local ScannedSlots = InstanceState.Selector.ScannedSlots;
  for _, Slots in pairs(Characters) do
    for _, Slot in ipairs(Slots) do
      local FileState = InstanceState.SlotFileState[Slot];
      local bNeedsScan = (FileState == nil or FileState.Entries == nil) and ScannedSlots[Slot] == nil;
      if bNeedsScan == true then ScannedSlots[Slot] = true; Persistence.GetSlotEntries(Slot, true); return end;
    end
  end
end

--- @brief Latest snapshot entry of a slot that has been indexed (nil until its index is read)
local function NewestEntry(Slot)
  local FileState = InstanceState.SlotFileState[Slot];
  local Entries = FileState ~= nil and FileState.Entries or nil;
  if Entries == nil then return nil end;
  
  return Entries[#Entries];
end

--
-- Fog data rows

--- @brief " · <status>" comparing a play time with the loaded save's
--- @note empty when unknown
local function CompareWithLoadedSave(PlayTime)
  local LoadedPlayTime = InstanceState.PlayTimeAtLoad;
  if PlayTime == nil or LoadedPlayTime == nil then return "" end;

  local Difference = PlayTime - LoadedPlayTime;
  if math.abs(Difference) <= PlayTimeMatchSeconds then return " · matches loaded save" end;

  return Difference < 0 and " · older" or " · newer than loaded save";
end

local function FormatRevealed(Revealed)
  local bHasOverworld = type(Revealed) == "table" and (Revealed.overworld_total or 0) > 0;
  if bHasOverworld == false then return "" end;

  return string.format(" · %.1f%%", 100 * Revealed.overworld / Revealed.overworld_total);
end

--- @brief Selectable rows of a slot: snapshots newest first, then its copy backups newest first.
--- @details Cached per slot until it goes stale (change to the slot's entries, backup count or loaded save).
local function GetFogDataRows(Slot)
  local Entries, CopyBackups = Persistence.GetSlotEntries(Slot, true) or {}, Backups.GetCopyBackups(Slot);
  local CachedRows = InstanceState.Selector.RowsBySlot[Slot];
  local bIsCacheValid = CachedRows ~= nil and CachedRows.Entries == Entries and CachedRows.EntryCount == #Entries and CachedRows.BackupCount == #CopyBackups
    and CachedRows.LoadedSlot == InstanceState.CurrentSlot and CachedRows.LoadedPlayTime == InstanceState.PlayTimeAtLoad;
  if bIsCacheValid == true then return CachedRows end;

  local bIsLoadedCharacter = InstanceState.CurrentSlot ~= nil and DescribeSlot(InstanceState.CurrentSlot) == DescribeSlot(Slot);
  local Rows = { Entries = Entries, EntryCount = #Entries, BackupCount = #CopyBackups, Labels = {},
    LoadedSlot = InstanceState.CurrentSlot, LoadedPlayTime = InstanceState.PlayTimeAtLoad };

  for EntryIndex = #Entries, 1, -1 do
    local Entry = Entries[EntryIndex];
    local Name = Entry.ring ~= nil and ("Snapshot #" .. (math.tointeger(Entry.seq) or Entry.seq)) or "Snapshot (1.3/1.4 file)";
    local Status = bIsLoadedCharacter == true and CompareWithLoadedSave(Entry.play) or "";
    Rows[#Rows + 1] = { file = Entry.file, name = Name, Revealed = Entry.revealed,
      Label = Name .. " · " .. FormatPlayTime(Entry.play) .. " · " .. (Entry.saved or "date unknown") .. FormatRevealed(Entry.revealed) .. Status };
  end

  for BackupIndex = #CopyBackups, 1, -1 do
    local CopyBackup = CopyBackups[BackupIndex];
    Rows[#Rows + 1] = { file = CopyBackup.file, name = "Backup " .. CopyBackup.name, Label = "Backup · " .. CopyBackup.name };
  end

  for RowIndex, Row in ipairs(Rows) do Rows.Labels[RowIndex] = Row.Label end;

  InstanceState.Selector.RowsBySlot[Slot] = Rows;
  return Rows;
end

--
-- Drawing

--- @brief A row of buttons, mapped to one per choice, returns the clicked choice's key (or nil). 
--- @note the selected one is denoted with "> ".
local function DrawChoiceButtons(Choices, SelectedKey)
  local ClickedKey;
  for ChoiceIndex, Choice in ipairs(Choices) do
    if ChoiceIndex > 1 then imgui.same_line() end;

    local Marker = Choice.Key == SelectedKey and "> " or "";
    if imgui.button(Marker .. Choice.Label) == true then ClickedKey = Choice.Key end;
  end

  return ClickedKey;
end

--- @brief Keeps a selection valid 
local function ResolveSelection(Choices, CurrentKey, PreferredKey)
  local bHasCurrent, bHasPreferred = false, false;
  for _, Choice in ipairs(Choices) do
    bHasCurrent, bHasPreferred = bHasCurrent or Choice.Key == CurrentKey, bHasPreferred or Choice.Key == PreferredKey;
  end

  if bHasCurrent == true then return CurrentKey end;
  if bHasPreferred == true then return PreferredKey end;
  return Choices[1] ~= nil and Choices[1].Key or nil;
end

local function DrawSelector()
  local Selector, Characters = InstanceState.Selector, GroupSlotsByCharacter();
  IndexOneSlot(Characters);
  local LoadedSlot = InstanceState.CurrentSlot;
  local LoadedCharacter = LoadedSlot ~= nil and DescribeSlot(LoadedSlot) or nil;

  -- character choice
  local CharacterChoices = {};
  for _, CharacterKey in ipairs(CharacterOrder) do
    local Slots = Characters[CharacterKey];
    if Slots ~= nil then
      local NewestPlayTime;
      for _, Slot in ipairs(Slots) do
        local Newest = NewestEntry(Slot);
        if Newest ~= nil and Newest.play ~= nil and (NewestPlayTime == nil or Newest.play > NewestPlayTime) then NewestPlayTime = Newest.play end;
      end

      local LoadedMark = CharacterKey == LoadedCharacter and " (loaded)" or "";
      local Latest = NewestPlayTime ~= nil and (" · latest " .. FormatPlayTime(NewestPlayTime)) or "";
      local Label = CharacterLabel(CharacterKey, Slots);
      local NameText, IdSuffix = Label:match("^(.-)(##.*)$");
      CharacterChoices[#CharacterChoices + 1] = { Key = CharacterKey, Label = NameText .. LoadedMark .. Latest .. IdSuffix };
    end
  end

  if #CharacterChoices == 0 then imgui.text("No NG+ fog files yet: they are written at each game save."); return end;
  imgui.text("1  Character");
  Selector.CharacterKey = ResolveSelection(CharacterChoices, Selector.CharacterKey, LoadedCharacter);
  Selector.CharacterKey = DrawChoiceButtons(CharacterChoices, Selector.CharacterKey) or Selector.CharacterKey;

  -- saves of character
  local SaveChoices = {};
  for _, Slot in ipairs(Characters[Selector.CharacterKey]) do
    local _CharacterKey, SaveType = DescribeSlot(Slot);
    local Newest = NewestEntry(Slot);
    local Row = LoadMenu.GetRow(SignedSlot(Slot));
    local Place = (Row ~= nil and Row.place ~= nil) and (" · " .. Row.place) or "";
    local LoadedMark = Slot == LoadedSlot and " (loaded)" or "";
    local Latest = Newest ~= nil and (" · " .. FormatPlayTime(Newest.play)) or "";
    SaveChoices[#SaveChoices + 1] = { Key = Slot, Label = SaveType .. Place .. LoadedMark .. Latest };
  end

  imgui.text("2  Save");
  Selector.Slot = ResolveSelection(SaveChoices, Selector.Slot, LoadedSlot);
  Selector.Slot = DrawChoiceButtons(SaveChoices, Selector.Slot) or Selector.Slot;

  -- fog data of selected save
  local Rows = GetFogDataRows(Selector.Slot);
  if #Rows == 0 then imgui.text("3  No fog data in this save."); return end;

  local SelectedRowIndex = math.min(math.max(Selector.RowIndexBySlot[Selector.Slot] or 1, 1), #Rows);
  local bSelectionChanged, NewRowIndex = imgui.combo("3  Fog data", SelectedRowIndex, Rows.Labels);
  if bSelectionChanged == true then SelectedRowIndex = NewRowIndex end;

  Selector.RowIndexBySlot[Selector.Slot] = SelectedRowIndex;
  local SelectedRow = Rows[SelectedRowIndex];
  local Revealed = SelectedRow.Revealed;
  if type(Revealed) == "table" then
    imgui.text(string.format("   Overworld %d of %d cells revealed · %d local maps, %d cells", Revealed.overworld or 0, Revealed.overworld_total or 0, Revealed.local_maps or 0, Revealed.local_cells or 0));
  end

  local bLoadClicked = imgui.button("Load selected fog data into NG+ fog") == true;
  if bLoadClicked == true then Backups.LoadFogFile(SelectedRow) end;
end

return {
  Draw = DrawSelector,

  -- Exposed for tests
  DescribeSlot = DescribeSlot,
};
