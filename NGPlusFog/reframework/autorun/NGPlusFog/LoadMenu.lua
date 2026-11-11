--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - LoadMenu
  Records the game's load menu rows (app.ui030901.MainListInfo, one per save) to slots.json, keyed by slot as the game numbers it:
  
  fields: Arisen and pawn name, level and vocation, place, play time, date saved, day and save type. 
  
  @note 
    - Fields read here are unconfirmed until tested in game. 
    - Each row records how its fields were read (backing field, getter, or unreadable), 
    - each menu opening logs the game's own save type -> slot calculation (calcSaveSlotNo) next to the assumed slot layout, to probe_events.json.
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Core        = require("NGPlusFog.Core");
local Persistence = require("NGPlusFog.Persistence");
local ProbeLog    = require("NGPlusFog.ProbeLog");

local InstanceState            = State.Instance;
local TryCall, GetField        = Core.TryCall, Core.GetField;
local HookThis, InstallHook    = Core.TryCall, Core.GetField, Core.HookThis, Core.InstallHook;
local SignedSlot               = Persistence.SignedSlot;
local LoadMenuType <const>     = Definitions.LoadMenuType;
local SaveDataTypeEnum <const> = Definitions.SaveDataTypeEnum;
local JobEnum <const>          = Definitions.JobEnum;
local SlotLayout <const>       = Definitions.ASSUMED_SAVE_SLOT_LAYOUT_PER_CHARACTER;
local JobNames <const>         = Definitions.ASSUMED_JOB_NAMES;
local SlotsPath <const>        = Definitions.DataDirectory .. "slots.json";

--
-- Reading managed values

--- @brief Reads an auto-property: its backing field first, then fallbacks to getter. 
--- @return the raw value and how it was read.
local function ReadProperty(Object, PropertyName)
  if Object == nil then return nil, "no object" end;

  local Value = GetField(Object, "<" .. PropertyName .. ">k__BackingField");
  if Value ~= nil then return Value, "field" end;

  Value = TryCall(function() return Object:call("get_" .. PropertyName) end);
  if Value ~= nil then return Value, "getter" end;

  return nil, "unreadable";
end

--- @brief Read a property as a Lua string or number (user strings convert to lua strings)
local function ReadPlainProperty(Object, PropertyName)
  local Value, ReadMethod = ReadProperty(Object, PropertyName);
  if type(Value) == "userdata" then Value = TryCall(function() return Value:call("ToString") end); ReadMethod = ReadMethod .. "+ToString" end;
  
  return Value, ReadMethod;
end

--- @brief Names from enum types, are read once from static fields
local function GetEnumNames(TypeName)
  local CachedNames = InstanceState.LoadMenu.EnumNames[TypeName];
  if CachedNames ~= nil then return CachedNames end;

  local EnumNames, TypeDefinition = {}, TryCall(sdk.find_type_definition, TypeName);
  local Fields = TypeDefinition ~= nil and TryCall(function() return TypeDefinition:get_fields() end) or {};
  for _, Field in ipairs(Fields) do
    local bIsStatic = TryCall(function() return Field:is_static() end) == true;
    local Value = bIsStatic == true and TryCall(function() return Field:get_data(nil) end) or nil;
    if Value ~= nil then EnumNames[Value] = Field:get_name() end;
  end

  InstanceState.LoadMenu.EnumNames[TypeName] = EnumNames;
  return EnumNames;
end

--
-- Rows

--- @brief One character of a row (Arisen or pawn): name, level and job, and method of reading data
local function ReadCharacter(CharacterInfo, ReadMethods, Prefix)
  local Name, NameMethod = ReadPlainProperty(CharacterInfo, "Name");
  local Level, LevelMethod = ReadPlainProperty(CharacterInfo, "Level");
  local Job, JobMethod = ReadPlainProperty(CharacterInfo, "Job");
  local JobEnumName = Job ~= nil and GetEnumNames(JobEnum)[Job] or nil;
  ReadMethods[Prefix .. "name"], ReadMethods[Prefix .. "level"], ReadMethods[Prefix .. "job"] = NameMethod, LevelMethod, JobMethod;

  return { name = Name, level = Level, job = Job, job_enum = JobEnumName, job_name = JobEnumName ~= nil and JobNames[JobEnumName] or nil };
end

--- @brief rows getter, keyed by slot as text 
--- @note loaded from slots.json on first use
local function GetRows()
  local LoadMenuState = InstanceState.LoadMenu;
  if LoadMenuState.Rows == nil then
    local SavedSlots = TryCall(json.load_file, SlotsPath);
    LoadMenuState.Rows = type(SavedSlots) == "table" and type(SavedSlots.rows) == "table" and SavedSlots.rows or {};
  end

  return LoadMenuState.Rows;
end

local function WriteSlots() pcall(json.dump_file, SlotsPath, { rows = GetRows() }) end;

