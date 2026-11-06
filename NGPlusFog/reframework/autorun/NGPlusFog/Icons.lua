--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Icons
  Icons in fog on the full map. Icons keep store their true position at all times, so zoom and pan behave normally.
   - Drawing pass: an icon whose surroundings are fogged is switched off (visibility and mouse hit-testing).
   - Cursor pass: for the duration of the game's cursor search, fogged icons are moved off the map, so the cursor cannot select them.
  The minimap hides fogged icons by itself (its code runs inside the scope with the private fog).
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Core        = require("NGPlusFog.Core");
local Masks       = require("NGPlusFog.Masks");


local function RestoreParkedIcons()
end

--
-- Hooks
local function InstallHooks()
end

return {
  RestoreParkedIcons = RestoreParkedIcons,
  InstallHooks       = InstallHooks,
}
