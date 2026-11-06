--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Persistence
  NG+ fog per save slot, stored as a ring of 8 snapshots (slot_<n>_h0..h7.json) with sequence, play time, and in-game time.
  A crash can only damage the snapshot being written. On load, the snapshot matching the save's play time is used, or closest below it if none match
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")
local Core        = require("NGPlusFog.Core")
local Masks       = require("NGPlusFog.Masks")

--
-- Snapshot files

local function SlotFileBase(Slot) return DataDirectory .. "slot_" .. tostring(Slot) end
local function ReadValidFile(Path) end

--- @brief Play time (TimeManager.WholePlayTime) and in-game time (day * InGameDaySeconds + seconds)
local function ReadTimes() end


local function FormatPlayTime(Seconds) end

--- @brief Chooses the snapshot for the loaded save. Returns the snapshot (or nil) and a note for the status line.
local function PickSnapshot(Snapshots, PlayTime) end

--
-- Load, save and reset

local function ApplySavedMasks() end

--- @brief Starts a slot load; the snapshot is chosen about half a second later, once the game has restored its own play time
local function LoadSlot(Slot) end

local function PickPendingSnapshot() end

--- @brief Writes the current NG+ fog as the next snapshot in the slot's ring
local function SaveSlot(Slot) end

local function ResetNgPlusFog() end


local function InstallHooks()
end

return {
  ReadValidFile       = ReadValidFile,
  ReadTimes           = ReadTimes,
  FormatPlayTime      = FormatPlayTime,
  ApplySavedMasks     = ApplySavedMasks,
  LoadSlot            = LoadSlot,
  PickPendingSnapshot = PickPendingSnapshot,
  SaveSlot            = SaveSlot,
  ResetNgPlusFog      = ResetNgPlusFog,
  InstallHooks        = InstallHooks,

  -- Exposed for tests
  PickSnapshot        = PickSnapshot,
}
