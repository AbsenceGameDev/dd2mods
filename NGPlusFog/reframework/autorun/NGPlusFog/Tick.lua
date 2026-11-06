--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Tick
  Safety guards (save guard, Reset Scripts, stuck scope and stuck cursor checks) and the per-tick state update.
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")
local Scope       = require("NGPlusFog.Scope")
local Masks       = require("NGPlusFog.Masks")
local Persistence = require("NGPlusFog.Persistence")
local Icons       = require("NGPlusFog.Icons")

local InstanceSettings, InstanceState = State.Settings, State.Instance
local GetField, Now, Increment, IsNgPlusFogShown = Core.GetField, Core.Now, Core.Increment, Core.IsNgPlusFogShown
local CloseScope = Scope.CloseScope
local StuckFrameLimit <const>     = Definitions.StuckFrameLimit
local TickIntervalSeconds <const> = Definitions.TickIntervalSeconds

--
-- State tick

--- @brief Per-tick update: NG+ detection, deferred snapshot choice, private copies, redraw generation and status line
local function StateTick()
  local GuiManager = Core.GetGuiManager()
  if GuiManager == nil then InstanceState.Status = "waiting for game"; return end

  local bNgPlusSave = InstanceState.bFlagSwapped == true or GetField(GuiManager, "_IsGameClearData") == true
  InstanceState.bNgPlusSave = bNgPlusSave
  InstanceState.bActive = InstanceSettings.bFogOfWar == true and InstanceState.bArrayLayoutValid ~= false and bNgPlusSave
  if InstanceState.bArrayLayoutValid == false then return end
  if bNgPlusSave == false then InstanceState.Status = "idle: not an NG+ save"; return end

  if InstanceState.PendingPickSlot ~= nil and Now() >= InstanceState.PendingPickTime then Persistence.PickPendingSnapshot() end

  if IsNgPlusFogShown() == true then
    Masks.EnsurePrivateMasks()
  elseif InstanceSettings.bShowRealMapProgress == true and (next(InstanceState.GameMasks) == nil or Now() - InstanceState.LastIndexTime > 5.0) then
    Masks.IndexGameMasks()
  end

  if InstanceState.bRedrawRequested == true then
    InstanceState.bRedrawRequested, InstanceState.ExplorationGeneration = false, InstanceState.ExplorationGeneration + 1
  end

  if InstanceSettings.bShowRealMapProgress == true then InstanceState.Status = "showing real map progress"
  elseif InstanceSettings.bFogOfWar == true then InstanceState.Status = "fog of war on"
  else InstanceState.Status = "fog of war off" end
end

local function OnFrame()
  InstanceState.FrameCounter = InstanceState.FrameCounter + 1; -- Exposure check: this callback runs outside map code; should never be above 0.

  -- A scope left open for several frames (if a hook throws) is closed, restoring the flag and the arrays.
  if InstanceState.bFlagSwapped == true then Increment("ngplus_flag_seen_off_outside_map_code") end

  local bScopeOpen = InstanceState.ScopeDepth ~= 0 or InstanceState.bFlagSwapped == true or InstanceState.SwappedArrays ~= nil
  InstanceState.ScopeStuckFrames = bScopeOpen and (InstanceState.ScopeStuckFrames or 0) + 1 or 0
  if InstanceState.ScopeStuckFrames > StuckFrameLimit then InstanceState.ScopeStuckFrames = 0; CloseScope(); Increment("scope_safety_resets") end
  
  InstanceState.CursorStuckFrames = InstanceState.ParkedIcons ~= nil and (InstanceState.CursorStuckFrames or 0) + 1 or 0
  if InstanceState.CursorStuckFrames > StuckFrameLimit then
    InstanceState.CursorStuckFrames, InstanceState.CursorSearchDepth = 0, 0
    Icons.RestoreParkedIcons(); Increment("cursor_park_safety_restores")
  end

  if Now() - (InstanceState.LastTickTime or 0) < TickIntervalSeconds then return end

  InstanceState.LastTickTime = Now()
  local bSucceeded, ErrorMessage = pcall(StateTick)
  if bSucceeded == false then InstanceState.Status = "error: " .. tostring(ErrorMessage) end
end

--
-- Install

local function Install()
  Core.InstallHook(Definitions.GuiManagerType, "saveGameSaveData()", function() CloseScope() end, nil)
  re.on_script_reset(CloseScope)
  re.on_frame(OnFrame)
end

return {
  Install = Install,
}
