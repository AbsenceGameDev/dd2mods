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

local InstanceState = State.Instance
local TryCall, AddressOf, GetField, ArrayLength = Core.TryCall, Core.AddressOf, Core.GetField, Core.ArrayLength
local ReadWord, WriteWord = Core.ReadWord, Core.WriteWord
local ReadValidFile, ReadTimes, FormatPlayTime = Persistence.ReadValidFile, Persistence.ReadTimes, Persistence.FormatPlayTime
local DataDirectory <const> = Definitions.DataDirectory

--
-- Copy backups
local function BackupIndexPath(Slot) return DataDirectory .. "backups/slot_" .. tostring(Slot) .. "_index.json" end

--- @brief Returns the slot's backup list (loaded once per slot); with no save loaded yet the slot is nil and "none" is used
local function GetCopyBackups(Slot)
  local SlotKey = Slot == nil and "none" or Slot
  if InstanceState.CopyBackups[SlotKey] == nil then
    local Index = TryCall(json.load_file, BackupIndexPath(Slot))
    InstanceState.CopyBackups[SlotKey] = type(Index) == "table" and type(Index.list) == "table" and Index.list or {}
  end
  
  return InstanceState.CopyBackups[SlotKey]
end

-- Any fog file (all slots)

--- @brief Every NG+ fog file in the data folder: ring snapshots, legacy files and backups of all slots, sorted by path.
--- fs.glob walks the folder on disk, so the list is cached and rebuilt only when bRefresh is true or a backup was added.
local function GetAllFogFiles(bRefresh)
  if InstanceState.AllFogFiles ~= nil and bRefresh ~= true then return InstanceState.AllFogFiles, InstanceState.AllFogFileNames end

  local FoundPaths = TryCall(function() return fs.glob([[NGPlusFog\\.*slot_.*\.json]]) end) or {}
  local FogFiles = {}
  for _, FoundPath in ipairs(FoundPaths) do
    local FilePath = type(FoundPath) == "string" and FoundPath:gsub("\\", "/") or nil
    local bIsFogFile = FilePath ~= nil and FilePath:match("_index%.json$") == nil
    if bIsFogFile == true then FogFiles[#FogFiles + 1] = { file = FilePath, name = FilePath:sub(#DataDirectory + 1) } end
  end
  table.sort(FogFiles, function(Lhs, Rhs) return Lhs.name < Rhs.name end)

  local FogFileNames = {}
  for FileIndex, FogFile in ipairs(FogFiles) do FogFileNames[FileIndex] = FogFile.name end
  InstanceState.AllFogFiles, InstanceState.AllFogFileNames, InstanceState.SelectedFogFileInfo = FogFiles, FogFileNames, nil
  return FogFiles, FogFileNames
end

--- @brief One line about a fog file's contents (play time and sequence), read from the file itself
local function DescribeFogFile(FogFile)
  local FogData = FogFile ~= nil and ReadValidFile(FogFile.file) or nil
  if FogData == nil then return "unreadable" end
  return "play time " .. FormatPlayTime(FogData.play) .. (FogData.seq ~= nil and ", save #" .. FogData.seq or "")
end

--- @brief Saves the current NG+ fog as a timestamped backup; returns false if the backup could not be written and read back
local function BackupNgPlusFog(Slot)
  local Backups, MaskHex = GetCopyBackups(Slot), {}
  for MaskKey, Private in pairs(InstanceState.PrivateMasks) do MaskHex[MaskKey] = Masks.HexOf(Private) end
  local PlayTime = ReadTimes()
  local Entry = {
    name = os.date("%Y-%m-%d %H:%M:%S") .. "  (play time " .. FormatPlayTime(PlayTime) .. ")",
    file = DataDirectory .. "backups/slot_" .. tostring(Slot) .. "_" .. os.date("%Y%m%d_%H%M%S") .. "_" .. (#Backups + 1) .. ".json",
  }

  local BackupData = { version = 1, play = PlayTime, masks = MaskHex }
  local bIsBackupVerified = pcall(json.dump_file, Entry.file, BackupData) == true and ReadValidFile(Entry.file) ~= nil
  if bIsBackupVerified == false then return false end

  Backups[#Backups + 1] = Entry
  pcall(json.dump_file, BackupIndexPath(Slot), { list = Backups })

  InstanceState.SelectedBackupIndex, InstanceState.AllFogFiles = #Backups, nil -- the new backup appears in the all-files list

  return true
end

--- @brief Loads any fog file (another slot, an older snapshot, a backup) into the current NG+ fog, after backing up the current NG+ fog
local function LoadFogFile(FogFile)
  local FogData = FogFile ~= nil and ReadValidFile(FogFile.file) or nil
  if FogData == nil then InstanceState.LoadedFogNote = "fog file unreadable: " .. tostring(FogFile ~= nil and FogFile.name or nil); return end
  if BackupNgPlusFog(InstanceState.CurrentSlot) == false then InstanceState.LoadedFogNote = "load cancelled: the backup could not be written"; return end

  InstanceState.SavedMaskHex = FogData.masks
  Persistence.ApplySavedMasks()
  InstanceState.LoadedFogNote = "NG+ fog loaded from " .. FogFile.name .. " (backup created; written to the fog files at the next game save)"
end  

local function RevertToBackup(Slot, BackupIndex)
  local Entry = GetCopyBackups(Slot)[BackupIndex]
  local Backup = Entry ~= nil and ReadValidFile(Entry.file) or nil
  if Backup == nil then InstanceState.LoadedFogNote = "backup unreadable: " .. tostring(Entry ~= nil and Entry.name or nil); return end
  
  InstanceState.SavedMaskHex = Backup.masks
  Persistence.ApplySavedMasks()
  InstanceState.LoadedFogNote = "NG+ fog reverted to backup " .. Entry.name .. " (written to the fog files at the next game save)"
end

--- @brief Copies the save's own fog (previous exploration) into the NG+ fog. Backs up the current NG+ fog first
local function CopyRealProgress()
  if BackupNgPlusFog(InstanceState.CurrentSlot) == false then InstanceState.LoadedFogNote = "copy cancelled: the backup could not be written"; return end

  Masks.IndexGameMasks()
  for _, Entry in pairs(InstanceState.GameMasks) do
    local Private, GameArray = Masks.GetPrivateMask(Entry), GetField(Entry.Object, "MaskBit")
    if Private ~= nil and GameArray ~= nil and AddressOf(GameArray) ~= AddressOf(Private.Bits) and ArrayLength(GameArray) == Private.WordCount then
      for WordIndex = 0, Private.WordCount - 1 do
        WriteWord(Private.Bits, WordIndex, ReadWord(Private.Bits, WordIndex) | ReadWord(GameArray, WordIndex))
      end
    end
  end

  InstanceState.bRedrawRequested = true
  local Backups = GetCopyBackups(InstanceState.CurrentSlot)
  InstanceState.LoadedFogNote = "real progress copied into the NG+ fog; backup " .. Backups[#Backups].name .. " created"
end

return {
  GetCopyBackups   = GetCopyBackups,
  GetAllFogFiles   = GetAllFogFiles,
  DescribeFogFile  = DescribeFogFile,
  LoadFogFile      = LoadFogFile,
  RevertToBackup   = RevertToBackup,
  CopyRealProgress = CopyRealProgress,
}
