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
local Preview     = require("NGPlusFog.Preview");
local ProbeLog    = require("NGPlusFog.ProbeLog");
local Widgets     = require("NGPlusFog.Widgets");

local InstanceSettings, InstanceState = State.Settings, State.Instance;
local FormatPlayTime, SignedSlot = Persistence.FormatPlayTime, Persistence.SignedSlot;
local Theme, Rect, Text, TextRight = Widgets.Theme, Widgets.Rect, Widgets.Text, Widgets.TextRight;
local SlotLayout <const>            = Definitions.ASSUMED_SAVE_SLOT_LAYOUT_PER_CHARACTER;
local PlayTimeMatchSeconds <const>  = Definitions.PlayTimeMatchSeconds;
local UnrecognisedCharacter <const> = -1; -- character key for slots outside the layout
local CharacterOrder <const>        = { 0, 1, 2, UnrecognisedCharacter };
local WindowTitle <const>           = "NG+ Fog - Fog data selector";
local NoCollapseFlag <const>        = 32; -- ImGuiWindowFlags_NoCollapse
local FirstUseEver <const>          = 4;  -- ImGuiCond_FirstUseEver
local Padding <const>, Gap <const>  = 10, 8;

for _, FieldName in ipairs({ "RowsBySlot", "FileBySlot", "ScannedSlots" }) do InstanceState.Selector[FieldName] = InstanceState.Selector[FieldName] or {} end;

--
-- Slots and characters

--- @brief Character key and save type label of a stored slot; 
--- @details Slots outside the layout gets UnrecognisedCharacter
local function DescribeSlot(Slot)
  local Layout = SlotLayout[SignedSlot(Slot)];
  if Layout == nil then return UnrecognisedCharacter, "Slot " .. tostring(SignedSlot(Slot)) end;

  return Layout[1], Layout[2];
end

--- @brief Find character row 
--- @return label using Name, level, vocation  
--- @note "##" suffix to keep the button unique if two characters read the same label
local function FindCharacterRow(Slots)
  for _, Slot in ipairs(Slots) do
    local Row = LoadMenu.GetRow(SignedSlot(Slot));
    if Row ~= nil and Row.arisen ~= nil and Row.arisen.name ~= nil then return Row end;
  end
end

--- @brief Short name of a character for titles: the Arisen's name, else "Character N" or "Other slots"
local function CharacterName(CharacterKey, Slots)
  if CharacterKey == UnrecognisedCharacter then return "Other slots" end;
  local Row = FindCharacterRow(Slots);
  return Row ~= nil and Row.arisen.name or ("Character " .. (CharacterKey + 1));
end

--- @brief Stored slots with snapshot files, grouped by character.
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

--- @brief Snapshot entries of a slot that has been indexed (index is exppected to have been read before calling this)
local function KnownEntries(Slot)
  local FileState = InstanceState.SlotFileState[Slot];
  return FileState ~= nil and FileState.Entries or {};
end

