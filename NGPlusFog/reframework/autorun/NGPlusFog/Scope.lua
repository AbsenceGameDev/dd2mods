--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Scope
  Scope in which the NG+ flag reads false and the game's own mask objects hold the private fog mask arrays.
  @note only open while map code runs (full map, minimap, fog painters) and during the mod's own mask calls.
  @todo test to ensure game does not lose ng+ features
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")

local InstanceSettings, InstanceState = State.Settings, State.Instance
local GetGuiManager, AddressOf, GetField, ArrayLength = Core.GetGuiManager, Core.AddressOf, Core.GetField, Core.ArrayLength
local HookThis, InstallHook, IsNgPlusFogShown = Core.HookThis, Core.InstallHook, Core.IsNgPlusFogShown
local MaskPainterType <const> = Definitions.MaskPainterType

--
-- Scope: NG+ flag and mask arrays

--- @brief While map code runs, the game's own mask objects hold the private arrays of fog mask cells.
--- Only the overworld mask, the current area's mask and the mask the full map shows are swapped when needed, to avoid spamming checks.
local function SwapMaskArrays(bSwapIn)
  if bSwapIn == false then
    if InstanceState.SwappedArrays == nil then return end
    for _, Swap in ipairs(InstanceState.SwappedArrays) do pcall(function() Swap.GameMask:set_field("MaskBit", Swap.OriginalArray) end) end
    InstanceState.SwappedArrays = nil
    return
  end
  if InstanceState.SwappedArrays ~= nil or IsNgPlusFogShown() == false then return end

  InstanceState.SwappedArrays = {}
  local GuiManager, SeenAddresses = GetGuiManager(), {}
  local FullMapEntry = InstanceState.GameMasks[InstanceState.FullMapMaskAddress or -1]
  local Candidates = { GetField(GuiManager, "MapMaskField"), GetField(GuiManager, "MapMaskCurrentArea"), FullMapEntry ~= nil and FullMapEntry.Object or nil }

  for _, GameMask in pairs(Candidates) do
    local Address = AddressOf(GameMask);
    local Entry = Address ~= nil and SeenAddresses[Address] == nil and InstanceState.GameMasks[Address] or nil;
    if Address ~= nil then SeenAddresses[Address] = true end;

    local Private = Entry ~= nil and InstanceState.PrivateMasks[Entry.Key] or nil;
    local OriginalArray = Entry ~= nil and GetField(Entry.Object, "MaskBit") or nil;
    local OriginalAddress = AddressOf(OriginalArray);

    local bCanSwapInCustomFogArray = Private ~= nil and OriginalAddress ~= nil and OriginalAddress ~= AddressOf(Private.Bits) and ArrayLength(OriginalArray) == Private.WordCount;
    if bCanSwapInCustomFogArray then
      local bGameFogDataNeedsPinning = InstanceState.PinnedGameArrays[OriginalAddress] == nil; 
      if bGameFogDataNeedsPinning then OriginalArray:add_ref(); InstanceState.PinnedGameArrays[OriginalAddress] = true end

      Entry.Object:set_field("MaskBit", Private.Bits)
      InstanceState.SwappedArrays[#InstanceState.SwappedArrays + 1] = { GameMask = Entry.Object, OriginalArray = OriginalArray }
    end
  end
end

--- @brief Opens or closes the scope in which the NG+ flag reads false. Closing always restores the flag and the game's arrays.
--- bForced: the mod's own calls into mask code (setMaskOff/isMaskOff do nothing while the flag reads true).
local function SetScope(bOpen, bForced)
  if bOpen == false then SwapMaskArrays(false) end
  if bOpen == true and bForced ~= true and InstanceSettings.bShowRealMapProgress == false and IsNgPlusFogShown() == false then return end

  local GuiManager = GetGuiManager()
  if GuiManager == nil then return end

  local bGameClearDataFlag = GetField(GuiManager, "_IsGameClearData");
  local bSaveRequested     = GetField(GuiManager, "<IsReqSave>k__BackingField");
  local bHideNgPlusFlag    = bOpen == true and InstanceState.bFlagSwapped ~= true and bGameClearDataFlag == true and bSaveRequested ~= true;
 
  local bRestoreNgPlusFlag    = bOpen == false and InstanceState.bFlagSwapped == true;
  local bSwapInCustomFogArray = bOpen == true and bForced ~= true;
 
  if bHideNgPlusFlag == true then
    GuiManager:set_field("_IsGameClearData", false); InstanceState.bFlagSwapped = true
  elseif bRestoreNgPlusFlag == true then
    GuiManager:set_field("_IsGameClearData", true); InstanceState.bFlagSwapped = false
  end

  if bSwapInCustomFogArray == true then SwapMaskArrays(true) end
end

local function EnterScope(bForced)
  InstanceState.ScopeDepth = InstanceState.ScopeDepth + 1
  if InstanceState.ScopeDepth == 1 or bForced == true then SetScope(true, bForced) end
end
local function LeaveScope(ReturnValue)
  InstanceState.ScopeDepth = math.max(0, InstanceState.ScopeDepth - 1)
  if InstanceState.ScopeDepth == 0 then SetScope(false) end
  return ReturnValue
end
--- @brief Runs the function inside a forced scope and returns its result (nil if it raised an error)
local function RunScoped(Function)
  EnterScope(true)
  local bSucceeded, Result = pcall(Function)
  LeaveScope()
  if bSucceeded == true then return Result end
end
local function CloseScope() InstanceState.ScopeDepth = 0; SetScope(false) end

--
-- Map code scope hooks (full map, minimap, fog painters)

--- @brief Painter pre-hook: opens the scope; minimap painters redraw when exploration changed (full-map painters redraw on every map open)
local function OnPainterEnter(Args)
  EnterScope()
  if IsNgPlusFogShown() == false then return end

  local Painter = HookThis(Args)
  if Painter == nil then return end
  
  local PainterAddress = AddressOf(Painter)
  local bNeedsRedraw = InstanceState.FullMapPainters[PainterAddress] == nil 
        and (InstanceState.PainterRedrawGeneration[PainterAddress] or -1) < InstanceState.ExplorationGeneration;
  if bNeedsRedraw then
    InstanceState.PainterRedrawGeneration[PainterAddress] = InstanceState.ExplorationGeneration
    pcall(function() Painter:call("reqDraw") end)
  end
end

local function ScopeMethods(TypeName, Signatures)
  for _, Signature in ipairs(Signatures) do InstallHook(TypeName, Signature, function() EnterScope() end, LeaveScope) end
end

--- @brief Hooks the map and fog painter methods, so the NG+ flag reads false while they run but never otherwise. Rest of the game stay untouched
local function InstallHooks()
  for _, Signature in ipairs({ "update()", "lateUpdate()", "reqDraw()", "reqDrawSub(System.Int32)", "calcLoopRange()",
                               "setup(app.AILocalAreaDefinition, System.Single)", "createMaskTex(System.Int32)" }) do
    InstallHook(MaskPainterType, Signature, OnPainterEnter, LeaveScope)
  end
  InstallHook(MaskPainterType, "setupMenu(app.GuiManager.MapMaskInfo, System.Int32, System.Int32, System.Single)", function(Args)
    EnterScope()
    local Painter = HookThis(Args)
    if Painter ~= nil then InstanceState.FullMapPainters[AddressOf(Painter)] = true end
  end, LeaveScope)

  ScopeMethods(MaskPainterType, { "reqDrawMenu(System.Int32, System.Int32)" })
  ScopeMethods(Definitions.FullMapType, { "updateMask()", "updateMaskSub()", "setupMask()" })
  ScopeMethods(Definitions.MinimapType, { "setupMask()", "updateMap()", "updateTexture()", "checkDispFieldMask()" })
end

return {
  EnterScope   = EnterScope,
  LeaveScope   = LeaveScope,
  RunScoped    = RunScoped,
  CloseScope   = CloseScope,
  InstallHooks = InstallHooks,
}
