--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Masks
  The game's own fog masks (MapMaskInfo), their private copies, bitmap helpers, and the exploration mirror
  that repeats each of the game's setMaskOff calls on the private copy.
]]

--
-- NG+ Fog
local Definitions = require("NGPlusFog.Definitions");
local State       = require("NGPlusFog.State");
local Core        = require("NGPlusFog.Core");
local Scope       = require("NGPlusFog.Scope");
local InstanceState = State.Instance;

-- func shorthands 
local TryCall, GetGuiManager, AddressOf, GetField = Core.TryCall, Core.GetGuiManager, Core.AddressOf, Core.GetField;
local HookThis, ArrayLength, ReadWord, WriteWord = Core.HookThis, Core.ArrayLength, Core.ReadWord, Core.WriteWord;
local Now, Increment, Components, Describe = Core.Now, Core.Increment, Core.Components, Core.Describe;

local LengthOffset <const>        = Definitions.ManagedArrayByteLengthFieldOffset;
local SetMaskOffSignature <const> = Definitions.SetMaskOffSignature;
local GeometryFields <const>      = Definitions.GeometryFields;

--
-- Game masks and private copies

--- @brief Rebuilds the address -> mask table from GuiManager.MapMaskField (Definitions.OverworldMaskKey) and MapMaskLocalArea[] ("L<index>")
local function IndexGameMasks()
  local GuiManager = GetGuiManager()
  if GuiManager == nil then return end

  local Masks, FieldMask = {}, GetField(GuiManager, "MapMaskField")
  if FieldMask ~= nil then Masks[AddressOf(FieldMask)] = { Key = Definitions.OverworldMaskKey, Object = FieldMask } end

  local LocalAreaMasks = GetField(GuiManager, "MapMaskLocalArea")
  for AreaIndex = 0, (ArrayLength(LocalAreaMasks) or 0) - 1 do
    local AreaMask = TryCall(function() return LocalAreaMasks:get_element(AreaIndex) end)
    if AreaMask ~= nil then Masks[AddressOf(AreaMask)] = { Key = "L" .. AreaIndex, Object = AreaMask } end
  end

  InstanceState.GameMasks, InstanceState.LastIndexTime = Masks, Now()
end

--- @brief Returns the game-mask entry for an address, re-indexing at most once per second for unknown addresses
local function FindGameMask(Address)
  if Address == nil or InstanceState.PrivateMaskAddresses[Address] == true then return nil end

  local Entry = InstanceState.GameMasks[Address]
  if Entry == nil and Now() - InstanceState.LastIndexTime > 1.0 then IndexGameMasks(); Entry = InstanceState.GameMasks[Address] end
  
  return Entry
end

---- bitmask helpers
local function ApplyHex(Private, Hex)
  if type(Hex) ~= "string" or #Hex ~= Private.WordCount * 8 then return false end
  for WordIndex = 0, Private.WordCount - 1 do
    WriteWord(Private.Bits, WordIndex, tonumber(Hex:sub(WordIndex * 8 + 1, WordIndex * 8 + 8), 16))
  end
  return true
end
local function ClearBits(Private) for WordIndex = 0, Private.WordCount - 1 do WriteWord(Private.Bits, WordIndex, 0) end end
local function HexOf(Private)
  local Words = {}
  for WordIndex = 0, Private.WordCount - 1 do Words[WordIndex + 1] = string.format("%08x", ReadWord(Private.Bits, WordIndex) & 0xFFFFFFFF) end
  return table.concat(Words)
end

--- @brief Number of set bits (revealed cells) in a UInt32 array
local function CountRevealedCells(Array, WordCount)
  local CellCount = 0
  for WordIndex = 0, WordCount - 1 do
    local Word = ReadWord(Array, WordIndex) & 0xFFFFFFFF
    while Word ~= 0 do Word = Word & (Word - 1); CellCount = CellCount + 1 end
  end

  return CellCount
end

--- @brief Checks the ASSUMED raw array layout against the array's own length and GetValue
local function IsArrayLayoutValid(Array, WordCount)
  if TryCall(function() return Array:read_dword(LengthOffset) end) ~= WordCount then return false end

  WriteWord(Array, WordCount - 1, 0xA5A5A5A5)
  local Boxed = TryCall(function() return Array:call("GetValue", WordCount - 1) end)
  local Value = type(Boxed) == "userdata" and TryCall(function() return Boxed:get_field("m_value") end) or Boxed
  WriteWord(Array, WordCount - 1, 0)
  
  return Value == nil or (math.tointeger(Value) or 0) & 0xFFFFFFFF == 0xA5A5A5A5
end

local function NewWordArray(WordCount)
  local Array = TryCall(sdk.create_managed_array, "System.UInt32", WordCount)
  if Array ~= nil then Array:add_ref() end

  return Array
end

