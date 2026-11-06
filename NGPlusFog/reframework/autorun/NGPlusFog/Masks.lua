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


-- Game masks and private copies
--- @brief Rebuilds the address -> mask table from GuiManager.MapMaskField (Definitions.OverworldMaskKey) and MapMaskLocalArea[] ("L<index>")
local function IndexGameMasks()
end

---- bitmask helpers
local function ApplyHex(Private, Hex)
end
local function ClearBits(Private) end
local function HexOf(Private) end

--- @brief Number of set bits (revealed cells) in a UInt32 array
local function CountRevealedCells(Array, WordCount) end

--- @brief true/false for a world position inside the mask; nil outside it (treated as not fogged)
local function IsRevealed(Mask, WorldX, WorldZ) end

--- @brief Returns the private copy for a game mask, creating it (MemberwiseClone + own UInt32[]) on first use
local function GetPrivateMask(Entry) end

--- @brief Every fog mask (overworld, caves, interiors) gets a private copy as soon as it exists, fully fogged unless saved NG+ data exists;
--- @note Masks the game initialises later (empty MaskBit) are picked up by the next check.
local function EnsurePrivateMasks() end

--
-- Exploration: mirror the game's own reveal calls
local function InstallHooks() end

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
