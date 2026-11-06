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


--
-- Install

local function Install()

end

return {
  Install = Install,
}
