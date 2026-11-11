--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - ProbeLog
  Persistent log of events to confirm or refute unconfirmed behaviour in game, used to probe suspected behaviour basically.
  - File: reframework/data/NGPlusFog/probe_events.json, oldest first, at most ProbeEventLimit events.
  - Note: Never use per frame!
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Core        = require("NGPlusFog.Core");

local InstanceState = State.Instance;
local ProbeEventsPath <const> = Definitions.DataDirectory .. "probe_events.json";
local ProbeEventLimit <const> = 200;

--- @brief The logged events, read from the file on first use
local function GetEvents()
  if InstanceState.ProbeEvents ~= nil then return InstanceState.ProbeEvents end;

  local SavedLog = Core.TryCall(json.load_file, ProbeEventsPath);
  InstanceState.ProbeEvents = type(SavedLog) == "table" and type(SavedLog.events) == "table" and SavedLog.events or {};
  return InstanceState.ProbeEvents;
end

--- @brief Append event with local time (writes to log)
--- @brief the oldest events are dropped if exceeding the lim
local function RecordEvent(EventName, Details)
  local Events = GetEvents();
  Events[#Events + 1] = { time = os.date("%Y-%m-%d %H:%M:%S"), event = EventName, details = Details };
  while #Events > ProbeEventLimit do table.remove(Events, 1) end;

  pcall(json.dump_file, ProbeEventsPath, { events = Events });
end

local function CountEvents() return #GetEvents() end;

--- @brief Newest event of a given name and event count of same event 
local function FindNewest(EventName)
  local Newest, Count = nil, 0;
  for _, Event in ipairs(GetEvents()) do
    if Event.event == EventName then Newest, Count = Event, Count + 1 end;
  end

  return Newest ~= nil and Newest.details or nil, Count;
end

--- @brief One status line per unconfirmed item.
--- @note { Item, Status } pairs derived from the logged events.
local function DescribeVerification()
  local Lines = {};
  local function Add(Item, Status) Lines[#Lines + 1] = { Item = Item, Status = Status } end;

  local Loaded = FindNewest("save_loaded");
  Add("Load slot form", Loaded == nil and "not seen yet: load a save"
    or string.format("getLoadingGameSlotId returned %s (%s); sources agree: %s", tostring(Loaded.game_slot_raw), tostring(Loaded.game_slot_raw_type), tostring(Loaded.sources_disagree == false)));

  local Picked = FindNewest("fog_picked");
  Add("Play time at load", Picked == nil and "not seen yet: load a save" or string.format("%s (play time %s)", tostring(Picked.note), tostring(Picked.play_time)));

  local Row, RowCount = FindNewest("load_menu_row");
  local Methods = Row ~= nil and Row.read_methods or {};
  Add("Load menu rows", Row == nil and "not seen yet: open the game's load menu"
    or string.format("%d recorded; names read via %s, slot via %s", RowCount, tostring(Methods.arisen_name), tostring(Methods.slot)));

  local Arisen = Row ~= nil and Row.row ~= nil and Row.row.arisen or nil;
  Add("Vocation names", Arisen == nil and "not seen yet: open the game's load menu"
    or string.format("%s shown as %s: compare with the game's menu", tostring(Arisen.job_enum), tostring(Arisen.job_name)));

  local Calculation = FindNewest("load_menu_slot_calculation");
  local CalculatedSlots = {};
  for TypeName, Result in pairs(Calculation ~= nil and Calculation.by_save_type or {}) do
    CalculatedSlots[#CalculatedSlots + 1] = string.format("%s=%s (%s)", TypeName, tostring(Result.slot), tostring(Result.assumed_save_type or "outside layout"));
  end
  table.sort(CalculatedSlots);
  Add("Slot layout", Calculation == nil and "not seen yet: open the game's load menu" or table.concat(CalculatedSlots, ", "));

  local _NewCycle, NewCycleCount = FindNewest("make_loop_save_data");
  Add("New cycle reset", NewCycleCount == 0 and "not seen yet: only when the next NG+ cycle starts" or string.format("makeLoopSaveData ran %d times", NewCycleCount));
  return Lines;
end

return {
  RecordEvent          = RecordEvent,
  CountEvents          = CountEvents,
  DescribeVerification = DescribeVerification,
};
