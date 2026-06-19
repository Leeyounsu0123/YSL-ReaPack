-- @description Sound Lib Manager Pro
-- @version 1.0.1
-- @author Yoon-Soo Lee
-- @changelog
--   + GitHub/ReaPack 배포용 메타데이터를 추가했습니다.
--   + v1.0.1 최초 배포 패키지를 구성했습니다.
-- @about
--   # Sound Lib Manager Pro
--   REAPER에서 사운드 라이브러리 검색어와 태그를 빠르게 관리하는 도구입니다.
--   ## 주요 기능
--   - 실시간 다중 단어 검색
--   - 검색어 및 태그 편집
--   - 안전한 삭제와 실행 취소
--   - 즐겨찾기와 최근 사용 정렬
--   - AND/OR 태그 필터
--   - JSON 백업 및 복원
--   - CSV 가져오기 및 내보내기
--   - ReaImGui 기반 반응형 인터페이스
--   ## 요구 사항
--   - REAPER
--   - ReaPack
--   - ReaImGui 0.9.2 이상
--   ## 라이선스
--   Copyright (c) 2026 Yoon-Soo Lee. All rights reserved.
--   Yoon-Soo Lee의 별도 서면 허가 없이 재배포, 재판매 또는 2차 배포할 수 없습니다.
-- @provides
--   [main] .

if not reaper.ImGui_GetBuiltinPath then
    reaper.ShowMessageBox("ReaImGui가 필요합니다. ReaPack을 통해 설치해주세요.", "오류", 0)
    return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.2'

local APP_NAME = 'SLM Pro v1.0.1'
local EXT_SECTION = 'SoundLibMgr'
local EXT_KEY_V7 = 'DataV7'
local DATA_VERSION = 7.1

local ctx = ImGui.CreateContext(APP_NAME)
local ui_font = ImGui.CreateFont('sans-serif', 12)
ImGui.Attach(ctx, ui_font)

local keywords = {}
local tags = {}
local next_keyword_id = 1

local new_keyword_text = ''
local new_tag_text = ''
local new_tag_color = 0xFFFFFFFF
local search_text = ''
local filter_mode = 'AND'
local sort_mode = 'newest'
local favorite_only = false
local filter_panel_open = false

local selected_tags_list = {}
local selected_tags_set = {}
local selected_filter_tags = {}
local selected_filter_set = {}

local tag_count_cache = {}
local tag_count_cache_dirty = true

local status_message = ''
local status_until = 0

local request_keyword_editor = false
local editing_keyword_id = nil
local editing_keyword_text = ''
local editing_keyword_tags = {}
local editing_keyword_tag_set = {}
local keyword_editor_error = ''

local request_tag_editor = false
local editing_tag_original_name = nil
local editing_tag_name = ''
local editing_tag_color = 0xFFFFFFFF
local tag_editor_error = ''

local request_csv_import_preview = false
local csv_import_preview = nil

local last_deleted_keyword = nil
local UNDO_DELETE_SECONDS = 12.0

local pending_save = false
local pending_save_legacy = false
local pending_save_due = 0

-- -----------------------------------------------------------------------------
-- 공용 문자열/목록 함수
-- -----------------------------------------------------------------------------

local function Trim(value)
    value = tostring(value or '')
    return value:match('^%s*(.-)%s*$') or ''
end

local function CollapseSpaces(value)
    return Trim(value):gsub('%s+', ' ')
end

local function SanitizeStoredText(value)
    -- V7 JSON은 특수문자를 안전하게 보존하므로 공백만 정리합니다.
    return CollapseSpaces(tostring(value or ''))
end

local function LegacySafeText(value)
    -- 구형 V6 구분자 충돌을 피하기 위한 호환 저장 전용 변환입니다.
    return CollapseSpaces(tostring(value or ''):gsub('[@;|]', ''))
end

local function Lower(value)
    return string.lower(tostring(value or ''))
end

local function SameText(a, b)
    return Lower(CollapseSpaces(a)) == Lower(CollapseSpaces(b))
end

