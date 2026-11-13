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
local Widgets     = require("NGPlusFog.Widgets");

local InstanceSettings, InstanceState = State.Settings, State.Instance;
local OverworldMaskKey <const>      = Definitions.OverworldMaskKey;
local OverworldColumns <const>      = Definitions.OverworldColumns;
local BlockCells <const>            = Definitions.PreviewBlockCells;
local PreviewRebuildSeconds <const> = Definitions.PreviewRebuildSeconds;
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
--- @return built runs of merged blocks. 
local function GetPreviewRuns(FogFile)
  local Preview = InstanceState.Preview;
  local SettingsKey = FogFile.file .. "|" .. BlockCells .. "|" .. tostring(InstanceSettings.bPreviewFlipVertical);
  local bSettingsChanged = Preview.SettingsKey ~= SettingsKey;
  local bExplorationChanged = Preview.Generation ~= InstanceState.ExplorationGeneration and Core.Now() - (Preview.BuildTime or -math.huge) >= PreviewRebuildSeconds;
  if bSettingsChanged == false and bExplorationChanged == false then return Preview.Built end;

  local CurrentMask = InstanceState.PrivateMasks[OverworldMaskKey];
  local CurrentHex = CurrentMask ~= nil and Masks.HexOf(CurrentMask) or "";
  Preview.Built = BuildRuns(GetSelectedHex(FogFile), CurrentHex, BlockCells, InstanceSettings.bPreviewFlipVertical);
  Preview.SettingsKey, Preview.Generation, Preview.BuildTime = SettingsKey, InstanceState.ExplorationGeneration, Core.Now();
  return Preview.Built;
end

--
-- Drawing

--- @brief Size in pixels of the preview drawn at most MaxWidth wide
local function MeasurePreview(FogFile, MaxWidth)
  local Built = GetPreviewRuns(FogFile);
  local PixelsPerBlock = math.max(1, math.floor(MaxWidth / math.max(1, Built.BlockColumns)));
  return Built.BlockColumns * PixelsPerBlock, Built.BlockRows * PixelsPerBlock, PixelsPerBlock;
end

--- @brief Draws the preview of a fog file (a selector row) against the current NG+ fog at X, Y; 
--- @return width and height
local function DrawPreview(DrawList, FogFile, X, Y, MaxWidth)
  local Built = GetPreviewRuns(FogFile);
  local Width, Height, PixelsPerBlock = MeasurePreview(FogFile, MaxWidth);
  local Colors = Definitions.PreviewColors;

  Widgets.Rect(DrawList, X, Y, Width, Height, Colors.Fog, nil, 0.0);
  for _, Run in ipairs(Built.Runs) do
    local RunX, RunY = X + Run[2] * PixelsPerBlock, Y + Run[1] * PixelsPerBlock;
    DrawList:add_rect_filled(Vector2f.new(RunX, RunY), Vector2f.new(RunX + Run[3] * PixelsPerBlock, RunY + PixelsPerBlock), Colors[CodeNames[Run[4]]], 0.0, 0);
  end

  return Width, Height;
end

return {
  Draw    = DrawPreview,
  Measure = MeasurePreview,

  -- Exposed for tests
  BuildRuns = BuildRuns,
};
