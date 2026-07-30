-- @description YSL Tools - Item Envelope Manager
-- @version 1.5.0
-- @author Yoon-Soo Lee
-- @link https://github.com/Leeyounsu0123/YSL-ReaPack
-- @changelog
--   + Reduces waveform draw density while preserving the visible peak shape and
--     editable curve overlay.
--   + Polls REAPER item selection at a short interval instead of rescanning every
--     selected item multiple times per UI frame.
--   + Caches native Take-envelope enabled state to avoid repeated state-chunk reads.
--   + Keeps multi-range editing, native Volume/Pitch/Pan envelopes, Speed Preview,
--     user presets, and bilingual controls intact.
-- @about
--   # Item Envelope Manager
--   A compact non-destructive sound-design editor for Volume, Pitch, Pan, and Speed curves.
--
--   ## Workflow
--   1. Select audio items, drag one region, then Ctrl+drag to add more regions.
--   2. Choose Volume, Pitch, Pan, or Speed.
--   3. The current curve is previewed over that exact waveform region.
--   4. Edit points, Alt+drag a segment for curvature, or load a preset.
--   5. Open/close Volume, Pitch, and Pan envelopes without deleting their points.
--   6. Apply maps every representative range proportionally to all selected items.
--   7. Speed uses replaceable Preview Takes for safe A/B, Commit, and Original Restore.
--
--   ## Requirements
--   - REAPER 7.0 or later
--   - ReaImGui 0.9.2 or later
--
--   ## License
--   Copyright (c) 2026 Yoon-Soo Lee. All rights reserved.
--   Redistribution, resale, or secondary distribution requires written permission.
-- @provides
--   [main] .

local APP_NAME = 'Item Envelope Manager'
local APP_VERSION = '1.5.0'
local WINDOW_ID = '###YSL_Item_Envelope_Manager_v1_5_0'
local MIN_REAPER_MAJOR = 7
local INSTANCE_SECTION = 'YSL_ITEM_ENVELOPE_MANAGER_V15'
local INSTANCE_TIMEOUT = 3.0

local function parse_major(text)
  return tonumber(tostring(text or ''):match('^(%d+)')) or 0
end

if parse_major(reaper.GetAppVersion and reaper.GetAppVersion() or '0') < MIN_REAPER_MAJOR then
  reaper.MB('REAPER 7.0 이상이 필요합니다.', APP_NAME, 0)
  return
end

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB(
    'ReaImGui가 필요합니다.\n\nExtensions > ReaPack > Browse packages에서 ReaImGui를 설치해주세요.',
    APP_NAME .. ' - Missing dependency', 0)
  return
end

-- -----------------------------------------------------------------------------
-- Graceful single-instance handling
-- A second action launch asks the existing instance to close after its current
-- ImGui frame, instead of force-killing a docked context.
-- -----------------------------------------------------------------------------
local now = reaper.time_precise()
local previous_token = reaper.GetExtState(INSTANCE_SECTION, 'RUN_TOKEN')
local previous_heartbeat = tonumber(reaper.GetExtState(INSTANCE_SECTION, 'HEARTBEAT')) or 0
if previous_token ~= '' and now - previous_heartbeat < INSTANCE_TIMEOUT then
  reaper.SetExtState(INSTANCE_SECTION, 'CLOSE_REQUEST', previous_token, false)
  return
end

local instance_token = reaper.genGuid()
reaper.SetExtState(INSTANCE_SECTION, 'RUN_TOKEN', instance_token, false)
reaper.SetExtState(INSTANCE_SECTION, 'HEARTBEAT', tostring(now), false)
reaper.DeleteExtState(INSTANCE_SECTION, 'CLOSE_REQUEST', false)

local _, _, action_section, action_command = reaper.get_action_context()
local action_kbd_section = nil
if action_section and action_section >= 0 and reaper.SectionFromUniqueID then
  action_kbd_section = reaper.SectionFromUniqueID(action_section)
end

local function set_action_toggle(enabled)
  if action_section and action_command and action_command > 0 then
    reaper.SetToggleCommandState(action_section, action_command, enabled and 1 or 0)
    reaper.RefreshToolbar2(action_section, action_command)
  end
end
set_action_toggle(true)

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.2'

local context_flags = 0
do
  local ok, value = pcall(function() return ImGui.ConfigFlags_DockingEnable end)
  if ok and value then context_flags = value end
end

local ctx = ImGui.CreateContext(APP_NAME, context_flags)
local font = ImGui.CreateFont('sans-serif', 13)
ImGui.Attach(ctx, font)

-- -----------------------------------------------------------------------------
-- Focus-safe self-shortcut closing
-- REAPER cannot always receive an Action List shortcut while a ReaImGui window
-- owns keyboard focus. Read this script's keyboard bindings and detect them in
-- the ImGui context itself. The singleton close request remains as a fallback
-- when REAPER does receive the action launch.
-- -----------------------------------------------------------------------------
local function safe_imgui_constant(name)
  local ok, value = pcall(function() return ImGui[name] end)
  if ok then return value end
  return nil
end

local function safe_key_down(key)
  if not key then return false end
  local ok, value = pcall(ImGui.IsKeyDown, ctx, key)
  return ok and value or false
end

local function safe_key_pressed(key)
  if not key then return false end
  local ok, value = pcall(ImGui.IsKeyPressed, ctx, key, false)
  return ok and value or false
end

local KEY_ALIASES = {
  escape='Escape', esc='Escape', tab='Tab', space='Space', spacebar='Space',
  enter='Enter', returnkey='Enter', ['return']='Enter', backspace='Backspace',
  insert='Insert', ins='Insert', delete='Delete', del='Delete',
  home='Home', ['end']='End', pageup='PageUp', pgup='PageUp',
  pagedown='PageDown', pgdn='PageDown', left='LeftArrow', leftarrow='LeftArrow',
  right='RightArrow', rightarrow='RightArrow', up='UpArrow', uparrow='UpArrow',
  down='DownArrow', downarrow='DownArrow',
  minus='Minus', hyphen='Minus', equal='Equal', equals='Equal',
  comma='Comma', period='Period', dot='Period', slash='Slash',
  backslash='Backslash', semicolon='Semicolon', apostrophe='Apostrophe', quote='Apostrophe',
  leftbracket='LeftBracket', rightbracket='RightBracket', grave='GraveAccent',
  graveaccent='GraveAccent', backquote='GraveAccent',
  printscreen='PrintScreen', pause='Pause', capslock='CapsLock',
  scrolllock='ScrollLock', numlock='NumLock',
}

for i = 1, 24 do KEY_ALIASES['f' .. i] = 'F' .. i end
for i = 0, 9 do
  KEY_ALIASES[tostring(i)] = tostring(i)
  KEY_ALIASES['numpad' .. i] = 'Keypad' .. i
  KEY_ALIASES['keypad' .. i] = 'Keypad' .. i
  KEY_ALIASES['num' .. i] = 'Keypad' .. i
end
for code = string.byte('a'), string.byte('z') do
  local letter = string.char(code)
  KEY_ALIASES[letter] = letter:upper()
end
KEY_ALIASES.numpaddecimal = 'KeypadDecimal'
KEY_ALIASES.keypaddecimal = 'KeypadDecimal'
KEY_ALIASES.numpaddivide = 'KeypadDivide'
KEY_ALIASES.keypaddivide = 'KeypadDivide'
KEY_ALIASES.numpadmultiply = 'KeypadMultiply'
KEY_ALIASES.keypadmultiply = 'KeypadMultiply'
KEY_ALIASES.numpadsubtract = 'KeypadSubtract'
KEY_ALIASES.keypadsubtract = 'KeypadSubtract'
KEY_ALIASES.numpadadd = 'KeypadAdd'
KEY_ALIASES.keypadadd = 'KeypadAdd'
KEY_ALIASES.numpadenter = 'KeypadEnter'
KEY_ALIASES.keypadenter = 'KeypadEnter'
KEY_ALIASES.numpadequal = 'KeypadEqual'
KEY_ALIASES.keypadequal = 'KeypadEqual'

local function normalize_shortcut_token(token)
  token = tostring(token or ''):lower()
  token = token:gsub('^%s+', ''):gsub('%s+$', '')
  token = token:gsub('[%s_%-]', '')
  return token
end

local function parse_keyboard_shortcut(desc)
  desc = tostring(desc or '')
  if desc == '' then return nil end
  local lower = desc:lower()
  if lower:find('midi', 1, true) or lower:find('osc', 1, true)
      or lower:find('mousewheel', 1, true) or lower:find('mouse wheel', 1, true) then
    return nil
  end

  -- Some themes/localizations prepend a category before a colon.
  desc = desc:match(':%s*(.+)$') or desc
  local chord = {ctrl=false, shift=false, alt=false, super=false, desc=desc}
  local key_token = nil
  for token in desc:gmatch('[^+]+') do
    local norm = normalize_shortcut_token(token)
    if norm == 'ctrl' or norm == 'control' then
      chord.ctrl = true
    elseif norm == 'shift' then
      chord.shift = true
    elseif norm == 'alt' or norm == 'option' then
      chord.alt = true
    elseif norm == 'win' or norm == 'windows' or norm == 'super'
        or norm == 'cmd' or norm == 'command' or norm == 'meta' then
      chord.super = true
    elseif norm ~= '' and norm ~= 'global' and norm ~= 'globalplus' then
      key_token = norm
    end
  end
  if not key_token then return nil end

  local suffix = KEY_ALIASES[key_token]
  if not suffix then return nil end
  chord.key = safe_imgui_constant('Key_' .. suffix)
  if not chord.key then return nil end
  return chord
end

