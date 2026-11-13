--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Panel
  The settings panel (REFramework → Script Generated UI → NG+ Fog) and the diagnostics probe.
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")
local Scope       = require("NGPlusFog.Scope")
local Masks       = require("NGPlusFog.Masks")
local Persistence = require("NGPlusFog.Persistence")
local Backups     = require("NGPlusFog.Backups")
local Selector    = require("NGPlusFog.Selector");
local ProbeLog    = require("NGPlusFog.ProbeLog");

local InstanceSettings, InstanceState = State.Settings, State.Instance
local GetField, ArrayLength, Components, Describe, Now = Core.GetField, Core.ArrayLength, Core.Components, Core.Describe, Core.Now
local CountRevealedCells = Masks.CountRevealedCells
local TreeNode = Core.TreeNode;
local IsMaskOffSignature <const> = Definitions.IsMaskOffSignature

--
-- Probe (diagnostics)

local function Probe()
  local GuiManager = Core.GetGuiManager()
  local FieldEntry
  for _, Entry in pairs(InstanceState.GameMasks) do if Entry.Key == Definitions.OverworldMaskKey then FieldEntry = Entry end end

  local Private, PlayerPosition = InstanceState.PrivateMasks.F, GetField(GuiManager, "PlUPos")
  local WorldX, WorldY, WorldZ = Components(PlayerPosition)
  local QueryPosition = WorldX ~= nil and Vector3f.new(WorldX, WorldY, WorldZ) or nil
  local FailedHooks, LocalMapCount, LocalCellCount = {}, 0, 0
  for HookName, bInstalled in pairs(InstanceState.HookResults) do if bInstalled == false then FailedHooks[#FailedHooks + 1] = HookName end end
  
  for MaskKey, Mask in pairs(InstanceState.PrivateMasks) do
    if MaskKey ~= Definitions.OverworldMaskKey then LocalMapCount, LocalCellCount = LocalMapCount + 1, LocalCellCount + CountRevealedCells(Mask.Bits, Mask.WordCount) end
  end
  
  local GameArray = FieldEntry ~= nil and GetField(FieldEntry.Object, "MaskBit") or nil
  local PlayTime, GameTime = Persistence.ReadTimes()
  local bNgPlusRevealedHere, bRealRevealedHere
  if Private ~= nil and QueryPosition ~= nil then
    bNgPlusRevealedHere = Scope.RunScoped(function() return Private.MaskInfo:call(IsMaskOffSignature, QueryPosition) end)
  end
  
  if FieldEntry ~= nil and QueryPosition ~= nil then
    bRealRevealedHere = Scope.RunScoped(function() return FieldEntry.Object:call(IsMaskOffSignature, QueryPosition) end)
  end
  
  local Report = {
    time = os.date("%Y-%m-%d %H:%M:%S"), status = InstanceState.Status, slot = InstanceState.CurrentSlot,
    slot_file = InstanceState.SlotFileState[InstanceState.CurrentSlot], loaded_fog = InstanceState.LoadedFogNote,
    play_time_at_load = InstanceState.PlayTimeAtLoad, play_time_now = PlayTime, in_game_time_now = GameTime,
    counts = InstanceState.Counters, hook_failures = FailedHooks, icon_error = InstanceState.IconError, PlUPos = Describe(PlayerPosition),
    ngplus_fog_overworld_cells = Private ~= nil and CountRevealedCells(Private.Bits, Private.WordCount) or nil,
    ngplus_fog_local_maps = LocalMapCount, ngplus_fog_local_cells = LocalCellCount,
    real_progress_cells = GameArray ~= nil and CountRevealedCells(GameArray, ArrayLength(GameArray)) or nil,
    ngplus_fog_revealed_here = bNgPlusRevealedHere, real_progress_revealed_here = bRealRevealedHere,
    overworld_geometry = Private ~= nil and Core.DescribeFields(Private.MaskInfo, Definitions.GeometryFields) or nil,
    verification = ProbeLog.DescribeVerification(),
  }

  local ReportPath = Definitions.DataDirectory .. "probe_" .. os.time() .. ".json"
  pcall(json.dump_file, ReportPath, Report)
  InstanceState.ProbeSummary = string.format("here: NG+ fog revealed=%s, real progress revealed=%s | wrote %s",
    tostring(Report.ngplus_fog_revealed_here), tostring(Report.real_progress_revealed_here), ReportPath)
end

--
-- Settings panel

local function SettingCheckbox(Label, SettingName)
  local bChanged, bValue = imgui.checkbox(Label, InstanceSettings[SettingName])
  if bChanged == true then InstanceSettings[SettingName] = bValue; State.SaveSettings() end
end

local function DrawDiagnostics()
  if imgui.button("Probe here") == true then
    local bSucceeded, ErrorMessage = pcall(Probe)
    if bSucceeded == false then InstanceState.ProbeSummary = "probe error: " .. tostring(ErrorMessage) end
  end

  if InstanceState.ProbeSummary ~= nil then imgui.text(InstanceState.ProbeSummary) end
  imgui.text("array layout ok: " .. tostring(InstanceState.bArrayLayoutValid))
  if Now() - (InstanceState.RevealedCellCountTime or -1) > 1.0 then
    InstanceState.RevealedCellCountTime, InstanceState.RevealedCellCounts = Now(), {}
    for MaskKey, Mask in pairs(InstanceState.PrivateMasks) do InstanceState.RevealedCellCounts[MaskKey] = CountRevealedCells(Mask.Bits, Mask.WordCount) end
  end

  local LocalMapCount, LocalCellCount = 0, 0
  for MaskKey, CellCount in pairs(InstanceState.RevealedCellCounts) do
    if MaskKey ~= Definitions.OverworldMaskKey then LocalMapCount, LocalCellCount = LocalMapCount + 1, LocalCellCount + CellCount end
  end

  imgui.text(string.format("  NG+ fog: overworld %d cells revealed | %d local maps (caves, interiors), %d cells revealed",
    InstanceState.RevealedCellCounts.F or 0, LocalMapCount, LocalCellCount))
  
    for CounterName, CounterValue in pairs(InstanceState.Counters) do imgui.text(string.format("  %-32s %d", CounterName, CounterValue)) end
  
  for HookName, bInstalled in pairs(InstanceState.HookResults) do if bInstalled == false then imgui.text("  HOOK FAILED: " .. HookName) end end

  TreeNode("Verification (" .. ProbeLog.CountEvents() .. " events in probe_events.json)", function()
    for _, Line in ipairs(ProbeLog.DescribeVerification()) do imgui.text(string.format("  %-20s %s", Line.Item, Line.Status)) end;
  end);
end

local function DrawPanel()
  local Slot = InstanceState.CurrentSlot
  imgui.text("Status: " .. InstanceState.Status .. " latest loaded save slot: " .. tostring(Persistence.SignedSlot(Slot)))
  if InstanceState.LoadedFogNote ~= nil then imgui.text("Loaded NG+ fog: " .. InstanceState.LoadedFogNote) end

  SettingCheckbox("Fog of war in NG+ (clears as you explore this playthrough)", "bFogOfWar")
  SettingCheckbox("Show real map progress (the save's own fog, as before NG+ revealed all)", "bShowRealMapProgress")
  if InstanceState.IconError ~= nil then imgui.text("icon error: " .. InstanceState.IconError) end

  if imgui.button("Open fog data selector (snapshots and backups of every save)") == true then Selector.Open() end;
  if imgui.button("Reset NG+ fog (this slot)") == true then Persistence.ResetNgPlusFog(); Persistence.SaveSlot(Slot) end; imgui.same_line()
  if imgui.button("Copy real progress into NG+ fog") == true then Backups.CopyRealProgress() end; imgui.same_line()

  TreeNode("Diagnostics", DrawDiagnostics)
end

--
-- Install
local function Install() re.on_draw_ui(function() TreeNode("NG+ Fog", DrawPanel) end) end

return {
  Install = Install,
}