--- @brief Keeps a private copy's grid identical to the game's (the game re-inits its masks after load: 512x512 -> 512x516)
local function SyncGeometry(Private, GameMask)
  if Now() - (Private.LastSync or -1) < 2.0 then return end
  Private.LastSync = Now()
  local WordCount = ArrayLength(GetField(GameMask, "MaskBit"))
  if WordCount ~= nil and WordCount > 0 and WordCount ~= Private.WordCount then
    local Resized = NewWordArray(WordCount)
    if Resized == nil then return end
    
    for WordIndex = 0, math.min(WordCount, Private.WordCount) - 1 
      do WriteWord(Resized, WordIndex, ReadWord(Private.Bits, WordIndex)) end

    Private.MaskInfo:set_field("MaskBit", Resized); Private.Bits, Private.WordCount = Resized, WordCount
  end

  for _, FieldName in ipairs(GeometryFields) do
    local GameValue = GetField(GameMask, FieldName)
    local bIsFieldOutOfSync = GameValue ~= nil and Describe(GameValue) ~= Describe(GetField(Private.MaskInfo, FieldName));
    if bIsFieldOutOfSync == true then
      pcall(function() Private.MaskInfo:set_field(FieldName, GameValue) end)
    end
  end

  -- Cached grid for fast lookups: cell = floor((position - BasePos) / Interval), bit index = row * MaskNum.x + column
  Private.BaseX, Private.BaseZ = Components(GetField(Private.MaskInfo, "BasePos"))
  Private.CellsX, Private.CellsZ = Components(GetField(Private.MaskInfo, "MaskNum"))
  Private.CellSize = GetField(Private.MaskInfo, "Interval")
end

--- @brief true/false for a world position inside the mask; nil outside it (treated as not fogged)
local function IsRevealed(Mask, WorldX, WorldZ)
  if Mask == nil or Mask.CellSize == nil or Mask.CellsX == nil then return nil end
  local Column = math.floor((WorldX - Mask.BaseX) / Mask.CellSize)
  local Row = math.floor((WorldZ - Mask.BaseZ) / Mask.CellSize)
  if Column < 0 or Row < 0 or Column >= Mask.CellsX or Row >= Mask.CellsZ then return nil end
  local BitIndex = math.tointeger(Row * Mask.CellsX + Column)
  return (ReadWord(Mask.Bits, BitIndex >> 5) >> (BitIndex & 31)) & 1 == 1
end

--- @brief Returns the private copy for a game mask, creating it (MemberwiseClone + own UInt32[]) on first use
local function GetPrivateMask(Entry)
  local Private = InstanceState.PrivateMasks[Entry.Key]
  if Private ~= nil then SyncGeometry(Private, Entry.Object); return Private end

  local WordCount = ArrayLength(GetField(Entry.Object, "MaskBit"))
  if WordCount == nil or WordCount == 0 or InstanceState.bArrayLayoutValid == false then return nil end

  local MaskInfo, Bits = TryCall(function() return Entry.Object:call("MemberwiseClone") end), NewWordArray(WordCount)
  if MaskInfo == nil or Bits == nil then return nil end

  MaskInfo:add_ref()
  if InstanceState.bArrayLayoutValid == nil then
    InstanceState.bArrayLayoutValid = IsArrayLayoutValid(Bits, WordCount)
    if InstanceState.bArrayLayoutValid == false then InstanceState.Status = "HALTED: managed array layout differs from the ASSUMED offsets"; return nil end
  end

  MaskInfo:set_field("MaskBit", Bits)
  Private = { MaskInfo = MaskInfo, Bits = Bits, WordCount = WordCount, Key = Entry.Key }
  if ApplyHex(Private, InstanceState.SavedMaskHex[Entry.Key]) == false then ClearBits(Private) end

  InstanceState.PrivateMasks[Entry.Key], InstanceState.PrivateMaskAddresses[AddressOf(MaskInfo)] = Private, true
  SyncGeometry(Private, Entry.Object)
  
  return Private
end

--- @brief Every fog mask (overworld, caves, interiors) gets a private copy as soon as it exists, fully fogged unless saved NG+ data exists;
--- @note Masks the game initialises later (empty MaskBit) are picked up by the next check.
local function EnsurePrivateMasks()
  if Now() - (InstanceState.LastEnsureTime or -1) < 1.0 then return end

  InstanceState.LastEnsureTime = Now()
  if next(InstanceState.GameMasks) == nil or Now() - InstanceState.LastIndexTime > 5.0 then IndexGameMasks() end
  
  for _, Entry in pairs(InstanceState.GameMasks) do GetPrivateMask(Entry) end
end

--
-- Exploration: mirror the game's own reveal calls
local function InstallHooks()
  Core.InstallHook(Definitions.MaskInfoType, SetMaskOffSignature, function(Args)
    if InstanceState.bActive ~= true then return end

    local Entry = FindGameMask(AddressOf(HookThis(Args)))
    if Entry == nil then return end -- not a game mask (or one of the mod's own copies)
    
    local Private = GetPrivateMask(Entry)
    if Private == nil then return end
    
    local WorldX, WorldY, WorldZ = Components(TryCall(sdk.to_valuetype, Args[3], "via.vec3"))
    if WorldX == nil then Increment("reveal_position_unreadable"); return end
    
    if Scope.RunScoped(function() return Private.MaskInfo:call(SetMaskOffSignature, Vector3f.new(WorldX, WorldY, WorldZ)) end) == true then
      InstanceState.bRedrawRequested = true
    end
  end, nil)
end

return {
  IndexGameMasks     = IndexGameMasks,
  ApplyHex           = ApplyHex,
  ClearBits          = ClearBits,
  HexOf              = HexOf,
  CountRevealedCells = CountRevealedCells,
  IsRevealed         = IsRevealed,
  GetPrivateMask     = GetPrivateMask,
  EnsurePrivateMasks = EnsurePrivateMasks,
  InstallHooks       = InstallHooks,
}
