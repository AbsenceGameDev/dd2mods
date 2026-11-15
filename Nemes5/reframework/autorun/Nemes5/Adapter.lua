--[[ @author: https://github.com/AbsenceGameDev. Nemes!5: Toil & Trouble - Adapter
  Checks the engine before runnning the meats of the mod.
  - Look up every engine point in Definitions.EnginePoints and switches off each system relying on a missing point.
  - Hooks go through InstallHook
  - The result goes to the probe log (startup_probes, shared_resolved), and the panel verification tab.
]]

--
-- Nemes5
local Definitions = require("Nemes5.Definitions");
local State       = require("Nemes5.State");
local Shared      = require("Nemes5.Shared");
local ProbeLog    = require("Nemes5.ProbeLog");

local SharedCore = Shared.Core;
local TryCall = SharedCore.TryCall;
local InstanceSettings, AdapterState = State.Settings, State.Instance.Adapter;

--
-- Engine points

--- @brief true if the type has the method
local function HasMethod(TypeDefinition, Method)
  local MethodName = Method:gsub("%(%)$", "");
  return TryCall(function() return TypeDefinition:get_method(MethodName) end) ~= nil;
end

local function HasField(TypeDefinition, FieldName) return TryCall(function() return TypeDefinition:get_field(FieldName) end) ~= nil end;

--- @brief Checks one engine point, appending missing parts '("type", "type::method" or "type.field")' to Failures.
--- @return number of checks made.
local function ProbePoint(Point, Failures)
  local TypeDefinition = TryCall(sdk.find_type_definition, Point.Type);
  if TypeDefinition == nil then Failures[#Failures + 1] = Point.Type; return 1 end;

  local Methods, Fields = Point.Methods or {}, Point.Fields or {};
  for _, Method in ipairs(Methods) do
    if HasMethod(TypeDefinition, Method) == false then Failures[#Failures + 1] = Point.Type .. "::" .. Method end;
  end
  for _, FieldName in ipairs(Fields) do
    if HasField(TypeDefinition, FieldName) == false then Failures[#Failures + 1] = Point.Type .. "." .. FieldName end;
  end

  return 1 + #Methods + #Fields;
end

--
-- Systems

local function IsSystemEnabled(SystemName)
  local SystemResult = AdapterState.Systems[SystemName];
  return AdapterState.bModEnabled == true and SystemResult ~= nil and SystemResult.bEnabled == true;
end

local function RefreshModEnabled()
  local WorldResult = AdapterState.Systems.World;
  AdapterState.bModEnabled = WorldResult ~= nil and WorldResult.bEnabled == true and InstanceSettings.bEnabled == true;
end

--- @brief Probes every engine point. 
--- @details sets which systems are on and logs the result
local function Start()
  local Systems, CheckCount, AllFailures, SystemFlags = {}, 0, {}, {};
  for _, SystemName in ipairs(Definitions.Systems) do Systems[SystemName] = { bEnabled = true, Failures = {} } end;
  for _, Point in ipairs(Definitions.EnginePoints) do CheckCount = CheckCount + ProbePoint(Point, Systems[Point.System].Failures) end;

  for _, SystemName in ipairs(Definitions.Systems) do
    local SystemResult = Systems[SystemName];
    SystemResult.bEnabled = #SystemResult.Failures == 0;
    SystemFlags[SystemName] = SystemResult.bEnabled;
    for _, Failure in ipairs(SystemResult.Failures) do AllFailures[#AllFailures + 1] = Failure end;
  end

  AdapterState.Systems, AdapterState.PointCount, AdapterState.bStarted = Systems, CheckCount, true;
  RefreshModEnabled();

  -- Probe: which shared library copy was resolved
  local MarkerPaths = Shared.MarkerPaths;
  ProbeLog.RecordEvent("shared_resolved", {
    version = Shared.Version, provider = Shared.Provider, skipped = Shared.SkippedCopies,
    marker_count = MarkerPaths ~= nil and #MarkerPaths or nil, first_marker = MarkerPaths ~= nil and MarkerPaths[1] or nil,
  });

  -- Probe: engine points found at startup, so updates that screw the mod up may easily be tracked as to why
  ProbeLog.RecordEvent("startup_probes", {
    mod_version = Definitions.ModVersion, checked = CheckCount, found = CheckCount - #AllFailures, failed = AllFailures,
    systems = SystemFlags, mod_enabled = AdapterState.bModEnabled,
  });
end

--- @brief Enables/disables mod functionality
local function SetEnabled(bEnabled)
  InstanceSettings.bEnabled = bEnabled;
  State.SaveSettings();
  RefreshModEnabled();
end

--
-- Hooks

--- @brief method hook logic
--- @return true (if the hook was installed.)
local function InstallHook(SystemName, TypeName, Signature, PreHook, PostHook)
  if IsSystemEnabled(SystemName) == false then return false end;

  local GuardedPre = PreHook ~= nil and function(Args)
    if IsSystemEnabled(SystemName) == true then return PreHook(Args) end;
  end or nil;
  local GuardedPost = PostHook ~= nil and function(ReturnValue)
    if IsSystemEnabled(SystemName) == true then return PostHook(ReturnValue) end;
    return ReturnValue;
  end or nil;

  SharedCore.InstallHook(AdapterState.HookResults, TypeName, Signature, GuardedPre, GuardedPost);
  return AdapterState.HookResults[TypeName .. "::" .. Signature] == true;
end

return {
  Start           = Start,
  SetEnabled      = SetEnabled,
  IsSystemEnabled = IsSystemEnabled,
  InstallHook     = InstallHook,
};