--- @brief Records one load menu row 
--- @note logs it to the probe log when it is new or har been changed
local function RecordRow(Row)
  local ReadMethods = {};
  local Slot, SlotMethod = ReadPlainProperty(Row, "SaveSlotNo");
  local bIsEmpty = ReadPlainProperty(Row, "IsEmpty");
  local SlotInfo = ReadProperty(Row, "SlotInfo");
  local SaveType, SaveTypeMethod = ReadPlainProperty(SlotInfo, "SaveDataType");
  ReadMethods.slot, ReadMethods.save_type = SlotMethod, SaveTypeMethod;

  local SignedRowSlot = SignedSlot(Slot);
  if SignedRowSlot == nil or bIsEmpty == true then
    ProbeLog.RecordEvent("load_menu_row_skipped", { slot_raw = Slot, empty = bIsEmpty, read_methods = ReadMethods });
    return;
  end

  local Place, PlaceMethod = ReadPlainProperty(SlotInfo, "PlaceName");
  local PlayTime = ReadPlainProperty(SlotInfo, "PlayTime");
  local SavedTime = ReadPlainProperty(SlotInfo, "SavedTime");
  local Day = ReadPlainProperty(SlotInfo, "DayValue");
  ReadMethods.place = PlaceMethod;

  local Layout = SlotLayout[SignedRowSlot];
  local Record = {
    slot = SignedRowSlot, save_type = SaveType, save_type_name = SaveType ~= nil and GetEnumNames(SaveDataTypeEnum)[SaveType] or nil,
    arisen = ReadCharacter(ReadProperty(Row, "ArisenInfo"), ReadMethods, "arisen_"),
    pawn = ReadCharacter(ReadProperty(Row, "PawnInfo"), ReadMethods, "pawn_"),
    place = Place, play_time = PlayTime, saved_time = SavedTime, day = Day, recorded = os.date("%Y-%m-%d %H:%M:%S"),
    assumed_character = Layout ~= nil and Layout[1] or nil, assumed_save_type = Layout ~= nil and Layout[2] or nil,
  };

  -- Rows are rewritten every time the menu open. saves and logs new or changed rows
  local SlotKey = tostring(SignedRowSlot);
  local PreviousRecord = GetRows()[SlotKey];
  local bIsUnchanged = PreviousRecord ~= nil and PreviousRecord.saved_time == Record.saved_time and PreviousRecord.play_time == Record.play_time;
  if bIsUnchanged == true then return end;

  GetRows()[SlotKey] = Record;
  WriteSlots();
  ProbeLog.RecordEvent("load_menu_row", { row = Record, read_methods = ReadMethods });
end

--- @brief Logs the game's save type -> slot calculation for the open menu, once per unique result
local function RecordSlotCalculation(LoadMenu)
  local Calculated, Summary = {}, {};
  
  for TypeValue, TypeName in pairs(GetEnumNames(SaveDataTypeEnum)) do
    local CalculatedSlot = TryCall(function() return LoadMenu:call("calcSaveSlotNo", TypeValue) end);
    local Layout = CalculatedSlot ~= nil and SlotLayout[SignedSlot(CalculatedSlot)] or nil;
    Calculated[TypeName] = { slot = CalculatedSlot, assumed_character = Layout ~= nil and Layout[1] or nil, assumed_save_type = Layout ~= nil and Layout[2] or nil };
    Summary[#Summary + 1] = TypeName .. "=" .. tostring(CalculatedSlot);
  end
  table.sort(Summary);

  local SummaryText = table.concat(Summary, ",");
  if InstanceState.LoadMenu.LastCalculation == SummaryText then return end;

  InstanceState.LoadMenu.LastCalculation = SummaryText;
  ProbeLog.RecordEvent("load_menu_slot_calculation", { by_save_type = Calculated, use_save_slot_no = GetField(LoadMenu, "UseSaveSlotNo") });
end

--
-- Access and hooks

--- @brief Recorded load menu row of a slot, or nil
local function GetRow(Slot) return GetRows()[tostring(Slot)] end;

local function InstallHooks()
  InstallHook(LoadMenuType, "createSaveSlotInfo(app.ui030901.SaveDataType, System.Nullable`1<System.Guid>)", function(Args)
    InstanceState.LoadMenu.OpenMenu = HookThis(Args);
  end, function(ReturnValue)
    local bRecorded, ErrorMessage = pcall(RecordRow, TryCall(sdk.to_managed_object, ReturnValue));
    if bRecorded == false then ProbeLog.RecordEvent("load_menu_row_error", { error = tostring(ErrorMessage) }) end;

    local OpenMenu = InstanceState.LoadMenu.OpenMenu;
    if OpenMenu ~= nil then pcall(RecordSlotCalculation, OpenMenu) end;

    return ReturnValue;
  end);
end

return {
  GetRow       = GetRow,
  InstallHooks = InstallHooks,
};
