--[[ @author: https://github.com/AbsenceGameDev. NG+ Fog - Widgets
  Drawing helpers for custom windows: colours, text, badges, bars, buttons, panels, and click areas.
  - Everything draws into the current ImGui window's draw list (imgui.get_window_draw_list), so it appears inside that window,
    above its background. REFramework's draw.* functions paint behind every ImGui window and cannot be used for this.
    
  - Click areas are invisible buttons placed at a screen position; the drawing is done separately
]]

--
-- Colours

--- @brief ImGui colour (ABGR) from 0xRRGGBB and an optional alpha (0..255)
local function Color(Rgb, Alpha)
  return ((Alpha or 255) << 24) | ((Rgb & 0xFF) << 16) | (Rgb & 0xFF00) | ((Rgb >> 16) & 0xFF);
end

local Theme <const> = {
  Panel = Color(0x1F2125), Card = Color(0x25282D), CardHover = Color(0x2C3036), Border = Color(0x363A41),
  Selected = Color(0x22344F), SelectedBorder = Color(0x3C82DC), RowHover = Color(0x2A2E34), RowSelected = Color(0x26406A),
  Text = Color(0xD8DCE2), TextBright = Color(0xF2F4F7), TextDim = Color(0x8A919B), Accent = Color(0x6EA8FF),
  Green = Color(0x58C46E), Amber = Color(0xE0A830), Purple = Color(0xC07CE0), Grey = Color(0x9AA3AE),
  WarningFill = Color(0x2E2614), WarningBorder = Color(0x8A6A22),
  Primary = Color(0x2F6FD6), PrimaryHover = Color(0x3D7FE6), Button = Color(0x353A42), ButtonHover = Color(0x414750),
  BarBack = Color(0x3A3F47), BarFill = Color(0x6E9FD1),
};

--
-- Drawing

local function Point(X, Y) return Vector2f.new(X, Y) end;

local function Rect(DrawList, X, Y, Width, Height, Fill, Border, Rounding)
  DrawList:add_rect_filled(Point(X, Y), Point(X + Width, Y + Height), Fill, Rounding or 3.0, 0);
  if Border ~= nil then DrawList:add_rect(Point(X, Y), Point(X + Width, Y + Height), Border, Rounding or 3.0, 0, 1.0) end;
end

local function Text(DrawList, X, Y, TextColor, Value) DrawList:add_text(Point(X, Y), TextColor, Value) end;

local function TextWidth(Value) return imgui.calc_text_size(Value).x end;

--- @brief Text ending at X (right-aligned)
local function TextRight(DrawList, X, Y, TextColor, Value) Text(DrawList, X - TextWidth(Value), Y, TextColor, Value) end;

local function Line(DrawList, X1, Y1, X2, Y2, LineColor) DrawList:add_line(Point(X1, Y1), Point(X2, Y2), LineColor, 1.0) end;

--- @brief Restricts drawing to a rectangle until PopClip
local function PushClip(DrawList, X, Y, Width, Height) DrawList:push_clip_rect(Point(X, Y), Point(X + Width, Y + Height), true) end;
local function PopClip(DrawList) DrawList:pop_clip_rect() end;

--- @brief A small outlined label (MATCHES LOADED SAVE, BACKUP, ...); returns its width
local function Badge(DrawList, X, Y, LineHeight, BadgeColor, Label)
  local Width = TextWidth(Label) + 10;
  Rect(DrawList, X, Y - 2, Width, LineHeight + 4, Color(0x000000, 0), BadgeColor, 2.0);
  Text(DrawList, X + 5, Y, BadgeColor, Label);
  return Width;
end

--- @brief A thin progress bar, Fraction 0..1
local function Bar(DrawList, X, Y, Width, Height, Fraction)
  Rect(DrawList, X, Y, Width, Height, Theme.BarBack, nil, 1.0);
  Rect(DrawList, X, Y, Width * math.max(0, math.min(1, Fraction)), Height, Theme.BarFill, nil, 1.0);
end

--
-- Interaction

--- @brief An invisible click area at a screen position; returns bClicked, bHovered
local function HitArea(Id, X, Y, Width, Height)
  imgui.set_cursor_screen_pos(Point(X, Y));
  local bClicked = imgui.invisible_button(Id, Point(math.max(1, Width), math.max(1, Height))) == true;
  return bClicked, imgui.is_item_hovered() == true;
end

--- @brief A drawn button with a centred label; returns true when clicked
local function Button(DrawList, Id, X, Y, Width, Height, Label, bPrimary)
  local bClicked, bHovered = HitArea(Id, X, Y, Width, Height);
  local Fill = bPrimary == true and (bHovered == true and Theme.PrimaryHover or Theme.Primary) or (bHovered == true and Theme.ButtonHover or Theme.Button);
  Rect(DrawList, X, Y, Width, Height, Fill);
  local LabelSize = imgui.calc_text_size(Label);
  Text(DrawList, X + (Width - LabelSize.x) / 2, Y + (Height - LabelSize.y) / 2, Theme.TextBright, Label);
  return bClicked;
end

--- @brief true when every function the widgets need exists in this REFramework build, and which ones exist
local function GetCapabilities()
  local Capabilities = {
    get_window_draw_list = type(imgui.get_window_draw_list) == "function",
    set_cursor_screen_pos = type(imgui.set_cursor_screen_pos) == "function",
    begin_window = type(imgui.begin_window) == "function",
    begin_child_window = type(imgui.begin_child_window) == "function",
    calc_text_size = type(imgui.calc_text_size) == "function",
  };
  local bComplete = true;
  for _, bPresent in pairs(Capabilities) do bComplete = bComplete and bPresent end;
  return Capabilities, bComplete;
end

return {
  Color           = Color,
  Theme           = Theme,
  Rect            = Rect,
  Text            = Text,
  TextWidth       = TextWidth,
  TextRight       = TextRight,
  Line            = Line,
  PushClip        = PushClip,
  PopClip         = PopClip,
  Badge           = Badge,
  Bar             = Bar,
  HitArea         = HitArea,
  Button          = Button,
  GetCapabilities = GetCapabilities,
};
