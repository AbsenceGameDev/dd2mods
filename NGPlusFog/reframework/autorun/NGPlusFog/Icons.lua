--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Icons
  Icons in fog on the full map. Icons keep store their true position at all times, so zoom and pan behave normally.
   - Drawing pass: an icon whose surroundings are fogged is switched off (visibility and mouse hit-testing).
   - Cursor pass: for the duration of the game's cursor search, fogged icons are moved off the map, so the cursor cannot select them.
  The minimap hides fogged icons by itself (its code runs inside the scope with the private fog).
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Core        = require("NGPlusFog.Core");
local Masks       = require("NGPlusFog.Masks");

local InstanceSettings, InstanceState = State.Settings, State.Instance;;
local TryCall, AddressOf, GetField, HookThis = Core.TryCall, Core.AddressOf, Core.GetField, Core.HookThis;
local ArrayLength, Components, IsNgPlusFogShown, InstallHook = Core.ArrayLength, Core.Components, Core.IsNgPlusFogShown, Core.InstallHook;
local IsRevealed = Masks.IsRevealed;
local FullMapType <const>           = Definitions.FullMapType;
local IconListFields <const>        = Definitions.IconListFields;
local IconRevealRadiusCells <const> = Definitions.IconRevealRadiusCells;
local ParkedCoordinate <const>      = Definitions.ParkedCoordinate;
local CellKeyStride <const>         = Definitions.CellKeyStride;

--
-- Fog test

--- @brief Icons in fog are always hidden while fog is shown: the NG+ fog, or the save's own fog in real-progress mode
local function IsIconFogShown() return IsNgPlusFogShown() or (InstanceSettings.bShowRealMapProgress == true and InstanceState.bNgPlusSave == true) end;

local function ForEachIcon(FullMap, Visitor)
  for _, ListField in ipairs(IconListFields) do
    local IconList = GetField(FullMap, ListField);

    local Items, ItemCount = GetField(IconList, "_items"), GetField(IconList, "_size") or 0;
    for ItemIndex = 0, ItemCount - 1 do
      local Icon = TryCall(function() return Items:get_element(ItemIndex) end);
      if Icon ~= nil then Visitor(Icon) end;
    end
  end
end

local function IsNearRevealed(Mask, WorldX, WorldZ)
  if Mask == nil or Mask.CellSize == nil then return true end;
  for OffsetZ = -IconRevealRadiusCells, IconRevealRadiusCells do
    for OffsetX = -IconRevealRadiusCells, IconRevealRadiusCells do
      if IsRevealed(Mask, WorldX + OffsetX * Mask.CellSize, WorldZ + OffsetZ * Mask.CellSize) ~= false then return true end;
    end
  end
  return false
end

local function SetIconShown(Icon, bShown)
  pcall(function() Icon:call("set_IconVisible", bShown) end)

  for _, ReferenceField in ipairs({ "Icon", "IconSprite" }) do
    local Reference = GetField(Icon, ReferenceField);
    if Reference ~= nil then pcall(function() Reference:call("setHitVisible", bShown) end) end;
  end
end

--- @brief Read-only view of the game's own bitmap for 'real-progress' mode (not swapped in that mode), grid from the game's mask
local function GetRealProgressView(Entry)
  local View = InstanceState.RealProgressViews[Entry.Key] or { Key = "R" .. Entry.Key };
  View.Bits = GetField(Entry.Object, "MaskBit");
  View.WordCount = ArrayLength(View.Bits);
  View.BaseX, View.BaseZ = Components(GetField(Entry.Object, "BasePos"));
  View.CellsX, View.CellsZ = Components(GetField(Entry.Object, "MaskNum"));
  View.CellSize = GetField(Entry.Object, "Interval");
  InstanceState.RealProgressViews[Entry.Key] = View;

  local bViewDataInvalid = View.Bits == nil or View.CellSize == nil or View.CellsX == nil;
  if bViewDataInvalid == true then return nil end;

  return View;
end