--- @brief Latest snapshot entry of a slot that has been indexed (index is exppected to have been read before calling this)
local function NewestEntryOf(Slots)
  local Newest;
  for _, Slot in ipairs(Slots) do
    local Entries = KnownEntries(Slot);
    local Candidate = Entries[#Entries];

    local bValidCandidateFound = Candidate ~= nil and (Newest == nil or (Candidate.play or 0) > (Newest.play or 0));
    if bValidCandidateFound == true then Newest = Candidate end;
  end

  return Newest;
end

--
-- Fog data rows

--- @brief " · <status>" comparing a play time with the loaded save's
--- @note empty when unknown
local function CompareWithLoadedSave(PlayTime)
  local LoadedPlayTime = InstanceState.PlayTimeAtLoad;
  if PlayTime == nil or LoadedPlayTime == nil then return nil end;

  local Difference = PlayTime - LoadedPlayTime;
  if math.abs(Difference) <= PlayTimeMatchSeconds then return "Matches" end;
  
  return Difference < 0 and "Older" or "Newer";
end

--- @brief Overworld fraction revealed (0..1), or nil
local function OverworldFraction(Revealed)
  local bHasOverworld = type(Revealed) == "table" and (Revealed.overworld_total or 0) > 0;
  if bHasOverworld == false then return nil end;
  
  return Revealed.overworld / Revealed.overworld_total;
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
  local Rows = { Entries = Entries, EntryCount = #Entries, BackupCount = #CopyBackups,
    LoadedSlot = InstanceState.CurrentSlot, LoadedPlayTime = InstanceState.PlayTimeAtLoad };

  for EntryIndex = #Entries, 1, -1 do
    local Entry = Entries[EntryIndex];
    local Name = Entry.ring ~= nil and ("Snapshot #" .. (math.tointeger(Entry.seq) or Entry.seq)) or "Snapshot";
    Rows[#Rows + 1] = {
      file = Entry.file, name = Name, Kind = "Snapshot", Note = EntryIndex == #Entries and "(latest)" or (Entry.ring == nil and "(1.3/1.4 file)" or nil),
      PlayText = FormatPlayTime(Entry.play), Saved = Entry.saved or "date unknown", Revealed = Entry.revealed,
      Status = bIsLoadedCharacter == true and CompareWithLoadedSave(Entry.play) or nil,
    };
  end

  for BackupIndex = #CopyBackups, 1, -1 do
    local CopyBackup = CopyBackups[BackupIndex];
    local Saved = CopyBackup.name:match("^(%S+ %S+)") or CopyBackup.name;
    Rows[#Rows + 1] = {
      file = CopyBackup.file, name = "Backup " .. Saved:sub(6, 16), Kind = "Backup",
      PlayText = CopyBackup.name:match("play time ([%d:]+)") or "?", Saved = Saved, Status = "Backup",
    };
  end

  InstanceState.Selector.RowsBySlot[Slot] = Rows;
  return Rows;
end

--- @brief Get filtered rows
local function FilterRows(Rows)
  local Selector, Visible = InstanceState.Selector, {};
  for _, Row in ipairs(Rows) do
    local bKindShown = (Row.Kind == "Snapshot" and Selector.bShowSnapshots ~= false) or (Row.Kind == "Backup" and Selector.bShowBackups ~= false);
    local bHidden = Selector.bHideNewer == true and Row.Status == "Newer";
    if bKindShown == true and bHidden == false then Visible[#Visible + 1] = Row end;
  end

  return Visible;
end

local StatusBadges <const> = {
  Matches = { "MATCHES LOADED SAVE", "Green" }, Older = { "OLDER", "Grey" }, Newer = { "NEWER THAN SAVE", "Amber" }, Backup = { "BACKUP", "Purple" },
};

--
-- Selection

--- @brief Keeps a selection valid 
local function ResolveSelection(Keys, CurrentKey, PreferredKey)
  local bHasCurrent, bHasPreferred = false, false;
  for _, Key in ipairs(Keys) do bHasCurrent, bHasPreferred = bHasCurrent or Key == CurrentKey, bHasPreferred or Key == PreferredKey end;
  if bHasCurrent == true then return CurrentKey end;
  if bHasPreferred == true then return PreferredKey end;
  return Keys[1];
end

--
-- Window sections

--- @brief Character cards along the top; 
--- @return CardHeight (height used for the card)
local function DrawCharacterCards(DrawList, Characters, CharacterKeys, X, Y, Width, LineHeight)
  local Selector = InstanceState.Selector;
  local LoadedCharacter = InstanceState.CurrentSlot ~= nil and DescribeSlot(InstanceState.CurrentSlot) or nil;
  local CardCount = math.max(#CharacterKeys, 3);
  local CardWidth, CardHeight = (Width - Gap * (CardCount - 1)) / CardCount, LineHeight * 4 + 26;

  for CardIndex, CharacterKey in ipairs(CharacterKeys) do
    local Slots, CardX = Characters[CharacterKey], X + (CardIndex - 1) * (CardWidth + Gap);
    local bClicked, bHovered = Widgets.HitArea("##character" .. CharacterKey, CardX, Y, CardWidth, CardHeight);
    if bClicked == true then Selector.CharacterKey = CharacterKey end;

    local bSelected = Selector.CharacterKey == CharacterKey;
    Rect(DrawList, CardX, Y, CardWidth, CardHeight, bSelected == true and Theme.Selected or (bHovered == true and Theme.CardHover or Theme.Card),
      bSelected == true and Theme.SelectedBorder or Theme.Border);
    Widgets.PushClip(DrawList, CardX, Y, CardWidth, CardHeight);

    local TextX, TextY, HalfWidth = CardX + 12, Y + 8, (CardWidth - 24) / 2;
    if CharacterKey == UnrecognisedCharacter then
      Text(DrawList, TextX, TextY, Theme.TextDim, "UNIDENTIFIED");
      Text(DrawList, TextX, TextY + LineHeight + 4, Theme.TextBright, "Other fog files");
      Text(DrawList, TextX, TextY + LineHeight * 2 + 4, Theme.TextDim, "slots outside the save layout");
    else
      Text(DrawList, TextX, TextY, Theme.TextDim, (CardIndex == 1 and "1  " or "") .. "CHARACTER");
      if CharacterKey == LoadedCharacter then Text(DrawList, TextX + Widgets.TextWidth((CardIndex == 1 and "1  " or "") .. "CHARACTER") + 8, TextY, Theme.Green, "• loaded") end;

      local Row = FindCharacterRow(Slots);
      local NameY = TextY + LineHeight + 4;
      if Row ~= nil then
        Widgets.Line(DrawList, TextX, NameY, TextX, NameY + LineHeight * 2, Theme.SelectedBorder);
        Text(DrawList, TextX + 6, NameY, Theme.TextBright, "Lv. " .. tostring(Row.arisen.level));
        Text(DrawList, TextX + 6, NameY + LineHeight, Theme.Text, Row.arisen.name);
        if Row.pawn ~= nil and Row.pawn.name ~= nil then
          Widgets.Line(DrawList, TextX + HalfWidth, NameY, TextX + HalfWidth, NameY + LineHeight * 2, Theme.Green);
          Text(DrawList, TextX + HalfWidth + 6, NameY, Theme.TextBright, "Lv. " .. tostring(Row.pawn.level));
          Text(DrawList, TextX + HalfWidth + 6, NameY + LineHeight, Theme.TextDim, Row.pawn.name .. " (pawn)");
        end
      else
        Text(DrawList, TextX, NameY, Theme.TextBright, "Character " .. (CharacterKey + 1));
        Text(DrawList, TextX, NameY + LineHeight, Theme.TextDim, "names appear after opening the load menu");
    end
  end

    local Newest, FooterY = NewestEntryOf(Slots), Y + CardHeight - LineHeight - 8;
    Widgets.Line(DrawList, TextX, FooterY - 5, CardX + CardWidth - 12, FooterY - 5, Theme.Border);
    Text(DrawList, TextX, FooterY, Theme.TextDim, "Latest fog");
    TextRight(DrawList, CardX + CardWidth - 12, FooterY, Theme.Text,
      Newest ~= nil and (FormatPlayTime(Newest.play) .. (Newest.saved ~= nil and ("  ·  " .. Newest.saved:sub(1, 10)) or "")) or "not indexed yet");    Widgets.PopClip(DrawList);
  end

  return CardHeight;
end

--- @brief Draws the Saves column 
--- @details Draws one card per save of the selected character, and the refresh button
local function DrawSaves(DrawList, Slots, X, Y, Width, Height, LineHeight)
  local Selector, LoadedSlot = InstanceState.Selector, InstanceState.CurrentSlot;
  Rect(DrawList, X, Y, Width, Height, Theme.Panel, Theme.Border);
  Text(DrawList, X + Padding, Y + 8, Theme.Accent, "2");
  Text(DrawList, X + Padding + 14, Y + 8, Theme.TextBright, "Saves - " .. CharacterName(Selector.CharacterKey, Slots));
  TextRight(DrawList, X + Width - Padding, Y + 8, Theme.TextDim, #Slots .. " saves");

  local NewestSlot, NewestPlay = nil, -1;
  for _, Slot in ipairs(Slots) do
    local Entries = KnownEntries(Slot);
    if Entries[#Entries] ~= nil and (Entries[#Entries].play or 0) > NewestPlay then NewestSlot, NewestPlay = Slot, Entries[#Entries].play or 0 end;
  end

  local ItemY, ItemHeight = Y + LineHeight + 20, LineHeight * 3 + 16;
  for _, Slot in ipairs(Slots) do
    local ItemX, ItemWidth = X + Padding, Width - Padding * 2;
    local bClicked, bHovered = Widgets.HitArea("##save" .. Slot, ItemX, ItemY, ItemWidth, ItemHeight);
    if bClicked == true then Selector.Slot = Slot end;

    local bSelected = Selector.Slot == Slot;
    Rect(DrawList, ItemX, ItemY, ItemWidth, ItemHeight, bSelected == true and Theme.Selected or (bHovered == true and Theme.CardHover or Theme.Card),
      bSelected == true and Theme.SelectedBorder or nil);
    Widgets.PushClip(DrawList, ItemX, ItemY, ItemWidth, ItemHeight);

    local _CharacterKey, SaveType = DescribeSlot(Slot);
    local Entries, MenuRow, CopyBackups = KnownEntries(Slot), LoadMenu.GetRow(SignedSlot(Slot)), Backups.GetCopyBackups(Slot);
    local Newest = Entries[#Entries];
    Text(DrawList, ItemX + 10, ItemY + 6, Theme.TextBright, SaveType);
    if Slot == LoadedSlot then TextRight(DrawList, ItemX + ItemWidth - 10, ItemY + 6, Theme.Green, "• loaded")
    elseif Slot == NewestSlot then TextRight(DrawList, ItemX + ItemWidth - 10, ItemY + 6, Theme.TextDim, "most recent") end;

    local Day = MenuRow ~= nil and MenuRow.day ~= nil and (" · day " .. tostring(MenuRow.day)) or "";
    Text(DrawList, ItemX + 10, ItemY + 8 + LineHeight, Theme.Text, "Play time " .. (Newest ~= nil and FormatPlayTime(Newest.play) or "?") .. Day);
    local BackupText = #CopyBackups > 0 and string.format(" · %d backup%s", #CopyBackups, #CopyBackups == 1 and "" or "s") or "";
    Text(DrawList, ItemX + 10, ItemY + 10 + LineHeight * 2, Theme.TextDim,
      (Newest ~= nil and tostring(Newest.saved or "date unknown"):sub(1, 16) or "not indexed yet") .. " · " .. #Entries .. " snapshots" .. BackupText);
    Widgets.PopClip(DrawList);
    ItemY = ItemY + ItemHeight + 6;
  end

  if Widgets.Button(DrawList, "##refresh", X + Padding, Y + Height - LineHeight - 22, Width - Padding * 2, LineHeight + 12, "Refresh") == true then
    Backups.GetAllFogFiles(true);
    Selector.RowsBySlot = {};
  end
end

--- @brief Rows of the fog data list, 
--- @details drawn inside its child window, into the child's draw list.
local function DrawFogRows(VisibleRows, Columns, ListWidth, LineHeight)
  local Selector = InstanceState.Selector;
  local ListDrawList, RowHeight = imgui.get_window_draw_list(), LineHeight + 14;
  local SelectedFile = Selector.FileBySlot[Selector.Slot];
  for RowIndex, Row in ipairs(VisibleRows) do
    local Origin = imgui.get_cursor_screen_pos();
    local bClicked = imgui.invisible_button("##row" .. RowIndex, Vector2f.new(ListWidth - 14, RowHeight)) == true;
    local bHovered = imgui.is_item_hovered() == true;
    if bClicked == true then Selector.FileBySlot[Selector.Slot], SelectedFile = Row.file, Row.file end;

    local bSelected = Row.file == SelectedFile;
    if bSelected == true or bHovered == true then
      Rect(ListDrawList, Origin.x, Origin.y, ListWidth - 14, RowHeight, bSelected == true and Theme.RowSelected or Theme.RowHover, nil, 0.0);
      if bSelected == true then Rect(ListDrawList, Origin.x, Origin.y, 3, RowHeight, Theme.SelectedBorder, nil, 0.0) end;
    end

    local TextY = Origin.y + 7;
    Text(ListDrawList, Origin.x + Columns.Name, TextY, bSelected == true and Theme.TextBright or Theme.Text, Row.name);
    if Row.Note ~= nil then Text(ListDrawList, Origin.x + Columns.Name + Widgets.TextWidth(Row.name) + 6, TextY, Theme.TextDim, Row.Note) end;
    Text(ListDrawList, Origin.x + Columns.Play, TextY, Theme.Text, Row.PlayText);
    Text(ListDrawList, Origin.x + Columns.Saved, TextY, Theme.Text, Row.Saved:sub(1, 16));

    local Fraction = OverworldFraction(Row.Revealed);
    if Fraction ~= nil then
      Widgets.Bar(ListDrawList, Origin.x + Columns.Overworld, TextY + LineHeight / 2 - 2, ListWidth * 0.06, 5, Fraction);
      Text(ListDrawList, Origin.x + Columns.Overworld + ListWidth * 0.06 + 6, TextY, Theme.Text, string.format("%.1f%%", 100 * Fraction));
    end

    local Badge = Row.Status ~= nil and StatusBadges[Row.Status] or nil;
    if Badge ~= nil then Widgets.Badge(ListDrawList, Origin.x + Columns.Status, TextY, LineHeight, Theme[Badge[2]], Badge[1]) end;
    Widgets.Line(ListDrawList, Origin.x, Origin.y + RowHeight, Origin.x + ListWidth - 14, Origin.y + RowHeight, Theme.Border);
  end
end

--- @brief Draws the Fog data column 
--- @details Drwas the filters, column headers and the scrollable list of snapshots and backups
local function DrawFogData(DrawList, Rows, Title, X, Y, Width, Height, LineHeight)
  local Selector = InstanceState.Selector;
  Rect(DrawList, X, Y, Width, Height, Theme.Panel, Theme.Border);
  Text(DrawList, X + Padding, Y + 8, Theme.Accent, "3");
  Text(DrawList, X + Padding + 14, Y + 8, Theme.TextBright, Title);
  TextRight(DrawList, X + Width - Padding, Y + 8, Theme.TextDim, "newest first");

  -- Filters (ImGui checkboxes placed on the panel)
  imgui.set_cursor_screen_pos(Vector2f.new(X + Padding, Y + LineHeight + 16));
  local bChanged, bValue = imgui.checkbox("Snapshots", Selector.bShowSnapshots ~= false);
  if bChanged == true then Selector.bShowSnapshots = bValue end;
  imgui.same_line();
  bChanged, bValue = imgui.checkbox("Backups", Selector.bShowBackups ~= false);
  if bChanged == true then Selector.bShowBackups = bValue end;
  imgui.same_line();
  bChanged, bValue = imgui.checkbox("Hide newer than loaded save", Selector.bHideNewer == true);
  if bChanged == true then Selector.bHideNewer = bValue end;

  local ListX, ListWidth = X + Padding, Width - Padding * 2;
  local Columns = { Name = 8, Play = ListWidth * 0.30, Saved = ListWidth * 0.42, Overworld = ListWidth * 0.60, Status = ListWidth * 0.75 };
  local HeaderY = Y + LineHeight * 2 + 30;
  for _, Header in ipairs({ { "Name", "Fog data" }, { "Play", "Play time" }, { "Saved", "Saved" }, { "Overworld", "Overworld" }, { "Status", "Status" } }) do
    Text(DrawList, ListX + Columns[Header[1]], HeaderY, Theme.TextDim, Header[2]);
  end
  Widgets.Line(DrawList, ListX, HeaderY + LineHeight + 4, ListX + ListWidth, HeaderY + LineHeight + 4, Theme.Border);

  -- The list scrolls in a child window (rows draw into the child's own draw list)
  local ListY = HeaderY + LineHeight + 8;
  local ListHeight = Y + Height - Padding - ListY;
  local VisibleRows = FilterRows(Rows);
  if #VisibleRows == 0 then Text(DrawList, ListX + 8, ListY + 8, Theme.TextDim, "No fog data with these filters."); return end;

  imgui.set_cursor_screen_pos(Vector2f.new(ListX, ListY));
  imgui.begin_child_window(Vector2f.new(ListWidth, ListHeight), false, 0);
  local bSucceeded, ErrorMessage = pcall(DrawFogRows, VisibleRows, Columns, ListWidth, LineHeight);
  if bSucceeded == false then imgui.text("list error: " .. tostring(ErrorMessage)) end; 

  imgui.end_child_window();
end

--- @brief Draw the Details column 
--- @details Draw preview, legend, facts about the selected fog data, the load and close buttons
local function DrawDetails(DrawList, Row, CharacterText, SaveText, X, Y, Width, Height, LineHeight)
  local Selector = InstanceState.Selector;
  Rect(DrawList, X, Y, Width, Height, Theme.Panel, Theme.Border);
  Text(DrawList, X + Padding, Y + 8, Theme.TextBright, "Fog details");
  if Row == nil then Text(DrawList, X + Padding, Y + LineHeight + 20, Theme.TextDim, "Select fog data."); return end;
  TextRight(DrawList, X + Width - Padding, Y + 8, Theme.TextDim, Row.name);

  -- Preview, framed, legend and orientation switch
  local InnerX, InnerWidth = X + Padding, Width - Padding * 2;
  local PreviewWidth, PreviewHeight = Preview.Measure(Row, InnerWidth - 16);
  local FrameY = Y + LineHeight + 20;
  Rect(DrawList, InnerX, FrameY, InnerWidth, PreviewHeight + 16, Widgets.Color(0x17191C), Theme.Border);
  Preview.Draw(DrawList, Row, InnerX + (InnerWidth - PreviewWidth) / 2, FrameY + 8, InnerWidth - 16);

  local Colors, LegendY, LegendX = Definitions.PreviewColors, FrameY + PreviewHeight + 24, InnerX;
  for _, Legend in ipairs({ { "Both", "both" }, { "OnlySelected", "only selected" }, { "OnlyCurrent", "only current" } }) do
    Rect(DrawList, LegendX, LegendY + 3, LineHeight - 6, LineHeight - 6, Colors[Legend[1]], nil, 1.0);
    Text(DrawList, LegendX + LineHeight, LegendY, Theme.TextDim, Legend[2]);
    LegendX = LegendX + LineHeight + Widgets.TextWidth(Legend[2]) + 12;
  end
  imgui.set_cursor_screen_pos(Vector2f.new(InnerX, LegendY + LineHeight + 6));
  
  local bFlipChanged, bFlip = imgui.checkbox("Flip vertically", InstanceSettings.bPreviewFlipVertical);
  if bFlipChanged == true then InstanceSettings.bPreviewFlipVertical = bFlip; State.SaveSettings() end;

  -- Progress facts
  local Revealed, Fraction, FactY = Row.Revealed, OverworldFraction(Row.Revealed), LegendY + LineHeight * 2 + 20;
  local ProgressFacts = {
    { "Character", CharacterText }, { "Save", SaveText },
    { "Play time", Row.PlayText .. (InstanceState.PlayTimeAtLoad ~= nil and ("  (loaded save " .. FormatPlayTime(InstanceState.PlayTimeAtLoad) .. ")") or "") },
    { "Saved", Row.Saved },
  };
  if type(Revealed) == "table" then
    ProgressFacts[#ProgressFacts + 1] = { "Overworld", string.format("%d cells (%.1f%%)", Revealed.overworld or 0, 100 * (Fraction or 0)) };
    ProgressFacts[#ProgressFacts + 1] = { "Caves/interiors", string.format("%d maps, %d cells", Revealed.local_maps or 0, Revealed.local_cells or 0) };
  end
  for _, Fact in ipairs(ProgressFacts) do
    Text(DrawList, InnerX, FactY, Theme.TextDim, Fact[1]);
    Text(DrawList, InnerX + InnerWidth * 0.36, FactY, Theme.Text, tostring(Fact[2]));
    FactY = FactY + LineHeight + 4;
  end

  -- Warning, load and close
  local ButtonHeight = LineHeight + 16;
  local CloseY = Y + Height - Padding - ButtonHeight;
  local LoadY = CloseY - Gap - ButtonHeight;
  local WarningLines = { "Loading replaces the current NG+ fog.", "A backup of the current fog is made", "first, so a load can be undone." };
  local WarningY = LoadY - Gap - (LineHeight * #WarningLines + 16);
  Rect(DrawList, InnerX, WarningY, InnerWidth, LineHeight * #WarningLines + 16, Theme.WarningFill, Theme.WarningBorder);
  for LineIndex, WarningLine in ipairs(WarningLines) do Text(DrawList, InnerX + 8, WarningY + 8 + (LineIndex - 1) * LineHeight, Theme.Amber, WarningLine) end;

  if Widgets.Button(DrawList, "##load", InnerX, LoadY, InnerWidth, ButtonHeight, "LOAD INTO NG+ FOG", true) == true then Backups.LoadFogFile(Row) end;
  if Widgets.Button(DrawList, "##close", InnerX, CloseY, InnerWidth, ButtonHeight, "CLOSE") == true then Selector.bWindowOpen = false end;
end

--- @brief Status bar along the bottom
local function DrawStatusBar(DrawList, Characters, X, Y)
  local SnapshotCount, BackupCount, CharacterCount = 0, 0, 0;
  for CharacterKey, Slots in pairs(Characters) do
    CharacterCount = CharacterCount + (CharacterKey == UnrecognisedCharacter and 0 or 1);
    for _, Slot in ipairs(Slots) do SnapshotCount, BackupCount = SnapshotCount + #KnownEntries(Slot), BackupCount + #Backups.GetCopyBackups(Slot) end;
  end

  local LoadedSlot = InstanceState.CurrentSlot;
  local LoadedText = "no save loaded";
  if LoadedSlot ~= nil then
    local CharacterKey, SaveType = DescribeSlot(LoadedSlot);
    LoadedText = CharacterName(CharacterKey, Characters[CharacterKey] or {}) .. " · " .. SaveType .. ", play time " .. FormatPlayTime(InstanceState.PlayTimeAtLoad);
  end

  local Line = string.format("Loaded: %s     Fog files: %d characters, %d snapshots, %d backups", LoadedText, CharacterCount, SnapshotCount, BackupCount);
  Text(DrawList, X, Y, Theme.TextDim, Line);
  if InstanceState.LoadedFogNote ~= nil then Text(DrawList, X + Widgets.TextWidth(Line) + 24, Y, Theme.Accent, InstanceState.LoadedFogNote) end;
end

--
-- Window

--- @brief Logs once per session which drawing functions exist, and the preview orientation in use
local function RecordCapabilities(Capabilities)
  if InstanceState.Selector.bCapabilitiesRecorded == true then return end;

  InstanceState.Selector.bCapabilitiesRecorded = true;
  Capabilities.flip_vertical = InstanceSettings.bPreviewFlipVertical;
  ProbeLog.RecordEvent("preview_capabilities", Capabilities);
end

--- @brief Draw window contents
--- @details Calls DrawSaves, DrawDetails, DrawFogData, DrawStatusBar
local function DrawWindowContents()
  local Selector, Characters = InstanceState.Selector, GroupSlotsByCharacter();
  IndexOneSlot(Characters);
  local DrawList, LineHeight = imgui.get_window_draw_list(), imgui.calc_text_size("Ag").y;
  local Origin, WindowPos, WindowSize = imgui.get_cursor_screen_pos(), imgui.get_window_pos(), imgui.get_window_size();
  local X, Y = Origin.x, Origin.y;
  local Width, Height = WindowPos.x + WindowSize.x - Padding - X, WindowPos.y + WindowSize.y - Padding - Y;

  local CharacterKeys = {};
  for _, CharacterKey in ipairs(CharacterOrder) do if Characters[CharacterKey] ~= nil then CharacterKeys[#CharacterKeys + 1] = CharacterKey end end;
  if #CharacterKeys == 0 then Text(DrawList, X, Y, Theme.TextDim, "No NG+ fog files yet: they are written at each game save."); return end;

  -- Character selection
  local LoadedSlot = InstanceState.CurrentSlot;
  Selector.CharacterKey = ResolveSelection(CharacterKeys, Selector.CharacterKey, LoadedSlot ~= nil and DescribeSlot(LoadedSlot) or nil);
  local CardsHeight = DrawCharacterCards(DrawList, Characters, CharacterKeys, X, Y, Width, LineHeight);
  local Slots = Characters[Selector.CharacterKey];
  Selector.Slot = ResolveSelection(Slots, Selector.Slot, LoadedSlot);

  local Rows = GetFogDataRows(Selector.Slot);
  local VisibleRows, SelectedRow = FilterRows(Rows), nil;
  for _, Row in ipairs(VisibleRows) do if Row.file == Selector.FileBySlot[Selector.Slot] then SelectedRow = Row end end;

  SelectedRow = SelectedRow or VisibleRows[1];
  Selector.FileBySlot[Selector.Slot] = SelectedRow ~= nil and SelectedRow.file or nil;

  -- Columns
  local StatusHeight = LineHeight + 8;
  local ColumnsY = Y + CardsHeight + Gap;
  local ColumnsHeight = Y + Height - StatusHeight - Gap - ColumnsY;
  local SavesWidth, DetailsWidth = Width * 0.22, Width * 0.28;
  local FogWidth = Width - SavesWidth - DetailsWidth - Gap * 2;

  -- Character slot text
  local CharacterText, SaveText = CharacterName(Selector.CharacterKey, Slots), select(2, DescribeSlot(Selector.Slot));
  SaveText = SaveText .. " (slot " .. tostring(SignedSlot(Selector.Slot)) .. ")";

  DrawSaves(DrawList, Slots, X, ColumnsY, SavesWidth, ColumnsHeight, LineHeight);
  DrawDetails(DrawList, SelectedRow, CharacterText, SaveText, X + SavesWidth + FogWidth + Gap * 2, ColumnsY, DetailsWidth, ColumnsHeight, LineHeight);
  DrawFogData(DrawList, Rows, "Fog data - " .. CharacterText .. " · " .. select(2, DescribeSlot(Selector.Slot)), X + SavesWidth + Gap, ColumnsY, FogWidth, ColumnsHeight, LineHeight);
  DrawStatusBar(DrawList, Characters, X, Y + Height - StatusHeight + 4);
end

--- @brief Draws the selector window
--- @details Draws the selector window while it is open and REFramework's UI is shown. 
local function DrawWindow()
  local Selector = InstanceState.Selector;
  if Selector.bWindowOpen ~= true then return end;

  local bCallSucceeded, bDrawingUi = pcall(function() return reframework:is_drawing_ui() end);
  if bCallSucceeded == true and bDrawingUi == false then return end;

  local Capabilities, bComplete = Widgets.GetCapabilities();
  RecordCapabilities(Capabilities);
  if bComplete == false then Selector.bWindowOpen = false; InstanceState.LoadedFogNote = "the selector window needs a newer REFramework (see Diagnostics > Verification)"; return end;

  local DisplaySize = imgui.get_display_size();
  imgui.set_next_window_size(Vector2f.new(math.min(1400, DisplaySize.x * 0.9), math.min(900, DisplaySize.y * 0.85)), FirstUseEver);
  imgui.set_next_window_pos(Vector2f.new(DisplaySize.x / 2, DisplaySize.y / 2), FirstUseEver, Vector2f.new(0.5, 0.5));
  local bKeepOpen = imgui.begin_window(WindowTitle, true, NoCollapseFlag);
  if bKeepOpen == false then Selector.bWindowOpen = false end;

  local bSucceeded, ErrorMessage = pcall(DrawWindowContents);
  if bSucceeded == false then imgui.text("selector error: " .. tostring(ErrorMessage)) end;
  imgui.end_window();
end

local function Install() re.on_frame(DrawWindow) end;

local function Open() InstanceState.Selector.bWindowOpen = true end;

return {
  Install = Install,
  Open    = Open,

  -- Exposed for tests
  DescribeSlot   = DescribeSlot,
  GetFogDataRows = GetFogDataRows,
  FilterRows     = FilterRows,
};
