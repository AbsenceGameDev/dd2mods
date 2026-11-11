--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Preview
  Overworld fog preview for the fog data selector. 
  
  Block codes. Selected fog data compared with the current NG+ fog:
    - Blue: revealed in both. 
    - Green: only in the selected data (a load reveals it). 
    - Amber: only in the current fog (a load hides it).
  
  - Overlay mode draws rectangles with draw.filled_rect over an area reserved in the panel; 
  - Text mode prints one character per block.

  @note Equal blocks along a row are merged into one block; merged blocks are cached and rebuilt only data goes stale (updated selection, updated settings, etc).
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Core        = require("NGPlusFog.Core");
local Masks       = require("NGPlusFog.Masks");
local Persistence = require("NGPlusFog.Persistence");
local ProbeLog    = require("NGPlusFog.ProbeLog");

local InstanceSettings, InstanceState = State.Settings, State.Instance;
local OverworldMaskKey <const>      = Definitions.OverworldMaskKey;
local OverworldColumns <const>      = Definitions.OverworldColumns;
local PixelsPerBlock <const>        = Definitions.PreviewPixelsPerBlock;
local PreviewRebuildSeconds <const> = Definitions.PreviewRebuildSeconds;
local PreviewModes <const>          = { "Overlay", "Text" };
-- Block code = 2 * revealed in the selected data + revealed in the current fog
local CodeNames <const>             = { [0] = "Fog", [1] = "OnlyCurrent", [2] = "OnlySelected", [3] = "Both" };

--
-- Bitmaps

--- @brief Hex bitmap to Words.
local function DecodeHexWords(Hex)
  local Words = {};
  for WordIndex = 0, #Hex // 8 - 1 do Words[WordIndex] = tonumber(Hex:sub(WordIndex * 8 + 1, WordIndex * 8 + 8), 16) or 0 end;
  return Words;
end

--- @brief Checks is block has been revealed by player.
--- @return true if any cell of a block is revealed. 
--- @note Blocks are 4 or 8 cells wide. Thus a block row never crosses a 32-bit word.
local function IsBlockRevealed(Words, BlockColumn, BlockRow, BlockCells)
  local FirstColumn, ColumnMask = BlockColumn * BlockCells, (1 << BlockCells) - 1;
  for Row = BlockRow * BlockCells, BlockRow * BlockCells + BlockCells - 1 do
    local BitIndex = Row * OverworldColumns + FirstColumn;
    if ((Words[BitIndex >> 5] or 0) >> (BitIndex & 31)) & ColumnMask ~= 0 then return true end;
  end

  return false;
end

