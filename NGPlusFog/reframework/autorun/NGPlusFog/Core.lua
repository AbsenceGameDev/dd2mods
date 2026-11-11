--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Core
  Helpers: 
  - protected calls
  - field access
  - raw array words
  - printable values
  - hooks
]]

--
-- NG+ Fog, state and settings setup
local Definitions = require("NGPlusFog.Definitions")
local State       = require("NGPlusFog.State")

local InstanceSettings, InstanceState = State.Settings, State.Instance
local DataOffset <const>     = Definitions.ManagedArrayByteDataOffset
local GuiManagerType <const> = Definitions.GuiManagerType

--
-- Helpers
--- @brief protected wrapper; returns its first result of function, or nil if an error was raised
local function TryCall(Function, ...)
  local bSucceeded, Result = pcall(Function, ...)
  if bSucceeded == true then return Result end
end

local function GetGuiManager() return sdk.get_managed_singleton(GuiManagerType) end
local function AddressOf(Object)
  if Object == nil then return nil end
  return TryCall(function() return Object:get_address() end)
end
--- @brief Field value of a managed object; nil if the object is nil or if the read fails (a false field stays false)
local function GetField(Object, FieldName)
  if Object == nil then return nil end
  return TryCall(function() return Object:get_field(FieldName) end)
end
local function HookThis(Args) return TryCall(sdk.to_managed_object, Args[2]) end
local function ArrayLength(Array)
  if Array == nil then return nil end
  return TryCall(function() return Array:call("get_Length") end)
end
local function ReadWord(Array, WordIndex) return Array:read_dword(DataOffset + 4 * WordIndex) end
local function WriteWord(Array, WordIndex, Word) Array:write_dword(DataOffset + 4 * WordIndex, Word) end
local function Now() return os.clock() end
local function Increment(CounterName) InstanceState.Counters[CounterName] = (InstanceState.Counters[CounterName] or 0) + 1 end

--- @brief Returns the x, y, z components of a vector, if valid vector
local function Components(Vector)
  if Vector == nil then return end
  local ComponentX = TryCall(function() return Vector.x end)
  if type(ComponentX) ~= "number" then return end
  return ComponentX, TryCall(function() return Vector.y end), TryCall(function() return Vector.z end)
end

--- @brief Printable form of a value: numbers & booleans as-is, vectors as "x, y" or "x, y, z", objects as PRIVATE / GAME:<key> / obj@<address>
local function Describe(Value)
  if type(Value) ~= "userdata" then return Value end
  local ComponentX, ComponentY, ComponentZ = Components(Value)
  if ComponentX ~= nil then
    return ComponentZ ~= nil and string.format("%.2f, %.2f, %.2f", ComponentX, ComponentY, ComponentZ) or string.format("%s, %s", ComponentX, ComponentY)
  end
  local Address = AddressOf(Value)
  if Address == nil then return tostring(Value) end
  if InstanceState.PrivateMaskAddresses[Address] == true then return "PRIVATE" end
  if InstanceState.GameMasks[Address] ~= nil then return "GAME:" .. InstanceState.GameMasks[Address].Key end
  return string.format("obj@%x", Address)
end

--- @brief Returns a table of named fields of an object, in printable form
local function DescribeFields(Object, FieldNames)
  local Description = {}
  for _, FieldName in ipairs(FieldNames) do Description[FieldName] = Describe(GetField(Object, FieldName)) end
  return Description
end

--- @brief Hooks a method by "name(params)" signature. Store result if it succeeded or not
local function InstallHook(TypeName, Signature, PreHook, PostHook)
  local MethodName = Signature:gsub("%(%)$", "")
  local Method = TryCall(function() return sdk.find_type_definition(TypeName):get_method(MethodName) end)
  InstanceState.HookResults[TypeName .. "::" .. Signature] = Method ~= nil and pcall(sdk.hook, Method, PreHook, PostHook)
end

--- @brief Runs a tree node's body protected. Errors are shown as text and the node always pops
local function TreeNode(Label, DrawBody)
  if imgui.tree_node(Label) == false then return end

  local bSucceeded, ErrorMessage = pcall(DrawBody)
  if bSucceeded == false then imgui.text("panel error: " .. tostring(ErrorMessage)) end

  imgui.tree_pop()
end

--- @brief True while the NG+ fog of war is shown (fog on, NG+ save, real-progress view off); cached per tick, read by hooks
local function IsNgPlusFogShown() return InstanceState.bActive == true and InstanceSettings.bShowRealMapProgress == false end

return {
  TryCall          = TryCall,
  GetGuiManager    = GetGuiManager,
  AddressOf        = AddressOf,
  GetField         = GetField,
  HookThis         = HookThis,
  ArrayLength      = ArrayLength,
  ReadWord         = ReadWord,
  WriteWord        = WriteWord,
  Now              = Now,
  Increment        = Increment,
  Components       = Components,
  Describe         = Describe,
  DescribeFields   = DescribeFields,
  InstallHook      = InstallHook,
  IsNgPlusFogShown = IsNgPlusFogShown,
  TreeNode         = TreeNode,
}
