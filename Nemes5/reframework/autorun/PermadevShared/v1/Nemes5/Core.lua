--[[ @author: https://github.com/AbsenceGameDev. PermadevShared v1 - Core
  Helpers shared by Permadev mods:
  - protected calls
  - field access
  - hooks
  - protected tree nodes
  Holds no mod state: anything kept per mod (hook results) is passed in by the caller.
]]

--
-- Helpers
--- @brief protected wrapper; returns its first result of function, or nil if an error was raised
local function TryCall(Function, ...)
  local bSucceeded, Result = pcall(Function, ...);
  if bSucceeded == true then return Result end;
end

local function AddressOf(Object)
  if Object == nil then return nil end;
  return TryCall(function() return Object:get_address() end);
end

--- @brief Field value of a managed object; nil if the object is nil or if the read fails (a false field stays false)
local function GetField(Object, FieldName)
  if Object == nil then return nil end;
  return TryCall(function() return Object:get_field(FieldName) end);
end

local function HookThis(Args) return TryCall(sdk.to_managed_object, Args[2]) end;

local function ArrayLength(Array)
  if Array == nil then return nil end;
  return TryCall(function() return Array:call("get_Length") end);
end

local function Now() return os.clock() end;

--- @brief Returns the x, y, z components of a vector, if valid vector
local function Components(Vector)
  if Vector == nil then return end;
  local ComponentX = TryCall(function() return Vector.x end);
  if type(ComponentX) ~= "number" then return end;
  return ComponentX, TryCall(function() return Vector.y end), TryCall(function() return Vector.z end);
end

--- @brief Hooks a method by "name(params)" signature and stores whether it succeeded in HookResults["type::signature"]
local function InstallHook(HookResults, TypeName, Signature, PreHook, PostHook)
  local MethodName = Signature:gsub("%(%)$", "");
  local Method = TryCall(function() return sdk.find_type_definition(TypeName):get_method(MethodName) end);
  HookResults[TypeName .. "::" .. Signature] = Method ~= nil and pcall(sdk.hook, Method, PreHook, PostHook);
end

--- @brief Runs a tree node's body protected. Errors are shown as text and the node always pops
local function TreeNode(Label, DrawBody)
  if imgui.tree_node(Label) == false then return end;

  local bSucceeded, ErrorMessage = pcall(DrawBody);
  if bSucceeded == false then imgui.text("panel error: " .. tostring(ErrorMessage)) end;

  imgui.tree_pop();
end

return {
  TryCall     = TryCall,
  AddressOf   = AddressOf,
  GetField    = GetField,
  HookThis    = HookThis,
  ArrayLength = ArrayLength,
  Now         = Now,
  Components  = Components,
  InstallHook = InstallHook,
  TreeNode    = TreeNode,
};
