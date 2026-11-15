--[[ @author: https://github.com/AbsenceGameDev. Nemes!5: Toil & Trouble - ProbeLog
  Probe events for in-game method and/or data verification
]]

--
-- Nemes5
local Definitions = require("Nemes5.Definitions");
local Shared      = require("Nemes5.Shared");

local EventLog = Shared.ProbeLog.New({ Path = Definitions.ProbeLogPath, Limit = Definitions.ProbeEventLimit });
local FindNewest = EventLog.FindNewest;

--- @brief One status line per unconfirmed item from pairs of {Item, Status}
local function DescribeVerification()
  local Lines = {};
  local function Add(Item, Status) Lines[#Lines + 1] = { Item = Item, Status = Status } end;

  local Resolved = FindNewest("shared_resolved");
  Add("Shared library", Resolved == nil and "not seen yet: start the game with the mod installed"
    or string.format("PermadevShared v%s from %s; fs.glob found %s marker(s), first %s", tostring(Resolved.version), tostring(Resolved.provider),
      tostring(Resolved.marker_count), tostring(Resolved.first_marker)));

  local Probes = FindNewest("startup_probes");
  Add("Engine points", Probes == nil and "not seen yet: start the game with the mod installed"
    or string.format("%d of %d found%s", Probes.found, Probes.checked, #Probes.failed == 0 and "" or "; missing: " .. table.concat(Probes.failed, ", ")));
  return Lines;
end

return {
  RecordEvent          = EventLog.RecordEvent,
  CountEvents          = EventLog.CountEvents,
  FindNewest           = FindNewest,
  DescribeVerification = DescribeVerification,

  -- Exposed for tests
  GetEvents            = EventLog.GetEvents,
};
