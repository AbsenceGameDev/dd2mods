--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Scope
  Scope in which the NG+ flag reads false and the game's own mask objects hold the private fog mask arrays.
  @note only open while map code runs (full map, minimap, fog painters) and during the mod's own mask calls.
  @todo test to ensure game does not lose ng+ features
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")


local function EnterScope(bForced) end
local function LeaveScope(ReturnValue) end

--- @brief Runs the function inside a forced scope and returns its result (nil if it raised an error)
local function RunScoped(Function) end
local function CloseScope()  end


--- @brief Hooks the map and fog painter methods, so the NG+ flag reads false while they run but never otherwise. Rest of the game stay untouched
local function InstallHooks()
end

return {
  EnterScope   = EnterScope,
  LeaveScope   = LeaveScope,
  RunScoped    = RunScoped,
  CloseScope   = CloseScope,
  InstallHooks = InstallHooks,
}