--- @brief Block codes of both bitmaps as merged blocks. 
--- { BlockRow, FirstBlockColumn, Length, Code } for every merged block that is not fog
local function BuildRuns(SelectedHex, CurrentHex, BlockCells, bFlipVertical)
  local SelectedWords, CurrentWords = DecodeHexWords(SelectedHex), DecodeHexWords(CurrentHex);
  local CellRows = math.max(#SelectedHex, #CurrentHex) * 4 // OverworldColumns;
  local BlockColumns, BlockRows = OverworldColumns // BlockCells, (CellRows + BlockCells - 1) // BlockCells;

  local Runs = {};
  for BlockRow = 0, BlockRows - 1 do
    local DrawnRow = bFlipVertical == true and (BlockRows - 1 - BlockRow) or BlockRow;
    local RunStart, RunCode = 0, nil;
    for BlockColumn = 0, BlockColumns do
      local Code = -1; -- past the last column: closes the open run
      if BlockColumn < BlockColumns then
        Code = (IsBlockRevealed(SelectedWords, BlockColumn, BlockRow, BlockCells) == true and 2 or 0)
             + (IsBlockRevealed(CurrentWords, BlockColumn, BlockRow, BlockCells) == true and 1 or 0);
      end
      if Code ~= RunCode then
        if RunCode ~= nil and RunCode ~= 0 then Runs[#Runs + 1] = { DrawnRow, RunStart, BlockColumn - RunStart, RunCode } end;
        RunStart, RunCode = BlockColumn, Code;
      end
    end
  end

  return { Runs = Runs, BlockColumns = BlockColumns, BlockRows = BlockRows };
end

--- @brief Overworld hex of the selected fog file. Read once per file!
local function GetSelectedHex(FogFile)
  local Preview = InstanceState.Preview;
  if Preview.SelectedFile ~= FogFile.file then
    local FogData = Persistence.ReadValidFile(FogFile.file);
    Preview.SelectedFile, Preview.SelectedHex = FogFile.file, FogData ~= nil and FogData.masks[OverworldMaskKey] or "";
  end

  return Preview.SelectedHex or "";
end

--- @brief The cached preview of teh fog data. 
--- @note rebuilt when data goes stale (updated selection, updated settings, etc).
local function GetPreviewRuns(FogFile, BlockCells)
  local Preview = InstanceState.Preview;
  local SettingsKey = FogFile.file .. "|" .. BlockCells .. "|" .. tostring(InstanceSettings.bPreviewFlipVertical);
  local bSettingsChanged = Preview.SettingsKey ~= SettingsKey;
  local bExplorationChanged = Preview.Generation ~= InstanceState.ExplorationGeneration and Core.Now() - (Preview.BuildTime or -math.huge) >= PreviewRebuildSeconds;
  if bSettingsChanged == false and bExplorationChanged == false then return Preview.Built end;

  local CurrentMask = InstanceState.PrivateMasks[OverworldMaskKey];
  local CurrentHex = CurrentMask ~= nil and Masks.HexOf(CurrentMask) or "";
  Preview.Built = BuildRuns(GetSelectedHex(FogFile), CurrentHex, BlockCells, InstanceSettings.bPreviewFlipVertical);
  Preview.SettingsKey, Preview.Generation, Preview.BuildTime, Preview.TextLines = SettingsKey, InstanceState.ExplorationGeneration, Core.Now(), nil;
  return Preview.Built;
end

--
-- Drawing

--- @brief Drawing functions for overlay mode. 
--- @note not tested
local function GetOverlayCapabilities()
  local Capabilities = {
    draw_filled_rect = type(draw) == "table" and type(draw.filled_rect) == "function",
    get_cursor_screen_pos = type(imgui.get_cursor_screen_pos) == "function",
    invisible_button = type(imgui.invisible_button) == "function",
  };
  return Capabilities, Capabilities.draw_filled_rect and Capabilities.get_cursor_screen_pos and Capabilities.invisible_button;
end

--- @brief Logs once per session which drawing functions exist
local function RecordCapabilities(Capabilities)
  if InstanceState.Preview.bCapabilitiesRecorded == true then return end;

  InstanceState.Preview.bCapabilitiesRecorded = true;
  Capabilities.mode, Capabilities.flip_vertical = InstanceSettings.PreviewMode, InstanceSettings.bPreviewFlipVertical;
  ProbeLog.RecordEvent("preview_capabilities", Capabilities);
end

local function DrawOverlay(Built)
  local Width, Height = Built.BlockColumns * PixelsPerBlock, Built.BlockRows * PixelsPerBlock;
  local Origin = imgui.get_cursor_screen_pos();
  imgui.invisible_button("##fogpreview", Vector2f.new(Width, Height));

  local Colors = Definitions.PreviewColors;
  draw.filled_rect(Origin.x, Origin.y, Width, Height, Colors.Fog);
  for _, Run in ipairs(Built.Runs) do
    draw.filled_rect(Origin.x + Run[2] * PixelsPerBlock, Origin.y + Run[1] * PixelsPerBlock, Run[3] * PixelsPerBlock, PixelsPerBlock, Colors[CodeNames[Run[4]]]);
  end
end

local function DrawText(Built)
  local Preview = InstanceState.Preview;
  if Preview.TextLines == nil then
    local Characters, Grid = Definitions.PreviewCharacters, {};
    for BlockRow = 0, Built.BlockRows - 1 do Grid[BlockRow] = string.rep(Characters.Fog, Built.BlockColumns) end;
    for _, Run in ipairs(Built.Runs) do
      local Line = Grid[Run[1]];
      Grid[Run[1]] = Line:sub(1, Run[2]) .. string.rep(Characters[CodeNames[Run[4]]], Run[3]) .. Line:sub(Run[2] + Run[3] + 1);
    end
    Preview.TextLines = Grid;
  end

  for BlockRow = 0, Built.BlockRows - 1 do imgui.text(Preview.TextLines[BlockRow]) end;
end

--- @brief Preview of a fog file (a selector row) against the current NG+ fog, with its mode and orientation settings
local function DrawPreview(FogFile)
  local Capabilities, bCanDrawOverlay = GetOverlayCapabilities();
  RecordCapabilities(Capabilities);

  local ModeIndex = InstanceSettings.PreviewMode == "Text" and 2 or 1;
  local bModeChanged, NewModeIndex = imgui.combo("Preview mode", ModeIndex, PreviewModes);
  if bModeChanged == true then InstanceSettings.PreviewMode = PreviewModes[NewModeIndex]; State.SaveSettings() end;
  imgui.same_line();
  local bFlipChanged, bFlip = imgui.checkbox("Flip vertically", InstanceSettings.bPreviewFlipVertical);
  if bFlipChanged == true then InstanceSettings.bPreviewFlipVertical = bFlip; State.SaveSettings() end;

  local bOverlay = InstanceSettings.PreviewMode ~= "Text" and bCanDrawOverlay == true;
  if InstanceSettings.PreviewMode ~= "Text" and bCanDrawOverlay == false then imgui.text("Overlay drawing is not available in this REFramework version: showing text.") end;
  local Characters = Definitions.PreviewCharacters;
  imgui.text(bOverlay == true and "Blue: revealed in both · Green: only in the selected data · Amber: only in the current fog (a load hides it)"
    or string.format("%s both · %s only selected · %s only current (a load hides it) · %s fog", Characters.Both, Characters.OnlySelected, Characters.OnlyCurrent, Characters.Fog));

  local Built = GetPreviewRuns(FogFile, bOverlay == true and Definitions.PreviewBlockCells or Definitions.PreviewTextBlockCells);
  if bOverlay == true then DrawOverlay(Built) else DrawText(Built) end;
end

return {
  Draw = DrawPreview,

  -- Exposed for tests
  BuildRuns = BuildRuns,
};
