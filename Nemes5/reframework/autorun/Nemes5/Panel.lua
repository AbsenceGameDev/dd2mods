--[[ @author: https://github.com/AbsenceGameDev. Nemes!5: Toil & Trouble - Panel
]]

--
-- Nemes5
local Definitions = require("Nemes5.Definitions");
local State       = require("Nemes5.State");
local Shared      = require("Nemes5.Shared");
local Adapter     = require("Nemes5.Adapter");
local ProbeLog    = require("Nemes5.ProbeLog");

local InstanceSettings, AdapterState = State.Settings, State.Instance.Adapter;
local TreeNode = Shared.Core.TreeNode;

--- @brief Status line of a system
local function DescribeSystem(SystemName)
  local SystemResult = AdapterState.Systems[SystemName];
  if SystemResult == nil then return "not checked" end;
  if SystemResult.bEnabled == false then
    return "off: missing " .. SystemResult.Failures[1] .. (#SystemResult.Failures > 1 and string.format(" and %d more", #SystemResult.Failures - 1) or "");
  end
  return Adapter.IsSystemEnabled(SystemName) == true and "on" or "off (mod off)";
end

local function DrawPanel()
  local bChanged, bEnabled = imgui.checkbox("Enabled", InstanceSettings.bEnabled);
  if bChanged == true then Adapter.SetEnabled(bEnabled) end;

  imgui.text(string.format("Version %s · PermadevShared v%s (%s)", Definitions.ModVersion, tostring(Shared.Version), tostring(Shared.Provider)));
  imgui.text("Status: " .. (AdapterState.bModEnabled == true and "on" or "off"));
  for _, SystemName in ipairs(Definitions.Systems) do imgui.text(string.format("  %-10s %s", SystemName, DescribeSystem(SystemName))) end;

  TreeNode("Verification (" .. ProbeLog.CountEvents() .. " events in probe_events.json)", function()
    for _, Line in ipairs(ProbeLog.DescribeVerification()) do imgui.text(string.format("  %-16s %s", Line.Item, Line.Status)) end;
  end);
end

local function Install()
  re.on_draw_ui(function() TreeNode(Definitions.DisplayName, DrawPanel) end);
end

return {
  Install = Install,
};
