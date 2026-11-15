--[[ @author: https://github.com/AbsenceGameDev. Nemes!5: Toil & Trouble - State
  - InstanceSettings: persisted user choices
  - InstanceState: runtime data
]]

--
-- Nemes5
local Definitions = require("Nemes5.Definitions");

--
-- Loaded instance settings
local InstanceSettings = {};
do
  local bLoaded, SavedSettings = pcall(json.load_file, Definitions.SettingsPath);
  for SettingName, DefaultValue in pairs(Definitions.SettingsDefaults) do
    InstanceSettings[SettingName] = DefaultValue;

    local bCanCacheSettings = bLoaded == true and type(SavedSettings) == "table" and type(SavedSettings[SettingName]) == type(DefaultValue);
    if bCanCacheSettings == true then
      InstanceSettings[SettingName] = SavedSettings[SettingName];
    end
  end
end

--- @brief Writes the current settings to the settings file
local function SaveSettings() pcall(json.dump_file, Definitions.SettingsPath, InstanceSettings) end;

--
-- Instance state, key -> value
local InstanceState = {
  Adapter = {
    bStarted = false,
    bModEnabled = false,  
    Systems = {},         -- (key -> value) system name -> { bEnabled, Failures = { "type::method" ... } }
    PointCount = 0,       -- engine points count checked at the last start, crude mismatch check
    HookResults = {},     -- (key -> value) "type::signature" -> bWasHooked
  },
};

return {
  Settings     = InstanceSettings,
  Instance     = InstanceState,
  SaveSettings = SaveSettings,
};