local function collect_action_shortcuts()
  local result = {}
  if not action_kbd_section or not action_command or action_command <= 0
      or not reaper.CountActionShortcuts or not reaper.GetActionShortcutDesc then
    return result
  end
  local count = reaper.CountActionShortcuts(action_kbd_section, action_command)
  for index = 0, count - 1 do
    local ok, desc = reaper.GetActionShortcutDesc(action_kbd_section, action_command, index)
    if ok then
      local chord = parse_keyboard_shortcut(desc)
      if chord then result[#result + 1] = chord end
    end
  end
  return result
end

local self_shortcuts = collect_action_shortcuts()
local shortcut_started_at = reaper.time_precise()
local shortcut_armed = false

local function modifier_state()
  local ctrl = safe_key_down(safe_imgui_constant('Key_LeftCtrl'))
    or safe_key_down(safe_imgui_constant('Key_RightCtrl'))
  local shift = safe_key_down(safe_imgui_constant('Key_LeftShift'))
    or safe_key_down(safe_imgui_constant('Key_RightShift'))
  local alt = safe_key_down(safe_imgui_constant('Key_LeftAlt'))
    or safe_key_down(safe_imgui_constant('Key_RightAlt'))
  local super = safe_key_down(safe_imgui_constant('Key_LeftSuper'))
    or safe_key_down(safe_imgui_constant('Key_RightSuper'))
  return ctrl, shift, alt, super
end

local function chord_modifiers_match(chord)
  local ctrl, shift, alt, super = modifier_state()
  return ctrl == chord.ctrl and shift == chord.shift
    and alt == chord.alt and super == chord.super
end

local function self_shortcut_close_requested()
  if #self_shortcuts == 0 then return false end

  -- Do not interpret the key-down that launched the script as a close request.
  if not shortcut_armed then
    if reaper.time_precise() - shortcut_started_at < 0.25 then return false end
    for _, chord in ipairs(self_shortcuts) do
      if safe_key_down(chord.key) then return false end
    end
    shortcut_armed = true
    return false
  end

  for _, chord in ipairs(self_shortcuts) do
    if safe_key_pressed(chord.key) and chord_modifiers_match(chord) then
      return true
    end
  end
  return false
end

local function allow_reaper_shortcuts_next_frame()
  -- Use the versioned Lua shim first. Keep the raw API as compatibility fallback.
  local ok = false
  local fn_ok, fn = pcall(function() return ImGui.SetNextFrameWantCaptureKeyboard end)
  if fn_ok and fn then ok = pcall(fn, ctx, false) end
  if not ok and reaper.APIExists and reaper.APIExists('ImGui_SetNextFrameWantCaptureKeyboard') then
    pcall(reaper.ImGui_SetNextFrameWantCaptureKeyboard, ctx, false)
  end
end

local COLORS = {
  bg = 0x11151BFF,
  panel = 0x171D25FF,
  panel2 = 0x1D2530FF,
  hover = 0x273443FF,
  border = 0x344354FF,
  text = 0xEAF0F6FF,
  muted = 0x8795A5FF,
  cyan = 0x38C6FFFF,
  cyan_dark = 0x176582FF,
  blue = 0x4A9EFFFF,
  blue_dark = 0x244F86FF,
  green = 0x4EDB85FF,
  green_dark = 0x216B43FF,
  yellow = 0xFFD166FF,
  yellow_dark = 0x765E25FF,
  orange = 0xF29A4AFF,
  orange_dark = 0x7A4824FF,
  red = 0xFF6B6BFF,
  red_dark = 0x743434FF,
  wave = 0x59C9F3FF,
  wave_dim = 0x285E72FF,
}

local TYPE_ORDER = {'Volume', 'Pitch', 'Pan', 'Speed'}
local TYPE_CONFIG = {
  Speed = {
    label = '속도', short = 'SPEED', min = 0.25, max = 4.0, baseline = 1.0,
    color = COLORS.yellow, dark = COLORS.yellow_dark, log = true,
    ext = 'YSL_CURVE_SPEED',
  },
  Volume = {
    label = '볼륨', short = 'VOLUME', min = -36.0, max = 12.0, baseline = 0.0,
    color = COLORS.green, dark = COLORS.green_dark,
    ext = 'YSL_CURVE_VOLUME',
  },
  Pitch = {
    label = '피치', short = 'PITCH', min = -24.0, max = 24.0, baseline = 0.0,
    color = COLORS.blue, dark = COLORS.blue_dark,
    ext = 'YSL_CURVE_PITCH',
  },
  Pan = {
    label = '팬', short = 'PAN', min = -1.0, max = 1.0, baseline = 0.0,
    color = COLORS.orange, dark = COLORS.orange_dark,
    ext = 'YSL_CURVE_PAN',
  },
}

local ENV_SPEC = {
  Volume = {
    key = 'Volume', alias = 'VOLENV', default = 1.0,
    action_text = {'take volume envelope'},
  },
  Pitch = {
    key = 'Pitch', alias = 'PITCHENV', default = 0.0,
    action_text = {'take pitch envelope'},
  },
  Pan = {
    key = 'Pan', alias = 'PANENV', default = 0.0,
    action_text = {'take pan envelope'},
  },
}

local state = {
  open = true,
  language = 'en',
  help_open = false,
  item = nil,
  take = nil,
  item_guid = nil,
  take_guid = nil,
  target_item_guids = {},
  target_audio_count = 0,
  next_context_poll = 0,
  envelope_enabled_cache = {},

  wave_zoom = 1.0,
  wave_offset = 0.0,
  wave_cache = nil,
  wave_cache_key = nil,
  wave_panning = false,
  wave_pan_anchor_x = nil,
  wave_pan_anchor_offset = nil,

  selection_start = nil,
  selection_end = nil,
  selection_start_norm = nil,
  selection_end_norm = nil,
  selection_item_guid = nil,
  selection_ranges_norm = {},
  active_selection = 1,
  selecting = false,
  selection_anchor = nil,
  selection_drag_mode = nil,

  audition_active = false,
  audition_end = nil,

  editor_type = 'Speed',
  curves = {},
  selected_point = 1,
  dragging_points = nil,
  dragging_segment = nil,
  preserve_pitch = true,
  speed_resolution = 28,
  envelope_resolution = 48,

  preview = {
    active = false,
    item_guid = nil,
    original_guid = nil,
    preview_guid = nil,
    original_length = nil,
    preview_length = nil,
    original_name = nil,
    current = nil,
  },

  user_presets = {},
  preset_search = '',
  save_preset_name = '',
  pending_delete_preset = nil,
  show_user_presets = false,
  applied = {Speed=false, Volume=false, Pitch=false, Pan=false},
  applied_curve_signature = {},
  native_import_count = {Volume=0, Pitch=0, Pan=0},

  status = '',
  status_until = 0,
  last_heartbeat = 0,
}

local function tr(english, korean)
  return state.language == 'ko' and korean or english
end

local function type_label(kind)
  local labels = {
    Speed = {'Speed', '속도'},
    Volume = {'Volume', '볼륨'},
    Pitch = {'Pitch', '피치'},
    Pan = {'Pan', '팬'},
  }
  local pair = labels[kind] or {tostring(kind), tostring(kind)}
  return tr(pair[1], pair[2])
end

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function db_to_amp(db)
  if db <= -150 then return 0 end
  return 10 ^ (db / 20)
end

local function amp_to_db(amplitude)
  amplitude = tonumber(amplitude) or 0
  if amplitude <= 0.0000001 then return -150 end
  return 20 * math.log(amplitude, 10)
end

local function value_to_norm(kind, value)
  local cfg = TYPE_CONFIG[kind]
  value = clamp(value, cfg.min, cfg.max)
  if cfg.log then
    local lo = math.log(cfg.min, 2)
    local hi = math.log(cfg.max, 2)
    return (math.log(value, 2) - lo) / (hi - lo)
  end
  return (value - cfg.min) / (cfg.max - cfg.min)
end

local function format_time(seconds)
  if reaper.format_timestr_pos then
    return reaper.format_timestr_pos(tonumber(seconds) or 0, '', 0)
  end
  return string.format('%.3f', tonumber(seconds) or 0)
end

local function valid_item(item)
  return item ~= nil and reaper.ValidatePtr2(0, item, 'MediaItem*')
end

local function valid_take(take)
  return take ~= nil and reaper.ValidatePtr2(0, take, 'MediaItem_Take*')
end

local function get_item_guid(item)
  if not valid_item(item) then return nil end
  local ok, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  return ok and guid or nil
end

local function get_take_guid(take)
  if not valid_take(take) then return nil end
  local ok, guid = reaper.GetSetMediaItemTakeInfo_String(take, 'GUID', '', false)
  return ok and guid or nil
end

local function find_item_by_guid(guid)
  if not guid or guid == '' then return nil end
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    if get_item_guid(item) == guid then return item end
  end
  return nil
end

local function find_take_by_guid(guid)
  if not guid or guid == '' then return nil end
  if reaper.GetMediaItemTakeByGUID then
    local take = reaper.GetMediaItemTakeByGUID(0, guid)
    if valid_take(take) then return take end
  end
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    for t = 0, reaper.CountTakes(item) - 1 do
      local take = reaper.GetTake(item, t)
      if valid_take(take) and get_take_guid(take) == guid then return take end
    end
  end
  return nil
end

local function set_status(text, seconds)
  state.status = tostring(text or '')
  state.status_until = reaper.time_precise() + (seconds or 3)
end

local function refresh(item)
  if valid_item(item) then reaper.UpdateItemInProject(item) end
  reaper.UpdateArrange()
end

local function invalidate_wave()
  state.wave_cache = nil
  state.wave_cache_key = nil
end

local function P(x, y, shape, tension, selected)
  return {
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
    shape = shape or 'linear',
    tension = clamp(tonumber(tension) or 0, -1, 1),
    selected = selected == true,
  }
end

local function flat_curve(kind)
  local base = TYPE_CONFIG[kind].baseline
  return {P(0, base), P(1, base)}
end

local function normalize_curve(kind, points)
  local cfg = TYPE_CONFIG[kind]
  local clean = {}
  for _, point in ipairs(points or {}) do
    if type(point) == 'table' and point.x ~= nil and point.y ~= nil then
      local shape = point.shape
      if shape ~= 'smooth' and shape ~= 'bezier' then shape = 'linear' end
      clean[#clean + 1] = {
        x = clamp(point.x, 0, 1),
        y = clamp(point.y, cfg.min, cfg.max),
        shape = shape,
        tension = clamp(point.tension or 0, -1, 1),
        selected = point.selected == true,
      }
    end
  end
  if #clean == 0 then clean = flat_curve(kind) end
  table.sort(clean, function(a, b) return a.x < b.x end)
  if clean[1].x > 0.000001 then
    table.insert(clean, 1, P(0, clean[1].y, clean[1].shape, clean[1].tension))
  end
  if clean[#clean].x < 0.999999 then
    clean[#clean + 1] = P(1, clean[#clean].y, 'linear', 0)
  end
  clean[1].x = 0
  clean[#clean].x = 1
  return clean
end

local function serialize_curve(kind, points)
  local parts = {}
  for _, point in ipairs(normalize_curve(kind, points)) do
    local shape_code = point.shape == 'smooth' and 'S'
      or (point.shape == 'bezier' and 'B' or 'L')
    parts[#parts + 1] = string.format(
      '%.7f:%.7f:%s:%.5f', point.x, point.y, shape_code, point.tension or 0)
  end
  return table.concat(parts, ';')
end

local function parse_curve(kind, text)
  local points = {}
  for token in tostring(text or ''):gmatch('[^;]+') do
    local x, y, shape_code, tension = token:match(
      '^([%d%.%-]+):([%d%.%-]+):([LSB]):([%d%.%-]+)$')
    if not x then
      x, y = token:match('^([%d%.%-]+):([%d%.%-]+)$')
    end
    if x and y then
      local shape = shape_code == 'S' and 'smooth'
        or (shape_code == 'B' and 'bezier' or 'linear')
      points[#points + 1] = P(
        tonumber(x), tonumber(y), shape, tonumber(tension) or 0)
    end
  end
  return normalize_curve(kind, points)
end

local function current_curve_signature(kind)
  local signature = serialize_curve(kind, state.curves[kind])
  if kind == 'Speed' then
    signature = signature .. '|preserve_pitch='
      .. (state.preserve_pitch and '1' or '0')
  end
  return signature
end

local function mark_curve_applied(kind)
  state.applied[kind] = true
  state.applied_curve_signature[kind] = current_curve_signature(kind)
end

local function curve_is_applied(kind)
  return state.applied[kind] == true
    and state.applied_curve_signature[kind] ~= nil
    and state.applied_curve_signature[kind] == current_curve_signature(kind)
end

local function clear_point_selection(kind)
  for _, point in ipairs(state.curves[kind] or {}) do point.selected = false end
end

local function select_only_point(kind, index)
  local points = state.curves[kind] or {}
  clear_point_selection(kind)
  if points[index] then
    points[index].selected = true
    state.selected_point = index
  end
end

local function selected_point_indices(kind)
  local result = {}
  for i, point in ipairs(state.curves[kind] or {}) do
    if point.selected then result[#result + 1] = i end
  end
  if #result == 0 and state.curves[kind] and state.curves[kind][state.selected_point] then
    state.curves[kind][state.selected_point].selected = true
    result[1] = state.selected_point
  end
  return result
end

local function segment_ease(shape, t, tension)
  t = clamp(t, 0, 1)
  if shape == 'smooth' then
    return t * t * (3 - 2 * t)
  elseif shape == 'bezier' then
    local amount = clamp(tonumber(tension) or 0, -1, 1)
    if math.abs(amount) < 0.0001 then return t end

    -- The previous cubic control range stayed close to a straight line even at
    -- its limits. A power curve gives the full slider a musically useful range:
    -- negative values hold near the first point, positive values move rapidly
    -- toward the next point. Adaptive envelope sampling below writes this exact
    -- visual curve to REAPER instead of depending on theme/native shape display.
    local exponent = 1 + math.abs(amount) * 7
    if amount < 0 then return t ^ exponent end
    return 1 - (1 - t) ^ exponent
  end
  return t
end

local function curve_segment_value(a, b, t)
  return lerp(a.y, b.y, segment_ease(a.shape, t, a.tension))
end

local function curve_value_at(kind, x)
  local points = normalize_curve(kind, state.curves[kind])
  x = clamp(x, 0, 1)
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    if x <= b.x then
      local span = math.max(0.000001, b.x - a.x)
      return curve_segment_value(a, b, (x - a.x) / span)
    end
  end
  return points[#points].y
end

-- Assigned after native Take-envelope helpers are declared. Waveform and UI
-- callbacks can still use it because frames begin after the whole script loads.
local import_native_curve
local take_envelope_enabled
local set_take_envelope_enabled

local function clear_applied_flags()
  state.applied = {Speed=false, Volume=false, Pitch=false, Pan=false}
  state.applied_curve_signature = {}
end

-- Graph edits remain editor-only until Apply is pressed. Once applied, keep the
-- curve metadata on the exact Take that owns the native envelope.
local function store_applied_curve_on_take(
    kind, take, range_start, range_end, item_length, range_list)
  if not valid_take(take) then return false end
  local cfg = TYPE_CONFIG[kind]
  reaper.GetSetMediaItemTakeInfo_String(
    take, 'P_EXT:' .. cfg.ext, serialize_curve(kind, state.curves[kind]), true)
  if range_start and range_end and item_length then
    reaper.GetSetMediaItemTakeInfo_String(
      take, 'P_EXT:' .. cfg.ext .. '_RANGE',
      string.format('%.9f:%.9f:%.9f', range_start, range_end, item_length), true)
  end
  if range_list and item_length then
    local encoded = {}
    for _, range in ipairs(range_list) do
      encoded[#encoded + 1] = string.format(
        '%.9f:%.9f', tonumber(range.a) or 0, tonumber(range.b) or 0)
    end
    reaper.GetSetMediaItemTakeInfo_String(
      take, 'P_EXT:' .. cfg.ext .. '_RANGES',
      table.concat(encoded, ';') .. string.format('|%.9f', item_length), true)
  end
  mark_curve_applied(kind)
  return true
end

local function load_curves(take)
  clear_applied_flags()
  for _, kind in ipairs(TYPE_ORDER) do
    local cfg = TYPE_CONFIG[kind]
    local curve = nil
    if valid_take(take) then
      local ok, text = reaper.GetSetMediaItemTakeInfo_String(
        take, 'P_EXT:' .. cfg.ext, '', false)
      if ok and text and text ~= '' then
        curve = parse_curve(kind, text)
        state.applied[kind] = true
      end
    end
    state.curves[kind] = curve or flat_curve(kind)
    if state.applied[kind] then
      state.applied_curve_signature[kind] = current_curve_signature(kind)
    end
    select_only_point(kind, 1)
  end
  state.selected_point = 1
  state.dragging_points = nil
  state.dragging_segment = nil
end

local function load_curves_with_native_fallback(take, item)
  load_curves(take)
  if valid_take(take) and valid_item(item)
      and import_native_curve and take_envelope_enabled then
    for _, kind in ipairs({'Volume', 'Pitch', 'Pan'}) do
      -- Curves applied by this script keep their compact editable metadata.
      -- Native envelopes made elsewhere have no metadata, so read their actual
      -- values automatically instead of requiring the import button.
      if not state.applied[kind] and take_envelope_enabled(kind, take) then
        import_native_curve(kind, take, item, true)
      end
    end
  end

  -- selected_point is shared by the compact lower controls. Native imports for
  -- other tabs must not leave it pointing at a different tab's selection.
  local active_points = state.curves[state.editor_type] or {}
  local active_index = 1
  for index, point in ipairs(active_points) do
    if point.selected then active_index = index; break end
  end
  state.selected_point = clamp(active_index, 1, math.max(1, #active_points))
end

local function copy_selection_ranges_norm(ranges)
  local result = {}
  for _, range in ipairs(ranges or {}) do
    local a = tonumber(range[1] or range.start_norm)
    local b = tonumber(range[2] or range.end_norm)
    if a and b then
      result[#result + 1] = {
        clamp(math.min(a, b), 0, 1),
        clamp(math.max(a, b), 0, 1),
      }
    end
  end
  return result
end

local function sync_active_selection_fields()
  local ranges = state.selection_ranges_norm or {}
  if #ranges == 0 or not valid_item(state.item) then
    state.selection_start = nil
    state.selection_end = nil
    state.selection_start_norm = nil
    state.selection_end_norm = nil
    state.selection_item_guid = nil
    state.active_selection = 1
    return
  end

  state.active_selection = clamp(
    math.floor(tonumber(state.active_selection) or 1), 1, #ranges)
  local range = ranges[state.active_selection]
  local pos = reaper.GetMediaItemInfo_Value(state.item, 'D_POSITION')
  local item_len = math.max(
    0.000001, reaper.GetMediaItemInfo_Value(state.item, 'D_LENGTH'))
  state.selection_start_norm = clamp(math.min(range[1], range[2]), 0, 1)
  state.selection_end_norm = clamp(math.max(range[1], range[2]), 0, 1)
  state.selection_start = pos + state.selection_start_norm * item_len
  state.selection_end = pos + state.selection_end_norm * item_len
  state.selection_item_guid = get_item_guid(state.item)
end

local function normalize_selection_ranges(preferred_norm)
  local ranges = copy_selection_ranges_norm(state.selection_ranges_norm)
  table.sort(ranges, function(a, b)
    if math.abs(a[1] - b[1]) < 0.0000001 then return a[2] < b[2] end
    return a[1] < b[1]
  end)

  local merged = {}
  for _, range in ipairs(ranges) do
    if range[2] - range[1] >= 0.000001 then
      local last = merged[#merged]
      if last and range[1] <= last[2] + 0.000001 then
        last[2] = math.max(last[2], range[2])
      else
        merged[#merged + 1] = {range[1], range[2]}
      end
    end
  end
  state.selection_ranges_norm = merged

  local preferred = tonumber(preferred_norm)
  local active = 1
  if preferred then
    for index, range in ipairs(merged) do
      if preferred >= range[1] - 0.000001
          and preferred <= range[2] + 0.000001 then
        active = index
        break
      end
    end
  end
  state.active_selection = clamp(active, 1, math.max(1, #merged))
  sync_active_selection_fields()
end

local function set_selection_ranges_norm(ranges, active_index)
  state.selection_ranges_norm = copy_selection_ranges_norm(ranges)
  state.active_selection = clamp(
    math.floor(tonumber(active_index) or 1), 1,
    math.max(1, #state.selection_ranges_norm))
  sync_active_selection_fields()
end

local function clear_internal_selection()
  state.selection_start = nil
  state.selection_end = nil
  state.selection_start_norm = nil
  state.selection_end_norm = nil
  state.selection_item_guid = nil
  state.selection_ranges_norm = {}
  state.active_selection = 1
  state.selecting = false
  state.selection_anchor = nil
  state.selection_drag_mode = nil
end

local function set_internal_selection(a, b, mode)
  if not valid_item(state.item) then return end
  local pos = reaper.GetMediaItemInfo_Value(state.item, 'D_POSITION')
  local item_end = pos + reaper.GetMediaItemInfo_Value(state.item, 'D_LENGTH')
  a = clamp(a, pos, item_end)
  b = clamp(b, pos, item_end)
  if b < a then a, b = b, a end
  local item_len = math.max(
    0.000001, reaper.GetMediaItemInfo_Value(state.item, 'D_LENGTH'))
  local normalized = {
    clamp((a - pos) / item_len, 0, 1),
    clamp((b - pos) / item_len, 0, 1),
  }

  if mode == 'add' then
    state.selection_ranges_norm[#state.selection_ranges_norm + 1] = normalized
    state.active_selection = #state.selection_ranges_norm
  elseif mode == 'update' and #state.selection_ranges_norm > 0 then
    state.active_selection = clamp(state.active_selection, 1, #state.selection_ranges_norm)
    state.selection_ranges_norm[state.active_selection] = normalized
  else
    state.selection_ranges_norm = {normalized}
    state.active_selection = 1
  end
  sync_active_selection_fields()
end

local function current_ranges(item)
  local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
  local item_end = pos + item_len
  local result = {}
  -- The range set is normalized on the representative item. It can then be
  -- mapped proportionally to every selected item, even when lengths differ.
  if state.selection_item_guid == state.item_guid then
    for index, range in ipairs(state.selection_ranges_norm or {}) do
      local a = pos + clamp(math.min(range[1], range[2]), 0, 1) * item_len
      local b = pos + clamp(math.max(range[1], range[2]), 0, 1) * item_len
      a = clamp(a, pos, item_end)
      b = clamp(b, pos, item_end)
      if b - a >= 0.001 then
        result[#result + 1] = {
          a = a, b = b, index = index,
          start_norm = clamp(math.min(range[1], range[2]), 0, 1),
          end_norm = clamp(math.max(range[1], range[2]), 0, 1),
        }
      end
    end
  end
  if #result == 0 then
    return {{a=pos, b=item_end, index=1, start_norm=0, end_norm=1}}, false
  end
  return result, true
end

local function current_range(item)
  local ranges, selected = current_ranges(item)
  local active = selected and clamp(state.active_selection, 1, #ranges) or 1
  local range = ranges[active] or ranges[1]
  return range.a, range.b, selected
end

local function collect_selected_audio_items()
  local result, seen = {}, {}
  local function append(item)
    if not valid_item(item) then return end
    local guid = get_item_guid(item)
    if not guid or seen[guid] then return end
    local take = reaper.GetActiveTake(item)
    if not valid_take(take) or reaper.TakeIsMIDI(take) then return end
    seen[guid] = true
    result[#result + 1] = item
  end

  -- Keep the displayed item first so status, Preview A/B, and the waveform
  -- remain anchored even when REAPER enumerates selected items by track order.
  if valid_item(state.item) and reaper.IsMediaItemSelected(state.item) then
    append(state.item)
  end
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    append(reaper.GetSelectedMediaItem(0, i))
  end
  if #result == 0 then append(state.item) end
  return result
end

local function selected_audio_item_count()
  return math.max(0, tonumber(state.target_audio_count) or 0)
end

local Preview = {}

local function take_ext_get(take, key)
  if not valid_take(take) then return '' end
  local ok, value = reaper.GetSetMediaItemTakeInfo_String(take, 'P_EXT:' .. key, '', false)
  return ok and tostring(value or '') or ''
end

local function take_ext_set(take, key, value)
  if valid_take(take) then
    reaper.GetSetMediaItemTakeInfo_String(take, 'P_EXT:' .. key, tostring(value or ''), true)
  end
end

function Preview.clear_state()
  state.preview.active = false
  state.preview.item_guid = nil
  state.preview.original_guid = nil
  state.preview.preview_guid = nil
  state.preview.original_length = nil
  state.preview.preview_length = nil
  state.preview.original_name = nil
  state.preview.current = nil
end

function Preview.recover(item)
  Preview.clear_state()
  if not valid_item(item) then return false end
  for i = 0, reaper.CountTakes(item) - 1 do
    local take = reaper.GetTake(item, i)
    if valid_take(take) and take_ext_get(take, 'YSL_PREVIEW_ROLE') == 'preview' then
      local original_guid = take_ext_get(take, 'YSL_PREVIEW_ORIGINAL_GUID')
      local original = find_take_by_guid(original_guid)
      if valid_take(original) and reaper.GetMediaItemTake_Item(original) == item then
        state.preview.active = true
        state.preview.item_guid = get_item_guid(item)
        state.preview.original_guid = original_guid
        state.preview.preview_guid = get_take_guid(take)
        state.preview.original_length = tonumber(
          take_ext_get(take, 'YSL_PREVIEW_ORIGINAL_LENGTH'))
          or reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        state.preview.preview_length = tonumber(
          take_ext_get(take, 'YSL_PREVIEW_CURRENT_LENGTH'))
          or reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        state.preview.original_name = take_ext_get(take, 'YSL_PREVIEW_ORIGINAL_NAME')
        state.preview.current = get_take_guid(reaper.GetActiveTake(item)) == state.preview.original_guid
          and 'original' or 'preview'
        return true
      end
    end
  end
  return false
end


local function reset_item_context(item)
  state.item = item
  state.item_guid = get_item_guid(item)
  state.take = valid_item(item) and reaper.GetActiveTake(item) or nil
  state.take_guid = get_take_guid(state.take)
  state.envelope_enabled_cache = {}
  state.wave_zoom = 1
  state.wave_offset = 0
  state.wave_panning = false
  state.wave_pan_anchor_x = nil
  state.wave_pan_anchor_offset = nil
  clear_internal_selection()
  invalidate_wave()
  Preview.recover(item)
  local curve_take = state.preview.active
      and find_take_by_guid(state.preview.preview_guid) or nil
  load_curves_with_native_fallback(curve_take or state.take, item)
end

local function update_context()
  local selected = nil
  state.target_item_guids = {}
  local target_audio_count = 0
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local candidate = reaper.GetSelectedMediaItem(0, i)
    local candidate_take = reaper.GetActiveTake(candidate)
    if valid_take(candidate_take) and not reaper.TakeIsMIDI(candidate_take) then
      target_audio_count = target_audio_count + 1
    end
    if not selected then selected = candidate end
  end
  state.target_audio_count = target_audio_count
  -- Adding more selected items must not unexpectedly swap the representative
  -- waveform. Retain the current one while it remains in the selection.
  if valid_item(state.item) and reaper.IsMediaItemSelected(state.item) then
    selected = state.item
  end

  if valid_item(selected) then
    local selected_guid = get_item_guid(selected)
    if selected_guid ~= state.item_guid then
      reset_item_context(selected)
      return
    end
    state.item = selected
  else
    local retained = find_item_by_guid(state.item_guid)
    if valid_item(retained) then
      state.item = retained
      state.target_item_guids = {state.item_guid}
      local retained_take = reaper.GetActiveTake(retained)
      state.target_audio_count =
        valid_take(retained_take) and not reaper.TakeIsMIDI(retained_take) and 1 or 0
    else
      state.item, state.take = nil, nil
      state.item_guid, state.take_guid = nil, nil
      state.target_item_guids = {}
      state.target_audio_count = 0
      Preview.clear_state()
      clear_internal_selection()
      invalidate_wave()
      return
    end
  end

  if valid_item(state.item) then
    if state.preview.active and state.preview.item_guid ~= get_item_guid(state.item) then
      Preview.clear_state()
    end
    local take = reaper.GetActiveTake(state.item)
    local guid = get_take_guid(take)
    if guid ~= state.take_guid then
      state.take = take
      state.take_guid = guid
      state.envelope_enabled_cache = {}
      invalidate_wave()
      if state.preview.active
          and (guid == state.preview.original_guid or guid == state.preview.preview_guid) then
        state.preview.current = guid == state.preview.original_guid and 'original' or 'preview'
      else
        Preview.recover(state.item)
        local curve_take = state.preview.active
            and find_take_by_guid(state.preview.preview_guid) or nil
        load_curves_with_native_fallback(curve_take or state.take, state.item)
      end
    else
      state.take = take
    end
  end
end

local function update_audition()
  if not state.audition_active then return end
  local playing = (reaper.GetPlayState() & 1) == 1
  if not playing then
    state.audition_active = false
    state.audition_end = nil
    return
  end
  if state.audition_end and reaper.GetPlayPosition() >= state.audition_end - 0.002 then
    reaper.OnStopButton()
    state.audition_active = false
    state.audition_end = nil
  end
end

local function start_audition(item)
  local a, b = current_range(item)
  reaper.SetEditCurPos(a, true, false)
  state.audition_end = b
  state.audition_active = true
  reaper.OnPlayButton()
end

local function stop_audition()
  reaper.OnStopButton()
  state.audition_active = false
  state.audition_end = nil
end

local function push_button_colors(base, hover, active)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, base)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hover)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, active)
end

local function pop_button_colors()
  ImGui.PopStyleColor(ctx, 3)
end

local function colored_button(label, width, base, hover)
  push_button_colors(base, hover, base)
  local clicked = ImGui.Button(ctx, label, width or 0, 0)
  pop_button_colors()
  return clicked
end

local function toggle_button(label, enabled, width, cfg)
  if enabled then
    return colored_button(label, width, cfg.dark, cfg.color)
  end
  return colored_button(label, width, COLORS.panel2, COLORS.hover)
end

local function content_width()
  local width = ImGui.GetContentRegionAvail(ctx)
  return math.max(120, width)
end

local function compact_button_width(label, padding)
  local visible = tostring(label or ''):match('^(.-)##') or tostring(label or '')
  local width = ImGui.CalcTextSize(ctx, visible)
  return math.ceil((tonumber(width) or 0) + (padding or 16))
end

local function draw_lock_badge(draw, center_x, center_y, label)
  local color = 0xAAB4C0FF
  local body_left, body_top = center_x - 8, center_y - 1
  ImGui.DrawList_AddRectFilled(
    draw, body_left, body_top, center_x + 8, center_y + 13, color, 2)
  ImGui.DrawList_AddRect(
    draw, center_x - 6, center_y - 10, center_x + 6, center_y + 4,
    color, 6, 0, 2)
  ImGui.DrawList_AddCircleFilled(draw, center_x, center_y + 5, 2, COLORS.bg)
  local text = tostring(label or '엔벨로프 닫힘')
  local text_width = ImGui.CalcTextSize(ctx, text)
  ImGui.DrawList_AddText(
    draw, center_x - text_width * 0.5, center_y + 19, color, text)
end

-- -----------------------------------------------------------------------------
-- Waveform
-- -----------------------------------------------------------------------------
local function build_wave_cache(item, take, width)
  if not valid_item(item) or not valid_take(take) then return nil end
  if reaper.TakeIsMIDI(take) then
    return {error = tr('MIDI Takes are not supported.', 'MIDI 테이크는 지원하지 않습니다.')}
  end

  local item_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
  local visible_len = item_len / math.max(1, state.wave_zoom)
  state.wave_offset = clamp(state.wave_offset, 0, math.max(0, item_len - visible_len))
  local visible_start = item_pos + state.wave_offset

  local source = reaper.GetMediaItemTake_Source(take)
  if not source then
    return {error = tr('Could not read the audio source.', '오디오 소스를 읽을 수 없습니다.')}
  end
  local channels = math.min(2, math.max(1, reaper.GetMediaSourceNumChannels(source)))
  local samples = clamp(math.floor(width * 0.55), 96, 720)
  local key = table.concat({
    get_take_guid(take) or '',
    string.format('%.7f', item_pos), string.format('%.7f', item_len),
    string.format('%.7f', visible_start), string.format('%.7f', visible_len),
    samples, channels, reaper.GetTakeNumStretchMarkers(take),
  }, '|')
  if state.wave_cache_key == key and state.wave_cache then return state.wave_cache end

  local buffer = reaper.new_array(samples * channels * 2)
  buffer.clear()
  local retval = reaper.GetMediaItemTake_Peaks(
    take, samples / visible_len, visible_start, channels, samples, 0, buffer)
  local returned = (math.floor(tonumber(retval) or 0)) & 0xFFFFF
  if returned <= 0 then
    return {error = tr('Could not build waveform peaks.', '파형 피크를 만들 수 없습니다.')}
  end

  local values = buffer.table(1, samples * channels * 2)
  local max_block = samples * channels
  local maxima, minima = {}, {}
  for c = 1, channels do maxima[c], minima[c] = {}, {} end
  for i = 0, returned - 1 do
    for c = 0, channels - 1 do
      local index = i * channels + c + 1
      maxima[c + 1][i + 1] = values[index] or 0
      minima[c + 1][i + 1] = values[max_block + index] or 0
    end
  end

  state.wave_cache_key = key
  state.wave_cache = {
    maxima = maxima, minima = minima, count = returned, channels = channels,
    visible_start = visible_start, visible_len = visible_len,
  }
  return state.wave_cache
end

local function draw_waveform(item, take, locked)
  local width = content_width()
  local height = 212
  ImGui.InvisibleButton(ctx, '##Waveform', width, height)
  local x1, y1 = ImGui.GetItemRectMin(ctx)
  local x2, y2 = ImGui.GetItemRectMax(ctx)
  local draw = ImGui.GetWindowDrawList(ctx)

  ImGui.DrawList_AddRectFilled(draw, x1, y1, x2, y2, COLORS.bg, 4)
  ImGui.DrawList_AddRect(draw, x1, y1, x2, y2, COLORS.border, 4, 0, 1)

  local cache = build_wave_cache(item, take, width)
  if not cache or cache.error then
    ImGui.DrawList_AddText(draw, x1 + 10, y1 + 10, COLORS.muted,
      cache and cache.error or tr(
        'Could not display the waveform.',
        '파형을 표시할 수 없습니다.'))
    return
  end

  local channel_h = height / cache.channels
  for c = 1, cache.channels do
    local center = y1 + (c - 0.5) * channel_h
    ImGui.DrawList_AddLine(draw, x1, center, x2, center, COLORS.wave_dim, 1)
    for i = 1, cache.count do
      local ratio = (i - 1) / math.max(1, cache.count - 1)
      local x = x1 + ratio * width
      local maxv = clamp(cache.maxima[c][i] or 0, -1, 1)
      local minv = clamp(cache.minima[c][i] or 0, -1, 1)
      ImGui.DrawList_AddLine(draw, x,
        center - maxv * channel_h * 0.47,
        x,
        center - minv * channel_h * 0.47,
        COLORS.wave, 1)
    end
  end

  local function time_to_x(time)
    return x1 + ((time - cache.visible_start) / cache.visible_len) * width
  end
  local function x_to_time(x)
    return cache.visible_start + clamp((x - x1) / width, 0, 1) * cache.visible_len
  end
  local function snapped_time(x)
    local edge = 10
    if x <= x1 + edge then return cache.visible_start end
    if x >= x2 - edge then return cache.visible_start + cache.visible_len end
    return x_to_time(x)
  end

  local ranges, has_selection = current_ranges(item)
  local active_range_index = has_selection
    and clamp(state.active_selection, 1, #ranges) or 1
  local active_range = ranges[active_range_index] or ranges[1]
  local s, e = active_range.a, active_range.b
  local range_screens = {}
  local sx, ex = nil, nil

  if has_selection then
    for index, range in ipairs(ranges) do
      if range.b >= cache.visible_start
          and range.a <= cache.visible_start + cache.visible_len then
        local rsx = clamp(time_to_x(range.a), x1, x2)
        local rex = clamp(time_to_x(range.b), x1, x2)
        local active = index == active_range_index
        range_screens[index] = {x1=rsx, x2=rex, active=active}
        ImGui.DrawList_AddRectFilled(
          draw, rsx, y1, rex, y2, active and 0x38C6FF32 or 0x38C6FF1C, 2)
        ImGui.DrawList_AddRect(
          draw, rsx, y1, rex, y2, active and COLORS.cyan or COLORS.cyan_dark,
          2, 0, active and 1.8 or 1)
        if active then sx, ex = rsx, rex end
      end
    end

    if sx and ex then
      -- Only the active range exposes handles; the same curve is repeated in
      -- every other selected range, but one range remains the editing anchor.
      ImGui.DrawList_AddLine(draw, sx, y1, sx, y2, COLORS.cyan, 3)
      ImGui.DrawList_AddLine(draw, ex, y1, ex, y2, COLORS.cyan, 3)
      ImGui.DrawList_AddCircleFilled(draw, sx, y1 + 10, 5, COLORS.cyan)
      ImGui.DrawList_AddCircleFilled(draw, ex, y1 + 10, 5, COLORS.cyan)
      ImGui.DrawList_AddText(draw, sx + 6, y1 + 3, COLORS.cyan, 'S')
      ImGui.DrawList_AddText(draw, ex - 15, y1 + 3, COLORS.cyan, 'E')
    end
  end

  -- The waveform is also the curve editor. The current curve is mapped onto
  -- the actual destination region, and its control points remain interactive
  -- on top of the audio instead of consuming a second graph below it.
  local kind = state.editor_type
  local cfg = TYPE_CONFIG[kind]
  local points = state.curves[kind]
  if type(points) ~= 'table' or #points < 2 then
    points = flat_curve(kind)
    state.curves[kind] = points
  end
  state.selected_point = clamp(state.selected_point, 1, #points)
  if #selected_point_indices(kind) == 0 then
    select_only_point(kind, state.selected_point)
  end

  local function norm_to_editor_value(norm)
    norm = clamp(norm, 0, 1)
    if cfg.log then
      local lo = math.log(cfg.min, 2)
      local hi = math.log(cfg.max, 2)
      return 2 ^ lerp(lo, hi, norm)
    end
    return lerp(cfg.min, cfg.max, norm)
  end

  local function sort_editor_curve(selected)
    for _, point in ipairs(points) do
      point.x = clamp(point.x, 0, 1)
      point.y = clamp(point.y, cfg.min, cfg.max)
    end
    table.sort(points, function(a, b) return a.x < b.x end)
    points[1].x = 0
    points[#points].x = 1
    if selected then
      for i, point in ipairs(points) do
        if point == selected then state.selected_point = i; break end
      end
    end
  end

  local overlay_top = y1 + 23
  local overlay_bottom = y2 - 23
  local overlay_height = math.max(20, overlay_bottom - overlay_top)
  local overlay_start = math.max(s, cache.visible_start)
  local overlay_end = math.min(e, cache.visible_start + cache.visible_len)
  local curve_screen, segment_lines = {}, {}

  -- Repeat the same curve in every additional selected range. Only the active
  -- range gets editable points so one gesture cannot ambiguously target two
  -- different copies of the same curve.
  if has_selection and #ranges > 1 then
    for range_index, range in ipairs(ranges) do
      if range_index ~= active_range_index then
        local visible_a = math.max(range.a, cache.visible_start)
        local visible_b = math.min(
          range.b, cache.visible_start + cache.visible_len)
        if visible_b - visible_a > 0.000001 then
          local repeated = {}
          for point_index, point in ipairs(points) do
            repeated[point_index] = {
              x = time_to_x(lerp(range.a, range.b, point.x)),
              y = overlay_bottom - value_to_norm(kind, point.y) * overlay_height,
            }
          end
          for point_index = 1, #points - 1 do
            local a, b = points[point_index], points[point_index + 1]
            local previous_x, previous_y =
              repeated[point_index].x, repeated[point_index].y
            local pixel_span = math.abs(
              repeated[point_index + 1].x - repeated[point_index].x)
            local steps = clamp(math.floor(pixel_span / 11), 6, 96)
            for step = 1, steps do
              local t = step / steps
              local x = lerp(
                repeated[point_index].x, repeated[point_index + 1].x, t)
              local value = curve_segment_value(a, b, t)
              local y = overlay_bottom
                - value_to_norm(kind, value) * overlay_height
              if math.max(previous_x, x) >= x1
                  and math.min(previous_x, x) <= x2 then
                ImGui.DrawList_AddLine(
                  draw, previous_x, previous_y, x, y, COLORS.bg, 4)
                ImGui.DrawList_AddLine(
                  draw, previous_x, previous_y, x, y, cfg.dark, 1.8)
              end
              previous_x, previous_y = x, y
            end
          end
        end
      end
    end
  end

  if overlay_end - overlay_start > 0.000001 then
    local baseline_y = overlay_bottom
      - value_to_norm(kind, cfg.baseline) * overlay_height
    ImGui.DrawList_AddLine(
      draw, time_to_x(overlay_start), baseline_y,
      time_to_x(overlay_end), baseline_y, cfg.dark, 1.5)

    for i, point in ipairs(points) do
      local point_time = lerp(s, e, point.x)
      curve_screen[i] = {
        x = time_to_x(point_time),
        y = overlay_bottom - value_to_norm(kind, point.y) * overlay_height,
      }
    end

    local active_segment = clamp(state.selected_point, 1, #points)
    if active_segment >= #points then active_segment = #points - 1 end
    active_segment = math.max(1, active_segment)

    for i = 1, #points - 1 do
      local a, b = points[i], points[i + 1]
      local previous_x, previous_y = curve_screen[i].x, curve_screen[i].y
      local pixel_span = math.abs(curve_screen[i + 1].x - curve_screen[i].x)
      local steps = clamp(math.floor(pixel_span / 11), 6, 96)
      segment_lines[i] = {}
      for step = 1, steps do
        local t = step / steps
        local x = lerp(curve_screen[i].x, curve_screen[i + 1].x, t)
        local value = curve_segment_value(a, b, t)
        local y = overlay_bottom - value_to_norm(kind, value) * overlay_height
        segment_lines[i][#segment_lines[i] + 1] = {
          previous_x, previous_y, x, y,
        }
        if math.max(previous_x, x) >= x1 and math.min(previous_x, x) <= x2 then
          local color = i == active_segment and cfg.color or cfg.dark
          local thickness = i == active_segment and 3.5 or 2
          ImGui.DrawList_AddLine(
            draw, previous_x, previous_y, x, y, COLORS.bg, thickness + 3)
          ImGui.DrawList_AddLine(
            draw, previous_x, previous_y, x, y, color, thickness)
        end
        previous_x, previous_y = x, y
      end
    end

    for i, screen_point in ipairs(curve_screen) do
      if screen_point.x >= x1 - 8 and screen_point.x <= x2 + 8 then
        local selected = points[i].selected == true
        ImGui.DrawList_AddCircleFilled(
          draw, screen_point.x, screen_point.y,
          selected and 6 or 4, cfg.color)
        ImGui.DrawList_AddCircle(
          draw, screen_point.x, screen_point.y,
          selected and 8 or 6,
          selected and COLORS.text or COLORS.bg, 0, 1.5)
      end
    end
  end

  local cursor = reaper.GetCursorPosition()
  if cursor >= cache.visible_start and cursor <= cache.visible_start + cache.visible_len then
    local x = time_to_x(cursor)
    ImGui.DrawList_AddLine(draw, x, y1, x, y2, COLORS.yellow, 1.5)
  end

  if (reaper.GetPlayState() & 1) == 1 then
    local play = reaper.GetPlayPosition()
    if play >= cache.visible_start and play <= cache.visible_start + cache.visible_len then
      local x = time_to_x(play)
      ImGui.DrawList_AddLine(draw, x, y1, x, y2, COLORS.green, 2)
    end
  end

  ImGui.DrawList_AddText(draw, x1 + 6, y2 - 18, COLORS.muted, format_time(cache.visible_start))
  local end_text = format_time(cache.visible_start + cache.visible_len)
  local end_w = ImGui.CalcTextSize(ctx, end_text)
  ImGui.DrawList_AddText(draw, x2 - end_w - 6, y2 - 18, COLORS.muted, end_text)

  if locked then
    ImGui.DrawList_AddRectFilled(draw, x1 + 1, y1 + 1, x2 - 1, y2 - 1,
      0x11151BD8, 4)
    draw_lock_badge(
      draw, (x1 + x2) * 0.5, (y1 + y2) * 0.5 - 12,
      tr(
        'Envelope closed · use the button above to open',
        '엔벨로프 닫힘 · 위 버튼으로 열기'))
    return
  end

  local hovered = ImGui.IsItemHovered(ctx)
  local mx, my = ImGui.GetMousePos(ctx)

  -- Zoom around the mouse position so the sound event under the cursor stays
  -- fixed on screen. Middle-drag navigates the zoomed waveform without touching
  -- REAPER's arrange-view zoom or time selection.
  if hovered then
    local wheel_ok, wheel = pcall(ImGui.GetMouseWheel, ctx)
    wheel = wheel_ok and wheel or 0
    if math.abs(wheel or 0) > 0.0001 then
      local item_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
      local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
      local ratio = clamp((mx - x1) / width, 0, 1)
      local anchor = (cache.visible_start - item_pos) + ratio * cache.visible_len
      local new_zoom = clamp(state.wave_zoom * (wheel > 0 and 1.5 or (1 / 1.5)), 1, 128)
      local new_visible_len = item_len / new_zoom
      state.wave_zoom = new_zoom
      state.wave_offset = clamp(
        anchor - ratio * new_visible_len, 0, math.max(0, item_len - new_visible_len))
      invalidate_wave()
    end
  end

  if hovered and ImGui.IsMouseClicked(ctx, 2) then
    state.wave_panning = true
    state.wave_pan_anchor_x = mx
    state.wave_pan_anchor_offset = state.wave_offset
  end
  if state.wave_panning and ImGui.IsMouseDown(ctx, 2) then
    local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
    local visible_len = item_len / math.max(1, state.wave_zoom)
    local delta = (mx - (state.wave_pan_anchor_x or mx)) / math.max(1, width) * visible_len
    state.wave_offset = clamp(
      (state.wave_pan_anchor_offset or state.wave_offset) - delta,
      0, math.max(0, item_len - visible_len))
    invalidate_wave()
  end
  if state.wave_panning and ImGui.IsMouseReleased(ctx, 2) then
    state.wave_panning = false
    state.wave_pan_anchor_x = nil
    state.wave_pan_anchor_offset = nil
  end

  local function nearest_curve_point(px, py)
    local index, best = nil, 14
    for i, point in ipairs(curve_screen) do
      if point.x >= x1 - 8 and point.x <= x2 + 8 then
        local distance = math.sqrt((point.x - px) ^ 2 + (point.y - py) ^ 2)
        if distance < best then index, best = i, distance end
      end
    end
    return index
  end

  local function distance_to_line(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length2 = dx * dx + dy * dy
    if length2 <= 0.000001 then
      return math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
    end
    local t = clamp(((px - ax) * dx + (py - ay) * dy) / length2, 0, 1)
    local qx, qy = ax + dx * t, ay + dy * t
    return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
  end

  local function nearest_curve_segment(px, py)
    local index, best = nil, 9
    for segment_index, lines in ipairs(segment_lines) do
      for _, line in ipairs(lines) do
        if math.max(line[1], line[3]) >= x1 and math.min(line[1], line[3]) <= x2 then
          local distance = distance_to_line(
            px, py, line[1], line[2], line[3], line[4])
          if distance < best then index, best = segment_index, distance end
        end
      end
    end
    return index
  end

  local function begin_point_drag(indices, px, py)
    local original = {}
    for _, index in ipairs(indices) do
      original[index] = {
        x = points[index].x,
        y_norm = value_to_norm(kind, points[index].y),
      }
    end
    state.dragging_points = {
      indices = indices,
      original = original,
      anchor_x = clamp(
        (x_to_time(px) - s) / math.max(0.000001, e - s), 0, 1),
      anchor_y = 1 - clamp((py - overlay_top) / overlay_height, 0, 1),
    }
  end

  local ctrl_down = safe_key_down(safe_imgui_constant('Key_LeftCtrl'))
    or safe_key_down(safe_imgui_constant('Key_RightCtrl'))
  local shift_down = safe_key_down(safe_imgui_constant('Key_LeftShift'))
    or safe_key_down(safe_imgui_constant('Key_RightShift'))
  local alt_down = safe_key_down(safe_imgui_constant('Key_LeftAlt'))
    or safe_key_down(safe_imgui_constant('Key_RightAlt'))
  local double_clicked = hovered and ImGui.IsMouseDoubleClicked(ctx, 0)

  if double_clicked and not nearest_curve_point(mx, my)
      and my >= overlay_top and my <= overlay_bottom
      and mx >= time_to_x(overlay_start) and mx <= time_to_x(overlay_end) then
    local region_x = clamp(
      (x_to_time(mx) - s) / math.max(0.000001, e - s), 0.002, 0.998)
    local point = P(
      region_x,
      norm_to_editor_value(
        1 - clamp((my - overlay_top) / overlay_height, 0, 1)),
      'linear', 0, true)
    points[#points + 1] = point
    sort_editor_curve(point)
    select_only_point(kind, state.selected_point)
    state.dragging_points = nil
    state.dragging_segment = nil
    state.selecting = false
    state.selection_drag_mode = nil
  elseif hovered and ImGui.IsMouseClicked(ctx, 0) then
    local point_index = nearest_curve_point(mx, my)
    if point_index then
      if shift_down then
        local anchor = clamp(state.selected_point, 1, #points)
        clear_point_selection(kind)
        for i = math.min(anchor, point_index), math.max(anchor, point_index) do
          points[i].selected = true
        end
        state.selected_point = point_index
        state.dragging_points = nil
      elseif ctrl_down then
        points[point_index].selected = true
        state.selected_point = point_index
        begin_point_drag(selected_point_indices(kind), mx, my)
      else
        select_only_point(kind, point_index)
        begin_point_drag({point_index}, mx, my)
      end
    else
      local handle_radius = 9
      if has_selection and sx and math.abs(mx - sx) <= handle_radius then
        state.selecting = true
        state.selection_drag_mode = 'start'
      elseif has_selection and ex and math.abs(mx - ex) <= handle_radius then
        state.selecting = true
        state.selection_drag_mode = 'end'
      else
        local segment_index = nearest_curve_segment(mx, my)
        if alt_down and segment_index then
          select_only_point(kind, segment_index)
          state.dragging_points = nil
          state.dragging_segment = {
            kind = kind,
            index = segment_index,
            anchor_y = my,
            original_tension = points[segment_index].tension or 0,
            direction = points[segment_index + 1].y >= points[segment_index].y
              and 1 or -1,
          }
          points[segment_index].shape = 'bezier'
        elseif segment_index then
          select_only_point(kind, segment_index)
          state.dragging_points = nil
          state.dragging_segment = nil
        else
          local clicked_range = nil
          if has_selection then
            for index, screen in pairs(range_screens) do
              if screen and mx >= screen.x1 and mx <= screen.x2 then
                clicked_range = index
                break
              end
            end
          end
          if clicked_range and not ctrl_down then
            state.active_selection = clicked_range
            sync_active_selection_fields()
            state.dragging_segment = nil
          else
            local time = snapped_time(mx)
            state.selecting = true
            state.selection_drag_mode = ctrl_down and 'new_add' or 'new'
            state.selection_anchor = time
            set_internal_selection(time, time, ctrl_down and 'add' or nil)
            state.dragging_segment = nil
          end
        end
      end
    end
  end

  if state.dragging_segment and ImGui.IsMouseDown(ctx, 0) then
    local drag = state.dragging_segment
    local point = drag.kind == kind and points[drag.index] or nil
    if point then
      local vertical = (drag.anchor_y - my) / math.max(1, overlay_height)
      point.shape = 'bezier'
      point.tension = clamp(
        drag.original_tension + vertical * 2.4 * drag.direction, -1, 1)
    end
  end

  if state.dragging_points and not state.dragging_segment
      and ImGui.IsMouseDown(ctx, 0) then
    local drag = state.dragging_points
    local current_x = clamp(
      (x_to_time(mx) - s) / math.max(0.000001, e - s), 0, 1)
    local current_y = 1 - clamp(
      (my - overlay_top) / overlay_height, 0, 1)
    local dx = current_x - drag.anchor_x
    local dy = current_y - drag.anchor_y
    local selected_set = {}
    for _, index in ipairs(drag.indices) do selected_set[index] = true end

    local min_dx, max_dx = -1, 1
    local min_dy, max_dy = -1, 1
    for _, index in ipairs(drag.indices) do
      local original = drag.original[index]
      min_dy = math.max(min_dy, -original.y_norm)
      max_dy = math.min(max_dy, 1 - original.y_norm)
      if index == 1 or index == #points then
        min_dx, max_dx = math.max(min_dx, 0), math.min(max_dx, 0)
      else
        local previous = index - 1
        while previous >= 1 and selected_set[previous] do
          previous = previous - 1
        end
        if previous >= 1 then
          min_dx = math.max(
            min_dx, points[previous].x + 0.002 - original.x)
        end
        local following = index + 1
        while following <= #points and selected_set[following] do
          following = following + 1
        end
        if following <= #points then
          max_dx = math.min(
            max_dx, points[following].x - 0.002 - original.x)
        end
      end
    end
    dx = clamp(dx, min_dx, max_dx)
    dy = clamp(dy, min_dy, max_dy)

    for _, index in ipairs(drag.indices) do
      local point, original = points[index], drag.original[index]
      if point and original then
        if index > 1 and index < #points then point.x = original.x + dx end
        point.y = norm_to_editor_value(original.y_norm + dy)
      end
    end
  end

  if state.dragging_points and ImGui.IsMouseReleased(ctx, 0) then
    state.dragging_points = nil
  end
  if state.dragging_segment and ImGui.IsMouseReleased(ctx, 0) then
    state.dragging_segment = nil
  end

  if state.selecting and not state.dragging_points and not state.dragging_segment
      and ImGui.IsMouseDown(ctx, 0) then
    local time = snapped_time(mx)
    if state.selection_drag_mode == 'start' and state.selection_end then
      local maximum = state.selection_end - 0.001
      set_internal_selection(
        math.min(time, maximum), state.selection_end, 'update')
    elseif state.selection_drag_mode == 'end' and state.selection_start then
      local minimum = state.selection_start + 0.001
      set_internal_selection(
        state.selection_start, math.max(time, minimum), 'update')
    else
      set_internal_selection(state.selection_anchor or time, time, 'update')
    end
  end

  if state.selecting and not state.dragging_points and not state.dragging_segment
      and ImGui.IsMouseReleased(ctx, 0) then
    local was_new = state.selection_drag_mode == 'new'
      or state.selection_drag_mode == 'new_add'
    local was_add = state.selection_drag_mode == 'new_add'
    local completed_new_selection = was_new
      and state.selection_start and state.selection_end
      and math.abs(state.selection_end - state.selection_start) >= 0.002
    state.selecting = false
    state.selection_drag_mode = nil
    if was_new and not completed_new_selection then
      local time = state.selection_start or cache.visible_start
      if was_add and #state.selection_ranges_norm > 1 then
        table.remove(state.selection_ranges_norm, state.active_selection)
        state.active_selection = clamp(
          state.active_selection - 1, 1, #state.selection_ranges_norm)
        sync_active_selection_fields()
      else
        clear_internal_selection()
      end
      reaper.SetEditCurPos(time, true, false)
    end
    if completed_new_selection then
      local preferred = (
        (state.selection_start_norm or 0) + (state.selection_end_norm or 0)) * 0.5
      normalize_selection_ranges(preferred)
    elseif not was_new and state.selection_start_norm and state.selection_end_norm then
      local preferred = (
        state.selection_start_norm + state.selection_end_norm) * 0.5
      normalize_selection_ranges(preferred)
    end
    if completed_new_selection and not was_add
        and state.editor_type ~= 'Speed' and import_native_curve
        and valid_take(state.take) and valid_item(state.item) then
      local loaded, count = import_native_curve(
        state.editor_type, state.take, state.item, true)
      if loaded then
        set_status(string.format(
          tr(
            'Loaded existing %s envelope in the selected range · %d edit points',
            '선택 구간의 기존 %s 엔벨로프를 불러왔습니다 · 편집 포인트 %d개'),
          type_label(state.editor_type), count or 0), 3)
      end
    end
  end

  if hovered and ImGui.IsMouseClicked(ctx, 1) then
    local point_index = nearest_curve_point(mx, my)
    if point_index then
      if not points[point_index].selected then
        select_only_point(kind, point_index)
      end
      local remove = selected_point_indices(kind)
      table.sort(remove, function(a, b) return a > b end)
      for _, remove_index in ipairs(remove) do
        if remove_index > 1 and remove_index < #points then
          table.remove(points, remove_index)
        end
      end
      state.selected_point = clamp(point_index - 1, 1, #points)
      select_only_point(kind, state.selected_point)
      state.dragging_points = nil
      state.dragging_segment = nil
    elseif has_selection then
      local remove_range = nil
      for index, screen in pairs(range_screens) do
        if screen and mx >= screen.x1 and mx <= screen.x2 then
          remove_range = index
          break
        end
      end
      if remove_range then
        table.remove(state.selection_ranges_norm, remove_range)
        if #state.selection_ranges_norm == 0 then
          clear_internal_selection()
        else
          state.active_selection = clamp(
            math.min(remove_range, #state.selection_ranges_norm),
            1, #state.selection_ranges_norm)
          sync_active_selection_fields()
        end
        state.dragging_points = nil
        state.dragging_segment = nil
      end
    end
  end

end

-- -----------------------------------------------------------------------------
-- Unified curve editor and presets
-- -----------------------------------------------------------------------------
local function norm_to_value(kind, norm)
  local cfg = TYPE_CONFIG[kind]
  norm = clamp(norm, 0, 1)
  if cfg.log then
    local lo = math.log(cfg.min, 2)
    local hi = math.log(cfg.max, 2)
    return 2 ^ lerp(lo, hi, norm)
  end
  return lerp(cfg.min, cfg.max, norm)
end

local function value_text(kind, value)
  if kind == 'Speed' then return string.format('%.3fx', value) end
  if kind == 'Volume' then return string.format('%+.1f dB', value) end
  if kind == 'Pitch' then return string.format('%+.1f st', value) end
  if value < -0.005 then return string.format('L %.0f%%', -value * 100) end
  if value > 0.005 then return string.format('R %.0f%%', value * 100) end
  return 'CENTER'
end

local function sort_curve(kind, selected)
  local points = state.curves[kind] or {}
  for _, point in ipairs(points) do
    point.x = clamp(point.x, 0, 1)
    point.y = clamp(point.y, TYPE_CONFIG[kind].min, TYPE_CONFIG[kind].max)
  end
  table.sort(points, function(a, b) return a.x < b.x end)
  if #points >= 2 then
    points[1].x = 0
    points[#points].x = 1
  end
  if selected then
    for i, point in ipairs(points) do
      if point == selected then state.selected_point = i; break end
    end
  end
end

local function keyboard_ctrl()
  return safe_key_down(safe_imgui_constant('Key_LeftCtrl'))
    or safe_key_down(safe_imgui_constant('Key_RightCtrl'))
end

local function keyboard_shift()
  return safe_key_down(safe_imgui_constant('Key_LeftShift'))
    or safe_key_down(safe_imgui_constant('Key_RightShift'))
end

local function active_segment_index(kind)
  local points = state.curves[kind] or {}
  if #points < 2 then return 1 end
  local index = clamp(state.selected_point, 1, #points)
  if index >= #points then index = #points - 1 end
  return math.max(1, index)
end

local function draw_curve_editor(kind, locked)
  local cfg = TYPE_CONFIG[kind]
  local points = state.curves[kind]
  if type(points) ~= 'table' or #points < 2 then
    points = flat_curve(kind)
    state.curves[kind] = points
  end
  state.selected_point = clamp(state.selected_point, 1, #points)
  if #selected_point_indices(kind) == 0 then select_only_point(kind, state.selected_point) end

  local width = content_width()
  local height = 180
  ImGui.InvisibleButton(ctx, '##CurveEditor', width, height)
  local x1, y1 = ImGui.GetItemRectMin(ctx)
  local x2, y2 = ImGui.GetItemRectMax(ctx)
  local draw = ImGui.GetWindowDrawList(ctx)

  ImGui.DrawList_AddRectFilled(draw, x1, y1, x2, y2, COLORS.bg, 5)
  ImGui.DrawList_AddRect(draw, x1, y1, x2, y2, COLORS.border, 5, 0, 1)
  for i = 0, 4 do
    local x = x1 + width * i / 4
    ImGui.DrawList_AddLine(draw, x, y1, x, y2, COLORS.border, 1)
    local y = y1 + height * i / 4
    ImGui.DrawList_AddLine(draw, x1, y, x2, y, COLORS.border, 1)
  end

  local base_y = y2 - value_to_norm(kind, cfg.baseline) * height
  ImGui.DrawList_AddLine(draw, x1, base_y, x2, base_y, cfg.dark, 2)
  ImGui.DrawList_AddText(draw, x1 + 7, base_y - 17, cfg.color, value_text(kind, cfg.baseline))
  ImGui.DrawList_AddText(draw, x1 + 7, y1 + 7, COLORS.muted, value_text(kind, cfg.max))
  ImGui.DrawList_AddText(draw, x1 + 7, y2 - 18, COLORS.muted, value_text(kind, cfg.min))

  local screen, segment_lines = {}, {}
  for i, point in ipairs(points) do
    screen[i] = {x = x1 + point.x * width, y = y2 - value_to_norm(kind, point.y) * height}
  end

  local active_segment = active_segment_index(kind)
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    local previous_x, previous_y = screen[i].x, screen[i].y
    local steps = math.max(8, math.floor((screen[i + 1].x - screen[i].x) / 8))
    segment_lines[i] = {}
    for step = 1, steps do
      local t = step / steps
      local x = lerp(screen[i].x, screen[i + 1].x, t)
      local value = curve_segment_value(a, b, t)
      local y = y2 - value_to_norm(kind, value) * height
      segment_lines[i][#segment_lines[i] + 1] = {previous_x, previous_y, x, y}
      local color = i == active_segment and cfg.color or cfg.dark
      local thickness = i == active_segment and 4 or 2
      ImGui.DrawList_AddLine(draw, previous_x, previous_y, x, y, color, thickness)
      previous_x, previous_y = x, y
    end
  end

  for i, point in ipairs(screen) do
    local selected = points[i].selected == true
    ImGui.DrawList_AddCircleFilled(draw, point.x, point.y,
      selected and 6 or 4, cfg.color)
    ImGui.DrawList_AddCircle(draw, point.x, point.y,
      selected and 8 or 6, selected and COLORS.text or COLORS.bg, 0, 1.5)
  end

  if locked then
    ImGui.DrawList_AddRectFilled(draw, x1 + 1, y1 + 1, x2 - 1, y2 - 1,
      0x11151BE6, 5)
    draw_lock_badge(
      draw, (x1 + x2) * 0.5, (y1 + y2) * 0.5 - 12,
      tr('Envelope manager locked', '엔벨로프 매니저 잠김'))
    return
  end

  local function nearest_point(mx, my)
    local index, best = nil, 14
    for i, point in ipairs(screen) do
      local d = math.sqrt((point.x - mx) ^ 2 + (point.y - my) ^ 2)
      if d < best then index, best = i, d end
    end
    return index
  end

  local function distance_to_line(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length2 = dx * dx + dy * dy
    if length2 <= 0.000001 then return math.sqrt((px-ax)^2 + (py-ay)^2) end
    local t = clamp(((px-ax)*dx + (py-ay)*dy) / length2, 0, 1)
    local qx, qy = ax + dx*t, ay + dy*t
    return math.sqrt((px-qx)^2 + (py-qy)^2)
  end

  local function nearest_segment(mx, my)
    local index, best = nil, 10
    for segment_index, lines in ipairs(segment_lines) do
      for _, line in ipairs(lines) do
        local d = distance_to_line(mx, my, line[1], line[2], line[3], line[4])
        if d < best then index, best = segment_index, d end
      end
    end
    return index
  end

  local function begin_drag(indices, mx, my)
    local original = {}
    for _, selected_index in ipairs(indices) do
      original[selected_index] = {
        x = points[selected_index].x,
        y_norm = value_to_norm(kind, points[selected_index].y),
      }
    end
    state.dragging_points = {
      indices = indices,
      original = original,
      anchor_x = clamp((mx - x1) / width, 0, 1),
      anchor_y = 1 - clamp((my - y1) / height, 0, 1),
    }
  end

  local hovered = ImGui.IsItemHovered(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local double_clicked = hovered and ImGui.IsMouseDoubleClicked(ctx, 0)

  -- Point creation is intentionally double-click only.
  if double_clicked and not nearest_point(mx, my) then
    local point = P(
      clamp((mx - x1) / width, 0.002, 0.998),
      norm_to_value(kind, 1 - clamp((my - y1) / height, 0, 1)),
      'linear', 0, true)
    points[#points + 1] = point
    sort_curve(kind, point)
    points = state.curves[kind]
    select_only_point(kind, state.selected_point)
    state.dragging_points = nil
  elseif hovered and ImGui.IsMouseClicked(ctx, 0) then
    local index = nearest_point(mx, my)
    local ctrl, shift = keyboard_ctrl(), keyboard_shift()
    if index then
      if shift then
        local anchor = clamp(state.selected_point, 1, #points)
        clear_point_selection(kind)
        for i = math.min(anchor, index), math.max(anchor, index) do points[i].selected = true end
        state.selected_point = index
        state.dragging_points = nil
      elseif ctrl then
        -- Ctrl explicitly opts into multi-selection and grouped dragging.
        points[index].selected = true
        state.selected_point = index
        begin_drag(selected_point_indices(kind), mx, my)
      else
        -- Ordinary click always collapses to the clicked point. This prevents
        -- previously selected, unclicked points from moving unexpectedly.
        select_only_point(kind, index)
        begin_drag({index}, mx, my)
      end
    else
      local segment_index = nearest_segment(mx, my)
      if segment_index then
        select_only_point(kind, segment_index)
        state.dragging_points = nil
      end
    end
  end

  if state.dragging_points and ImGui.IsMouseDown(ctx, 0) then
    local drag = state.dragging_points
    local current_x = clamp((mx - x1) / width, 0, 1)
    local current_y = 1 - clamp((my - y1) / height, 0, 1)
    local dx = current_x - drag.anchor_x
    local dy = current_y - drag.anchor_y
    local selected_set = {}
    for _, index in ipairs(drag.indices) do selected_set[index] = true end

    local min_dx, max_dx = -1, 1
    local min_dy, max_dy = -1, 1
    for _, index in ipairs(drag.indices) do
      local original = drag.original[index]
      min_dy = math.max(min_dy, -original.y_norm)
      max_dy = math.min(max_dy, 1 - original.y_norm)
      if index == 1 or index == #points then
        min_dx, max_dx = math.max(min_dx, 0), math.min(max_dx, 0)
      else
        local previous = index - 1
        while previous >= 1 and selected_set[previous] do previous = previous - 1 end
        if previous >= 1 then min_dx = math.max(min_dx, points[previous].x + 0.002 - original.x) end
        local following = index + 1
        while following <= #points and selected_set[following] do following = following + 1 end
        if following <= #points then max_dx = math.min(max_dx, points[following].x - 0.002 - original.x) end
      end
    end
    dx = clamp(dx, min_dx, max_dx)
    dy = clamp(dy, min_dy, max_dy)

    for _, index in ipairs(drag.indices) do
      local point, original = points[index], drag.original[index]
      if point and original then
        if index > 1 and index < #points then point.x = original.x + dx end
        point.y = norm_to_value(kind, original.y_norm + dy)
      end
    end
  end

  if state.dragging_points and ImGui.IsMouseReleased(ctx, 0) then
    state.dragging_points = nil
  end

  if hovered and ImGui.IsMouseClicked(ctx, 1) then
    local index = nearest_point(mx, my)
    if index then
      if not points[index].selected then select_only_point(kind, index) end
      local remove = selected_point_indices(kind)
      table.sort(remove, function(a, b) return a > b end)
      for _, remove_index in ipairs(remove) do
        if remove_index > 1 and remove_index < #points then table.remove(points, remove_index) end
      end
      state.selected_point = clamp(index - 1, 1, #points)
      select_only_point(kind, state.selected_point)
    end
  end

end

local function seeded_random(seed)
  local value = math.floor(seed or 1) % 2147483647
  if value <= 0 then value = 1 end
  return function()
    value = (value * 48271) % 2147483647
    return value / 2147483647
  end
end

local function preset_curve(kind, id)
  local rnd = seeded_random(math.floor(reaper.time_precise() * 100000) % 2147483647)

  if kind == 'Speed' then
    local presets = {
      FLAT = {P(0,1), P(1,1)},
      TAPE_STOP = {P(0,1,'smooth'), P(0.52,1,'bezier',0.35), P(0.78,0.58,'bezier',0.55), P(1,0.25)},
      TAPE_START = {P(0,0.25,'bezier',-0.45), P(0.2,0.55,'bezier',-0.2), P(0.46,1,'smooth'), P(1,1)},
      RAMP_UP = {P(0,0.5,'smooth'), P(1,2)},
      RAMP_DOWN = {P(0,2,'smooth'), P(1,0.5)},
      PUNCH = {P(0,1), P(0.33,1), P(0.5,3), P(0.67,1), P(1,1)},
    }
    return presets[id] or presets.FLAT
  end

  if kind == 'Volume' then
    if id == 'FLAT' then return {P(0,0), P(1,0)} end
    if id == 'ATTACK' then return {P(0,0,'bezier',0.55), P(0.035,7,'bezier',-0.4), P(0.16,0,'smooth'), P(1,0)} end
    if id == 'DUCK' then return {P(0,0), P(0.22,0,'bezier',0.4), P(0.5,-15,'bezier',-0.4), P(0.78,0,'smooth'), P(1,0)} end
    if id == 'TREMOLO' or id == 'PULSE' then
      local result = {}
      local cycles = id == 'TREMOLO' and 6 or 4
      local low = id == 'TREMOLO' and -8 or -18
      for i = 0, cycles * 2 do
        result[#result + 1] = P(i / (cycles * 2), i % 2 == 0 and 0 or low)
      end
      return result
    end
    if id == 'RANDOM' then
      local result = {P(0,0)}
      for i = 1, 11 do result[#result + 1] = P(i/12, -12 * rnd()) end
      result[#result + 1] = P(1,0)
      return result
    end
  end

  if kind == 'Pitch' then
    if id == 'FLAT' then return {P(0,0), P(1,0)} end
    if id == 'RISE' then return {P(0,0,'smooth'), P(1,12)} end
    if id == 'DIVE' then return {P(0,0,'smooth'), P(1,-12)} end
    if id == 'IMPACT' then return {P(0,4,'bezier',0.65), P(0.045,-14,'bezier',-0.5), P(0.26,-4,'smooth'), P(1,0)} end
    if id == 'FLUTTER' then
      local result = {}
      for i = 0, 16 do result[#result + 1] = P(i/16, i%2==0 and 1.5 or -1.5) end
      return result
    end
    if id == 'RANDOM' then
      local result = {P(0,0)}
      for i = 1, 11 do result[#result + 1] = P(i/12, (rnd()*2-1)*4) end
      result[#result + 1] = P(1,0)
      return result
    end
  end

  if kind == 'Pan' then
    if id == 'CENTER' then return {P(0,0), P(1,0)} end
    if id == 'LTR' then return {P(0,-1,'smooth'), P(1,1)} end
    if id == 'RTL' then return {P(0,1,'smooth'), P(1,-1)} end
    if id == 'BOUNCE' then return {P(0,0,'smooth'), P(0.25,-1,'smooth'), P(0.5,0,'smooth'), P(0.75,1,'smooth'), P(1,0)} end
    if id == 'ALTERNATE' then
      local result = {}
      for i = 0, 10 do result[#result + 1] = P(i/10, i%2==0 and -1 or 1) end
      return result
    end
    if id == 'RANDOM' then
      local result = {P(0,0)}
      for i = 1, 9 do result[#result + 1] = P(i/10, rnd()*2-1) end
      result[#result + 1] = P(1,0)
      return result
    end
  end

  return flat_curve(kind)
end

local PRESETS = {
  Speed = {
    {'FLAT','기본'}, {'TAPE_STOP','TAPE STOP'}, {'TAPE_START','TAPE START'},
    {'RAMP_UP','점점 빠르게'}, {'RAMP_DOWN','점점 느리게'}, {'PUNCH','SPEED PUNCH'},
  },
  Volume = {
    {'FLAT','기본'}, {'ATTACK','어택 강조'}, {'DUCK','덕킹'},
    {'TREMOLO','트레몰로'}, {'PULSE','펄스'}, {'RANDOM','랜덤 플러터'},
  },
  Pitch = {
    {'FLAT','기본'}, {'RISE','상승'}, {'DIVE','하강'},
    {'IMPACT','임팩트 드롭'}, {'FLUTTER','플러터'}, {'RANDOM','랜덤 디튠'},
  },
  Pan = {
    {'CENTER','센터'}, {'LTR','왼쪽 → 오른쪽'}, {'RTL','오른쪽 → 왼쪽'},
    {'BOUNCE','센터 바운스'}, {'ALTERNATE','좌우 교차'}, {'RANDOM','랜덤 팬'},
  },
}

local PRESET_LABELS_EN = {
  Speed = {
    FLAT='DEFAULT', TAPE_STOP='TAPE STOP', TAPE_START='TAPE START',
    RAMP_UP='SPEED UP', RAMP_DOWN='SLOW DOWN', PUNCH='SPEED PUNCH',
  },
  Volume = {
    FLAT='DEFAULT', ATTACK='ATTACK', DUCK='DUCK',
    TREMOLO='TREMOLO', PULSE='PULSE', RANDOM='RANDOM FLUTTER',
  },
  Pitch = {
    FLAT='DEFAULT', RISE='RISE', DIVE='DIVE',
    IMPACT='IMPACT DROP', FLUTTER='FLUTTER', RANDOM='RANDOM DETUNE',
  },
  Pan = {
    CENTER='CENTER', LTR='LEFT → RIGHT', RTL='RIGHT → LEFT',
    BOUNCE='CENTER BOUNCE', ALTERNATE='ALTERNATE', RANDOM='RANDOM PAN',
  },
}

local function preset_label(kind, preset)
  if state.language == 'en' then
    return (PRESET_LABELS_EN[kind] or {})[preset[1]] or preset[2]
  end
  return preset[2]
end

-- -----------------------------------------------------------------------------
-- User preset library
-- -----------------------------------------------------------------------------
local PresetDB = {}

function PresetDB.separator()
  return reaper.GetOS():match('Win') and '\\' or '/'
end

function PresetDB.directory()
  return reaper.GetResourcePath() .. PresetDB.separator()
    .. 'Data' .. PresetDB.separator() .. 'YSL Tools'
    .. PresetDB.separator() .. 'Item Envelope Manager'
end

function PresetDB.path()
  return PresetDB.directory() .. PresetDB.separator() .. 'user_presets.dat'
end

function PresetDB.escape(value)
  return tostring(value or ''):gsub('\\', '\\\\'):gsub('\t', '\\t'):gsub('\r', '\\r'):gsub('\n', '\\n')
end

function PresetDB.unescape(value)
  local result, i = {}, 1
  value = tostring(value or '')
  while i <= #value do
    local char = value:sub(i, i)
    if char == '\\' and i < #value then
      local next_char = value:sub(i + 1, i + 1)
      if next_char == 't' then result[#result + 1] = '\t'
      elseif next_char == 'r' then result[#result + 1] = '\r'
      elseif next_char == 'n' then result[#result + 1] = '\n'
      else result[#result + 1] = next_char end
      i = i + 2
    else
      result[#result + 1] = char
      i = i + 1
    end
  end
  return table.concat(result)
end

function PresetDB.save_file()
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(PresetDB.directory(), 0)
  end
  local lines = {'YSL_ITEM_ENVELOPE_PRESETS_V1'}
  table.sort(state.user_presets, function(a, b)
    if a.kind == b.kind then return tostring(a.name):lower() < tostring(b.name):lower() end
    return tostring(a.kind) < tostring(b.kind)
  end)
  for _, preset in ipairs(state.user_presets) do
    lines[#lines + 1] = table.concat({
      PresetDB.escape(preset.id), PresetDB.escape(preset.kind),
      PresetDB.escape(preset.name), PresetDB.escape(preset.curve),
      tostring(tonumber(preset.created_at) or os.time()),
    }, '\t')
  end

  local filename = PresetDB.path()
  local temporary = filename .. '.tmp'
  local backup = filename .. '.bak'
  os.remove(temporary)

  local file, open_error = io.open(temporary, 'wb')
  if not file then return false, '프리셋 임시 파일 생성 실패: ' .. tostring(open_error) end
  local write_ok, write_error = pcall(function()
    file:write(table.concat(lines, '\n') .. '\n')
    file:flush()
  end)
  file:close()
  if not write_ok then
    os.remove(temporary)
    return false, '프리셋 파일 쓰기 실패: ' .. tostring(write_error)
  end

  os.remove(backup)
  local old = io.open(filename, 'rb')
  if old then
    old:close()
    local moved, move_error = os.rename(filename, backup)
    if not moved then
      os.remove(temporary)
      return false, '기존 프리셋 보호 실패: ' .. tostring(move_error)
    end
  end

  local finalized, finalize_error = os.rename(temporary, filename)
  if not finalized then
    os.remove(temporary)
    os.rename(backup, filename)
    return false, '프리셋 파일 확정 실패: ' .. tostring(finalize_error)
  end

  local verify = io.open(filename, 'rb')
  if not verify then
    os.remove(filename)
    os.rename(backup, filename)
    return false, '저장된 프리셋 파일 검증 실패'
  end
  local first = verify:read('*l')
  verify:close()
  if first ~= 'YSL_ITEM_ENVELOPE_PRESETS_V1' then
    os.remove(filename)
    os.rename(backup, filename)
    return false, '저장된 프리셋 파일 형식 검증 실패'
  end
  return true
end

function PresetDB.load_file()
  state.user_presets = {}
  local file = io.open(PresetDB.path(), 'rb')
  if not file then return end
  local first = file:read('*l')
  if first ~= 'YSL_ITEM_ENVELOPE_PRESETS_V1' then file:close(); return end
  for line in file:lines() do
    local fields = {}
    for field in (line .. '\t'):gmatch('(.-)\t') do fields[#fields + 1] = field end
    if #fields >= 5 then
      local kind = PresetDB.unescape(fields[2])
      if TYPE_CONFIG[kind] then
        state.user_presets[#state.user_presets + 1] = {
          id = PresetDB.unescape(fields[1]),
          kind = kind,
          name = PresetDB.unescape(fields[3]),
          curve = PresetDB.unescape(fields[4]),
          created_at = tonumber(fields[5]) or 0,
        }
      end
    end
  end
  file:close()
end

function PresetDB.new_id()
  return tostring(os.time()) .. '_' .. tostring(math.floor(reaper.time_precise() * 1000000))
end

function PresetDB.save_current(kind, name)
  name = tostring(name or ''):match('^%s*(.-)%s*$') or ''
  if name == '' then return false, '프리셋 이름을 입력해주세요.' end
  for _, preset in ipairs(state.user_presets) do
    if preset.kind == kind and preset.name:lower() == name:lower() then
      preset.curve = serialize_curve(kind, state.curves[kind])
      preset.created_at = os.time()
      local ok, err = PresetDB.save_file()
      return ok, ok and '기존 사용자 프리셋을 업데이트했습니다.' or err
    end
  end
  state.user_presets[#state.user_presets + 1] = {
    id = PresetDB.new_id(),
    kind = kind,
    name = name,
    curve = serialize_curve(kind, state.curves[kind]),
    created_at = os.time(),
  }
  local ok, err = PresetDB.save_file()
  return ok, ok and '사용자 프리셋을 저장했습니다.' or err
end

function PresetDB.delete(id)
  for i, preset in ipairs(state.user_presets) do
    if preset.id == id then
      table.remove(state.user_presets, i)
      return PresetDB.save_file()
    end
  end
  return false, '프리셋을 찾지 못했습니다.'
end

function PresetDB.filtered(kind)
  local query = tostring(state.preset_search or ''):lower():match('^%s*(.-)%s*$') or ''
  local result = {}
  for _, preset in ipairs(state.user_presets) do
    if preset.kind == kind and (query == '' or preset.name:lower():find(query, 1, true)) then
      result[#result + 1] = preset
    end
  end
  table.sort(result, function(a, b) return a.name:lower() < b.name:lower() end)
  return result
end

PresetDB.load_file()

-- -----------------------------------------------------------------------------
-- Native take envelope creation/application
-- -----------------------------------------------------------------------------
local function split_lines(text)
  local lines = {}
  text = tostring(text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
  if text:sub(-1) ~= '\n' then text = text .. '\n' end
  for line in text:gmatch('(.-)\n') do lines[#lines + 1] = line end
  return lines
end

local function compute_depths(lines)
  local before, depth = {}, 0
  for i, line in ipairs(lines) do
    local trimmed = line:match('^%s*(.-)%s*$')
    if trimmed == '>' then depth = math.max(0, depth - 1) end
    before[i] = depth
    if trimmed:sub(1, 1) == '<' then depth = depth + 1 end
  end
  return before
end

local function resolve_take_envelope(take, key)
  if not valid_take(take) then return nil end
  local env = reaper.GetTakeEnvelopeByName(take, key)
  if env and reaper.ValidatePtr2(0, env, 'TrackEnvelope*') then return env end
  local target = key:lower()
  local target_alias = nil
  for _, spec in pairs(ENV_SPEC) do
    if spec.key == key then target_alias = spec.alias; break end
  end
  for i = 0, reaper.CountTakeEnvelopes(take) - 1 do
    local candidate = reaper.GetTakeEnvelope(take, i)
    if target_alias and reaper.GetEnvelopeStateChunk then
      local chunk_ok, envelope_chunk = reaper.GetEnvelopeStateChunk(candidate, '', false)
      if chunk_ok and tostring(envelope_chunk):match('^<' .. target_alias .. '[%s\r\n]') then
        return candidate
      end
    end
    local ok, name = reaper.GetEnvelopeName(candidate)
    if ok and tostring(name):lower():find(target, 1, true) then return candidate end
  end
  return nil
end

local native_envelope_actions = {}

local function find_native_envelope_action(spec)
  if native_envelope_actions[spec.alias] ~= nil then
    return native_envelope_actions[spec.alias] or nil
  end
  if not reaper.SectionFromUniqueID or not reaper.kbd_enumerateActions then
    native_envelope_actions[spec.alias] = false
    return nil
  end

  local section = reaper.SectionFromUniqueID(0)
  if not section then
    native_envelope_actions[spec.alias] = false
    return nil
  end

  local fallback = nil
  for index = 0, 20000 do
    local command, name = reaper.kbd_enumerateActions(section, index)
    if not command or command == 0 then break end
    local lower = tostring(name or ''):lower()
    for _, fragment in ipairs(spec.action_text or {}) do
      if lower:find(fragment, 1, true) then
        if lower:find('toggle', 1, true) then
          native_envelope_actions[spec.alias] = command
          return command
        end
        fallback = fallback or command
      end
    end
  end
  native_envelope_actions[spec.alias] = fallback or false
  return fallback
end

local function create_take_envelope_with_native_action(item, take, spec)
  local command = find_native_envelope_action(spec)
  if not command then return nil end

  local selected_guids = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local candidate = reaper.GetMediaItem(0, i)
    if reaper.IsMediaItemSelected(candidate) then
      selected_guids[#selected_guids + 1] = get_item_guid(candidate)
    end
  end

  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.SetActiveTake(take)
  reaper.Main_OnCommandEx(command, 0, 0)
  reaper.SelectAllMediaItems(0, false)
  for _, guid in ipairs(selected_guids) do
    local candidate = find_item_by_guid(guid)
    if valid_item(candidate) then reaper.SetMediaItemSelected(candidate, true) end
  end

  local refreshed_take = find_take_by_guid(get_take_guid(take)) or take
  return resolve_take_envelope(refreshed_take, spec.key)
end

local function create_take_envelope(item, take, spec)
  local existing = resolve_take_envelope(take, spec.key)
  if existing then return existing end

  -- Prefer REAPER's own Take envelope action. This preserves REAPER's current
  -- pitch-envelope range/snap settings and avoids hand-building state chunks.
  local native = create_take_envelope_with_native_action(item, take, spec)
  if native then return native end

  -- Portable fallback for localized/custom action lists where the native
  -- command cannot be resolved.
  local ok, chunk = reaper.GetItemStateChunk(item, '', false)
  if not ok or chunk == '' then return nil, '아이템 상태를 읽지 못했습니다.' end
  local take_guid = get_take_guid(take)
  if not take_guid then return nil, '테이크 GUID를 읽지 못했습니다.' end

  local lines = split_lines(chunk)
  local depths = compute_depths(lines)
  local guid_index = nil
  for i, line in ipairs(lines) do
    if line:find(take_guid, 1, true) then guid_index = i; break end
  end
  if not guid_index then return nil, '현재 테이크 블록을 찾지 못했습니다.' end

  local insert_index = nil
  for i = guid_index + 1, #lines do
    local trimmed = lines[i]:match('^%s*(.-)%s*$')
    if depths[i] == 1 and trimmed:match('^TAKE%s') then insert_index = i; break end
    if trimmed == '>' and depths[i] == 0 then insert_index = i; break end
  end
  if not insert_index then return nil, '테이크 블록 끝을 찾지 못했습니다.' end

  local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
  local block = {
    '<' .. spec.alias,
    'EGUID ' .. reaper.genGuid(),
    'ACT 1 -1',
    'VIS 1 0 1.000000',
    'LANEHEIGHT 0 0',
    'ARM 0',
    'DEFSHAPE 0 -1 -1',
    string.format('PT 0.000000000000 %.12f 0 0 0', spec.default),
    string.format('PT %.12f %.12f 0 0 0', item_len, spec.default),
    '>',
  }
  for i = #block, 1, -1 do table.insert(lines, insert_index, block[i]) end

  local item_guid = get_item_guid(item)
  local set_ok = reaper.SetItemStateChunk(item, table.concat(lines, '\n'), false)
  if not set_ok then return nil, '엔벨로프 생성에 실패했습니다.' end

  local refreshed_item = find_item_by_guid(item_guid) or item
  local refreshed_take = find_take_by_guid(take_guid) or take
  return resolve_take_envelope(refreshed_take, spec.key)
end

local function replace_envelope_chunk_line(chunk, key, replacement)
  local pattern = '([\r\n])' .. key .. '[^\r\n]*'
  local replaced, count = tostring(chunk or ''):gsub(
    pattern, '%1' .. replacement, 1)
  if count > 0 then return replaced end
  local first_break = replaced:find('[\r\n]')
  if not first_break then return replaced end
  return replaced:sub(1, first_break)
    .. replacement .. '\n' .. replaced:sub(first_break + 1)
end

local function envelope_chunk_enabled(env)
  if not env or not reaper.GetEnvelopeStateChunk then return false end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, '', false)
  if not ok then return false end
  local active = tonumber(tostring(chunk):match('[\r\n]ACT%s+([%-%d]+)')) or 0
  local visible = tonumber(tostring(chunk):match('[\r\n]VIS%s+([%-%d]+)')) or 0
  return active ~= 0 and visible ~= 0
end

local function set_envelope_chunk_enabled(env, enabled)
  if not env or not reaper.GetEnvelopeStateChunk
      or not reaper.SetEnvelopeStateChunk then
    return false, '엔벨로프 상태 API를 사용할 수 없습니다.'
  end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, '', false)
  if not ok or chunk == '' then return false, '엔벨로프 상태를 읽지 못했습니다.' end

  chunk = replace_envelope_chunk_line(
    chunk, 'ACT', enabled and 'ACT 1 -1' or 'ACT 0 -1')
  chunk = replace_envelope_chunk_line(
    chunk, 'VIS', enabled and 'VIS 1 0 1.000000' or 'VIS 0 0 1.000000')
  chunk = replace_envelope_chunk_line(chunk, 'ARM', 'ARM 0')
  local set_ok = reaper.SetEnvelopeStateChunk(env, chunk, false)
  if not set_ok then return false, '엔벨로프 상태를 저장하지 못했습니다.' end
  return true
end

take_envelope_enabled = function(kind, take)
  local spec = ENV_SPEC[kind]
  if not spec or not valid_take(take) then return false end
  return envelope_chunk_enabled(resolve_take_envelope(take, spec.key))
end

set_take_envelope_enabled = function(kind, item, take, enabled)
  local spec = ENV_SPEC[kind]
  if not spec or not valid_item(item) or not valid_take(take) then
    return false, '활성 오디오 Take가 없습니다.'
  end

  local take_guid = get_take_guid(take)
  local env = resolve_take_envelope(take, spec.key)
  local create_error = nil
  if enabled and not env then
    env, create_error = create_take_envelope(item, take, spec)
    take = find_take_by_guid(take_guid) or take
    env = env or resolve_take_envelope(take, spec.key)
  end
  if not env then
    return false, create_error or (spec.key .. ' 엔벨로프가 없습니다.')
  end

  local ok, err = set_envelope_chunk_enabled(env, enabled)
  if not ok then return false, err end
  reaper.TrackList_AdjustWindows(false)
  refresh(item)
  return true, env, take
end

local function env_evaluate(env, time, fallback)
  if not env or not reaper.Envelope_Evaluate then return fallback end
  local ok, value = reaper.Envelope_Evaluate(env, time, 0, 0)
  return ok and value or fallback
end

local function envelope_scaling_mode(env)
  if env and reaper.GetEnvelopeScalingMode then
    return tonumber(reaper.GetEnvelopeScalingMode(env)) or 0
  end
  return 0
end

local function envelope_value_from_editor(kind, env, value)
  if kind ~= 'Volume' then return value end
  local amplitude = db_to_amp(value)
  if reaper.ScaleToEnvelopeMode then
    return reaper.ScaleToEnvelopeMode(envelope_scaling_mode(env), amplitude)
  end
  return amplitude
end

local function editor_value_from_envelope(kind, env, value)
  if kind ~= 'Volume' then
    return clamp(value, TYPE_CONFIG[kind].min, TYPE_CONFIG[kind].max)
  end
  local amplitude = value
  if reaper.ScaleFromEnvelopeMode then
    amplitude = reaper.ScaleFromEnvelopeMode(envelope_scaling_mode(env), value)
  end
  return clamp(amp_to_db(amplitude), TYPE_CONFIG.Volume.min, TYPE_CONFIG.Volume.max)
end

local function point_line_distance(point, first, last, kind)
  local px, py = point.x, value_to_norm(kind, point.y)
  local ax, ay = first.x, value_to_norm(kind, first.y)
  local bx, by = last.x, value_to_norm(kind, last.y)
  local dx, dy = bx - ax, by - ay
  local length2 = dx * dx + dy * dy
  if length2 <= 0.0000000001 then
    return math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
  end
  local t = clamp(((px - ax) * dx + (py - ay) * dy) / length2, 0, 1)
  local qx, qy = ax + dx * t, ay + dy * t
  return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

local function simplify_curve_points(kind, points, tolerance)
  if #points <= 2 then return points end
  local keep = {[1]=true, [#points]=true}

  local function simplify(first_index, last_index)
    if last_index - first_index <= 1 then return end
    local greatest, selected = -1, nil
    for index = first_index + 1, last_index - 1 do
      local distance = point_line_distance(
        points[index], points[first_index], points[last_index], kind)
      if distance > greatest then
        greatest, selected = distance, index
      end
    end
    if selected and greatest > tolerance then
      keep[selected] = true
      simplify(first_index, selected)
      simplify(selected, last_index)
    end
  end

  simplify(1, #points)
  local result = {}
  for index, point in ipairs(points) do
    if keep[index] then result[#result + 1] = point end
  end
  return result
end

import_native_curve = function(kind, take, item, quiet)
  local spec = ENV_SPEC[kind]
  if not spec or not valid_take(take) or not valid_item(item) then
    return false, 0, '불러올 Take 엔벨로프가 없습니다.'
  end
  local env = resolve_take_envelope(take, spec.key)
  if not env then return false, 0, spec.key .. ' 엔벨로프가 아직 없습니다.' end
  if not take_envelope_enabled(kind, take) then
    return false, 0, tr(
      type_label(kind) .. ' envelope is locked.',
      type_label(kind) .. ' 엔벨로프가 잠겨 있습니다.')
  end

  local item_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
  local range_start, range_end = current_range(item)
  local a = clamp(range_start - item_pos, 0, item_len)
  local b = clamp(range_end - item_pos, 0, item_len)
  if b - a < 0.001 then return false, 0, '불러올 구간이 너무 짧습니다.' end

  -- Evaluate the native envelope at uniform positions and at every real point.
  -- RDP simplification then turns dense previously-written samples back into a
  -- manageable editable curve while preserving its audible shape.
  local times = {a, b}
  local resolution = 96
  for step = 1, resolution - 1 do
    times[#times + 1] = lerp(a, b, step / resolution)
  end
  for index = 0, reaper.CountEnvelopePoints(env) - 1 do
    local ok, time = reaper.GetEnvelopePoint(env, index)
    if ok and time > a and time < b then times[#times + 1] = time end
  end
  table.sort(times)

  local samples, previous_time = {}, nil
  for _, time in ipairs(times) do
    if not previous_time or math.abs(time - previous_time) > 0.0000001 then
      local raw = env_evaluate(env, time, spec.default)
      samples[#samples + 1] = {
        x = clamp((time - a) / (b - a), 0, 1),
        y = editor_value_from_envelope(kind, env, raw),
        shape = 'linear', tension = 0,
      }
      previous_time = time
    end
  end

  local tolerance = 0.005
  local simplified = simplify_curve_points(kind, samples, tolerance)
  while #simplified > 48 and tolerance < 0.04 do
    tolerance = tolerance * 1.5
    simplified = simplify_curve_points(kind, samples, tolerance)
  end
  state.curves[kind] = normalize_curve(kind, simplified)
  select_only_point(kind, math.min(2, #state.curves[kind]))
  state.dragging_points = nil
  state.dragging_segment = nil
  mark_curve_applied(kind)
  state.native_import_count[kind] = #state.curves[kind]

  if not quiet then
    set_status(string.format(
      tr(
        'Loaded existing %s envelope in the current range · %d edit points',
        '현재 구간의 기존 %s 엔벨로프를 불러왔습니다 · 편집 포인트 %d개'),
      type_label(kind), #state.curves[kind]), 4)
  end
  return true, #state.curves[kind]
end

local function force_envelope_line_visible(env)
  if not env then return end
  set_envelope_chunk_enabled(env, true)
end

local function force_take_envelope_lines_visible(take)
  if not valid_take(take) then return end
  for _, kind in ipairs({'Volume', 'Pitch', 'Pan'}) do
    local env = resolve_take_envelope(take, ENV_SPEC[kind].key)
    if env and envelope_chunk_enabled(env) then force_envelope_line_visible(env) end
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local TAKE_VALUE_FIELDS = {
  'D_STARTOFFS', 'D_VOL', 'D_PAN', 'D_PANLAW', 'D_PLAYRATE', 'D_PITCH',
  'B_PPITCH', 'I_CHANMODE', 'I_PITCHMODE', 'I_STRETCHFLAGS',
  'F_STRETCHFADESIZE', 'I_CUSTOMCOLOR',
}

function Preview.copy_envelope(item, source_take, dest_take, kind)
  local spec = ENV_SPEC[kind]
  local source_env = resolve_take_envelope(source_take, spec.key)
  if not source_env then return true end

  -- Snapshot before item-chunk mutation. Creating the destination envelope can
  -- invalidate envelope pointers belonging to the same MediaItem.
  local points = {}
  for i = 0, reaper.CountEnvelopePoints(source_env) - 1 do
    local ok, time, value, shape, tension, selected = reaper.GetEnvelopePoint(source_env, i)
    if ok then
      points[#points + 1] = {
        time=time, value=value, shape=shape,
        tension=tension, selected=selected,
      }
    end
  end
  local source_enabled = envelope_chunk_enabled(source_env)

  local dest_env, err = create_take_envelope(item, dest_take, spec)
  if not dest_env then return false, err end
  reaper.DeleteEnvelopePointRange(dest_env, -1e100, 1e100)
  for _, point in ipairs(points) do
    reaper.InsertEnvelopePoint(dest_env, point.time, point.value,
      point.shape, point.tension, point.selected, true)
  end
  reaper.Envelope_SortPoints(dest_env)
  set_envelope_chunk_enabled(dest_env, source_enabled)
  return true
end

function Preview.clone_take(item, source_take)
  if not valid_item(item) or not valid_take(source_take) then
    return nil, '복제할 테이크가 없습니다.'
  end

  local source_guid = get_take_guid(source_take)
  local new_take = reaper.AddTakeToMediaItem(item)
  if not valid_take(new_take) then return nil, 'Preview Take 생성에 실패했습니다.' end
  local function fail_clone(message)
    local candidate = find_take_by_guid(get_take_guid(new_take)) or new_take
    if valid_take(candidate) and Preview.delete_take then Preview.delete_take(item, candidate) end
    return nil, message
  end

  local source = reaper.GetMediaItemTake_Source(source_take)
  if not source then return fail_clone('복제할 오디오 소스를 찾지 못했습니다.') end
  reaper.SetMediaItemTake_Source(new_take, source)
  if not reaper.GetMediaItemTake_Source(new_take) then
    return fail_clone('Preview Take에 오디오 소스를 복사하지 못했습니다.')
  end

  for _, field in ipairs(TAKE_VALUE_FIELDS) do
    reaper.SetMediaItemTakeInfo_Value(
      new_take, field, reaper.GetMediaItemTakeInfo_Value(source_take, field))
  end

  local source_name = reaper.GetTakeName(source_take) or ''
  reaper.GetSetMediaItemTakeInfo_String(
    new_take, 'P_NAME',
    (source_name ~= '' and source_name or 'Take') .. ' [YSL Preview]', true)

  local stretch_count = reaper.GetTakeNumStretchMarkers(source_take)
  for i = 0, stretch_count - 1 do
    local retval, pos, srcpos = reaper.GetTakeStretchMarker(source_take, i)
    if retval >= 0 then
      local index = reaper.SetTakeStretchMarker(new_take, -1, pos, srcpos)
      if index >= 0 then
        reaper.SetTakeStretchMarkerSlope(
          new_take, index, reaper.GetTakeStretchMarkerSlope(source_take, i))
      end
    end
  end

  if reaper.GetNumTakeMarkers and reaper.GetTakeMarker and reaper.SetTakeMarker then
    for i = 0, reaper.GetNumTakeMarkers(source_take) - 1 do
      local position, name, color = reaper.GetTakeMarker(source_take, i)
      if position and position >= 0 then
        reaper.SetTakeMarker(new_take, -1, name or '', position, color or 0)
      end
    end
  end

  if reaper.TakeFX_CopyToTake then
    local fx_count = reaper.TakeFX_GetCount(source_take)
    for i = 0, fx_count - 1 do
      reaper.TakeFX_CopyToTake(source_take, i, new_take, reaper.TakeFX_GetCount(new_take), false)
    end
  end

  local new_guid = get_take_guid(new_take)
  for _, kind in ipairs({'Volume', 'Pitch', 'Pan'}) do
    new_take = find_take_by_guid(new_guid) or new_take
    source_take = find_take_by_guid(source_guid) or source_take
    local ok, err = Preview.copy_envelope(item, source_take, new_take, kind)
    if not ok then return fail_clone(err) end
  end

  return find_take_by_guid(new_guid) or new_take
end

function Preview.write_metadata()
  if not state.preview.active then return end
  local preview_take = find_take_by_guid(state.preview.preview_guid)
  local original_take = find_take_by_guid(state.preview.original_guid)
  if valid_take(preview_take) then
    take_ext_set(preview_take, 'YSL_PREVIEW_ROLE', 'preview')
    take_ext_set(preview_take, 'YSL_PREVIEW_ORIGINAL_GUID', state.preview.original_guid)
    take_ext_set(preview_take, 'YSL_PREVIEW_ORIGINAL_LENGTH', state.preview.original_length)
    take_ext_set(preview_take, 'YSL_PREVIEW_CURRENT_LENGTH', state.preview.preview_length)
    take_ext_set(preview_take, 'YSL_PREVIEW_ORIGINAL_NAME', state.preview.original_name)
  end
  if valid_take(original_take) then
    take_ext_set(original_take, 'YSL_PREVIEW_ROLE', 'original')
    take_ext_set(original_take, 'YSL_PREVIEW_PREVIEW_GUID', state.preview.preview_guid)
  end
end

function Preview.clear_metadata()
  local preview_take = find_take_by_guid(state.preview.preview_guid)
  local original_take = find_take_by_guid(state.preview.original_guid)
  for _, take in ipairs({preview_take, original_take}) do
    if valid_take(take) then
      for _, key in ipairs({
        'YSL_PREVIEW_ROLE', 'YSL_PREVIEW_ORIGINAL_GUID',
        'YSL_PREVIEW_PREVIEW_GUID', 'YSL_PREVIEW_ORIGINAL_LENGTH',
        'YSL_PREVIEW_CURRENT_LENGTH', 'YSL_PREVIEW_ORIGINAL_NAME',
      }) do
        take_ext_set(take, key, '')
      end
    end
  end
end

function Preview.create()
  if state.preview.active then
    return Preview.switch('preview')
  end
  if not valid_item(state.item) or not valid_take(state.take) then
    return false, '오디오 아이템을 선택해주세요.'
  end

  local item = state.item
  local original_take = state.take
  local original_guid = get_take_guid(original_take)
  local original_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local original_name = reaper.GetTakeName(original_take) or ''

  reaper.Undo_BeginBlock2(0)
  local preview_take, err = Preview.clone_take(item, original_take)
  if not preview_take then
    reaper.Undo_EndBlock2(0, APP_NAME .. ': Preview Take creation failed', -1)
    return false, err
  end

  state.preview.active = true
  state.preview.item_guid = get_item_guid(item)
  state.preview.original_guid = original_guid
  state.preview.preview_guid = get_take_guid(preview_take)
  state.preview.original_length = original_length
  state.preview.preview_length = original_length
  state.preview.original_name = original_name
  state.preview.current = 'preview'
  Preview.write_metadata()

  reaper.SetActiveTake(preview_take)
  state.take = preview_take
  state.take_guid = state.preview.preview_guid
  reaper.Undo_EndBlock2(0, APP_NAME .. ': Create Preview Take', -1)
  refresh(item)
  return true
end

function Preview.switch(target)
  if not state.preview.active then return false, 'Preview Take가 없습니다.' end
  local item = find_item_by_guid(state.preview.item_guid)
  local guid = target == 'original'
      and state.preview.original_guid or state.preview.preview_guid
  local take = find_take_by_guid(guid)
  if not valid_item(item) or not valid_take(take) then
    Preview.clear_state()
    return false, 'Preview 세션을 복구하지 못했습니다.'
  end

  local length = target == 'original'
      and state.preview.original_length or state.preview.preview_length
  reaper.SetMediaItemLength(item, math.max(0.001, tonumber(length) or 0.001), false)
  reaper.SetActiveTake(take)
  state.item = item
  state.take = take
  state.take_guid = guid
  state.preview.current = target
  invalidate_wave()
  refresh(item)
  return true
end

function Preview.ensure_editable()
  if not state.preview.active then
    local ok, err = Preview.create()
    if not ok then return false, err end
  end
  return Preview.switch('preview')
end

function Preview.capture_selection()
  local selected = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    if reaper.IsMediaItemSelected(item) then selected[#selected + 1] = get_item_guid(item) end
  end
  return selected
end

function Preview.restore_selection(guids)
  reaper.SelectAllMediaItems(0, false)
  for _, guid in ipairs(guids or {}) do
    local item = find_item_by_guid(guid)
    if valid_item(item) then reaper.SetMediaItemSelected(item, true) end
  end
end

function Preview.delete_take(item, take)
  if not valid_item(item) or not valid_take(take) or reaper.CountTakes(item) <= 1 then
    return false
  end
  local before = reaper.CountTakes(item)
  local selected = Preview.capture_selection()
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.SetActiveTake(take)
  reaper.Main_OnCommand(40129, 0)
  Preview.restore_selection(selected)
  return reaper.CountTakes(item) == before - 1
end

function Preview.commit()
  if not state.preview.active then return false, 'Commit할 Preview Take가 없습니다.' end
  local item = find_item_by_guid(state.preview.item_guid)
  local preview_take = find_take_by_guid(state.preview.preview_guid)
  local original_take = find_take_by_guid(state.preview.original_guid)
  if not valid_item(item) or not valid_take(preview_take) or not valid_take(original_take) then
    return false, 'Preview 세션을 찾지 못했습니다.'
  end

  reaper.Undo_BeginBlock2(0)
  Preview.switch('preview')
  force_take_envelope_lines_visible(preview_take)
  Preview.clear_metadata()
  local stored_preview_name = reaper.GetTakeName(preview_take) or ''
  local preview_name = stored_preview_name:gsub('%s*%[YSL Preview%]$', '')
  reaper.GetSetMediaItemTakeInfo_String(preview_take, 'P_NAME', preview_name, true)
  local deleted = Preview.delete_take(item, original_take)
  if not deleted then
    reaper.GetSetMediaItemTakeInfo_String(preview_take, 'P_NAME', stored_preview_name, true)
    Preview.write_metadata()
    reaper.Undo_EndBlock2(0, APP_NAME .. ': Commit Preview failed', -1)
    return false, 'Original Take를 제거하지 못했습니다.'
  end
  state.take = reaper.GetActiveTake(item)
  state.take_guid = get_take_guid(state.take)
  force_take_envelope_lines_visible(state.take)
  Preview.clear_state()
  reaper.Undo_EndBlock2(0, APP_NAME .. ': Commit Preview Take', -1)
  refresh(item)
  return true
end

function Preview.revert()
  if not state.preview.active then return false, '되돌릴 Preview Take가 없습니다.' end
  local item = find_item_by_guid(state.preview.item_guid)
  local preview_take = find_take_by_guid(state.preview.preview_guid)
  local original_take = find_take_by_guid(state.preview.original_guid)
  if not valid_item(item) or not valid_take(preview_take) or not valid_take(original_take) then
    return false, 'Preview 세션을 찾지 못했습니다.'
  end

  reaper.Undo_BeginBlock2(0)
  reaper.SetMediaItemLength(item, state.preview.original_length, false)
  reaper.SetActiveTake(original_take)
  Preview.clear_metadata()
  local deleted = Preview.delete_take(item, preview_take)
  if not deleted then
    Preview.write_metadata()
    reaper.Undo_EndBlock2(0, APP_NAME .. ': Revert Preview failed', -1)
    return false, 'Preview Take를 제거하지 못했습니다.'
  end
  state.take = reaper.GetActiveTake(item)
  state.take_guid = get_take_guid(state.take)
  Preview.clear_state()
  load_curves(state.take)
  invalidate_wave()
  reaper.Undo_EndBlock2(0, APP_NAME .. ': Revert Preview Take', -1)
  refresh(item)
  return true
end

local function preview_operation_on_selected(operation, target)
  local items = collect_selected_audio_items()
  local anchor_guid = state.item_guid
  local ranges_norm = copy_selection_ranges_norm(state.selection_ranges_norm)
  local active_selection = state.active_selection
  local processed = 0

  for _, item in ipairs(items) do
    state.item = item
    state.item_guid = get_item_guid(item)
    state.take = reaper.GetActiveTake(item)
    state.take_guid = get_take_guid(state.take)
    Preview.clear_state()
    Preview.recover(item)
    if state.preview.active or operation == 'create' then
      local ok, err
      if operation == 'create' then
        ok, err = Preview.ensure_editable()
      elseif operation == 'switch' then
        ok, err = Preview.switch(target)
      elseif operation == 'commit' then
        ok, err = Preview.commit()
      else
        ok, err = Preview.revert()
      end
      if not ok then
        local anchor = find_item_by_guid(anchor_guid)
        if valid_item(anchor) then reset_item_context(anchor) end
        return false, processed, err
      end
      processed = processed + 1
    end
  end

  local anchor = find_item_by_guid(anchor_guid)
  if valid_item(anchor) then
    reset_item_context(anchor)
    set_selection_ranges_norm(ranges_norm, active_selection)
  end
  return true, processed
end


local ENVELOPE_TOLERANCE = {
  Volume = 0.0015, -- raw envelope units after scaling-mode conversion
  Pitch = 0.02,  -- semitone
  Pan = 0.002,
}

local function sample_curve_for_envelope(kind, env)
  local curve = normalize_curve(kind, state.curves[kind])
  local result = {{x=curve[1].x, y=curve[1].y}}
  local target_resolution = math.floor(clamp(state.envelope_resolution, 16, 96))
  local tolerance = ENVELOPE_TOLERANCE[kind] or 0.002

  local function append(x, y)
    local last = result[#result]
    if last and math.abs(last.x - x) < 0.0000001 then
      last.y = y
    else
      result[#result + 1] = {x=x, y=y}
    end
  end

  for index = 1, #curve - 1 do
    local a, b = curve[index], curve[index + 1]
    if a.shape == 'linear' then
      append(b.x, b.y)
    else
      local estimated = math.max(4, math.ceil((b.x - a.x) * target_resolution))
      local max_depth = clamp(math.ceil(math.log(estimated, 2)), 2, 7)

      local function value_at(t)
        return curve_segment_value(a, b, t)
      end

      local function subdivide(t0, v0, t1, v1, depth)
        local span = t1 - t0
        local q1 = t0 + span * 0.25
        local qm = t0 + span * 0.50
        local q3 = t0 + span * 0.75
        local yq1, yqm, yq3 = value_at(q1), value_at(qm), value_at(q3)
        local aq1 = envelope_value_from_editor(kind, env, yq1)
        local aqm = envelope_value_from_editor(kind, env, yqm)
        local aq3 = envelope_value_from_editor(kind, env, yq3)
        local raw0 = envelope_value_from_editor(kind, env, v0)
        local raw1 = envelope_value_from_editor(kind, env, v1)
        local lq1 = lerp(raw0, raw1, 0.25)
        local lqm = lerp(raw0, raw1, 0.50)
        local lq3 = lerp(raw0, raw1, 0.75)
        local error = math.max(
          math.abs(aq1 - lq1), math.abs(aqm - lqm), math.abs(aq3 - lq3))

        if depth < 2 or (error > tolerance and depth < max_depth) then
          subdivide(t0, v0, qm, yqm, depth + 1)
          subdivide(qm, yqm, t1, v1, depth + 1)
        else
          append(lerp(a.x, b.x, t1), v1)
        end
      end

      subdivide(0, a.y, 1, b.y, 0)
    end
  end
  return result
end

local function verify_envelope_write(env, kind, a, b, sampled)
  if not env or #sampled == 0 then return false, '확인할 엔벨로프 포인트가 없습니다.' end

  local spec = ENV_SPEC[kind]
  local probe = sampled[1]
  local greatest = -1
  for _, point in ipairs(sampled) do
    local raw = envelope_value_from_editor(kind, env, point.y)
    local default_raw = envelope_value_from_editor(
      kind, env, TYPE_CONFIG[kind].baseline)
    local distance = math.abs(raw - default_raw)
    if distance > greatest then
      greatest = distance
      probe = point
    end
  end

  local expected_time = a + (b - a) * probe.x
  local expected_value = envelope_value_from_editor(kind, env, probe.y)
  local point_index = reaper.GetEnvelopePointByTime(env, expected_time)
  if not point_index or point_index < 0 then
    return false, '작성한 엔벨로프 포인트를 다시 찾지 못했습니다.'
  end
  local ok, actual_time, actual_value = reaper.GetEnvelopePoint(env, point_index)
  if not ok
      or math.abs(actual_time - expected_time) > 0.0001
      or math.abs(actual_value - expected_value) > 0.0001 then
    return false, kind == 'Pitch'
      and '피치 엔벨로프 값이 REAPER에 정확히 기록되지 않았습니다.'
      or '엔벨로프 기록값 검증에 실패했습니다.'
  end
  return true
end

local function apply_native_envelope(kind, item, take)
  local spec = ENV_SPEC[kind]
  if not spec then return false, '지원하지 않는 엔벨로프입니다.' end

  local item_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local project_ranges = current_ranges(item)
  local local_ranges = {}
  for _, range in ipairs(project_ranges) do
    local a = clamp(range.a - item_pos, 0, item_len)
    local b = clamp(range.b - item_pos, 0, item_len)
    if b - a >= 0.001 then local_ranges[#local_ranges + 1] = {a=a, b=b} end
  end
  if #local_ranges == 0 then return false, '적용 구간이 너무 짧습니다.' end

  local take_guid = get_take_guid(take)
  local undo_open = false
  local function abort_apply(message)
    if undo_open then
      reaper.Undo_EndBlock2(0, APP_NAME .. ': Failed ' .. kind .. ' curve', -1)
      undo_open = false
      reaper.Undo_DoUndo2(0)
    end
    refresh(item)
    return false, message
  end

  reaper.Undo_BeginBlock2(0)
  undo_open = true

  local env, create_error = create_take_envelope(item, take, spec)
  take = find_take_by_guid(take_guid) or take
  env = env or resolve_take_envelope(take, spec.key)
  if not env then
    return abort_apply(create_error or (spec.key .. ' 엔벨로프를 생성하지 못했습니다.'))
  end

  local sampled = sample_curve_for_envelope(kind, env)
  local write_ranges = {}

  -- Capture every boundary before deleting anything. This preserves the native
  -- envelope in all gaps between disjoint selected ranges.
  for _, range in ipairs(local_ranges) do
    local span = range.b - range.a
    local guard = math.min(0.0001, math.max(0.000001, span * 0.001))
    write_ranges[#write_ranges + 1] = {
      a = range.a,
      b = range.b,
      guard = guard,
      before = env_evaluate(
        env, math.max(0, range.a - guard * 2), spec.default),
      after = env_evaluate(
        env, math.min(item_len, range.b + guard * 2), spec.default),
    }
  end

  for _, range in ipairs(write_ranges) do
    local a, b, guard = range.a, range.b, range.guard
    -- REAPER's upper bound is exclusive. The extra fraction also removes an
    -- earlier YSL guard so repeated multi-range Apply replaces instead of stacks.
    local cleanup_start = math.max(-guard, a - guard * 1.5)
    local cleanup_end = math.min(
      item_len + guard, b + guard * 1.5) + guard * 0.1
    reaper.DeleteEnvelopePointRange(env, cleanup_start, cleanup_end)
    if a > guard then
      if not reaper.InsertEnvelopePoint(
          env, a - guard, range.before, 0, 0, false, true) then
        return abort_apply('적용 구간 앞의 엔벨로프 값을 보존하지 못했습니다.')
      end
    end
    for _, point in ipairs(sampled) do
      local time = a + (b - a) * point.x
      local value = envelope_value_from_editor(kind, env, point.y)
      if not reaper.InsertEnvelopePoint(
          env, time, value, 0, 0, false, true) then
        return abort_apply(spec.key .. ' 엔벨로프 포인트 작성에 실패했습니다.')
      end
    end
    if b < item_len - guard then
      if not reaper.InsertEnvelopePoint(
          env, b + guard, range.after, 0, 0, false, true) then
        return abort_apply('적용 구간 뒤의 엔벨로프 값을 보존하지 못했습니다.')
      end
    end
  end

  reaper.Envelope_SortPoints(env)
  for _, range in ipairs(write_ranges) do
    local verified, verify_error = verify_envelope_write(
      env, kind, range.a, range.b, sampled)
    if not verified then return abort_apply(verify_error) end
  end

  force_envelope_line_visible(env)
  store_applied_curve_on_take(
    kind, take, write_ranges[1].a, write_ranges[1].b, item_len, write_ranges)
  reaper.TrackList_AdjustWindows(false)
  reaper.Undo_EndBlock2(0, APP_NAME .. ': Apply native Take ' .. kind .. ' envelope', -1)
  undo_open = false
  state.take = take
  state.take_guid = get_take_guid(take)
  refresh(item)
  return true, #sampled * #write_ranges
end

-- -----------------------------------------------------------------------------
-- Single-item speed envelope
-- No item split is performed. The item length and stretch-marker timeline are
-- rebuilt so audio before and after the selected region keeps its prior mapping.
-- -----------------------------------------------------------------------------
local function collect_take_map(take, item_len)
  local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
  local playrate = math.max(0.000001, reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE'))
  local markers = {}
  local count = reaper.GetTakeNumStretchMarkers(take)
  for i = 0, count - 1 do
    local retval, pos, srcpos = reaper.GetTakeStretchMarker(take, i)
    if retval >= 0 then
      markers[#markers + 1] = {
        pos = pos,
        src = srcpos,
        slope = reaper.GetTakeStretchMarkerSlope(take, i),
      }
    end
  end
  table.sort(markers, function(a, b) return a.pos < b.pos end)

  local anchors = {P(0, startoffs)}
  for _, marker in ipairs(markers) do
    anchors[#anchors + 1] = P(marker.pos, marker.src)
  end
  anchors[#anchors + 1] = P(item_len, startoffs + item_len * playrate)
  table.sort(anchors, function(a, b) return a.x < b.x end)

  local deduped = {}
  for _, anchor in ipairs(anchors) do
    if #deduped > 0 and math.abs(deduped[#deduped].x - anchor.x) < 0.0000001 then
      deduped[#deduped] = anchor
    else
      deduped[#deduped + 1] = anchor
    end
  end

  local function source_at(pos)
    pos = clamp(pos, 0, item_len)
    for i = 1, #deduped - 1 do
      local a, b = deduped[i], deduped[i + 1]
      if pos <= b.x + 0.0000001 then
        local span = math.max(0.0000001, b.x - a.x)
        return lerp(a.y, b.y, (pos - a.x) / span)
      end
    end
    return deduped[#deduped].y
  end

  return {
    take = take,
    markers = markers,
    source_at = source_at,
    start_source = source_at(0),
    end_source = source_at(item_len),
  }
end

local function add_marker_record(records, pos, src, slope, priority)
  records[#records + 1] = {
    pos = pos,
    src = src,
    slope = slope or 0,
    priority = priority or 0,
  }
end

local function rebuild_take_markers(data, local_start, local_end,
    new_region_len, delta, old_item_len, new_item_len, resolution)
  local take = data.take
  local epsilon = 0.000001
  local source_start = data.source_at(local_start)
  local source_end = data.source_at(local_end)
  local records = {}

  add_marker_record(records, 0, data.start_source, 0, 100)

  for _, marker in ipairs(data.markers) do
    if marker.pos > epsilon and marker.pos < local_start - epsilon then
      add_marker_record(records, marker.pos, marker.src, marker.slope, 20)
    end
  end

  add_marker_record(records, local_start, source_start, 0, 100)

  local original_region_len = local_end - local_start
  local project_pos = local_start
  for step = 1, resolution do
    local factor = curve_value_at('Speed', (step - 0.5) / resolution)
    project_pos = project_pos + (original_region_len / resolution) / factor
    local source_pos = source_start + (source_end - source_start) * (step / resolution)
    add_marker_record(records, project_pos, source_pos, 0, 100)
  end

  for _, marker in ipairs(data.markers) do
    if marker.pos > local_end + epsilon and marker.pos < old_item_len - epsilon then
      add_marker_record(records, marker.pos + delta, marker.src, marker.slope, 20)
    end
  end

  add_marker_record(records, new_item_len, data.end_source, 0, 100)
  table.sort(records, function(a, b)
    if math.abs(a.pos - b.pos) < epsilon then return a.priority < b.priority end
    return a.pos < b.pos
  end)

  local unique = {}
  for _, record in ipairs(records) do
    record.pos = clamp(record.pos, 0, new_item_len)
    if #unique > 0 and math.abs(unique[#unique].pos - record.pos) < epsilon then
      if record.priority >= unique[#unique].priority then unique[#unique] = record end
    else
      unique[#unique + 1] = record
    end
  end

  local old_count = reaper.GetTakeNumStretchMarkers(take)
  if old_count > 0 then reaper.DeleteTakeStretchMarkers(take, 0, old_count) end

  for _, record in ipairs(unique) do
    local index = reaper.SetTakeStretchMarker(take, -1, record.pos, record.src)
    if index >= 0 and math.abs(record.slope or 0) > 0.0000001 then
      reaper.SetTakeStretchMarkerSlope(take, index, record.slope)
    end
  end
end

local function serialize_local_ranges(ranges)
  local parts = {}
  for _, range in ipairs(ranges or {}) do
    local a = tonumber(range.a or range[1])
    local b = tonumber(range.b or range[2])
    if a and b then
      parts[#parts + 1] = string.format(
        '%.12f:%.12f', math.min(a, b), math.max(a, b))
    end
  end
  return table.concat(parts, ';')
end

local function parse_local_ranges(text)
  local ranges = {}
  for token in tostring(text or ''):gmatch('[^;]+') do
    local a, b = token:match('^([%d%.%-]+):([%d%.%-]+)$')
    a, b = tonumber(a), tonumber(b)
    if a and b and math.abs(b - a) >= 0.000001 then
      ranges[#ranges + 1] = {a=math.min(a, b), b=math.max(a, b)}
    end
  end
  table.sort(ranges, function(a, b) return a.a < b.a end)
  return ranges
end

local function local_ranges_match(first, second, tolerance)
  if #first ~= #second then return false end
  tolerance = tonumber(tolerance) or 0.0005
  for index = 1, #first do
    if math.abs(first[index].a - second[index].a) > tolerance
        or math.abs(first[index].b - second[index].b) > tolerance then
      return false
    end
  end
  return true
end

local function rebuild_take_markers_for_ranges(
    item, data, local_ranges, old_item_len, resolution)
  local take = data.take
  local epsilon = 0.000001
  local records = {}
  local output_ranges = {}
  local cumulative_delta = 0
  local previous_end = 0

  add_marker_record(records, 0, data.start_source, 0, 100)

  for _, range in ipairs(local_ranges) do
    local local_start = clamp(range.a, previous_end, old_item_len)
    local local_end = clamp(range.b, local_start, old_item_len)
    if local_end - local_start >= 0.000001 then
      for _, marker in ipairs(data.markers) do
        if marker.pos > previous_end + epsilon
            and marker.pos < local_start - epsilon then
          add_marker_record(
            records, marker.pos + cumulative_delta,
            marker.src, marker.slope, 20)
        end
      end

      local output_start = local_start + cumulative_delta
      add_marker_record(
        records, output_start, data.source_at(local_start), 0, 100)
      local output_pos = output_start
      local span = local_end - local_start
      for step = 1, resolution do
        local factor = curve_value_at('Speed', (step - 0.5) / resolution)
        output_pos = output_pos + (span / resolution) / factor
        local baseline_pos = local_start + span * (step / resolution)
        add_marker_record(
          records, output_pos, data.source_at(baseline_pos), 0, 100)
      end

      output_ranges[#output_ranges + 1] = {a=output_start, b=output_pos}
      cumulative_delta = cumulative_delta + (output_pos - output_start) - span
      previous_end = local_end
    end
  end

  for _, marker in ipairs(data.markers) do
    if marker.pos > previous_end + epsilon
        and marker.pos < old_item_len - epsilon then
      add_marker_record(
        records, marker.pos + cumulative_delta,
        marker.src, marker.slope, 20)
    end
  end

  local new_item_len = old_item_len + cumulative_delta
  add_marker_record(records, new_item_len, data.end_source, 0, 100)
  table.sort(records, function(a, b)
    if math.abs(a.pos - b.pos) < epsilon then return a.priority < b.priority end
    return a.pos < b.pos
  end)

  local unique = {}
  for _, record in ipairs(records) do
    record.pos = clamp(record.pos, 0, new_item_len)
    if #unique > 0 and math.abs(unique[#unique].pos - record.pos) < epsilon then
      if record.priority >= unique[#unique].priority then unique[#unique] = record end
    else
      unique[#unique + 1] = record
    end
  end

  reaper.SetMediaItemLength(item, new_item_len, false)
  local old_count = reaper.GetTakeNumStretchMarkers(take)
  if old_count > 0 then reaper.DeleteTakeStretchMarkers(take, 0, old_count) end
  for _, record in ipairs(unique) do
    local index = reaper.SetTakeStretchMarker(take, -1, record.pos, record.src)
    if index >= 0 and math.abs(record.slope or 0) > 0.0000001 then
      reaper.SetTakeStretchMarkerSlope(take, index, record.slope)
    end
  end
  return new_item_len, output_ranges
end

local function capture_speed_baseline(take, item_len, local_ranges)
  local header = table.concat({
    'V2',
    string.format('%.12f', item_len),
    string.format('%.12f', reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')),
    string.format('%.12f', reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')),
    serialize_local_ranges(local_ranges),
  }, ',')
  local markers = {}
  for index = 0, reaper.GetTakeNumStretchMarkers(take) - 1 do
    local retval, position, source_position = reaper.GetTakeStretchMarker(take, index)
    if retval >= 0 then
      markers[#markers + 1] = string.format('%.12f,%.12f,%.12f',
        position, source_position, reaper.GetTakeStretchMarkerSlope(take, index))
    end
  end
  return header .. '|' .. table.concat(markers, ';')
end

local function parse_speed_baseline(text)
  local header, marker_text = tostring(text or ''):match('^([^|]+)|?(.*)$')
  if not header then return nil end
  local baseline
  if header:sub(1, 3) == 'V2,' then
    local item_len, startoffs, playrate, ranges_text = header:match(
      '^V2,([^,]+),([^,]+),([^,]+),(.*)$')
    baseline = {
      item_len = tonumber(item_len),
      startoffs = tonumber(startoffs),
      playrate = tonumber(playrate),
      base_ranges = parse_local_ranges(ranges_text or ''),
      markers = {},
    }
  else
    local values = {}
    for token in header:gmatch('[^,]+') do values[#values + 1] = tonumber(token) end
    if #values < 5 or not values[1] or not values[2] or not values[3]
        or not values[4] or not values[5] then
      return nil
    end
    baseline = {
      item_len = values[1],
      local_start = values[2],
      local_end = values[3],
      startoffs = values[4],
      playrate = values[5],
      base_ranges = {{a=values[2], b=values[3]}},
      markers = {},
    }
  end
  if not baseline.item_len or not baseline.startoffs or not baseline.playrate then
    return nil
  end
  for token in tostring(marker_text or ''):gmatch('[^;]+') do
    local fields = {}
    for value in token:gmatch('[^,]+') do fields[#fields + 1] = tonumber(value) end
    if fields[1] and fields[2] then
      baseline.markers[#baseline.markers + 1] = {
        pos = fields[1], src = fields[2], slope = fields[3] or 0,
      }
    end
  end
  return baseline
end

local function restore_speed_baseline(item, take, baseline)
  reaper.SetMediaItemLength(item, baseline.item_len, false)
  reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', baseline.startoffs)
  reaper.SetMediaItemTakeInfo_Value(take, 'D_PLAYRATE', baseline.playrate)
  local count = reaper.GetTakeNumStretchMarkers(take)
  if count > 0 then reaper.DeleteTakeStretchMarkers(take, 0, count) end
  for _, marker in ipairs(baseline.markers) do
    local index = reaper.SetTakeStretchMarker(take, -1, marker.pos, marker.src)
    if index >= 0 and math.abs(marker.slope or 0) > 0.0000001 then
      reaper.SetTakeStretchMarkerSlope(take, index, marker.slope)
    end
  end
end

local function apply_speed_curve(item)
  local item_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local current_item_len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local project_ranges = current_ranges(item)
  local current_ranges_local = {}
  for _, range in ipairs(project_ranges) do
    local a = clamp(range.a - item_pos, 0, current_item_len)
    local b = clamp(range.b - item_pos, 0, current_item_len)
    if b - a >= 0.001 then
      current_ranges_local[#current_ranges_local + 1] = {a=a, b=b}
    end
  end
  if #current_ranges_local == 0 then return false, '적용 구간이 너무 짧습니다.' end

  local active_take = reaper.GetActiveTake(item)
  if not valid_take(active_take) or reaper.TakeIsMIDI(active_take) then
    return false, '적용할 오디오 Preview Take가 없습니다.'
  end

  -- If the same visible range set is applied again, rebuild every range from
  -- the one shared pre-apply baseline. This prevents multi-range speed edits
  -- from accumulating stretch markers or repeatedly changing the item length.
  local stored_text = take_ext_get(active_take, 'YSL_SPEED_REPLACE_BASE')
  local stored = parse_speed_baseline(stored_text)
  local stored_current_ranges = parse_local_ranges(
    take_ext_get(active_take, 'YSL_SPEED_CURRENT_RANGES'))
  local stored_current_start = tonumber(take_ext_get(active_take, 'YSL_SPEED_CURRENT_START'))
  local stored_current_end = tonumber(take_ext_get(active_take, 'YSL_SPEED_CURRENT_END'))
  local stored_current_length = tonumber(take_ext_get(active_take, 'YSL_SPEED_CURRENT_LENGTH'))
  if #stored_current_ranges == 0 and stored_current_start and stored_current_end then
    stored_current_ranges = {{a=stored_current_start, b=stored_current_end}}
  end
  local match_tolerance = 0.0005
  local replacing_previous = stored and stored_current_length
    and local_ranges_match(
      current_ranges_local, stored_current_ranges, match_tolerance)
    and math.abs(current_item_len - stored_current_length) <= match_tolerance

  local baseline_text = stored_text
  local baseline = stored
  if not replacing_previous then
    baseline_text = capture_speed_baseline(
      active_take, current_item_len, current_ranges_local)
    baseline = parse_speed_baseline(baseline_text)
  end
  if not baseline then return false, '속도 재적용 기준 정보를 만들지 못했습니다.' end

  local base_item_len = baseline.item_len
  local base_ranges = baseline.base_ranges or current_ranges_local
  for _, range in ipairs(base_ranges) do
    range.a = clamp(range.a, 0, base_item_len)
    range.b = clamp(range.b, range.a, base_item_len)
    if range.b - range.a < 0.01 then
      return false, '속도 적용 구간은 각각 0.01초 이상이어야 합니다.'
    end
  end

  local resolution = math.floor(clamp(state.speed_resolution, 8, 48))
  local new_item_len, output_ranges

  local undo_started = false
  local refresh_locked = false
  local ok, err = xpcall(function()
    reaper.Undo_BeginBlock2(0)
    undo_started = true
    reaper.PreventUIRefresh(1)
    refresh_locked = true

    if replacing_previous then
      restore_speed_baseline(item, active_take, baseline)
    end
    local data = collect_take_map(active_take, base_item_len)

    -- Keep one MediaItem. Only its length and take stretch-marker mapping change.
    new_item_len, output_ranges = rebuild_take_markers_for_ranges(
      item, data, base_ranges, base_item_len, resolution)
    if new_item_len < 0.005 then error('변형 후 아이템 길이가 너무 짧습니다.') end
    reaper.SetMediaItemTakeInfo_Value(
      active_take, 'B_PPITCH', state.preserve_pitch and 1 or 0)
    reaper.GetSetMediaItemTakeInfo_String(
      active_take, 'P_EXT:' .. TYPE_CONFIG.Speed.ext,
      serialize_curve('Speed', state.curves.Speed), true)
    take_ext_set(active_take, 'YSL_SPEED_REPLACE_BASE', baseline_text)
    take_ext_set(
      active_take, 'YSL_SPEED_BASE_RANGES', serialize_local_ranges(base_ranges))
    take_ext_set(
      active_take, 'YSL_SPEED_CURRENT_RANGES', serialize_local_ranges(output_ranges))
    take_ext_set(active_take, 'YSL_SPEED_CURRENT_START', output_ranges[1].a)
    take_ext_set(active_take, 'YSL_SPEED_CURRENT_END', output_ranges[1].b)
    take_ext_set(active_take, 'YSL_SPEED_CURRENT_LENGTH', new_item_len)

    reaper.PreventUIRefresh(-1)
    refresh_locked = false
    refresh(item)
    reaper.Undo_EndBlock2(0, APP_NAME .. ': Apply Speed curve in one item', -1)
    undo_started = false

    state.item = item
    state.item_guid = get_item_guid(item)
    state.take = reaper.GetActiveTake(item)
    state.take_guid = get_take_guid(state.take)
    mark_curve_applied('Speed')
    if state.preview.active and state.take_guid == state.preview.preview_guid then
      state.preview.preview_length = new_item_len
      state.preview.current = 'preview'
      Preview.write_metadata()
    end
    local normalized_output = {}
    for _, range in ipairs(output_ranges) do
      normalized_output[#normalized_output + 1] = {
        range.a / new_item_len, range.b / new_item_len,
      }
    end
    set_selection_ranges_norm(
      normalized_output, math.min(state.active_selection, #normalized_output))
    invalidate_wave()
  end, debug.traceback)

  if not ok then
    if refresh_locked then pcall(reaper.PreventUIRefresh, -1) end
    if undo_started then
      pcall(reaper.Undo_EndBlock2, 0, APP_NAME .. ': Speed curve failed', -1)
      pcall(reaper.Undo_DoUndo2, 0)
    end
    return false, err
  end
  return true, {length=new_item_len, ranges=output_ranges}
end

local function apply_current_curve()
  if not valid_item(state.item) or not valid_take(state.take) then
    return false, '오디오 아이템을 선택해주세요.'
  end

  local targets = collect_selected_audio_items()
  if #targets == 0 then return false, '선택한 오디오 아이템이 없습니다.' end
  local anchor_guid = state.item_guid
  local anchor_ranges_norm = copy_selection_ranges_norm(state.selection_ranges_norm)
  local anchor_active_selection = state.active_selection

  if state.editor_type == 'Speed' then
    local applied, final_length = 0, nil
    local anchor_output_ranges = nil
    local anchor_output_active = anchor_active_selection
    for _, item in ipairs(targets) do
      state.item = item
      state.item_guid = get_item_guid(item)
      state.take = reaper.GetActiveTake(item)
      state.take_guid = get_take_guid(state.take)
      Preview.clear_state()
      Preview.recover(item)

      set_selection_ranges_norm(anchor_ranges_norm, anchor_active_selection)

      local ready, ready_error = Preview.ensure_editable()
      if not ready then
        local anchor = find_item_by_guid(anchor_guid)
        if valid_item(anchor) then reset_item_context(anchor) end
        return false, string.format(
          '%d개 적용 후 Preview 준비 실패: %s', applied, tostring(ready_error))
      end
      local ok, detail = apply_speed_curve(item)
      if not ok then
        local anchor = find_item_by_guid(anchor_guid)
        if valid_item(anchor) then reset_item_context(anchor) end
        return false, string.format(
          '%d개 적용 후 속도 곡선 실패: %s', applied, tostring(detail))
      end
      applied = applied + 1
      final_length = type(detail) == 'table' and detail.length or detail
      if get_item_guid(item) == anchor_guid then
        anchor_output_ranges = copy_selection_ranges_norm(state.selection_ranges_norm)
        anchor_output_active = state.active_selection
      end
    end

    local anchor = find_item_by_guid(anchor_guid)
    if valid_item(anchor) then
      reset_item_context(anchor)
      set_selection_ranges_norm(
        anchor_output_ranges or anchor_ranges_norm, anchor_output_active)
    end
    if applied > 1 then return true, {items=applied, length=final_length} end
    return true, final_length
  end

  -- Native Take envelopes are already non-destructive and fully undoable, so
  -- duplicating the source Take only adds memory, UI noise, and pointer churn.
  local total_points, applied = 0, 0
  for _, item in ipairs(targets) do
    local take = reaper.GetActiveTake(item)
    local ok, detail = apply_native_envelope(state.editor_type, item, take)
    if not ok then
      local anchor = find_item_by_guid(anchor_guid)
      if valid_item(anchor) then
        state.item = anchor
        state.item_guid = anchor_guid
        state.take = reaper.GetActiveTake(anchor)
        state.take_guid = get_take_guid(state.take)
      end
      return false, string.format(
        '%d개 적용 후 실패: %s', applied, tostring(detail))
    end
    applied = applied + 1
    total_points = total_points + (tonumber(detail) or 0)
  end

  local anchor = find_item_by_guid(anchor_guid)
  if valid_item(anchor) then
    state.item = anchor
    state.item_guid = anchor_guid
    state.take = reaper.GetActiveTake(anchor)
    state.take_guid = get_take_guid(state.take)
  end
  if applied > 1 then return true, {items=applied, points=total_points} end
  return true, total_points
end

-- -----------------------------------------------------------------------------
-- UI
-- -----------------------------------------------------------------------------
local function draw_top_bar()
  ImGui.TextColored(ctx, COLORS.muted, tr('LANGUAGE', '언어'))
  ImGui.SameLine(ctx, 0, 6)
  local language_label = state.language == 'en' and 'ENGLISH' or '한국어'
  if toggle_button(
      language_label, true, compact_button_width(language_label, 18),
      {dark = COLORS.cyan_dark, color = COLORS.cyan}) then
    state.language = state.language == 'en' and 'ko' or 'en'
  end

  local help_label = tr('HELP', '도움말')
  local help_width = compact_button_width(help_label, 18)
  local right_x = ImGui.GetWindowWidth(ctx) - help_width - 14
  ImGui.SameLine(ctx, 0, 8)
  ImGui.SetCursorPosX(ctx, math.max(ImGui.GetCursorPosX(ctx), right_x))
  if ImGui.Button(ctx, help_label .. '##OpenHelp', help_width, 0) then
    state.help_open = true
    ImGui.OpenPopup(ctx, '##YSLItemEnvelopeHelp')
  end

  if ImGui.BeginPopup(ctx, '##YSLItemEnvelopeHelp') then
    ImGui.TextColored(
      ctx, COLORS.cyan, tr('WAVEFORM & ENVELOPE CONTROLS', '파형 · 엔벨로프 조작'))
    ImGui.Separator(ctx)
    ImGui.Text(ctx, tr('Drag empty space', '빈 공간 드래그'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Replace the active range', '적용 구간 새로 선택'))
    ImGui.Text(ctx, tr('Ctrl + drag empty space', 'Ctrl + 빈 공간 드래그'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Add another range', '적용 구간 추가'))
    ImGui.Text(ctx, tr('Click / right-click a range', '선택 구간 클릭 / 우클릭'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Activate / remove the range', '활성 구간 지정 / 구간 제거'))
    ImGui.Text(ctx, tr('Drag a point', '포인트 드래그'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Move its time and value', '시간과 값을 함께 이동'))
    ImGui.Text(ctx, tr('Ctrl + click or drag a point', 'Ctrl + 포인트 클릭·드래그'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Add to selection and move together', '추가 선택 후 함께 이동'))
    ImGui.Text(ctx, tr('Shift + click a point', 'Shift + 포인트 클릭'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Select a continuous point range', '연속 포인트 선택'))
    ImGui.Text(ctx, tr('Alt + drag a curve', 'Alt + 곡선 드래그'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Adjust segment curvature', '포인트 사이 곡률 조절'))
    ImGui.Text(ctx, tr('Double-click / right-click', '더블클릭 / 우클릭'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Add / delete a point', '포인트 추가 / 삭제'))
    ImGui.Text(ctx, tr('Mouse wheel / middle-drag', '마우스 휠 / 가운데 드래그'))
    ImGui.SameLine(ctx, 0, 12)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Zoom / move horizontally', '확대·축소 / 좌우 이동'))

    if #self_shortcuts > 0 then
      local descriptions = {}
      for _, shortcut in ipairs(self_shortcuts) do
        descriptions[#descriptions + 1] = shortcut.desc
      end
      ImGui.Separator(ctx)
      ImGui.TextColored(ctx, COLORS.cyan,
        tr('MANAGER SHORTCUT', '매니저 단축키'))
      ImGui.SameLine(ctx, 0, 12)
      ImGui.Text(ctx, table.concat(descriptions, ', '))
      ImGui.TextColored(ctx, COLORS.muted,
        tr('Press again while focused to close the manager.',
          '매니저에 포커스가 있어도 같은 단축키로 닫을 수 있습니다.'))
    end

    ImGui.Separator(ctx)
    local close_label = tr('CLOSE', '닫기')
    if ImGui.Button(ctx, close_label, compact_button_width(close_label, 22), 0) then
      state.help_open = false
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  ImGui.Separator(ctx)
end

local function draw_toolbar(item)
  local playing = (reaper.GetPlayState() & 1) == 1 and state.audition_active
  local play_label = playing and tr('PLAYING', '재생 중') or tr('PLAY RANGE', '구간 재생')
  if toggle_button(play_label, playing, compact_button_width(play_label, 18),
      {dark = COLORS.green_dark, color = COLORS.green}) then
    if playing then stop_audition() else start_audition(item) end
  end
  ImGui.SameLine(ctx, 0, 4)
  local stop_label = tr('STOP', '정지')
  if ImGui.Button(ctx, stop_label, compact_button_width(stop_label, 16), 0) then
    stop_audition()
  end
  ImGui.SameLine(ctx, 0, 4)
  local clear_label = tr('CLEAR RANGES', '구간 해제')
  if ImGui.Button(ctx, clear_label, compact_button_width(clear_label, 16), 0) then
    clear_internal_selection()
    if state.editor_type ~= 'Speed' and import_native_curve then
      import_native_curve(state.editor_type, state.take, state.item, true)
    end
  end
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, COLORS.muted,
    tr('REAPER time selection is not used', '타임 셀렉션 미사용'))
end

local function draw_preview_bar(kind)
  if kind ~= 'Speed' then
    local cfg = TYPE_CONFIG[kind]
    local now = reaper.time_precise()
    local cache_key = kind .. '|' .. tostring(get_take_guid(state.take) or '')
    local cached = state.envelope_enabled_cache[cache_key]
    local enabled
    if cached and now < (cached.next_check or 0) then
      enabled = cached.value == true
    else
      enabled = take_envelope_enabled(kind, state.take)
      state.envelope_enabled_cache[cache_key] = {
        value = enabled,
        next_check = now + 0.25,
      }
    end
    ImGui.TextColored(ctx, cfg.color, 'NATIVE TAKE ENVELOPE')
    ImGui.SameLine(ctx, 0, 8)
    ImGui.TextColored(ctx, enabled and COLORS.muted or 0xAAB4C0FF,
      enabled and tr(
        'Directly edits active Take · REAPER Undo supported',
        '활성 Take에 직접 적용 · REAPER Undo 지원')
        or tr(
          'Disabled · points preserved · manager locked',
          '비활성 · 포인트 보존 · 매니저 잠김'))
    ImGui.SameLine(ctx, 0, 8)
    local toggle_label = enabled
      and tr('CLOSE ENVELOPE', '엔벨로프 닫기')
      or tr('OPEN ENVELOPE', '엔벨로프 열기')
    if toggle_button(toggle_label, enabled,
        compact_button_width(toggle_label, 18), cfg) then
      local wanted = not enabled
      reaper.Undo_BeginBlock2(0)
      local ok, env_or_error, refreshed_take = set_take_envelope_enabled(
        kind, state.item, state.take, wanted)
      if valid_take(refreshed_take) then
        state.take = refreshed_take
        state.take_guid = get_take_guid(refreshed_take)
      end
      state.envelope_enabled_cache = {}
      if ok then enabled = wanted end
      reaper.Undo_EndBlock2(
        0, APP_NAME .. (wanted and ': Open ' or ': Close ')
          .. 'native Take ' .. kind .. ' envelope', -1)
      if ok and wanted and import_native_curve then
        import_native_curve(kind, state.take, state.item, true)
      end
      set_status(
        ok and (type_label(kind) .. (wanted
          and tr(' Take envelope opened.', ' Take 엔벨로프를 열었습니다.')
          or tr(
            ' Take envelope closed and locked.',
            ' Take 엔벨로프를 닫고 잠갔습니다.')))
          or tostring(env_or_error or tr(
            'Could not change the Take envelope state.',
            'Take 엔벨로프 상태를 바꾸지 못했습니다.')),
        ok and 3 or 6)
    end
    return enabled
  end

  if not state.preview.active then
    local target_count = selected_audio_item_count()
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Non-destructive Speed Preview', '속도 전용 비파괴 Preview'))
    ImGui.SameLine(ctx, 0, 6)
    local create_label = target_count > 1
      and tr(
        'CREATE ' .. target_count .. ' PREVIEWS',
        '선택 ' .. target_count .. '개 Preview 만들기')
      or tr('CREATE PREVIEW', 'Preview 만들기')
    if colored_button(create_label, compact_button_width(create_label, 18),
        COLORS.cyan_dark, COLORS.cyan) then
      local ok, count, err = preview_operation_on_selected('create')
      set_status(ok and string.format(
        tr('Preview Takes created · %d', 'Preview Take를 만들었습니다 · %d개'),
        count or 0)
        or tostring(err), ok and 3 or 6)
    end
    ImGui.SameLine(ctx, 0, 8)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Created automatically when applying', '곡선 적용 시 자동 생성'))
    return
  end

  local original_on = state.preview.current == 'original'
  local preview_on = state.preview.current ~= 'original'
  local target_count = selected_audio_item_count()
  if toggle_button('A ORIGINAL', original_on, compact_button_width('A ORIGINAL', 18),
      {dark = COLORS.cyan_dark, color = COLORS.cyan}) then
    stop_audition()
    local ok, count, err = preview_operation_on_selected('switch', 'original')
    set_status(ok and string.format(
      tr('Switched to Original Take · %d', 'Original Take로 전환했습니다 · %d개'),
      count or 0)
      or tostring(err), ok and 2 or 5)
  end
  ImGui.SameLine(ctx, 0, 4)
  if toggle_button('B PREVIEW', preview_on, compact_button_width('B PREVIEW', 18),
      {dark = COLORS.green_dark, color = COLORS.green}) then
    stop_audition()
    local ok, count, err = preview_operation_on_selected('switch', 'preview')
    set_status(ok and string.format(
      tr('Switched to Preview Take · %d', 'Preview Take로 전환했습니다 · %d개'),
      count or 0)
      or tostring(err), ok and 2 or 5)
  end
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, COLORS.muted,
    string.format(tr(
      'A %.3fs · B %.3fs · %d selected',
      'A %.3fs · B %.3fs · 선택 %d개'),
      tonumber(state.preview.original_length) or 0,
      tonumber(state.preview.preview_length) or 0,
      target_count))
  ImGui.SameLine(ctx, 0, 8)
  if colored_button('COMMIT', compact_button_width('COMMIT', 18), COLORS.green_dark, COLORS.green) then
    stop_audition()
    local ok, count, err = preview_operation_on_selected('commit')
    if ok then load_curves(state.take); invalidate_wave() end
    set_status(ok and string.format(
      tr('Preview committed · %d', 'Preview를 확정했습니다 · %d개'),
      count or 0)
      or tostring(err), ok and 4 or 7)
  end
  ImGui.SameLine(ctx, 0, 4)
  local restore_label = tr('RESTORE ORIGINAL', '원본 복원')
  if colored_button(
      restore_label, compact_button_width(restore_label, 18),
      COLORS.red_dark, COLORS.red) then
    stop_audition()
    local ok, count, err = preview_operation_on_selected('revert')
    set_status(ok and string.format(
      tr('Original Take restored · %d', 'Original Take로 복원했습니다 · %d개'),
      count or 0)
      or tostring(err), ok and 4 or 7)
  end
end

local function draw_wave_zoom(item)
  local item_len = math.max(0.000001, reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
  if ImGui.SmallButton(ctx, '−##WaveZoom') then
    state.wave_zoom = math.max(1, state.wave_zoom / 1.5)
    state.wave_offset = clamp(state.wave_offset, 0, math.max(0, item_len - item_len / state.wave_zoom))
    invalidate_wave()
  end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, '+##WaveZoom') then
    state.wave_zoom = math.min(128, state.wave_zoom * 1.5)
    invalidate_wave()
  end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, tr('ALL', '전체') .. '##WaveZoom') then
    state.wave_zoom = 1
    state.wave_offset = 0
    invalidate_wave()
  end
  ImGui.SameLine(ctx)
  ImGui.TextColored(ctx, COLORS.muted,
    string.format(tr('Waveform %.1fx', '파형 %.1fx'), state.wave_zoom))

  if state.wave_zoom > 1.001 then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, math.max(100, content_width() - 250))
    local visible_len = item_len / state.wave_zoom
    local changed, value = ImGui.SliderDouble(ctx, '##WaveOffset', state.wave_offset,
      0, math.max(0, item_len - visible_len), '%.3f s')
    if changed then state.wave_offset = value; invalidate_wave() end
  else
    ImGui.SameLine(ctx, 0, 10)
    ImGui.TextColored(ctx, COLORS.muted,
      tr('Wheel zoom · middle-drag pan', '휠 확대 · 가운데 드래그 이동'))
  end
end

local function draw_type_buttons()
  local gap = 5
  local button_width = math.max(
    72, math.floor((content_width() - gap * (#TYPE_ORDER - 1)) / #TYPE_ORDER))
  for i, kind in ipairs(TYPE_ORDER) do
    local cfg = TYPE_CONFIG[kind]
    local locked = kind ~= 'Speed' and not take_envelope_enabled(kind, state.take)
    local label = cfg.short .. (locked and '  🔒' or '')
    if toggle_button(label, state.editor_type == kind, button_width, cfg) then
      state.editor_type = kind
      select_only_point(kind, 1)
      state.dragging_points = nil
      state.dragging_segment = nil
    end
    if i < #TYPE_ORDER then ImGui.SameLine(ctx, 0, gap) end
  end
end

local function preset_group_width(kind)
  local width = ImGui.CalcTextSize(ctx, tr('PRESETS', '프리셋'))
  local gap = 4
  for _, preset in ipairs(PRESETS[kind]) do
    width = width + 6 + compact_button_width(preset_label(kind, preset), 16)
  end
  return width + gap
end

local function draw_preset_buttons(kind, align_right)
  local cfg = TYPE_CONFIG[kind]
  local presets = PRESETS[kind]
  local gap = 4
  if align_right then
    local right_x = ImGui.GetWindowWidth(ctx) - preset_group_width(kind) - 14
    ImGui.SetCursorPosX(ctx, math.max(ImGui.GetCursorPosX(ctx), right_x))
  end
  ImGui.TextColored(ctx, COLORS.muted, tr('PRESETS', '프리셋'))
  for _, preset in ipairs(presets) do
    local label = preset_label(kind, preset)
    local width = compact_button_width(label, 16)
    ImGui.SameLine(ctx, 0, gap)
    if colored_button(label, width, cfg.dark, cfg.color) then
      state.curves[kind] = normalize_curve(kind, preset_curve(kind, preset[1]))
      select_only_point(kind, math.min(2, #state.curves[kind]))
      state.dragging_points = nil
      state.dragging_segment = nil
      set_status(tr(
        label .. ' preset loaded.',
        label .. ' 프리셋을 불러왔습니다.'), 2)
    end
  end
end

local function selected_segment_indices(kind)
  local points = state.curves[kind] or {}
  local result, seen = {}, {}
  for _, index in ipairs(selected_point_indices(kind)) do
    local segment = index < #points and index or (#points - 1)
    if segment >= 1 and not seen[segment] then
      seen[segment] = true
      result[#result + 1] = segment
    end
  end
  if #result == 0 and #points >= 2 then result[1] = active_segment_index(kind) end
  return result
end

local function apply_shape_to_selected_segments(kind, shape)
  local points = state.curves[kind]
  for _, segment in ipairs(selected_segment_indices(kind)) do
    local point = points[segment]
    if point then
      point.shape = shape
      if shape ~= 'bezier' then point.tension = 0 end
    end
  end
end

local function draw_selected_point(kind)
  local cfg = TYPE_CONFIG[kind]
  local points = state.curves[kind]
  local indices = selected_point_indices(kind)
  local point = points[clamp(state.selected_point, 1, #points)]
  if not point then return end

  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, cfg.dark)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, cfg.color)

  ImGui.TextColored(ctx, cfg.color,
    #indices > 1
      and tr(tostring(#indices) .. ' POINTS', '포인트 ' .. tostring(#indices) .. '개')
      or tr('POINT', '포인트'))
  ImGui.SameLine(ctx, 0, 5)
  ImGui.SetNextItemWidth(ctx, kind == 'Pan' and 210 or 150)
  local changed, value
  if kind == 'Pan' then
    -- Keep the Pan value on its own explicit ID. This restores the visible
    -- L/R slider without sharing state with the adjacent point-position slider.
    changed, value = ImGui.SliderDouble(
      ctx, '##PanPointValue', point.y, cfg.min, cfg.max, '%+.2f')
  else
    local format = kind == 'Speed' and '%.3fx'
      or (kind == 'Volume' and '%+.1f dB' or '%+.1f st')
    changed, value = ImGui.SliderDouble(
      ctx, '##PointValue', point.y, cfg.min, cfg.max, format)
  end
  value = tonumber(value) or point.y
  if changed then
    if #indices > 1 then
      -- Treat the slider as a group offset. Clamp one shared delta against the
      -- first point that would reach the limit so all vertical differences stay
      -- intact instead of collapsing to the reference point's absolute value.
      local delta = value - point.y
      local minimum_delta, maximum_delta = -math.huge, math.huge
      for _, index in ipairs(indices) do
        local selected = points[index]
        if selected then
          minimum_delta = math.max(minimum_delta, cfg.min - selected.y)
          maximum_delta = math.min(maximum_delta, cfg.max - selected.y)
        end
      end
      delta = clamp(delta, minimum_delta, maximum_delta)
      for _, index in ipairs(indices) do
        local selected = points[index]
        if selected then selected.y = selected.y + delta end
      end
    else
      point.y = clamp(value, cfg.min, cfg.max)
    end
    value = point.y
  end
  if kind == 'Pan' then
    ImGui.SameLine(ctx, 0, 5)
    ImGui.TextColored(ctx, cfg.color, value_text(kind, value))
  end

  if #indices == 1 and state.selected_point > 1 and state.selected_point < #points then
    ImGui.SameLine(ctx, 0, 5)
    ImGui.SetNextItemWidth(ctx, 112)
    local left = points[state.selected_point - 1].x + 0.002
    local right = points[state.selected_point + 1].x - 0.002
    local changed_x, percent = ImGui.SliderDouble(ctx, '##PointTimePosition', point.x * 100,
      left * 100, right * 100, '%.1f%%')
    if changed_x then point.x = percent / 100 end
  end

  local segment_indices = selected_segment_indices(kind)
  local segment = segment_indices[1]
  local segment_point = points[segment]
  local linear_w = compact_button_width('LINEAR', 14)
  local smooth_w = compact_button_width('SMOOTH', 14)
  local bezier_w = compact_button_width('BEZIER', 14)

  -- Curve/segment controls stay on the left. Presets share this row but are
  -- anchored to the right edge, making the two groups immediately scannable.
  ImGui.TextColored(ctx, cfg.color, string.format('%d→%d', segment, segment + 1))
  ImGui.SameLine(ctx, 0, 4)
  local selected_shape = segment_point and segment_point.shape or 'linear'
  if toggle_button('LINEAR', selected_shape == 'linear', linear_w,
      {dark = cfg.dark, color = cfg.color}) then
    apply_shape_to_selected_segments(kind, 'linear')
  end
  ImGui.SameLine(ctx, 0, 3)
  if toggle_button('SMOOTH', selected_shape == 'smooth', smooth_w,
      {dark = cfg.dark, color = cfg.color}) then
    apply_shape_to_selected_segments(kind, 'smooth')
  end
  ImGui.SameLine(ctx, 0, 3)
  if toggle_button('BEZIER', selected_shape == 'bezier', bezier_w,
      {dark = cfg.dark, color = cfg.color}) then
    apply_shape_to_selected_segments(kind, 'bezier')
  end

  local any_bezier = false
  for _, index in ipairs(segment_indices) do
    if points[index] and points[index].shape == 'bezier' then any_bezier = true; break end
  end
  if any_bezier then
    ImGui.SameLine(ctx, 0, 8)
    ImGui.TextColored(ctx, cfg.color, tr('CURVATURE', '구간 곡률'))
    ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, 190)
    local reference = points[segment]
    local changed_tension, tension_percent = ImGui.SliderDouble(
      ctx, '##BezierTension', (reference.tension or 0) * 100,
      -100, 100, '%+.0f%%')
    if changed_tension then
      for _, index in ipairs(segment_indices) do
        if points[index] and points[index].shape == 'bezier' then
          points[index].tension = tension_percent / 100
        end
      end
    end
  end

  ImGui.SameLine(ctx, 0, 10)
  draw_preset_buttons(kind, true)

  ImGui.PopStyleColor(ctx, 2)
end

local function draw_user_preset_library(kind)
  local cfg = TYPE_CONFIG[kind]
  local presets = PresetDB.filtered(kind)
  local header = state.show_user_presets
    and tr('USER PRESETS ▲', '사용자 프리셋 ▲')
    or tr('USER PRESETS ▼', '사용자 프리셋 ▼')
  if toggle_button(header .. '##UserPresetToggle', state.show_user_presets,
      compact_button_width(header, 16), {dark = cfg.dark, color = cfg.color}) then
    state.show_user_presets = not state.show_user_presets
  end
  ImGui.SameLine(ctx, 0, 6)
  ImGui.TextColored(ctx, COLORS.muted,
    tr(string.format('%d', #presets), string.format('%d개', #presets)))
  if not state.show_user_presets then return end

  ImGui.SetNextItemWidth(ctx, math.max(150, content_width() - 260))
  local name_changed, preset_name = ImGui.InputTextWithHint(
    ctx, '##PresetName', tr('Preset name...', '저장 이름...'), state.save_preset_name)
  if name_changed then state.save_preset_name = preset_name end
  local name_input_active = ImGui.IsItemActive(ctx)
  ImGui.SameLine(ctx, 0, 4)
  local save_label = tr('SAVE / UPDATE', '저장/업데이트')
  local save_clicked = colored_button(save_label,
    compact_button_width(save_label, 16), cfg.dark, cfg.color)
  local enter_pressed = name_input_active
    and safe_key_pressed(safe_imgui_constant('Key_Enter'))
  if save_clicked or enter_pressed then
    local ok, message = PresetDB.save_current(kind, state.save_preset_name)
    set_status(ok and message or tostring(message), ok and 4 or 6)
  end
  ImGui.SameLine(ctx, 0, 4)
  ImGui.SetNextItemWidth(ctx, 120)
  local changed, search = ImGui.InputTextWithHint(
    ctx, '##UserPresetSearch', tr('Search...', '검색...'), state.preset_search)
  if changed then state.preset_search = search end

  presets = PresetDB.filtered(kind)
  local available, used, gap = content_width(), 0, 4
  for i = 1, math.min(#presets, 8) do
    local preset = presets[i]
    local load_w = math.min(180, compact_button_width(preset.name, 18))
    local delete_w = compact_button_width('×', 12)
    local unit_w = load_w + gap + delete_w
    if used > 0 and used + gap + unit_w <= available then
      ImGui.SameLine(ctx, 0, gap)
      used = used + gap + unit_w
    else
      used = unit_w
    end

    if colored_button(preset.name .. '##LoadUserPreset' .. preset.id,
        load_w, cfg.dark, cfg.color) then
      state.curves[kind] = parse_curve(kind, preset.curve)
      select_only_point(kind, math.min(2, #state.curves[kind]))
      state.dragging_points = nil
      state.dragging_segment = nil
      state.save_preset_name = preset.name
      set_status(tr(
        'Preset loaded: ' .. preset.name,
        '프리셋을 불러왔습니다: ' .. preset.name), 3)
    end
    ImGui.SameLine(ctx, 0, gap)
    if colored_button('×##DeleteUserPreset' .. preset.id,
      delete_w, COLORS.red_dark, COLORS.red) then
      state.pending_delete_preset = preset
      ImGui.OpenPopup(ctx, '###DeleteUserPreset')
    end
  end

  if ImGui.BeginPopupModal(ctx,
      tr('Delete User Preset', '사용자 프리셋 삭제') .. '###DeleteUserPreset', nil,
      ImGui.WindowFlags_AlwaysAutoResize) then
    local preset = state.pending_delete_preset
    ImGui.TextWrapped(ctx,
      preset and tr(
        "Delete preset '" .. preset.name .. "'?",
        "'" .. preset.name .. "' 프리셋을 삭제할까요?")
      or tr('Delete this preset?', '프리셋을 삭제할까요?'))
    local delete_label = tr('DELETE', '삭제')
    if colored_button(delete_label, compact_button_width(delete_label, 20),
        COLORS.red_dark, COLORS.red) then
      if preset then
        local ok, err = PresetDB.delete(preset.id)
        set_status(ok and tr(
          'User preset deleted.',
          '사용자 프리셋을 삭제했습니다.') or tostring(err),
          ok and 3 or 5)
      end
      state.pending_delete_preset = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx, 0, 4)
    local cancel_label = tr('CANCEL', '취소')
    if ImGui.Button(ctx, cancel_label, compact_button_width(cancel_label, 20), 0) then
      state.pending_delete_preset = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end
end

local function draw_apply_area(kind)
  local cfg = TYPE_CONFIG[kind]
  local target_count = selected_audio_item_count()
  local apply_label = kind == 'Speed'
      and (target_count > 1
        and tr(
          'APPLY TO ' .. target_count .. ' PREVIEWS',
          '선택 ' .. target_count .. '개 PREVIEW 적용')
        or tr('APPLY PREVIEW', 'PREVIEW 적용'))
    or (target_count > 1
      and tr(
        'APPLY TO ' .. target_count .. ' TAKES',
        '선택 ' .. target_count .. '개 TAKE 적용')
      or tr('APPLY TO ACTIVE TAKE', '활성 TAKE 적용'))

  ImGui.Separator(ctx)
  if colored_button(
      apply_label, compact_button_width(apply_label, 24), cfg.dark, cfg.color) then
    local ok, detail = apply_current_curve()
    if ok then
      if type(detail) == 'table' then
        if kind == 'Speed' then
          set_status(string.format(
            tr(
              'Speed curve applied · %d Previews',
              '속도 곡선 일괄 적용 완료 · %d개 Preview'),
            detail.items or 0), 5)
        else
          set_status(string.format(
            tr(
              '%s envelope applied · %d items · %d points',
              '%s 엔벨로프 일괄 적용 완료 · %d개 아이템 · 포인트 %d개'),
            type_label(kind), detail.items or 0, detail.points or 0), 5)
        end
      elseif kind == 'Speed' and type(detail) == 'number' then
        set_status(string.format(
          tr('Speed curve applied · %.3fs', '속도 곡선 적용 완료 · %.3f초'),
          detail), 4)
      elseif type(detail) == 'number' then
        set_status(string.format(
          tr(
            '%s Take envelope applied · %d points',
            '%s Take 엔벨로프 적용 완료 · 포인트 %d개'),
          type_label(kind), detail), 4)
      else
        set_status(tr(
          type_label(kind) .. ' curve applied.',
          type_label(kind) .. ' 곡선 적용 완료'), 4)
      end
    else
      set_status(detail or tr('Apply failed.', '적용 실패'), 7)
    end
  end

  local applied = curve_is_applied(kind)
  local applied_label = applied
    and tr('● APPLIED', '● 적용됨')
    or tr('○ EDITING', '○ 편집 중')
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, applied and cfg.color or COLORS.muted,
    applied_label)
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, COLORS.muted,
    target_count > 1
      and tr(
        'Maps representative ranges proportionally',
        '대표 파형 구간을 길이 비율로 일괄 적용')
      or tr('Applies to the representative item', '현재 대표 아이템에 적용'))

  local reset_label = tr('RESET CURVE', '곡선 초기화')
  local import_label = tr('LOAD EXISTING', '기존값 불러오기')
  local preserve_label = tr('PRESERVE PITCH', '피치 유지')
  local change_pitch_label = tr('CHANGE PITCH', '피치 변경')
  local reset_w = compact_button_width(reset_label, 18)
  local import_w = kind ~= 'Speed'
      and compact_button_width(import_label, 18) or 0
  local pitch_w = kind == 'Speed'
      and math.max(
        compact_button_width(preserve_label, 18),
        compact_button_width(change_pitch_label, 18)) or 0
  local right_width = reset_w
    + (import_w > 0 and import_w + 4 or 0)
    + (pitch_w > 0 and pitch_w + 4 or 0)
  local minimum_x = ImGui.GetCursorPosX(ctx) + 10
  local right_x = ImGui.GetWindowWidth(ctx) - right_width - 14
  if minimum_x + right_width > ImGui.GetWindowWidth(ctx) - 14 then
    ImGui.NewLine(ctx)
    ImGui.SetCursorPosX(ctx, math.max(7, right_x))
  else
    ImGui.SameLine(ctx, 0, 8)
    ImGui.SetCursorPosX(ctx, math.max(minimum_x, right_x))
  end

  if kind == 'Speed' then
    if toggle_button(
        state.preserve_pitch and preserve_label or change_pitch_label,
        state.preserve_pitch, pitch_w,
        {dark = COLORS.green_dark, color = COLORS.green}) then
      state.preserve_pitch = not state.preserve_pitch
    end
    ImGui.SameLine(ctx, 0, 4)
  else
    if ImGui.Button(ctx, import_label, import_w, 0) then
      local ok, _, err = import_native_curve(kind, state.take, state.item, false)
      if not ok then
        set_status(err or tr(
          'Could not load the existing envelope.',
          '기존 엔벨로프를 불러오지 못했습니다.'), 5)
      end
    end
    ImGui.SameLine(ctx, 0, 4)
  end

  if ImGui.Button(ctx, reset_label, reset_w, 0) then
    state.curves[kind] = flat_curve(kind)
    select_only_point(kind, 1)
    state.dragging_points = nil
    state.dragging_segment = nil
    set_status(tr('Editing curve reset.', '편집 곡선만 초기화했습니다.'), 3)
  end
end

local function push_theme()
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, COLORS.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, COLORS.border)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, COLORS.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, COLORS.panel2)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, COLORS.hover)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, COLORS.border)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, COLORS.panel2)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, COLORS.hover)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, COLORS.cyan_dark)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, COLORS.cyan)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 3)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 7, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 5, 2)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 4, 3)
end

local function pop_theme()
  ImGui.PopStyleVar(ctx, 5)
  ImGui.PopStyleColor(ctx, 10)
end

local function draw_empty()
  ImGui.Dummy(ctx, 0, 90)
  local text = tr(
    'Select an audio item in the Arrange view.',
    'Arrange에서 편집할 오디오 아이템을 한 번 선택해주세요.')
  local width = ImGui.CalcTextSize(ctx, text)
  local available = content_width()
  ImGui.SetCursorPosX(ctx, math.max(10, (available - width) * 0.5))
  ImGui.TextColored(ctx, COLORS.muted, text)
end

local function heartbeat_and_close_check()
  local t = reaper.time_precise()
  if t - state.last_heartbeat > 0.5 then
    reaper.SetExtState(INSTANCE_SECTION, 'HEARTBEAT', tostring(t), false)
    state.last_heartbeat = t
  end
  local request = reaper.GetExtState(INSTANCE_SECTION, 'CLOSE_REQUEST')
  if request == instance_token then
    state.open = false
  end
end

local function run_frame()
  heartbeat_and_close_check()
  local frame_time = reaper.time_precise()
  if frame_time >= (state.next_context_poll or 0) then
    update_context()
    state.next_context_poll = frame_time + 0.08
  end
  update_audition()

  if self_shortcut_close_requested() then
    state.open = false
    return false
  end

  allow_reaper_shortcuts_next_frame()
  ImGui.SetNextWindowSize(ctx, 1040, 590, ImGui.Cond_FirstUseEver)

  push_theme()
  ImGui.PushFont(ctx, font)
  local visible
  visible, state.open = ImGui.Begin(ctx,
    APP_NAME .. ' v' .. APP_VERSION .. WINDOW_ID,
    state.open, ImGui.WindowFlags_NoCollapse)

  local ok, err = true, nil
  if visible then
    ok, err = xpcall(function()
      draw_top_bar()
      if valid_item(state.item) and valid_take(state.take) then
        draw_toolbar(state.item)
        draw_type_buttons()
        local envelope_enabled = draw_preview_bar(state.editor_type)
        local manager_locked = state.editor_type ~= 'Speed'
          and envelope_enabled == false
        draw_wave_zoom(state.item)
        draw_waveform(state.item, state.take, manager_locked)

        local ranges, selected = current_ranges(state.item)
        local active = selected
          and ranges[clamp(state.active_selection, 1, #ranges)] or ranges[1]
        local target_count = selected_audio_item_count()
        if selected then
          local total_duration = 0
          for _, range in ipairs(ranges) do
            total_duration = total_duration + (range.b - range.a)
          end
          ImGui.TextColored(ctx, COLORS.cyan,
            string.format(
              tr(
                '%d ranges · active %s → %s · total %.3fs · %d targets',
                '구간 %d개 · 활성 %s → %s · 총 %.3f초 · 적용 대상 %d개'),
              #ranges, format_time(active.a), format_time(active.b),
              total_duration, target_count))
        else
          ImGui.TextColored(ctx, COLORS.muted,
            string.format(
              tr(
                'No range · entire item · %d targets',
                '구간 없음 · 전체 아이템 적용 · 적용 대상 %d개'),
              target_count))
        end

        if manager_locked then ImGui.BeginDisabled(ctx, true) end
        draw_selected_point(state.editor_type)
        -- Apply stays directly below the integrated waveform/curve editor.
        -- Built-in presets sit on the right of the curve controls.
        draw_apply_area(state.editor_type)
        draw_user_preset_library(state.editor_type)
        if manager_locked then ImGui.EndDisabled(ctx) end
      elseif valid_item(state.item) then
        ImGui.TextColored(ctx, COLORS.yellow,
          tr(
            'The selected item has no active audio Take.',
            '현재 아이템에 활성 오디오 테이크가 없습니다.'))
      else
        draw_empty()
      end

      if state.status ~= '' and reaper.time_precise() < state.status_until then
        ImGui.TextColored(ctx, COLORS.cyan, state.status)
      end
    end, debug.traceback)
  end

  -- ReaImGui's Begin return value is also the contract for End: collapsed
  -- windows and the transient frame used while detaching from a REAPER dock
  -- return false and must not receive End. Calling End unconditionally here was
  -- the source of the dock -> floating "Calling End() too many times" error.
  if visible then ImGui.End(ctx) end
  ImGui.PopFont(ctx)
  pop_theme()

  if not ok then
    reaper.ShowConsoleMsg('\n[' .. APP_NAME .. ' v' .. APP_VERSION .. ']\n' .. tostring(err) .. '\n')
    state.open = false
  end
  return state.open
end

local function loop()
  local ok, continue_or_error = xpcall(run_frame, debug.traceback)
  if not ok then
    reaper.MB('스크립트 실행 중 오류가 발생했습니다.\n\n' .. tostring(continue_or_error),
      APP_NAME .. ' Error', 0)
    return
  end
  if continue_or_error then reaper.defer(loop) end
end

reaper.atexit(function()
  if state.audition_active then reaper.OnStopButton() end
  if reaper.GetExtState(INSTANCE_SECTION, 'RUN_TOKEN') == instance_token then
    reaper.DeleteExtState(INSTANCE_SECTION, 'RUN_TOKEN', false)
    reaper.DeleteExtState(INSTANCE_SECTION, 'HEARTBEAT', false)
    reaper.DeleteExtState(INSTANCE_SECTION, 'CLOSE_REQUEST', false)
  end
  set_action_toggle(false)
end)

reaper.defer(loop)