--- @brief The mask the full map is showing (overworld or the current cave/interior), as NG+ fog or as real progress
local function GetShownMask(FullMap)
  local Address = AddressOf(GetField(FullMap, "MaskInfo"));
  local Entry = Address ~= nil and InstanceState.GameMasks[Address] or nil;
  if Entry ~= nil then InstanceState.FullMapMaskAddress = Address end;

  if InstanceSettings.bShowRealMapProgress == true then
    if Entry == nil then
      for _, GameEntry in pairs(InstanceState.GameMasks) 
        do if GameEntry.Key == Definitions.OverworldMaskKey then Entry = GameEntry end 
      end
    end

    return Entry ~= nil and GetRealProgressView(Entry) or nil
  end

  return Entry ~= nil and InstanceState.PrivateMasks[Entry.Key] or InstanceState.PrivateMasks.F
end

--- @brief Fog test by position, cached per 'Mask.CellSize' cells and cleared whenever exploration changes. 
local function IsFoggedAt(Mask, WorldX, WorldZ)
  local bMaskCellInvalid = Mask == nil or Mask.CellSize == nil or WorldX == nil or WorldX >= ParkedCoordinate;
  if bMaskCellInvalid == true then return false end
  
 local bIsMaskCacheStale  =  InstanceState.CellFogCacheGeneration ~= InstanceState.ExplorationGeneration;
  if bIsMaskCacheStale == true then
    InstanceState.CellFogCache, InstanceState.CellFogCacheGeneration = {}, InstanceState.ExplorationGeneration
  end

  local MaskCache = InstanceState.CellFogCache[Mask.Key] or {}
  InstanceState.CellFogCache[Mask.Key] = MaskCache
  local Column = math.floor((WorldX - Mask.BaseX) / Mask.CellSize)
  local Row = math.floor((WorldZ - Mask.BaseZ) / Mask.CellSize)
  local CellKey = Row * CellKeyStride + Column
  
  local bFogged = MaskCache[CellKey]
  if bFogged == nil then
    bFogged = IsNearRevealed(Mask, Mask.BaseX + (Column + 0.5) * Mask.CellSize, Mask.BaseZ + (Row + 0.5) * Mask.CellSize) == false
    MaskCache[CellKey] = bFogged
  end
  
  return bFogged
end

--- @brief Icons follow the fog of the map being shown only; cave icons stay hidden until found inside.
local function IsIconFogged(Mask, Icon)
  local Address = AddressOf(Icon)

  local bIsIconParked  = Address ~= nil and InstanceState.ParkedIconAddresses ~= nil and InstanceState.ParkedIconAddresses[Address] == true;
  if bIsIconParked then return true end
  
  local WorldX, _, WorldZ = Components(GetField(Icon, "Pos"))
  return WorldX ~= nil and IsFoggedAt(Mask, WorldX, WorldZ)
end

--
-- Drawing pass

--- @brief Runs after every full-map icon update 
local function ApplyIconFog(FullMap)
  if FullMap == nil then return end

  local bIconFog, ShownMask = IsIconFogShown(), GetShownMask(FullMap)
  ForEachIcon(FullMap, function(Icon)
    local Address = AddressOf(Icon)
    if Address == nil then return end

    local WorldX, _, WorldZ = Components(GetField(Icon, "Pos"))
    if WorldX == nil then return end

    local HiddenAt = InstanceState.HiddenIcons[Address];
    local bObjReusedByOtherIcon = HiddenAt ~= nil and (HiddenAt.WorldX ~= WorldX or HiddenAt.WorldZ ~= WorldZ);
    if bObjReusedByOtherIcon == true then
      InstanceState.HiddenIcons[Address], HiddenAt = nil, nil
    end

    local bShouldIconHide = bIconFog == true and IsFoggedAt(ShownMask, WorldX, WorldZ) == true;
    if bShouldIconHide == true then
      local bIsGameCountingIconAsHidden = TryCall(function() return Icon:call("get_IconVisible") end) == true;
      if bIsGameCountingIconAsHidden == true then
        SetIconShown(Icon, false); InstanceState.HiddenIcons[Address] = { WorldX = WorldX, WorldZ = WorldZ }
      end
    elseif HiddenAt ~= nil then
      SetIconShown(Icon, true); InstanceState.HiddenIcons[Address] = nil
    end
  end)
end

--
-- Cursor pass
-- Fogged icons are 'parked' off the map only while the cursor search runs, and restored in the same call.
-- @note Pinned per icon object for the duration of one cursor search: world position (Pos) and on-screen position (IconPos).
-- @note The cursor selects from the on-screen position

