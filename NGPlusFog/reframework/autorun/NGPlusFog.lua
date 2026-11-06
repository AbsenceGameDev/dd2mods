--[[@author: https://github.com/AbsenceGameDev. NG+ Fog: Map fog-of-war in NG+ for Dragon's Dogma 2 (REFramework).

  Read README for an explanation of the usage of this mod.
]]

--
-- NG+ Fog
local Persistence = require("NGPlusFog.Persistence")
local Masks       = require("NGPlusFog.Masks")
local Scope       = require("NGPlusFog.Scope")
local Icons       = require("NGPlusFog.Icons")
local Tick        = require("NGPlusFog.Tick")
local Panel       = require("NGPlusFog.Panel")

--
-- Install
Persistence.InstallHooks()
Masks.InstallHooks()
Scope.InstallHooks()
Icons.InstallHooks()
Tick.Install()
Panel.Install()