local function CopyArray(source)
    local result = {}
    for _, value in ipairs(source or {}) do
        result[#result + 1] = value
    end
    return result
end

local function ArrayContains(source, value)
    for _, item in ipairs(source or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local function RemoveFromArray(source, value)
    for index = #source, 1, -1 do
        if source[index] == value then
            table.remove(source, index)
        end
    end
end

local function ReplaceInArray(source, old_value, new_value)
    for index, value in ipairs(source or {}) do
        if value == old_value then
            source[index] = new_value
        end
    end
end

local function UniqueArray(source)
    local result = {}
    local seen = {}
    for _, value in ipairs(source or {}) do
        if value ~= '' and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    return result
end

local function ArraysEqual(left, right)
    left = left or {}
    right = right or {}
    if #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

local function CopyKeyword(keyword)
    return {
        id = keyword.id,
        word = keyword.word,
        tags = CopyArray(keyword.tags),
        favorite = keyword.favorite == true,
        last_used = tonumber(keyword.last_used) or 0,
        use_count = tonumber(keyword.use_count) or 0,
        created_at = tonumber(keyword.created_at) or 0,
    }
end

local function SetStatus(message, seconds)
    status_message = tostring(message or '')
    status_until = reaper.time_precise() + (seconds or 3.0)
end

local UI_ACCENT = 0x74B9FFFF
local UI_ACCENT_SOFT = 0xAFCFFFFF

local function DrawSectionTitle(title, description)
    ImGui.TextColored(ctx, UI_ACCENT, title)
    if description and description ~= '' then
        ImGui.SameLine(ctx, 0, 8)
        ImGui.TextDisabled(ctx, description)
    end
    ImGui.Separator(ctx)
end

local function DrawDangerButton(label, id, width, height)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x633638FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x7D4447FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x4F2B2DFF)
    local clicked = ImGui.Button(ctx, label .. '##' .. tostring(id), width or 0, height or 0)
    ImGui.PopStyleColor(ctx, 3)
    return clicked
end

local function DrawStatus()
    if status_message ~= '' and reaper.time_precise() < status_until then
        ImGui.TextColored(ctx, 0x7FD8FFFF, status_message)
        ImGui.Separator(ctx)
    elseif status_message ~= '' then
        status_message = ''
    end
end

-- -----------------------------------------------------------------------------
-- 내장 JSON 인코더/디코더 (외부 json.lua 불필요)
-- -----------------------------------------------------------------------------

local function JsonEscape(value)
    return tostring(value):gsub('[%z\1-\31\\"]', function(char)
        local replacements = {
            ['"'] = '\\"',
            ['\\'] = '\\\\',
            ['\b'] = '\\b',
            ['\f'] = '\\f',
            ['\n'] = '\\n',
            ['\r'] = '\\r',
            ['\t'] = '\\t',
        }
        return replacements[char] or string.format('\\u%04X', string.byte(char))
    end)
end

local function IsArrayTable(value)
    if type(value) ~= 'table' then
        return false
    end

    local count = 0
    local max_index = 0
    for key, _ in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > max_index then
            max_index = key
        end
    end

    return count == max_index
end

local function JsonEncode(value)
    local value_type = type(value)

    if value_type == 'nil' then
        return 'null'
    elseif value_type == 'boolean' then
        return value and 'true' or 'false'
    elseif value_type == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return 'null'
        end
        return tostring(value)
    elseif value_type == 'string' then
        return '"' .. JsonEscape(value) .. '"'
    elseif value_type == 'table' then
        local parts = {}

        if IsArrayTable(value) then
            for index = 1, #value do
                parts[#parts + 1] = JsonEncode(value[index])
            end
            return '[' .. table.concat(parts, ',') .. ']'
        end

        local keys = {}
        for key, _ in pairs(value) do
            keys[#keys + 1] = tostring(key)
        end
        table.sort(keys)

        for _, key in ipairs(keys) do
            parts[#parts + 1] = '"' .. JsonEscape(key) .. '":' .. JsonEncode(value[key])
        end
        return '{' .. table.concat(parts, ',') .. '}'
    end

    error('JSON으로 저장할 수 없는 값 형식: ' .. value_type)
end

local function Utf8FromCodepoint(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + (math.floor(codepoint / 0x1000) % 0x40),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    return ''
end

local function JsonDecode(text)
    local position = 1
    local length = #text

    local function SkipWhitespace()
        while position <= length do
            local char = text:sub(position, position)
            if char ~= ' ' and char ~= '\t' and char ~= '\r' and char ~= '\n' then
                break
            end
            position = position + 1
        end
    end

    local ParseValue

    local function ParseString()
        if text:sub(position, position) ~= '"' then
            error('JSON 문자열 시작 문자가 없습니다.')
        end

        position = position + 1
        local output = {}

        while position <= length do
            local char = text:sub(position, position)

            if char == '"' then
                position = position + 1
                return table.concat(output)
            elseif char == '\\' then
                position = position + 1
                local escaped = text:sub(position, position)
                local simple = {
                    ['"'] = '"',
                    ['\\'] = '\\',
                    ['/'] = '/',
                    ['b'] = '\b',
                    ['f'] = '\f',
                    ['n'] = '\n',
                    ['r'] = '\r',
                    ['t'] = '\t',
                }

                if simple[escaped] then
                    output[#output + 1] = simple[escaped]
                    position = position + 1
                elseif escaped == 'u' then
                    local hex = text:sub(position + 1, position + 4)
                    if not hex:match('^%x%x%x%x$') then
                        error('잘못된 JSON 유니코드 이스케이프입니다.')
                    end

                    local codepoint = tonumber(hex, 16)
                    position = position + 5

                    if codepoint >= 0xD800 and codepoint <= 0xDBFF
                        and text:sub(position, position + 1) == '\\u' then
                        local low_hex = text:sub(position + 2, position + 5)
                        local low = tonumber(low_hex, 16)
                        if low and low >= 0xDC00 and low <= 0xDFFF then
                            codepoint = 0x10000
                                + (codepoint - 0xD800) * 0x400
                                + (low - 0xDC00)
                            position = position + 6
                        end
                    end

                    output[#output + 1] = Utf8FromCodepoint(codepoint)
                else
                    error('지원하지 않는 JSON 이스케이프입니다.')
                end
            else
                output[#output + 1] = char
                position = position + 1
            end
        end

        error('JSON 문자열이 닫히지 않았습니다.')
    end

    local function ParseNumber()
        local start_position = position
        local char = text:sub(position, position)

        if char == '-' then
            position = position + 1
        end

        while text:sub(position, position):match('%d') do
            position = position + 1
        end

        if text:sub(position, position) == '.' then
            position = position + 1
            while text:sub(position, position):match('%d') do
                position = position + 1
            end
        end

        local exponent = text:sub(position, position)
        if exponent == 'e' or exponent == 'E' then
            position = position + 1
            local sign = text:sub(position, position)
            if sign == '+' or sign == '-' then
                position = position + 1
            end
            while text:sub(position, position):match('%d') do
                position = position + 1
            end
        end

        local number_text = text:sub(start_position, position - 1)
        local number_value = tonumber(number_text)
        if not number_value then
            error('잘못된 JSON 숫자입니다: ' .. number_text)
        end
        return number_value
    end

    local function ParseArray()
        local result = {}
        position = position + 1
        SkipWhitespace()

        if text:sub(position, position) == ']' then
            position = position + 1
            return result
        end

        while true do
            result[#result + 1] = ParseValue()
            SkipWhitespace()

            local char = text:sub(position, position)
            if char == ']' then
                position = position + 1
                return result
            elseif char ~= ',' then
                error('JSON 배열 구분자가 올바르지 않습니다.')
            end

            position = position + 1
            SkipWhitespace()
        end
    end

    local function ParseObject()
        local result = {}
        position = position + 1
        SkipWhitespace()

        if text:sub(position, position) == '}' then
            position = position + 1
            return result
        end

        while true do
            SkipWhitespace()
            local key = ParseString()
            SkipWhitespace()

            if text:sub(position, position) ~= ':' then
                error('JSON 객체의 콜론이 없습니다.')
            end

            position = position + 1
            SkipWhitespace()
            result[key] = ParseValue()
            SkipWhitespace()

            local char = text:sub(position, position)
            if char == '}' then
                position = position + 1
                return result
            elseif char ~= ',' then
                error('JSON 객체 구분자가 올바르지 않습니다.')
            end

            position = position + 1
            SkipWhitespace()
        end
    end

    ParseValue = function()
        SkipWhitespace()
        local char = text:sub(position, position)

        if char == '"' then
            return ParseString()
        elseif char == '{' then
            return ParseObject()
        elseif char == '[' then
            return ParseArray()
        elseif char == '-' or char:match('%d') then
            return ParseNumber()
        elseif text:sub(position, position + 3) == 'true' then
            position = position + 4
            return true
        elseif text:sub(position, position + 4) == 'false' then
            position = position + 5
            return false
        elseif text:sub(position, position + 3) == 'null' then
            position = position + 4
            return nil
        end

        error('알 수 없는 JSON 값입니다. 위치: ' .. tostring(position))
    end

    local result = ParseValue()
    SkipWhitespace()
    if position <= length then
        error('JSON 뒤에 불필요한 데이터가 있습니다.')
    end
    return result
end

-- -----------------------------------------------------------------------------
-- 색상/UI 보조 함수
-- -----------------------------------------------------------------------------

local function ClampByte(value)
    return math.max(0, math.min(255, math.floor(value + 0.5)))
end

local function UnpackColor(color)
    color = tonumber(color) or 0xFFFFFFFF
    local r = math.floor(color / 0x1000000) % 256
    local g = math.floor(color / 0x10000) % 256
    local b = math.floor(color / 0x100) % 256
    local a = color % 256
    return r, g, b, a
end

local function PackColor(r, g, b, a)
    return ClampByte(r) * 0x1000000
        + ClampByte(g) * 0x10000
        + ClampByte(b) * 0x100
        + ClampByte(a)
end

local function MakeOpaque(color)
    local r, g, b = UnpackColor(color)
    return PackColor(r, g, b, 255)
end

local function AdjustColor(color, factor)
    local r, g, b = UnpackColor(color)

    if factor >= 1 then
        r = r + (255 - r) * (factor - 1)
        g = g + (255 - g) * (factor - 1)
        b = b + (255 - b) * (factor - 1)
    else
        r = r * factor
        g = g * factor
        b = b * factor
    end

    return PackColor(r, g, b, 255)
end

local function GetContrastingTextColor(color)
    local r, g, b = UnpackColor(color)
    local luminance = 0.299 * r + 0.587 * g + 0.114 * b
    return luminance >= 155 and 0x111111FF or 0xFFFFFFFF
end

local function GetTagColor(tag_name)
    for _, tag in ipairs(tags) do
        if tag.name == tag_name then
            return tag.color
        end
    end
    return 0xFFFFFFFF
end

local function GetTagButtonWidth(label, extra_padding)
    local text_width = ImGui.CalcTextSize(ctx, label)
    return text_width + (extra_padding or 14)
end

local function DrawTagButton(label, color, id, width, height)
    local base_color = MakeOpaque(color)
    local hover_color = AdjustColor(base_color, 1.12)
    local active_color = AdjustColor(base_color, 0.82)
    local text_color = GetContrastingTextColor(base_color)

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, base_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hover_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, active_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)

    local clicked = ImGui.Button(
        ctx,
        label .. '##' .. tostring(id),
        width or 0,
        height or 0
    )

    ImGui.PopStyleColor(ctx, 4)
    return clicked
end

local function DrawWrappedButtons(items, id_prefix, selected_value, on_click)
    local available_width = ImGui.GetContentRegionAvail(ctx)
    local used_width = 0
    local spacing = 4

    for index, item in ipairs(items) do
        local label = item.label
        if selected_value == item.value then
            label = '✓ ' .. label
        end

        local width = GetTagButtonWidth(label, 12)
        if used_width > 0 and used_width + spacing + width <= available_width then
            ImGui.SameLine(ctx, 0, spacing)
            used_width = used_width + spacing + width
        else
            used_width = width
        end

        if ImGui.Button(ctx, label .. '##' .. id_prefix .. tostring(index), width, 21) then
            on_click(item.value)
        end
    end
end

local function DrawWrappedTagButtons(tag_items, id_prefix, on_click, show_count, selected_set)
    local available_width = ImGui.GetContentRegionAvail(ctx)
    local used_width = 0
    local spacing = 5

    for index, tag_item in ipairs(tag_items) do
        local tag_name = tag_item.name or tag_item
        local color = tag_item.color or GetTagColor(tag_name)
        local selected = selected_set and selected_set[tag_name] or false
        local label = tag_name

        if show_count then
            label = string.format('%s (%d)', tag_name, tag_count_cache[tag_name] or 0)
        end
        if selected then
            label = '✓ ' .. label
        end

        local width = GetTagButtonWidth(label)
        if used_width > 0 and used_width + spacing + width <= available_width then
            ImGui.SameLine(ctx, 0, spacing)
            used_width = used_width + spacing + width
        else
            used_width = width
        end

        if DrawTagButton(label, color, id_prefix .. tostring(index), width, 21) and on_click then
            on_click(tag_name)
        end
    end
end

-- -----------------------------------------------------------------------------
-- 데이터 검색/저장/마이그레이션
-- -----------------------------------------------------------------------------

local function InvalidateTagCountCache()
    tag_count_cache_dirty = true
end

local function RebuildTagCountCache()
    if not tag_count_cache_dirty then
        return
    end

    tag_count_cache = {}
    for _, keyword in ipairs(keywords) do
        local counted = {}
        for _, tag_name in ipairs(keyword.tags or {}) do
            if not counted[tag_name] then
                tag_count_cache[tag_name] = (tag_count_cache[tag_name] or 0) + 1
                counted[tag_name] = true
            end
        end
    end

    tag_count_cache_dirty = false
end

local function GetKeywordById(keyword_id)
    for index, keyword in ipairs(keywords) do
        if keyword.id == keyword_id then
            return keyword, index
        end
    end
    return nil, nil
end

local function FindDuplicateKeyword(word, excluded_id)
    for _, keyword in ipairs(keywords) do
        if keyword.id ~= excluded_id and SameText(keyword.word, word) then
            return keyword
        end
    end
    return nil
end

local function FindTagByName(name, excluded_name)
    for index, tag in ipairs(tags) do
        if tag.name ~= excluded_name and SameText(tag.name, name) then
            return tag, index
        end
    end
    return nil, nil
end

local function BuildDataTable()
    return {
        version = DATA_VERSION,
        next_keyword_id = next_keyword_id,
        tags = tags,
        keywords = keywords,
        settings = {
            filter_mode = filter_mode,
            sort_mode = sort_mode,
            favorite_only = favorite_only,
        },
    }
end

local function SaveLegacyV6()
    local tag_parts = {}
    for _, tag in ipairs(tags) do
        tag_parts[#tag_parts + 1] = LegacySafeText(tag.name) .. ';;' .. tostring(tag.color)
    end
    reaper.SetExtState(EXT_SECTION, 'TagsV6', table.concat(tag_parts, '@@'), true)

    local keyword_parts = {}
    for _, keyword in ipairs(keywords) do
        local legacy_tags = {}
        for _, tag_name in ipairs(keyword.tags or {}) do
            legacy_tags[#legacy_tags + 1] = LegacySafeText(tag_name)
        end
        keyword_parts[#keyword_parts + 1] =
            LegacySafeText(keyword.word) .. ';;' .. table.concat(legacy_tags, '||')
    end
    reaper.SetExtState(EXT_SECTION, 'KeywordsV6', table.concat(keyword_parts, '@@'), true)
end

local function SaveData(options)
    options = options or {}

    if options.invalidate_tag_cache then
        InvalidateTagCountCache()
    end

    local save_legacy = options.save_legacy == true or pending_save_legacy
    local ok, encoded = pcall(JsonEncode, BuildDataTable())
    if not ok then
        reaper.ShowMessageBox(
            '데이터 저장 중 오류가 발생했습니다.\n기존 저장 데이터는 유지됩니다.\n\n' .. tostring(encoded),
            '저장 오류',
            0
        )
        return false
    end

    reaper.SetExtState(EXT_SECTION, EXT_KEY_V7, encoded, true)
    if save_legacy then
        SaveLegacyV6()
    end

    pending_save = false
    pending_save_legacy = false
    pending_save_due = 0
    return true
end

local function ScheduleSave(save_legacy, delay_seconds)
    pending_save = true
    pending_save_legacy = pending_save_legacy or save_legacy == true
    pending_save_due = reaper.time_precise() + (delay_seconds or 0.8)
end

local function FlushScheduledSave(force)
    if not pending_save then
        return true
    end

    if force or reaper.time_precise() >= pending_save_due then
        return SaveData({save_legacy = pending_save_legacy})
    end

    return true
end

local function SplitString(value, delimiter)
    local result = {}
    local pattern = '(.-)' .. delimiter
    for part in string.gmatch((value or '') .. delimiter, pattern) do
        if part ~= '' then
            result[#result + 1] = part
        end
    end
    return result
end

local function ResetTransientSelections()
    selected_tags_list = {}
    selected_tags_set = {}
    selected_filter_tags = {}
    selected_filter_set = {}
end

local function ApplyDataTable(data)
    if type(data) ~= 'table' then
        return false, '백업 데이터의 최상위 형식이 올바르지 않습니다.'
    end
    if type(data.tags) ~= 'table' or type(data.keywords) ~= 'table' then
        return false, 'tags 또는 keywords 데이터가 없습니다.'
    end

    local imported_tags = {}
    local imported_tag_set = {}

    for _, raw_tag in ipairs(data.tags) do
        if type(raw_tag) == 'table' then
            local name = SanitizeStoredText(raw_tag.name)
            local normalized = Lower(name)
            if name ~= '' and not imported_tag_set[normalized] then
                imported_tag_set[normalized] = true
                imported_tags[#imported_tags + 1] = {
                    name = name,
                    color = MakeOpaque(tonumber(raw_tag.color) or 0xFFFFFFFF),
                }
            end
        end
    end

    local tag_name_lookup = {}
    for _, tag in ipairs(imported_tags) do
        tag_name_lookup[tag.name] = true
    end

    local imported_keywords = {}
    local imported_word_set = {}
    local used_ids = {}
    local max_id = 0

    for _, raw_keyword in ipairs(data.keywords) do
        if type(raw_keyword) == 'table' then
            local word = SanitizeStoredText(raw_keyword.word)
            local normalized = Lower(word)

            if word ~= '' and not imported_word_set[normalized] then
                imported_word_set[normalized] = true

                local id = math.floor(tonumber(raw_keyword.id) or 0)
                if id < 1 or used_ids[id] then
                    id = max_id + 1
                    while used_ids[id] do
                        id = id + 1
                    end
                end
                used_ids[id] = true
                if id > max_id then
                    max_id = id
                end

                local keyword_tags = {}
                local keyword_tag_set = {}
                for _, tag_name in ipairs(raw_keyword.tags or {}) do
                    if tag_name_lookup[tag_name] and not keyword_tag_set[tag_name] then
                        keyword_tag_set[tag_name] = true
                        keyword_tags[#keyword_tags + 1] = tag_name
                    end
                end

                imported_keywords[#imported_keywords + 1] = {
                    id = id,
                    word = word,
                    tags = keyword_tags,
                    favorite = raw_keyword.favorite == true,
                    last_used = math.max(0, math.floor(tonumber(raw_keyword.last_used) or 0)),
                    use_count = math.max(0, math.floor(tonumber(raw_keyword.use_count) or 0)),
                    created_at = math.max(0, math.floor(tonumber(raw_keyword.created_at) or 0)),
                }
            end
        end
    end

    tags = imported_tags
    keywords = imported_keywords
    next_keyword_id = math.max(max_id + 1, math.floor(tonumber(data.next_keyword_id) or 1))

    local settings = type(data.settings) == 'table' and data.settings or {}
    filter_mode = settings.filter_mode == 'OR' and 'OR' or 'AND'

    local allowed_sort_modes = {
        newest = true,
        favorite = true,
        recent = true,
        usage = true,
        name = true,
    }
    sort_mode = allowed_sort_modes[settings.sort_mode] and settings.sort_mode or 'newest'
    favorite_only = settings.favorite_only == true
    ResetTransientSelections()
    InvalidateTagCountCache()
    RebuildTagCountCache()
    return true
end

local function LoadLegacyData()
    local migrated_tags = {}
    local migrated_keywords = {}

    local tags_v6 = reaper.GetExtState(EXT_SECTION, 'TagsV6')
    if tags_v6 ~= '' then
        for _, item in ipairs(SplitString(tags_v6, '@@')) do
            local name, color_text = item:match('^(.-);;(.*)$')
            if name and color_text then
                migrated_tags[#migrated_tags + 1] = {
                    name = name,
                    color = tonumber(color_text) or 0xFFFFFFFF,
                }
            end
        end
    else
        local tags_v4 = reaper.GetExtState(EXT_SECTION, 'TagsV4')
        if tags_v4 ~= '' then
            for item in tags_v4:gmatch('([^,]+)') do
                local name, color_text = item:match('(.-)#(.*)')
                if name and color_text then
                    migrated_tags[#migrated_tags + 1] = {
                        name = name,
                        color = tonumber(color_text, 16) or 0xFFFFFFFF,
                    }
                end
            end
        end
    end

    local keywords_v6 = reaper.GetExtState(EXT_SECTION, 'KeywordsV6')
    if keywords_v6 ~= '' then
        for _, item in ipairs(SplitString(keywords_v6, '@@')) do
            local word, tags_text = item:match('^(.-);;(.*)$')
            if word then
                migrated_keywords[#migrated_keywords + 1] = {
                    word = word,
                    tags = tags_text ~= '' and SplitString(tags_text, '||') or {},
                }
            end
        end
    else
        local legacy = reaper.GetExtState(EXT_SECTION, 'KeywordsV3')
        if legacy == '' then
            legacy = reaper.GetExtState(EXT_SECTION, 'KeywordsV2')
        end

        if legacy ~= '' then
            for item in legacy:gmatch('([^@]+)') do
                local word, tags_text = item:match('(.-)||(.*)')
                if word then
                    local tag_list = {}
                    if tags_text and tags_text ~= '' then
                        for tag_name in tags_text:gmatch('([^|]+)') do
                            tag_list[#tag_list + 1] = tag_name
                        end
                    end
                    migrated_keywords[#migrated_keywords + 1] = {
                        word = word,
                        tags = tag_list,
                    }
                end
            end
        end
    end

    return ApplyDataTable({
        version = DATA_VERSION,
        next_keyword_id = 1,
        tags = migrated_tags,
        keywords = migrated_keywords,
        settings = {},
    })
end

local function LoadData()
    local encoded = reaper.GetExtState(EXT_SECTION, EXT_KEY_V7)
    if encoded ~= '' then
        local ok, decoded = pcall(JsonDecode, encoded)
        if ok then
            local applied, error_message = ApplyDataTable(decoded)
            if applied then
                return
            end
            reaper.ShowMessageBox('V7 데이터 로드 실패:\n' .. tostring(error_message), '데이터 오류', 0)
        else
            reaper.ShowMessageBox('V7 JSON 데이터가 손상되어 V6 데이터를 복구합니다.\n' .. tostring(decoded), '데이터 복구', 0)
        end
    end

    LoadLegacyData()
    SaveData({save_legacy = true, invalidate_tag_cache = true})
end

LoadData()
RebuildTagCountCache()

-- -----------------------------------------------------------------------------
-- 선택/필터/검색/정렬
-- -----------------------------------------------------------------------------

local function RemoveSelectedFilterTag(tag_name)
    selected_filter_set[tag_name] = nil
    RemoveFromArray(selected_filter_tags, tag_name)
end

local function ToggleFilterTag(tag_name)
    if selected_filter_set[tag_name] then
        RemoveSelectedFilterTag(tag_name)
    else
        selected_filter_tags[#selected_filter_tags + 1] = tag_name
        selected_filter_set[tag_name] = true
    end
end

local function ApplySingleTagFilter(tag_name)
    selected_filter_tags = {tag_name}
    selected_filter_set = {[tag_name] = true}
    filter_panel_open = true
    SetStatus('태그 필터 적용: ' .. tostring(tag_name), 2.0)
end

local function RemoveSelectedInputTag(tag_name)
    selected_tags_set[tag_name] = nil
    RemoveFromArray(selected_tags_list, tag_name)
end

local function ToggleInputTag(tag_name)
    if selected_tags_set[tag_name] then
        RemoveSelectedInputTag(tag_name)
    else
        selected_tags_list[#selected_tags_list + 1] = tag_name
        selected_tags_set[tag_name] = true
    end
end

local function ToggleEditKeywordTag(tag_name)
    if editing_keyword_tag_set[tag_name] then
        editing_keyword_tag_set[tag_name] = nil
        RemoveFromArray(editing_keyword_tags, tag_name)
    else
        editing_keyword_tags[#editing_keyword_tags + 1] = tag_name
        editing_keyword_tag_set[tag_name] = true
    end
end

local function MatchesSelectedTags(keyword_tags)
    if #selected_filter_tags == 0 then
        return true
    end

    local keyword_tag_set = {}
    for _, tag_name in ipairs(keyword_tags or {}) do
        keyword_tag_set[tag_name] = true
    end

    if filter_mode == 'OR' then
        for _, required_tag in ipairs(selected_filter_tags) do
            if keyword_tag_set[required_tag] then
                return true
            end
        end
        return false
    end

    for _, required_tag in ipairs(selected_filter_tags) do
        if not keyword_tag_set[required_tag] then
            return false
        end
    end
    return true
end

local function MatchesLiveSearch(keyword)
    local query = Lower(CollapseSpaces(search_text))
    if query == '' then
        return true
    end

    local haystack_parts = {Lower(keyword.word)}
    for _, tag_name in ipairs(keyword.tags or {}) do
        haystack_parts[#haystack_parts + 1] = Lower(tag_name)
    end
    local haystack = table.concat(haystack_parts, ' ')

    for token in query:gmatch('%S+') do
        if not haystack:find(token, 1, true) then
            return false
        end
    end

    return true
end

local function BuildVisibleKeywordEntries()
    local entries = {}

    for index, keyword in ipairs(keywords) do
        if MatchesLiveSearch(keyword)
            and MatchesSelectedTags(keyword.tags)
            and (not favorite_only or keyword.favorite) then
            entries[#entries + 1] = {
                keyword = keyword,
                index = index,
            }
        end
    end

    table.sort(entries, function(a, b)
        local left = a.keyword
        local right = b.keyword

        if sort_mode == 'favorite' then
            if left.favorite ~= right.favorite then
                return left.favorite
            end
            if left.last_used ~= right.last_used then
                return left.last_used > right.last_used
            end
        elseif sort_mode == 'recent' then
            if left.last_used ~= right.last_used then
                return left.last_used > right.last_used
            end
        elseif sort_mode == 'usage' then
            if left.use_count ~= right.use_count then
                return left.use_count > right.use_count
            end
        elseif sort_mode == 'name' then
            local left_name = Lower(left.word)
            local right_name = Lower(right.word)
            if left_name ~= right_name then
                return left_name < right_name
            end
        else
            if left.created_at ~= right.created_at then
                return left.created_at > right.created_at
            end
        end

        return left.id > right.id
    end)

    return entries
end

local function FormatLastUsed(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then
        return '아직 사용하지 않음'
    end
    return os.date('%Y-%m-%d %H:%M', timestamp)
end

-- -----------------------------------------------------------------------------
-- 검색어/태그/클립보드 동작
-- -----------------------------------------------------------------------------

local function RecordKeywordUse(keyword)
    keyword.use_count = (tonumber(keyword.use_count) or 0) + 1
    keyword.last_used = os.time()
end

local function CopyText(text_value, used_keywords)
    ImGui.SetClipboardText(ctx, tostring(text_value or ''))

    if used_keywords then
        for _, keyword in ipairs(used_keywords) do
            RecordKeywordUse(keyword)
        end
        ScheduleSave(false, 0.8)
    end

    SetStatus('클립보드에 복사했습니다: ' .. tostring(text_value or ''), 2.5)
end

local function SaveNewKeyword()
    local word = SanitizeStoredText(new_keyword_text)
    if word == '' then
        SetStatus('검색어를 입력해주세요.')
        return false
    end

    if FindDuplicateKeyword(word, nil) then
        SetStatus('이미 등록된 검색어입니다: ' .. word, 4.0)
        return false
    end

    local assigned_tags = UniqueArray(CopyArray(selected_tags_list))
    keywords[#keywords + 1] = {
        id = next_keyword_id,
        word = word,
        tags = assigned_tags,
        favorite = false,
        last_used = 0,
        use_count = 0,
        created_at = os.time(),
    }
    next_keyword_id = next_keyword_id + 1

    new_keyword_text = ''
    selected_tags_list = {}
    selected_tags_set = {}
    SaveData({
        save_legacy = true,
        invalidate_tag_cache = #assigned_tags > 0,
    })
    SetStatus('검색어를 저장했습니다: ' .. word)
    return true
end

local function DeleteKeyword(keyword_index)
    local keyword = keywords[keyword_index]
    if not keyword then
        return false
    end

    local answer = reaper.ShowMessageBox(
        "검색어 '" .. keyword.word .. "' 을(를) 삭제하시겠습니까?",
        '삭제 확인',
        4
    )

    if answer ~= 6 then
        return false
    end

    if editing_keyword_id == keyword.id then
        editing_keyword_id = nil
    end

    last_deleted_keyword = {
        keyword = CopyKeyword(keyword),
        index = keyword_index,
        expires_at = reaper.time_precise() + UNDO_DELETE_SECONDS,
    }

    local had_tags = #(keyword.tags or {}) > 0
    table.remove(keywords, keyword_index)
    SaveData({
        save_legacy = true,
        invalidate_tag_cache = had_tags,
    })
    SetStatus('검색어를 삭제했습니다. 아래의 실행 취소 버튼으로 복구할 수 있습니다.', UNDO_DELETE_SECONDS)
    return true
end

local function UndoLastKeywordDelete()
    local deleted = last_deleted_keyword
    if not deleted then
        return false
    end

    if reaper.time_precise() > (deleted.expires_at or 0) then
        last_deleted_keyword = nil
        SetStatus('삭제 실행 취소 시간이 지났습니다.')
        return false
    end

    local keyword = deleted.keyword
    if FindDuplicateKeyword(keyword.word, nil) then
        last_deleted_keyword = nil
        SetStatus('같은 검색어가 이미 존재해 복구하지 못했습니다.', 4.0)
        return false
    end

    local insert_index = math.max(1, math.min(tonumber(deleted.index) or (#keywords + 1), #keywords + 1))
    table.insert(keywords, insert_index, CopyKeyword(keyword))
    if keyword.id >= next_keyword_id then
        next_keyword_id = keyword.id + 1
    end

    SaveData({
        save_legacy = true,
        invalidate_tag_cache = #(keyword.tags or {}) > 0,
    })
    last_deleted_keyword = nil
    SetStatus('삭제한 검색어를 복구했습니다: ' .. keyword.word)
    return true
end

local function DrawUndoDelete()
    if not last_deleted_keyword then
        return
    end

    local remaining = (last_deleted_keyword.expires_at or 0) - reaper.time_precise()
    if remaining <= 0 then
        last_deleted_keyword = nil
        return
    end

    ImGui.TextColored(
        ctx,
        0xFFD166FF,
        string.format('삭제한 검색어를 %.0f초 동안 복구할 수 있습니다.', math.ceil(remaining))
    )
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, '실행 취소##UndoKeywordDelete') then
        UndoLastKeywordDelete()
    end
    ImGui.Separator(ctx)
end

local function BeginKeywordEdit(keyword)
    editing_keyword_id = keyword.id
    editing_keyword_text = keyword.word
    editing_keyword_tags = CopyArray(keyword.tags)
    editing_keyword_tag_set = {}
    keyword_editor_error = ''
    for _, tag_name in ipairs(editing_keyword_tags) do
        editing_keyword_tag_set[tag_name] = true
    end
    request_keyword_editor = true
end

local function SaveKeywordEdit()
    keyword_editor_error = ''

    local keyword = GetKeywordById(editing_keyword_id)
    if not keyword then
        keyword_editor_error = '편집할 검색어를 찾지 못했습니다.'
        return false
    end

    local word = SanitizeStoredText(editing_keyword_text)
    if word == '' then
        keyword_editor_error = '검색어를 입력해주세요.'
        return false
    end

    if FindDuplicateKeyword(word, keyword.id) then
        keyword_editor_error = '같은 검색어가 이미 등록되어 있습니다: ' .. word
        return false
    end

    local new_tags = UniqueArray(CopyArray(editing_keyword_tags))
    local tags_changed = not ArraysEqual(keyword.tags, new_tags)

    keyword.word = word
    keyword.tags = new_tags
    SaveData({
        save_legacy = true,
        invalidate_tag_cache = tags_changed,
    })
    keyword_editor_error = ''
    SetStatus('검색어를 수정했습니다: ' .. word)
    return true
end

local function RenameTagReferences(old_name, new_name)
    for _, keyword in ipairs(keywords) do
        ReplaceInArray(keyword.tags, old_name, new_name)
        keyword.tags = UniqueArray(keyword.tags)
    end

    ReplaceInArray(selected_tags_list, old_name, new_name)
    ReplaceInArray(selected_filter_tags, old_name, new_name)
    ReplaceInArray(editing_keyword_tags, old_name, new_name)

    if selected_tags_set[old_name] then
        selected_tags_set[old_name] = nil
        selected_tags_set[new_name] = true
    end
    if selected_filter_set[old_name] then
        selected_filter_set[old_name] = nil
        selected_filter_set[new_name] = true
    end
    if editing_keyword_tag_set[old_name] then
        editing_keyword_tag_set[old_name] = nil
        editing_keyword_tag_set[new_name] = true
    end
end

local function BeginTagEdit(tag)
    editing_tag_original_name = tag.name
    editing_tag_name = tag.name
    editing_tag_color = tag.color
    tag_editor_error = ''
    request_tag_editor = true
end

local function SaveTagEdit()
    tag_editor_error = ''

    local tag = nil
    for _, candidate in ipairs(tags) do
        if candidate.name == editing_tag_original_name then
            tag = candidate
            break
        end
    end

    if not tag then
        tag_editor_error = '편집할 태그를 찾지 못했습니다.'
        return false
    end

    local new_name = SanitizeStoredText(editing_tag_name)
    if new_name == '' then
        tag_editor_error = '태그 이름을 입력해주세요.'
        return false
    end

    if FindTagByName(new_name, editing_tag_original_name) then
        tag_editor_error = '같은 이름의 태그가 이미 있습니다: ' .. new_name
        return false
    end

    local old_name = tag.name
    local renamed = old_name ~= new_name
    tag.name = new_name
    tag.color = MakeOpaque(editing_tag_color)

    if renamed then
        RenameTagReferences(old_name, new_name)
    end

    SaveData({
        save_legacy = true,
        invalidate_tag_cache = renamed,
    })
    tag_editor_error = ''
    SetStatus('태그를 수정했습니다: ' .. new_name)
    return true
end

local function DeleteTag(tag_index)
    local tag = tags[tag_index]
    if not tag then
        return false
    end

    RebuildTagCountCache()
    local count = tag_count_cache[tag.name] or 0
    local message = string.format(
        "태그 '%s'을(를) 삭제하시겠습니까?\n이 태그가 연결된 검색어 %d개에서도 함께 제거됩니다.",
        tag.name,
        count
    )

    local answer = reaper.ShowMessageBox(message, '태그 삭제 확인', 4)
    if answer ~= 6 then
        return false
    end

    for _, keyword in ipairs(keywords) do
        RemoveFromArray(keyword.tags, tag.name)
    end

    RemoveSelectedInputTag(tag.name)
    RemoveSelectedFilterTag(tag.name)
    editing_keyword_tag_set[tag.name] = nil
    RemoveFromArray(editing_keyword_tags, tag.name)

    table.remove(tags, tag_index)
    SaveData({
        save_legacy = true,
        invalidate_tag_cache = true,
    })
    SetStatus('태그와 연결 데이터를 정리해 삭제했습니다.')
    return true
end

local function CreateNewTag()
    local name = SanitizeStoredText(new_tag_text)
    if name == '' then
        SetStatus('태그 이름을 입력해주세요.')
        return false
    end

    if FindTagByName(name, nil) then
        SetStatus('이미 존재하는 태그입니다: ' .. name, 4.0)
        return false
    end

    tags[#tags + 1] = {
        name = name,
        color = MakeOpaque(new_tag_color),
    }

    new_tag_text = ''
    SaveData({
        save_legacy = true,
        invalidate_tag_cache = false,
    })
    SetStatus('태그를 생성했습니다: ' .. name)
    return true
end

-- -----------------------------------------------------------------------------
-- JSON 백업/복원
-- -----------------------------------------------------------------------------

local function GetPathSeparator()
    return reaper.GetOS():match('Win') and '\\' or '/'
end

local function GetBackupDirectory()
    local separator = GetPathSeparator()
    return reaper.GetResourcePath()
        .. separator .. 'Data'
        .. separator .. 'SoundLibraryManager'
end

local function FileExists(filename)
    local file = io.open(filename, 'rb')
    if file then
        file:close()
        return true
    end
    return false
end

local function MakeUniqueBackupFilename(prefix)
    local separator = GetPathSeparator()
    local directory = GetBackupDirectory()
    reaper.RecursiveCreateDirectory(directory, 0)

    local stem = directory
        .. separator
        .. tostring(prefix or 'sound_library_backup')
        .. '_'
        .. os.date('%Y%m%d_%H%M%S')

    local filename = stem .. '.json'
    local suffix = 1
    while FileExists(filename) do
        filename = stem .. '_' .. tostring(suffix) .. '.json'
        suffix = suffix + 1
    end
    return filename
end

local function WriteFileAtomic(filename, content)
    local temporary = filename .. '.tmp'
    os.remove(temporary)

    local file, open_error = io.open(temporary, 'wb')
    if not file then
        return false, '임시 파일을 만들 수 없습니다: ' .. tostring(open_error)
    end

    local write_ok, write_error = pcall(function()
        file:write(content)
        file:flush()
    end)
    file:close()

    if not write_ok then
        os.remove(temporary)
        return false, '파일 쓰기에 실패했습니다: ' .. tostring(write_error)
    end

    local renamed, rename_error = os.rename(temporary, filename)
    if not renamed then
        os.remove(temporary)
        return false, '백업 파일 확정에 실패했습니다: ' .. tostring(rename_error)
    end

    return true
end

local function ReadWholeFile(filename)
    local file, open_error = io.open(filename, 'rb')
    if not file then
        return nil, '파일을 열 수 없습니다: ' .. tostring(open_error)
    end

    local ok, content = pcall(function()
        return file:read('*a')
    end)
    file:close()

    if not ok then
        return nil, '파일 읽기에 실패했습니다: ' .. tostring(content)
    end
    return content
end

local function BackupToJson(options)
    options = options or {}
    local filename = MakeUniqueBackupFilename(options.prefix)

    local ok, encoded = pcall(JsonEncode, BuildDataTable())
    if not ok then
        local message = 'JSON 생성 실패: ' .. tostring(encoded)
        if not options.silent then
            reaper.ShowMessageBox(message, '백업 오류', 0)
        end
        return false, nil, message
    end

    local written, write_error = WriteFileAtomic(filename, encoded)
    if not written then
        if not options.silent then
            reaper.ShowMessageBox(write_error, '백업 오류', 0)
        end
        return false, nil, write_error
    end

    local verify_content, read_error = ReadWholeFile(filename)
    if not verify_content then
        os.remove(filename)
        if not options.silent then
            reaper.ShowMessageBox(read_error, '백업 오류', 0)
        end
        return false, nil, read_error
    end

    local verify_ok, verify_data = pcall(JsonDecode, verify_content)
    if not verify_ok or type(verify_data) ~= 'table' then
        os.remove(filename)
        local message = '백업 검증에 실패했습니다: ' .. tostring(verify_data)
        if not options.silent then
            reaper.ShowMessageBox(message, '백업 오류', 0)
        end
        return false, nil, message
    end

    if not options.silent then
        reaper.ShowMessageBox('JSON 백업을 완료했습니다.\n\n' .. filename, '백업 완료', 0)
        SetStatus('JSON 백업 완료')
    end
    return true, filename
end

local function RestoreFromJson()
    local selected, filename = reaper.GetUserFileNameForRead('', '복원할 JSON 백업 파일 선택', '.json')
    if not selected or not filename or filename == '' then
        return
    end

    local content, read_error = ReadWholeFile(filename)
    if not content then
        reaper.ShowMessageBox(read_error, '복원 오류', 0)
        return
    end

    local decoded_ok, decoded = pcall(JsonDecode, content)
    if not decoded_ok then
        reaper.ShowMessageBox('JSON 해석 실패:\n' .. tostring(decoded), '복원 오류', 0)
        return
    end
    if type(decoded) ~= 'table'
        or type(decoded.tags) ~= 'table'
        or type(decoded.keywords) ~= 'table' then
        reaper.ShowMessageBox('백업 데이터에 tags 또는 keywords가 없습니다.', '복원 오류', 0)
        return
    end

    local answer = reaper.ShowMessageBox(
        '현재 데이터를 선택한 백업으로 교체하시겠습니까?\n복원 전에 현재 데이터가 자동으로 안전 백업됩니다.',
        '복원 확인',
        4
    )
    if answer ~= 6 then
        return
    end

    FlushScheduledSave(true)

    local snapshot_ok, current_snapshot = pcall(JsonEncode, BuildDataTable())
    if not snapshot_ok then
        reaper.ShowMessageBox(
            '현재 데이터의 복원용 스냅샷을 만들지 못했습니다.\n복원을 중단합니다.\n\n'
                .. tostring(current_snapshot),
            '복원 오류',
            0
        )
        return
    end

    local backup_ok, automatic_backup, backup_error = BackupToJson({
        silent = true,
        prefix = 'pre_restore_backup',
    })
    if not backup_ok then
        reaper.ShowMessageBox(
            '현재 데이터 자동 백업에 실패하여 복원을 중단합니다.\n\n' .. tostring(backup_error),
            '복원 오류',
            0
        )
        return
    end

    local applied_ok, applied, apply_error = pcall(ApplyDataTable, decoded)
    if not applied_ok or not applied then
        local rollback_ok, rollback_data = pcall(JsonDecode, current_snapshot)
        if rollback_ok then
            pcall(ApplyDataTable, rollback_data)
        end
        reaper.ShowMessageBox(
            '백업 데이터 적용에 실패했습니다. 기존 데이터를 유지합니다.\n\n'
                .. tostring(applied_ok and apply_error or applied),
            '복원 오류',
            0
        )
        return
    end

    if not SaveData({save_legacy = true, invalidate_tag_cache = true}) then
        local rollback_ok, rollback_data = pcall(JsonDecode, current_snapshot)
        if rollback_ok then
            pcall(ApplyDataTable, rollback_data)
            SaveData({save_legacy = true, invalidate_tag_cache = true})
        end
        reaper.ShowMessageBox('복원 데이터 저장에 실패해 기존 데이터로 되돌렸습니다.', '복원 오류', 0)
        return
    end

    reaper.ShowMessageBox(
        'JSON 데이터를 복원했습니다.\n\n복원 전 자동 백업:\n' .. tostring(automatic_backup),
        '복원 완료',
        0
    )
    SetStatus('JSON 복원 완료')
end

-- -----------------------------------------------------------------------------
-- 목록 행/UI
-- -----------------------------------------------------------------------------

local function DrawKeywordTagArea(keyword, keyword_id, area_width)
    if ImGui.BeginChild(ctx, 'KeywordTagsRow##' .. tostring(keyword_id), area_width, 23) then
        local used_width = 0
        local hidden_tags = {}
        local spacing = 4

        for tag_index, tag_name in ipairs(keyword.tags or {}) do
            local width = GetTagButtonWidth(tag_name, 14)
            local required = width + (used_width > 0 and spacing or 0)

            if used_width + required <= area_width then
                if used_width > 0 then
                    ImGui.SameLine(ctx, 0, spacing)
                    used_width = used_width + spacing
                end

                if DrawTagButton(
                    tag_name,
                    GetTagColor(tag_name),
                    'KeywordTag' .. tostring(keyword_id) .. '_' .. tostring(tag_index),
                    width,
                    22
                ) then
                    ApplySingleTagFilter(tag_name)
                end
                if ImGui.IsItemHovered(ctx) then
                    ImGui.BeginTooltip(ctx)
                    ImGui.Text(ctx, '클릭하여 이 태그로 필터링')
                    ImGui.EndTooltip(ctx)
                end
                used_width = used_width + width
            else
                hidden_tags[#hidden_tags + 1] = tag_name
            end
        end

        if #hidden_tags > 0 then
            local label = '+' .. tostring(#hidden_tags)
            local width = GetTagButtonWidth(label, 12)
            if used_width == 0 or used_width + spacing + width <= area_width then
                if used_width > 0 then
                    ImGui.SameLine(ctx, 0, spacing)
                end
                ImGui.Button(ctx, label .. '##HiddenTags' .. tostring(keyword_id), width, 19)
                if ImGui.IsItemHovered(ctx) then
                    ImGui.BeginTooltip(ctx)
                    ImGui.Text(ctx, '숨겨진 태그')
                    ImGui.Separator(ctx)
                    ImGui.TextWrapped(ctx, table.concat(hidden_tags, ', '))
                    ImGui.EndTooltip(ctx)
                end
            end
        elseif #(keyword.tags or {}) == 0 then
            ImGui.TextDisabled(ctx, '태그 없음')
        end

        ImGui.EndChild(ctx)
    end
end

local function DrawKeywordSecondRow(keyword, keyword_index)
    local available_width = ImGui.GetContentRegionAvail(ctx)
    local spacing = 4
    local edit_width = 44
    local copy_width = 44
    local delete_width = 44
    local action_width = edit_width + copy_width + delete_width + spacing * 2
    local compact = available_width < 470

    if compact then
        DrawKeywordTagArea(keyword, keyword.id, available_width)
        local row_start = ImGui.GetCursorPosX(ctx)
        local remaining = ImGui.GetContentRegionAvail(ctx)
        if remaining > action_width then
            ImGui.SetCursorPosX(ctx, row_start + remaining - action_width)
        end
    else
        local tag_area_width = math.max(100, available_width - action_width - spacing)
        DrawKeywordTagArea(keyword, keyword.id, tag_area_width)
        ImGui.SameLine(ctx, 0, spacing)
    end

    if ImGui.Button(ctx, '편집##Edit' .. tostring(keyword.id), edit_width, 19) then
        BeginKeywordEdit(keyword)
    end
    ImGui.SameLine(ctx, 0, spacing)
    if ImGui.Button(ctx, '복사##Copy' .. tostring(keyword.id), copy_width, 19) then
        CopyText(keyword.word, {keyword})
    end
    ImGui.SameLine(ctx, 0, spacing)
    if DrawDangerButton('삭제', 'Delete' .. tostring(keyword.id), delete_width, 19) then
        return DeleteKeyword(keyword_index)
    end
    return false
end

local function DrawKeywordRow(keyword, keyword_index)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 4)
    local star_label = keyword.favorite and '★' or '☆'
    if ImGui.Button(ctx, star_label .. '##Favorite' .. tostring(keyword.id), 26, 24) then
        keyword.favorite = not keyword.favorite
        ScheduleSave(false, 0.5)
    end

    ImGui.SameLine(ctx, 0, 8)
    ImGui.AlignTextToFramePadding(ctx)
    
    local y = ImGui.GetCursorPosY(ctx)
    ImGui.SetCursorPosY(ctx, y - -2)
    
    ImGui.TextWrapped(ctx, keyword.word)
    if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(
            ctx,
            '더블클릭: 즉시 복사\n최근 사용: ' .. FormatLastUsed(keyword.last_used)
                .. '\n사용 횟수: ' .. tostring(keyword.use_count or 0)
        )
        if ImGui.IsMouseDoubleClicked(ctx, 0) then
            CopyText(keyword.word, {keyword})
        end
    end

    local deleted = DrawKeywordSecondRow(keyword, keyword_index)
    ImGui.PopStyleVar(ctx)
    ImGui.Separator(ctx)
    return deleted
end

local function DrawFilterAndSearchControls()
    DrawSectionTitle('빠른 검색', '검색어와 태그를 함께 찾습니다')

    ImGui.SetNextItemWidth(ctx, -66)
    local changed, value = ImGui.InputTextWithHint(
        ctx,
        '##LiveSearch',
        '검색어 또는 태그 입력...',
        search_text
    )
    if changed then
        search_text = value
    end

    ImGui.SameLine(ctx, 0, 6)
    if ImGui.Button(ctx, '지우기', 58, 0) then
        search_text = ''
    end

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, filter_panel_open and '필터 접기' or '필터 보기', 80, 23) then
        filter_panel_open = not filter_panel_open
    end
    ImGui.SameLine(ctx, 0, 8)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, string.format('선택 %d개 · %s 조건', #selected_filter_tags, filter_mode))

    if #selected_filter_tags > 0 then
        ImGui.SameLine(ctx, 0, 8)
        if ImGui.Button(ctx, '필터 초기화', 76, 23) then
            selected_filter_tags = {}
            selected_filter_set = {}
        end
    end

    if filter_panel_open then
        ImGui.Spacing(ctx)
        ImGui.TextDisabled(ctx, '검색 조건')
        ImGui.SameLine(ctx, 0, 8)
        if ImGui.Button(ctx, (filter_mode == 'AND' and '✓ ' or '') .. 'AND##FilterMode', 52, 21) then
            filter_mode = 'AND'
            ScheduleSave(false, 0.5)
        end
        ImGui.SameLine(ctx, 0, 4)
        if ImGui.Button(ctx, (filter_mode == 'OR' and '✓ ' or '') .. 'OR##FilterMode', 50, 21) then
            filter_mode = 'OR'
            ScheduleSave(false, 0.5)
        end

        if #selected_filter_tags > 0 then
            ImGui.TextDisabled(ctx, '선택된 태그 · 클릭하면 해제')
            local selected_items = {}
            for _, tag_name in ipairs(selected_filter_tags) do
                selected_items[#selected_items + 1] = {name = tag_name, color = GetTagColor(tag_name)}
            end
            DrawWrappedTagButtons(selected_items, 'SelectedFilter', RemoveSelectedFilterTag, false, nil)
        end

        ImGui.Spacing(ctx)
        if ImGui.BeginChild(ctx, 'FilterTagButtons', 0, 78, ImGui.ChildFlags_Border) then
            if #tags == 0 then
                ImGui.TextDisabled(ctx, '등록된 태그가 없습니다.')
            else
                RebuildTagCountCache()
                DrawWrappedTagButtons(tags, 'FilterTag', ToggleFilterTag, true, selected_filter_set)
            end
            ImGui.EndChild(ctx)
        end
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, '정렬')
    local sort_items = {
        {label = '최신', value = 'newest'},
        {label = '즐겨찾기', value = 'favorite'},
        {label = '최근 사용', value = 'recent'},
        {label = '많이 사용', value = 'usage'},
        {label = '이름', value = 'name'},
    }
    DrawWrappedButtons(sort_items, 'SortMode', sort_mode, function(value_name)
        sort_mode = value_name
        ScheduleSave(false, 0.5)
    end)

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, (favorite_only and '✓ ' or '') .. '즐겨찾기만 보기', 120, 23) then
        favorite_only = not favorite_only
        ScheduleSave(false, 0.5)
    end
end

-- -----------------------------------------------------------------------------
-- 팝업
-- -----------------------------------------------------------------------------

local function RenderKeywordEditorPopup()
    if request_keyword_editor then
        ImGui.OpenPopup(ctx, '검색어 편집')
        request_keyword_editor = false
    end

    if ImGui.BeginPopupModal(ctx, '검색어 편집', nil, ImGui.WindowFlags_AlwaysAutoResize) then
        ImGui.SetNextItemWidth(ctx, 390)
        local enter_from_input, value = ImGui.InputTextWithHint(
            ctx,
            '##EditKeywordText',
            '검색어...',
            editing_keyword_text,
            ImGui.InputTextFlags_EnterReturnsTrue
        )
        editing_keyword_text = value

        ImGui.Text(ctx, '적용할 태그')
        if ImGui.BeginChild(ctx, 'EditKeywordTags', 390, 128, ImGui.ChildFlags_Border) then
            if #tags == 0 then
                ImGui.TextDisabled(ctx, '등록된 태그가 없습니다.')
            else
                DrawWrappedTagButtons(
                    tags,
                    'EditKeywordTag',
                    ToggleEditKeywordTag,
                    false,
                    editing_keyword_tag_set
                )
            end
            ImGui.EndChild(ctx)
        end

        if keyword_editor_error ~= '' then
            ImGui.TextColored(ctx, 0xFF6B6BFF, keyword_editor_error)
        end

        local enter_pressed = enter_from_input
            or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
        local escape_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)
        local save_clicked = ImGui.Button(ctx, '저장', 88, 26)

        ImGui.SameLine(ctx)
        local cancel_clicked = ImGui.Button(ctx, '취소', 88, 26)

        if save_clicked or enter_pressed then
            if SaveKeywordEdit() then
                ImGui.CloseCurrentPopup(ctx)
            end
        elseif cancel_clicked or escape_pressed then
            keyword_editor_error = ''
            ImGui.CloseCurrentPopup(ctx)
        end

        ImGui.EndPopup(ctx)
    end
end

local function RenderTagEditorPopup()
    if request_tag_editor then
        ImGui.OpenPopup(ctx, '태그 편집')
        request_tag_editor = false
    end

    if ImGui.BeginPopupModal(ctx, '태그 편집', nil, ImGui.WindowFlags_AlwaysAutoResize) then
        ImGui.SetNextItemWidth(ctx, 300)
        local enter_from_input, value = ImGui.InputTextWithHint(
            ctx,
            '##EditTagName',
            '태그 이름...',
            editing_tag_name,
            ImGui.InputTextFlags_EnterReturnsTrue
        )
        editing_tag_name = value

        ImGui.SetNextItemWidth(ctx, 300)
        local changed_color, color = ImGui.ColorEdit4(
            ctx,
            '색상##EditTagColor',
            editing_tag_color
        )
        if changed_color then
            editing_tag_color = MakeOpaque(color)
        end

        if tag_editor_error ~= '' then
            ImGui.TextColored(ctx, 0xFF6B6BFF, tag_editor_error)
        end

        local enter_pressed = enter_from_input
            or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
        local escape_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)
        local save_clicked = ImGui.Button(ctx, '저장', 88, 26)

        ImGui.SameLine(ctx)
        local cancel_clicked = ImGui.Button(ctx, '취소', 88, 26)

        if save_clicked or enter_pressed then
            if SaveTagEdit() then
                ImGui.CloseCurrentPopup(ctx)
            end
        elseif cancel_clicked or escape_pressed then
            tag_editor_error = ''
            ImGui.CloseCurrentPopup(ctx)
        end

        ImGui.EndPopup(ctx)
    end
end

-- -----------------------------------------------------------------------------
-- 탭
-- -----------------------------------------------------------------------------

local function DrawSearchTab()
    ImGui.Spacing(ctx)
    DrawFilterAndSearchControls()

    local entries = BuildVisibleKeywordEntries()
    local favorite_count = 0
    for _, keyword in ipairs(keywords) do
        if keyword.favorite then
            favorite_count = favorite_count + 1
        end
    end

    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, UI_ACCENT_SOFT, string.format('결과 %d개', #entries))
    ImGui.SameLine(ctx, 0, 10)
    ImGui.TextDisabled(ctx, string.format('전체 %d · 즐겨찾기 %d', #keywords, favorite_count))

    if ImGui.BeginChild(ctx, 'KeywordList', 0, -1, ImGui.ChildFlags_Border) then
        if #entries == 0 then
            ImGui.Spacing(ctx)
            ImGui.TextDisabled(ctx, '검색 조건과 일치하는 결과가 없습니다.')
            if search_text ~= '' then
                ImGui.TextDisabled(ctx, '검색어를 지우거나 다른 단어를 입력해보세요.')
            elseif #selected_filter_tags > 0 then
                ImGui.TextDisabled(ctx, '태그 필터를 줄이거나 AND/OR 조건을 바꿔보세요.')
            elseif favorite_only then
                ImGui.TextDisabled(ctx, '즐겨찾기만 보기 옵션을 해제해보세요.')
            end
        else
            for _, entry in ipairs(entries) do
                if DrawKeywordRow(entry.keyword, entry.index) then break end
            end
        end
        ImGui.EndChild(ctx)
    end
end

local function DrawAddAndManageTab()
    ImGui.Spacing(ctx)
    DrawSectionTitle('새 검색어 추가', '검색어와 태그를 한 번에 저장합니다')
    ImGui.SetNextItemWidth(ctx, -1)
    local keyword_changed, value = ImGui.InputTextWithHint(
        ctx, '##NewKeyword', '새 검색어 입력 후 태그 선택', new_keyword_text
    )
    local keyword_input_active = ImGui.IsItemActive(ctx)
    local keyword_input_committed = ImGui.IsItemDeactivatedAfterEdit(ctx)
    local keyword_enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
        and (keyword_input_active or keyword_input_committed)
    if keyword_changed and (keyword_input_active or SanitizeStoredText(value) ~= '') then
        new_keyword_text = value
    end
    if keyword_enter_pressed then SaveNewKeyword() end

    ImGui.TextDisabled(ctx, string.format('적용할 태그 · %d개 선택', #selected_tags_list))
    if ImGui.BeginChild(ctx, 'NewKeywordTagButtons', 0, 80, ImGui.ChildFlags_Border) then
        if #tags == 0 then
            ImGui.TextDisabled(ctx, '먼저 아래에서 태그를 생성해주세요.')
        else
            DrawWrappedTagButtons(tags, 'NewKeywordTag', ToggleInputTag, false, selected_tags_set)
        end
        ImGui.EndChild(ctx)
    end

    if ImGui.Button(ctx, '검색어 저장', -1, 30) then SaveNewKeyword() end

    ImGui.Spacing(ctx)
    DrawSectionTitle('태그 관리', '생성·편집·순서 변경')
    ImGui.SetNextItemWidth(ctx, -1)
    local tag_changed, tag_value = ImGui.InputTextWithHint(
        ctx, '##NewTag', '새 태그 이름 입력 후 Enter...', new_tag_text
    )
    local tag_input_active = ImGui.IsItemActive(ctx)
    local tag_input_committed = ImGui.IsItemDeactivatedAfterEdit(ctx)
    local tag_enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
        and (tag_input_active or tag_input_committed)
    if tag_changed and (tag_input_active or SanitizeStoredText(tag_value) ~= '') then
        new_tag_text = tag_value
    end

    local create_tag_clicked = ImGui.Button(ctx, '태그 생성', 96, 28)
    ImGui.SameLine(ctx, 0, 8)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, '색상')
    ImGui.SameLine(ctx, 0, 6)

    local color_flags = (ImGui.ColorEditFlags_NoInputs or 0) + (ImGui.ColorEditFlags_NoLabel or 0)
    local color_changed, color_value = ImGui.ColorEdit4(ctx, '##NewTagColor', new_tag_color, color_flags)
    if color_changed then new_tag_color = MakeOpaque(color_value) end

    if tag_enter_pressed or create_tag_clicked then CreateNewTag() end

    ImGui.Spacing(ctx)
    if ImGui.BeginChild(ctx, 'SystemTagManager', 0, -1, ImGui.ChildFlags_Border) then
        RebuildTagCountCache()
        if #tags == 0 then
            ImGui.TextDisabled(ctx, '등록된 태그가 없습니다.')
        else
            for index, tag in ipairs(tags) do
                ImGui.PushID(ctx, index)
                local row_start = ImGui.GetCursorPosX(ctx)
                local row_width = ImGui.GetContentRegionAvail(ctx)
                local spacing = 4
                local action_width = 42 + 28 + 28 + 42 + spacing * 3
                local label = string.format('%s (%d)', tag.name, tag_count_cache[tag.name] or 0)
                local tag_width = math.min(GetTagButtonWidth(label), math.max(90, row_width - action_width - 8))
                DrawTagButton(label, tag.color, 'ManagerTag', tag_width, 21)

                ImGui.SameLine(ctx, 0, spacing)
                local target_x = row_start + row_width - action_width
                if ImGui.GetCursorPosX(ctx) < target_x then ImGui.SetCursorPosX(ctx, target_x) end

                if ImGui.Button(ctx, '편집', 42, 19) then BeginTagEdit(tag) end
                ImGui.SameLine(ctx, 0, spacing)
                if ImGui.Button(ctx, '↑', 28, 19) and index > 1 then
                    tags[index], tags[index - 1] = tags[index - 1], tags[index]
                    SaveData({save_legacy = true})
                end
                ImGui.SameLine(ctx, 0, spacing)
                if ImGui.Button(ctx, '↓', 28, 19) and index < #tags then
                    tags[index], tags[index + 1] = tags[index + 1], tags[index]
                    SaveData({save_legacy = true})
                end
                ImGui.SameLine(ctx, 0, spacing)
                if DrawDangerButton('삭제', 'DeleteTag', 42, 19) then
                    if DeleteTag(index) then ImGui.PopID(ctx); break end
                end
                ImGui.Separator(ctx)
                ImGui.PopID(ctx)
            end
        end
        ImGui.EndChild(ctx)
    end
end

-- -----------------------------------------------------------------------------
-- CSV 내보내기/불러오기
-- -----------------------------------------------------------------------------

local function EnsureCsvExtension(filename)
    filename = tostring(filename or '')
    if filename == '' then
        return filename
    end
    if not filename:lower():match('%.csv$') then
        filename = filename .. '.csv'
    end
    return filename
end

local function GetDefaultCsvFilename(export_kind)
    local suffix = export_kind == 'full' and 'full' or 'simple'
    return 'SoundLibrary_' .. suffix .. '_' .. os.date('%Y%m%d_%H%M%S') .. '.csv'
end

local function SanitizeFilename(filename)
    filename = Trim(filename):gsub('[\\/:*?"<>|]', '_')
    if filename == '' then
        filename = GetDefaultCsvFilename('simple')
    end
    return EnsureCsvExtension(filename)
end

local function BrowseCsvSaveFilename(export_kind)
    local directory = GetBackupDirectory()
    reaper.RecursiveCreateDirectory(directory, 0)
    local default_name = GetDefaultCsvFilename(export_kind)

    if reaper.JS_Dialog_BrowseForSaveFile then
        local selected, filename = reaper.JS_Dialog_BrowseForSaveFile(
            export_kind == 'full' and '전체 이전용 CSV 저장' or 'Excel 편집용 CSV 저장',
            directory,
            default_name,
            'CSV files (*.csv)\0*.csv\0All files (*.*)\0*.*\0\0'
        )
        if selected and filename and filename ~= '' then
            return EnsureCsvExtension(filename)
        end
        return nil
    end

    local accepted, filename = reaper.GetUserInputs(
        'CSV 파일 이름',
        1,
        '백업 폴더에 저장할 파일 이름:,extrawidth=220',
        default_name
    )
    if not accepted then
        return nil
    end

    filename = SanitizeFilename(filename)
    return directory .. GetPathSeparator() .. filename
end

local function BrowseCsvOpenFilename()
    local directory = GetBackupDirectory()
    reaper.RecursiveCreateDirectory(directory, 0)

    local selected, filename = reaper.GetUserFileNameForRead(
        directory .. GetPathSeparator() .. 'SoundLibrary.csv',
        '불러올 CSV 파일 선택',
        '.csv'
    )
    if selected and filename and filename ~= '' then
        return filename
    end
    return nil
end

local function CsvEscape(value)
    value = tostring(value or ''):gsub('"', '""')
    return '"' .. value .. '"'
end

local function ParseCsvLine(line)
    local fields = {}
    local field = {}
    local index = 1
    local in_quotes = false

    while index <= #line do
        local char = line:sub(index, index)
        if in_quotes then
            if char == '"' then
                local next_char = line:sub(index + 1, index + 1)
                if next_char == '"' then
                    field[#field + 1] = '"'
                    index = index + 1
                else
                    in_quotes = false
                end
            else
                field[#field + 1] = char
            end
        else
            if char == '"' then
                in_quotes = true
            elseif char == ',' then
                fields[#fields + 1] = table.concat(field)
                field = {}
            else
                field[#field + 1] = char
            end
        end
        index = index + 1
    end

    fields[#fields + 1] = table.concat(field)
    return fields
end

local function ParseTagText(tag_text)
    local result = {}
    for tag_name in tostring(tag_text or ''):gmatch('([^|]+)') do
        local clean_tag = SanitizeStoredText(tag_name)
        if clean_tag ~= '' then
            result[#result + 1] = clean_tag
        end
    end
    return UniqueArray(result)
end

local function ParseCsvBoolean(value)
    value = Lower(Trim(value))
    return value == 'true' or value == '1' or value == 'yes' or value == 'y'
end

local function ParseCsvInteger(value, default_value)
    local number = tonumber(Trim(value))
    if not number then
        return default_value or 0
    end
    return math.max(0, math.floor(number))
end

local function ParseCsvColor(value)
    value = Trim(value)
    if value == '' then
        return 0xFFFFFFFF
    end

    local hex = value:match('^0[xX]([%x]+)$') or value:match('^#([%x]+)$')
    local color = hex and tonumber(hex, 16) or tonumber(value)
    return MakeOpaque(color or 0xFFFFFFFF)
end

local function NormalizeCsvHeader(value)
    return Lower(Trim(value)):gsub('[%s_%-]+', '')
end

local function BuildCsvHeaderMap(fields)
    local result = {}
    for index, value in ipairs(fields or {}) do
        result[NormalizeCsvHeader(value)] = index
    end
    return result
end

local function FindTagByNormalizedName(normalized_name)
    for _, tag in ipairs(tags) do
        if Lower(CollapseSpaces(tag.name)) == normalized_name then
            return tag
        end
    end
    return nil
end

local function ConfirmCsvOverwrite(filename)
    if not FileExists(filename) then
        return true
    end
    return reaper.ShowMessageBox(
        '같은 이름의 CSV 파일이 이미 있습니다.\n덮어쓰시겠습니까?\n\n' .. filename,
        'CSV 덮어쓰기 확인',
        4
    ) == 6
end

local function WriteCsvContent(filename, content)
    if not ConfirmCsvOverwrite(filename) then
        return false
    end

    if FileExists(filename) then
        os.remove(filename)
    end

    local ok, err = WriteFileAtomic(filename, content)
    if not ok then
        reaper.ShowMessageBox('CSV 파일을 생성할 수 없습니다:\n' .. tostring(err), '내보내기 오류', 0)
        return false
    end

    reaper.ShowMessageBox('CSV 내보내기를 완료했습니다.\n\n' .. filename, '내보내기 완료', 0)
    SetStatus('CSV 내보내기 성공')
    return true
end

local function ExportSimpleCSV()
    local filename = BrowseCsvSaveFilename('simple')
    if not filename then
        return
    end

    local lines = {'Keyword,Tags'}
    for _, keyword in ipairs(keywords) do
        lines[#lines + 1] = CsvEscape(keyword.word)
            .. ',' .. CsvEscape(table.concat(keyword.tags or {}, ' | '))
    end

    WriteCsvContent(filename, '\239\187\191' .. table.concat(lines, '\r\n') .. '\r\n')
end

local function ExportFullCSV()
    local filename = BrowseCsvSaveFilename('full')
    if not filename then
        return
    end

    local lines = {
        'RecordType,Keyword,Tags,Favorite,UseCount,LastUsed,CreatedAt,TagName,TagColor'
    }

    for _, tag in ipairs(tags) do
        lines[#lines + 1] = table.concat({
            CsvEscape('TAG'), CsvEscape(''), CsvEscape(''), CsvEscape(''),
            CsvEscape(''), CsvEscape(''), CsvEscape(''), CsvEscape(tag.name),
            CsvEscape(string.format('0x%08X', MakeOpaque(tag.color))),
        }, ',')
    end

    for _, keyword in ipairs(keywords) do
        lines[#lines + 1] = table.concat({
            CsvEscape('KEYWORD'),
            CsvEscape(keyword.word),
            CsvEscape(table.concat(keyword.tags or {}, ' | ')),
            CsvEscape(keyword.favorite and 'true' or 'false'),
            CsvEscape(tostring(tonumber(keyword.use_count) or 0)),
            CsvEscape(tostring(tonumber(keyword.last_used) or 0)),
            CsvEscape(tostring(tonumber(keyword.created_at) or 0)),
            CsvEscape(''),
            CsvEscape(''),
        }, ',')
    end

    WriteCsvContent(filename, '\239\187\191' .. table.concat(lines, '\r\n') .. '\r\n')
end

local function BuildCsvImportPlan(filename)
    local content, read_error = ReadWholeFile(filename)
    if not content then
        return nil, read_error
    end

    content = content:gsub('^\239\187\191', '')
    local lines = {}
    for line in (content .. '\n'):gmatch('(.-)\r?\n') do
        lines[#lines + 1] = line
    end

    local first_data_line = nil
    for index, line in ipairs(lines) do
        if Trim(line) ~= '' then
            first_data_line = index
            break
        end
    end
    if not first_data_line then
        return nil, 'CSV 파일에 불러올 데이터가 없습니다.'
    end

    local first_fields = ParseCsvLine(lines[first_data_line])
    local header_map = BuildCsvHeaderMap(first_fields)
    local is_full = header_map.recordtype ~= nil
    local is_simple = header_map.keyword ~= nil and header_map.tags ~= nil and not is_full
    local has_header = is_full or is_simple
    local start_line = has_header and (first_data_line + 1) or first_data_line

    local plan = {
        filename = filename,
        format_name = is_full and '전체 이전용 CSV' or '간단 편집용 CSV',
        header_status = has_header and '헤더 확인됨' or '헤더 없음 · 첫 행도 데이터로 처리',
        items = {},
        tag_definitions = {},
        tag_definition_order = {},
        duplicate_count = 0,
        error_count = 0,
        errors = {},
        preview_rows = {},
        new_tag_count = 0,
        tag_color_update_count = 0,
    }

    local existing_words = {}
    for _, keyword in ipairs(keywords) do
        existing_words[Lower(CollapseSpaces(keyword.word))] = true
    end
    local pending_words = {}

    local function add_error(line_number, message)
        plan.error_count = plan.error_count + 1
        if #plan.errors < 10 then
            plan.errors[#plan.errors + 1] = string.format('%d행: %s', line_number, message)
        end
    end

    local function add_tag_definition(tag_name, color, explicit_color)
        tag_name = SanitizeStoredText(tag_name)
        if tag_name == '' then
            return nil
        end

        local normalized = Lower(CollapseSpaces(tag_name))
        local existing_tag = FindTagByNormalizedName(normalized)
        if existing_tag then
            if explicit_color then
                plan.tag_definitions[normalized] = {
                    name = existing_tag.name,
                    color = MakeOpaque(color),
                    existing = true,
                    explicit_color = true,
                }
            end
            return existing_tag.name
        end

        local definition = plan.tag_definitions[normalized]
        if not definition then
            definition = {
                name = tag_name,
                color = MakeOpaque(color or 0xFFFFFFFF),
                existing = false,
                explicit_color = explicit_color == true,
            }
            plan.tag_definitions[normalized] = definition
            plan.tag_definition_order[#plan.tag_definition_order + 1] = normalized
        elseif explicit_color then
            definition.color = MakeOpaque(color)
            definition.explicit_color = true
        end
        return definition.name
    end

    local function add_keyword(line_number, word, keyword_tags, favorite, use_count, last_used, created_at)
        word = SanitizeStoredText(word)
        if word == '' then
            add_error(line_number, '검색어가 비어 있습니다.')
            return
        end

        local normalized_word = Lower(CollapseSpaces(word))
        if existing_words[normalized_word] or pending_words[normalized_word] then
            plan.duplicate_count = plan.duplicate_count + 1
            return
        end

        local resolved_tags = {}
        for _, tag_name in ipairs(keyword_tags or {}) do
            local resolved_name = add_tag_definition(tag_name, 0xFFFFFFFF, false)
            if resolved_name then
                resolved_tags[#resolved_tags + 1] = resolved_name
            end
        end

        pending_words[normalized_word] = true
        plan.items[#plan.items + 1] = {
            word = word,
            tags = UniqueArray(resolved_tags),
            favorite = favorite == true,
            use_count = tonumber(use_count) or 0,
            last_used = tonumber(last_used) or 0,
            created_at = tonumber(created_at) or os.time(),
        }
        if #plan.preview_rows < 12 then
            local tag_note = #resolved_tags > 0 and (' · ' .. table.concat(resolved_tags, ', ')) or ''
            plan.preview_rows[#plan.preview_rows + 1] = '+ ' .. word .. tag_note
        end
    end

    for line_number = start_line, #lines do
        local line = lines[line_number]
        if Trim(line) ~= '' then
            local fields = ParseCsvLine(line)
            if is_full then
                local record_type = string.upper(Trim(fields[header_map.recordtype] or ''))
                if record_type == 'TAG' then
                    local tag_name = SanitizeStoredText(fields[header_map.tagname] or '')
                    if tag_name == '' then
                        add_error(line_number, 'TAG 행의 태그 이름이 비어 있습니다.')
                    else
                        add_tag_definition(
                            tag_name,
                            ParseCsvColor(fields[header_map.tagcolor] or ''),
                            true
                        )
                    end
                elseif record_type == 'KEYWORD' then
                    add_keyword(
                        line_number,
                        fields[header_map.keyword] or '',
                        ParseTagText(fields[header_map.tags] or ''),
                        ParseCsvBoolean(fields[header_map.favorite] or ''),
                        ParseCsvInteger(fields[header_map.usecount] or '', 0),
                        ParseCsvInteger(fields[header_map.lastused] or '', 0),
                        ParseCsvInteger(fields[header_map.createdat] or '', os.time())
                    )
                else
                    add_error(line_number, 'RecordType은 TAG 또는 KEYWORD여야 합니다.')
                end
            else
                local keyword_index = is_simple and header_map.keyword or 1
                local tags_index = is_simple and header_map.tags or 2
                add_keyword(
                    line_number,
                    fields[keyword_index] or '',
                    ParseTagText(fields[tags_index] or ''),
                    false,
                    0,
                    0,
                    os.time()
                )
            end
        end
    end

    for normalized, definition in pairs(plan.tag_definitions) do
        local existing_tag = FindTagByNormalizedName(normalized)
        if not existing_tag then
            plan.new_tag_count = plan.new_tag_count + 1
        elseif definition.explicit_color and MakeOpaque(existing_tag.color) ~= MakeOpaque(definition.color) then
            plan.tag_color_update_count = plan.tag_color_update_count + 1
        end
    end

    plan.add_count = #plan.items
    return plan
end

local function ApplyCsvImportPlan(plan)
    if not plan then
        return false
    end

    for _, normalized in ipairs(plan.tag_definition_order or {}) do
        local definition = plan.tag_definitions[normalized]
        if definition and not FindTagByNormalizedName(normalized) then
            tags[#tags + 1] = {
                name = definition.name,
                color = MakeOpaque(definition.color),
            }
        end
    end

    for normalized, definition in pairs(plan.tag_definitions or {}) do
        local existing_tag = FindTagByNormalizedName(normalized)
        if existing_tag and definition.explicit_color then
            existing_tag.color = MakeOpaque(definition.color)
        end
    end

    for _, item in ipairs(plan.items or {}) do
        keywords[#keywords + 1] = {
            id = next_keyword_id,
            word = item.word,
            tags = UniqueArray(CopyArray(item.tags)),
            favorite = item.favorite == true,
            last_used = tonumber(item.last_used) or 0,
            use_count = tonumber(item.use_count) or 0,
            created_at = tonumber(item.created_at) or os.time(),
        }
        next_keyword_id = next_keyword_id + 1
    end

    local saved = SaveData({save_legacy = true, invalidate_tag_cache = true})
    if not saved then
        reaper.ShowMessageBox('CSV 데이터를 저장하지 못했습니다.', '불러오기 오류', 0)
        return false
    end

    reaper.ShowMessageBox(
        string.format(
            'CSV 불러오기를 완료했습니다.\n\n검색어 추가: %d개\n중복 건너뜀: %d개\n오류 제외: %d개\n새 태그: %d개\n태그 색상 변경: %d개',
            plan.add_count or 0,
            plan.duplicate_count or 0,
            plan.error_count or 0,
            plan.new_tag_count or 0,
            plan.tag_color_update_count or 0
        ),
        '불러오기 완료',
        0
    )
    SetStatus('CSV 불러오기 완료')
    return true
end

local function ImportFromCSV()
    local filename = BrowseCsvOpenFilename()
    if not filename then
        return
    end

    local plan, err = BuildCsvImportPlan(filename)
    if not plan then
        reaper.ShowMessageBox(tostring(err), 'CSV 불러오기 오류', 0)
        return
    end

    csv_import_preview = plan
    request_csv_import_preview = true
end

local function RenderCsvImportPreviewPopup()
    if request_csv_import_preview then
        ImGui.OpenPopup(ctx, 'CSV 불러오기 미리보기')
        request_csv_import_preview = false
    end

    if ImGui.BeginPopupModal(ctx, 'CSV 불러오기 미리보기', nil, ImGui.WindowFlags_AlwaysAutoResize) then
        local plan = csv_import_preview
        if not plan then
            ImGui.TextDisabled(ctx, '미리보기 데이터가 없습니다.')
            if ImGui.Button(ctx, '닫기', 90, 26) then
                ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
            return
        end

        ImGui.TextColored(ctx, UI_ACCENT, plan.format_name)
        ImGui.TextDisabled(ctx, plan.header_status)
        ImGui.TextWrapped(ctx, plan.filename)
        ImGui.Separator(ctx)
        ImGui.Text(ctx, string.format('추가 예정 검색어: %d개', plan.add_count or 0))
        ImGui.Text(ctx, string.format('중복 건너뜀: %d개', plan.duplicate_count or 0))
        ImGui.Text(ctx, string.format('오류 제외: %d개', plan.error_count or 0))
        ImGui.Text(ctx, string.format('새 태그: %d개', plan.new_tag_count or 0))
        ImGui.Text(ctx, string.format('태그 색상 변경: %d개', plan.tag_color_update_count or 0))

        ImGui.Spacing(ctx)
        if ImGui.BeginChild(ctx, 'CsvPreviewRows', 560, 220, ImGui.ChildFlags_Border) then
            if #plan.preview_rows == 0 then
                ImGui.TextDisabled(ctx, '추가 가능한 검색어가 없습니다.')
            else
                ImGui.TextDisabled(ctx, '추가 예정 항목 일부')
                for _, row in ipairs(plan.preview_rows) do
                    ImGui.TextWrapped(ctx, row)
                end
                if (plan.add_count or 0) > #plan.preview_rows then
                    ImGui.TextDisabled(ctx, string.format('... 외 %d개', plan.add_count - #plan.preview_rows))
                end
            end

            if #plan.errors > 0 then
                ImGui.Spacing(ctx)
                ImGui.Separator(ctx)
                ImGui.TextColored(ctx, 0xFFB36BFF, '오류 항목')
                for _, message in ipairs(plan.errors) do
                    ImGui.TextWrapped(ctx, message)
                end
                if (plan.error_count or 0) > #plan.errors then
                    ImGui.TextDisabled(ctx, string.format('... 외 %d개 오류', plan.error_count - #plan.errors))
                end
            end
            ImGui.EndChild(ctx)
        end

        local can_apply = (plan.add_count or 0) > 0
            or (plan.new_tag_count or 0) > 0
            or (plan.tag_color_update_count or 0) > 0

        if not can_apply then
            ImGui.BeginDisabled(ctx)
        end
        local apply_clicked = ImGui.Button(ctx, '불러오기 실행', 120, 28)
        if not can_apply then
            ImGui.EndDisabled(ctx)
        end

        ImGui.SameLine(ctx)
        local cancel_clicked = ImGui.Button(ctx, '취소', 90, 28)
        local escape_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)

        if apply_clicked and can_apply then
            if ApplyCsvImportPlan(plan) then
                csv_import_preview = nil
                ImGui.CloseCurrentPopup(ctx)
            end
        elseif cancel_clicked or escape_pressed then
            csv_import_preview = nil
            ImGui.CloseCurrentPopup(ctx)
        end

        ImGui.EndPopup(ctx)
    end
end

local function QuoteShellArgument(value)
    value = tostring(value or '')
    if reaper.GetOS():match('Win') then
        return '"' .. value:gsub('"', '""') .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function OpenBackupDirectory()
    local directory = GetBackupDirectory()
    reaper.RecursiveCreateDirectory(directory, 0)

    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(directory)
        SetStatus('백업 폴더를 열었습니다.')
        return
    end

    local os_name = reaper.GetOS()
    local command
    if os_name:match('Win') then
        command = 'start "" ' .. QuoteShellArgument(directory)
    elseif os_name:match('OSX') or os_name:match('macOS') then
        command = 'open ' .. QuoteShellArgument(directory)
    else
        command = 'xdg-open ' .. QuoteShellArgument(directory) .. ' >/dev/null 2>&1 &'
    end

    local result = os.execute(command)
    if result then
        SetStatus('백업 폴더를 열었습니다.')
    else
        reaper.ShowMessageBox('백업 폴더를 열지 못했습니다.\n\n' .. directory, '폴더 열기 오류', 0)
    end
end

local function DrawBackupTab()
    ImGui.Spacing(ctx)
    DrawSectionTitle('백업 및 데이터 관리', 'JSON 백업/복원 및 CSV 내보내기/불러오기')

    ImGui.TextWrapped(ctx, 'JSON은 전체 데이터를 안전하게 보관·복원합니다. CSV는 용도에 따라 간단 편집용과 전체 이전용으로 나뉩니다.')

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, '현재 데이터 JSON 백업', -1, 34) then BackupToJson() end
    if ImGui.Button(ctx, '백업 파일에서 JSON 복원', -1, 34) then RestoreFromJson() end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.TextColored(ctx, UI_ACCENT_SOFT, 'CSV 내보내기')
    ImGui.TextDisabled(ctx, '간단 CSV: 검색어·태그만 포함 · Excel 편집용')
    ImGui.TextDisabled(ctx, '전체 CSV: 즐겨찾기·사용 기록·생성일·태그 색상 포함 · 이전/보관용')

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x2A5D37FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x367A46FF)
    if ImGui.Button(ctx, '간단 CSV 내보내기 · Excel 편집용', -1, 34) then ExportSimpleCSV() end
    if ImGui.Button(ctx, '전체 CSV 내보내기 · 이전/보관용', -1, 34) then ExportFullCSV() end
    ImGui.PopStyleColor(ctx, 2)

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x3A5D2AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x4B7A36FF)
    if ImGui.Button(ctx, 'CSV 파일 불러오기 · 미리보기 후 적용', -1, 34) then ImportFromCSV() end
    ImGui.PopStyleColor(ctx, 2)

    ImGui.Spacing(ctx)
    if reaper.JS_Dialog_BrowseForSaveFile then
        ImGui.TextColored(ctx, 0x7FD89BFF, 'JS_ReaScriptAPI 설치됨 · CSV 저장 위치를 직접 선택할 수 있습니다.')
    else
        ImGui.TextColored(ctx, 0xFFBE73FF, 'JS_ReaScriptAPI 미설치 · CSV 내보내기는 가능하지만 아래 백업 폴더에 저장됩니다.')
        ImGui.TextWrapped(ctx, '저장 위치 선택 창이 필요하면 ReaPack에서 js_ReaScriptAPI를 설치하세요.')
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, '기본 저장 위치')
    ImGui.TextWrapped(ctx, GetBackupDirectory())
    if ImGui.Button(ctx, '백업 폴더 열기', -1, 30) then
        OpenBackupDirectory()
    end
end

-- -----------------------------------------------------------------------------
-- 메인 루프
-- -----------------------------------------------------------------------------

local function RunFrame()
    FlushScheduledSave(false)

    ImGui.PushFont(ctx, ui_font)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 6, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 4.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 5, 2)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 5, 4)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing, 3, 3)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, 10)

    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x171A1FFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x1D2127FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x252A31FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x303741FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x39424DFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x2B313AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x39424EFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x46515FFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x2D3C4CFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x395067FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x46627DFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Separator, 0x343A43FF)

    ImGui.SetNextWindowSize(ctx, 590, 680, ImGui.Cond_Once)
    local visible, open = ImGui.Begin(ctx, APP_NAME, true)
    if visible then
        DrawStatus()
        DrawUndoDelete()
        if ImGui.BeginTabBar(ctx, 'MainTabs') then
            if ImGui.BeginTabItem(ctx, '검색 · 목록') then DrawSearchTab(); ImGui.EndTabItem(ctx) end
            if ImGui.BeginTabItem(ctx, '추가 · 태그 관리') then DrawAddAndManageTab(); ImGui.EndTabItem(ctx) end
            if ImGui.BeginTabItem(ctx, '백업 · 복원') then DrawBackupTab(); ImGui.EndTabItem(ctx) end
            ImGui.EndTabBar(ctx)
        end
        RenderKeywordEditorPopup()
        RenderTagEditorPopup()
        RenderCsvImportPreviewPopup()
    end

    ImGui.End(ctx)
    ImGui.PopStyleColor(ctx, 12)
    ImGui.PopStyleVar(ctx, 8)
    ImGui.PopFont(ctx)
    return open ~= false
end

local function loop()
    local ok, should_continue = xpcall(RunFrame, debug.traceback)
    if not ok then
        pcall(FlushScheduledSave, true)

        local recovery_note = ''
        local backup_call_ok, backup_ok, backup_filename = pcall(function()
            local saved, filename = BackupToJson({
                silent = true,
                prefix = 'error_recovery_backup',
            })
            return saved, filename
        end)

        if backup_call_ok and backup_ok and backup_filename then
            recovery_note = '\n\n오류 발생 시점의 데이터 백업:\n' .. tostring(backup_filename)
        end

        reaper.ShowMessageBox(
            '스크립트 실행 중 오류가 발생해 안전하게 종료합니다.\n'
                .. '기존 저장 데이터는 유지됩니다.'
                .. recovery_note
                .. '\n\n오류 내용:\n'
                .. tostring(should_continue),
            '사운드 라이브러리 매니저 오류',
            0
        )
        return
    end

    if should_continue then
        reaper.defer(loop)
    else
        FlushScheduledSave(true)
    end
end

reaper.atexit(function()
    pcall(FlushScheduledSave, true)
end)

reaper.defer(loop)