local ParkedScreenPosition <const> = Vector3f.new(ParkedCoordinate, ParkedCoordinate, 0)

local function RestoreParkedIcons()
  for _, Parked in ipairs(InstanceState.ParkedIcons or {}) do
    pcall(function() Parked.Icon:set_field("Pos", Parked.WorldPosition) end)
    if Parked.ScreenPosition ~= nil then pcall(function() Parked.Icon:call("set_IconPos", Parked.ScreenPosition) end) end
  end

  InstanceState.ParkedIcons, InstanceState.ParkedIconAddresses = nil, nil
end

local function OnCursorSearchEnter(Args)
  InstanceState.CursorSearchDepth = InstanceState.CursorSearchDepth + 1
  if InstanceState.CursorSearchDepth > 1 or IsIconFogShown() == false then return end

  local FullMap, ParkedIcons, ParkedAddresses = HookThis(Args), {}, {}
  if FullMap ~= nil then
    local ShownMask = GetShownMask(FullMap)

    ForEachIcon(FullMap, function(Icon)
      local WorldX, WorldY, WorldZ = Components(GetField(Icon, "Pos"))
      local bIsNotFogged = WorldX == nil or IsFoggedAt(ShownMask, WorldX, WorldZ) == false;
      if bIsNotFogged == true then return end

      local ScreenX, ScreenY, ScreenZ = Components(TryCall(function() return Icon:call("get_IconPos") end))
      ParkedIcons[#ParkedIcons + 1] = {
        Icon = Icon,
        WorldPosition = Vector3f.new(WorldX, WorldY, WorldZ),
        ScreenPosition = ScreenX ~= nil and Vector3f.new(ScreenX, ScreenY, ScreenZ) or nil,
      }

      ParkedAddresses[AddressOf(Icon)] = true
      Icon:set_field("Pos", Vector3f.new(ParkedCoordinate, WorldY, ParkedCoordinate))
      if ScreenX ~= nil then pcall(function() Icon:call("set_IconPos", ParkedScreenPosition) end) end
    end)
  end
  InstanceState.ParkedIconAddresses, InstanceState.ParkedIcons = ParkedAddresses, ParkedIcons
end

local function OnCursorSearchLeave(ReturnValue)
  InstanceState.CursorSearchDepth = math.max(0, InstanceState.CursorSearchDepth - 1)
  if InstanceState.CursorSearchDepth > 0 then return ReturnValue end

  RestoreParkedIcons()
  local FullMap = InstanceState.CursorMap
  local bIsIconFogged = FullMap ~= nil and IsIconFogged(GetShownMask(FullMap), GetField(FullMap, "SelectedIcon")) == true;
  if bIsIconFogged then
    pcall(function() FullMap:set_field("SelectedIcon", nil) end)
  end

  return ReturnValue
end

--
-- Hooks
local function InstallHooks()
  for _, Signature in ipairs({ "setupMapIcon()", "updateMapIcon()", "updateIconPos()", "updateIconAnim()" }) do
    InstallHook(FullMapType, Signature, function(Args) InstanceState.IconUpdateMap = HookThis(Args) end, function(ReturnValue)
      local bSucceeded, ErrorMessage = pcall(ApplyIconFog, InstanceState.IconUpdateMap)
      if bSucceeded == false then InstanceState.IconError = tostring(ErrorMessage) end
      return ReturnValue
    end)
  end

  for _, Signature in ipairs({ "updateCursor(System.Boolean)", "updateCursorMouseKeyboard(System.Boolean)", "updateCursorTarget()" }) do
    InstallHook(FullMapType, Signature, function(Args) InstanceState.CursorMap = HookThis(Args); OnCursorSearchEnter(Args) end, OnCursorSearchLeave)
  end

  InstallHook(FullMapType, "setDetailName()", function(Args)
    if IsIconFogShown() == false then return end
    
    local FullMap = HookThis(Args)
    if FullMap ~= nil and IsIconFogged(GetShownMask(FullMap), GetField(FullMap, "SelectedIcon")) == true then return sdk.PreHookResult.SKIP_ORIGINAL end
  end, nil)
end

return {
  RestoreParkedIcons = RestoreParkedIcons,
  InstallHooks       = InstallHooks,
}
