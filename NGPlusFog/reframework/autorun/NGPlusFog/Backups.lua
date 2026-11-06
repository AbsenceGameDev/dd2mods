--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Backups
  Copies actual game progress into the custom NG+ fog, with a timestamped backup per save slot before each copy
  'backups/slot_<n>_<time>_<index>.json, listed in backups/slot_<n>_index.json'. 
  @note: Any backup can be restored from the panel.
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")
local Masks       = require("NGPlusFog.Masks")
local Persistence = require("NGPlusFog.Persistence")


--- @brief Returns the slot's backup list (loaded once per slot); with no save loaded yet the slot is nil and "none" is used
local function GetCopyBackups(Slot) end

local function RevertToBackup(Slot, BackupIndex) end

--- @brief Copies the save's own fog (previous exploration) into the NG+ fog. Backs up the current NG+ fog first
local function CopyRealProgress() end

return {
  GetCopyBackups    = GetCopyBackups,
  RevertToBackup    = RevertToBackup,
  CopyRealProgress  = CopyRealProgress,
}
