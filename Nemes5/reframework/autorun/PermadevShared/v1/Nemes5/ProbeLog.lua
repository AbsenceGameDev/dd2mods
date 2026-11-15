--[[ @author: https://github.com/AbsenceGameDev. Shared - ProbeLog
  Persistent log of events to confirm or refute unconfirmed behaviour in game, used to probe suspected behaviour basically.
  - File: reframework/data/NGPlusFog/probe_events.json, oldest first, at most ProbeEventLimit events.
  - Note: Never use per frame!
]]


local SharedPrefix <const> = (...):match("^(.*%.)[^.]+$");
local Core = require(SharedPrefix .. "Core");
local DefaultEventLimit <const> = 200;

--- @brief A probe log stored at Options.Path, keeping at most <Options.Limit> events. Limit defaults to 200
local function New(Options)
  local Path, EventLimit = Options.Path, Options.Limit or DefaultEventLimit;
  local Events = nil;

  --- @brief The logged events, read from the file on first use
  local function GetEvents()
    if Events ~= nil then return Events end;

    local SavedLog = Core.TryCall(json.load_file, Path);
    Events = type(SavedLog) == "table" and type(SavedLog.events) == "table" and SavedLog.events or {};
    return Events;
  end

  --- @brief Appends an event with the local time and writes the log; the oldest events are dropped past the limit
  local function RecordEvent(EventName, Details)
    local LoggedEvents = GetEvents();
    LoggedEvents[#LoggedEvents + 1] = { time = os.date("%Y-%m-%d %H:%M:%S"), event = EventName, details = Details };
    while #LoggedEvents > EventLimit do table.remove(LoggedEvents, 1) end;
    pcall(json.dump_file, Path, { events = LoggedEvents });
  end

  local function CountEvents() return #GetEvents() end;

  --- @brief Details of the newest event of a name, and how many there are
  local function FindNewest(EventName)
    local Newest, Count = nil, 0;
    for _, Event in ipairs(GetEvents()) do
      if Event.event == EventName then Newest, Count = Event, Count + 1 end;
    end

    return Newest ~= nil and Newest.details or nil, Count;
  end

  return {
    GetEvents   = GetEvents,
    RecordEvent = RecordEvent,
    CountEvents = CountEvents,
    FindNewest  = FindNewest,
  };
end

return {
  New = New,
};
