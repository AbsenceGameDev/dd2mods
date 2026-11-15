--[[ @author: https://github.com/AbsenceGameDev. Nemes!5: Toil & Trouble - Shared
  Resolves shared library version: the newest installed version, provided by existing Permadev mods,
  - Each mod ships its own copy under its own name (autorun/PermadevShared/v<N>/<Mod>/) with a marker file
    (data/PermadevShared/versions/v<N>_<Mod>.json), so mods don't ship the same file-path and uninstalling a mod doesn't remove a copy another mod uses.
  Hope is that fluffymodmanager allows scriptable installs/uninstalls in the future which would allow this to make more sense
]]

local BundledVersion <const>  = 1;
local BundledProvider <const> = "Nemes5";
local MarkerPattern <const>   = [[PermadevShared\\versions\\v\d+_\w+\.json]];

--- @brief Sort rank of a copy at equal versions. @note sorts this mod's own copy first, then by name of mod/provider
local function ProviderRank(Copy) return Copy.Provider == BundledProvider and "" or Copy.Provider end;

local function ListNewerCopies()
  local Copies = {};
  local bGlobbed, MarkerPaths = pcall(function() return fs.glob(MarkerPattern) end);
  if bGlobbed == false or type(MarkerPaths) ~= "table" then return Copies, nil end;

  for _, MarkerPath in ipairs(MarkerPaths) do
    local VersionText, Provider = tostring(MarkerPath):match("v(%d+)_([%w_]+)%.json$");
    local Version = math.tointeger(tonumber(VersionText or ""));

    local bIsNewer = Version ~= nil and Version > BundledVersion;
    if bIsNewer == true then Copies[#Copies + 1] = { Version = Version, Provider = Provider } end;
  end

  table.sort(Copies, function(Lhs, Rhs)
    if Lhs.Version ~= Rhs.Version then return Lhs.Version > Rhs.Version end;
    return ProviderRank(Lhs) < ProviderRank(Rhs);
  end);

  return Copies, MarkerPaths;
end

--- @brief The library loads a copy of shared data, based on what is available
local function LoadCopy(Version, Provider)
  local Prefix = "PermadevShared.v" .. Version .. "." .. Provider .. ".";
  local bLoaded, Library = pcall(function()
    return { Core = require(Prefix .. "Core"), Persistence = require(Prefix .. "Persistence"), ProbeLog = require(Prefix .. "ProbeLog") };
  end);
  if bLoaded == false then return nil end;

  Library.Version, Library.Provider, Library.Prefix = Version, Provider, Prefix;
  return Library;
end

--- @brief The newest copy that loads; a copy listed by its marker but missing its files is skipped
local function Resolve()
  local Copies, MarkerPaths = ListNewerCopies();
  local SkippedCopies = {};
  for _, Copy in ipairs(Copies) do
    local Library = LoadCopy(Copy.Version, Copy.Provider);

    if Library ~= nil 
      then Library.MarkerPaths, Library.SkippedCopies = MarkerPaths, SkippedCopies; 
      return Library 
    end;
    
    SkippedCopies[#SkippedCopies + 1] = Copy.Provider .. " v" .. Copy.Version;
  end

  local Library = LoadCopy(BundledVersion, BundledProvider);
  Library.MarkerPaths, Library.SkippedCopies = MarkerPaths, SkippedCopies;
  return Library;
end

return Resolve();
