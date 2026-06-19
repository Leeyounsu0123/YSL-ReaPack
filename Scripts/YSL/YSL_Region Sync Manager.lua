-- @description Region Sync Manager - CSV collaboration editor
-- @version 1.0.0
-- @author Yoon-Soo Lee
-- @about
--   Safe region CSV import/export, preview, UID-based diff/merge,
--   staged editing, project metadata, reports, bilingual UI and bulk tools.
--   Required: ReaImGui (installable from the default ReaTeam Extensions repository).
--   Optional: js_ReaScriptAPI for native file dialogs.
--   REAPER 7.62 or newer is recommended for native per-region hidden-state support.
-- @changelog
--   + Initial release package for GitHub and ReaPack distribution
--   + Fixed ReaImGui BeginChild/EndChild compatibility and bulk rename popup crashes
-- @provides
--   [main] .
--
-- Copyright (C) 2026 Yoon-Soo Lee. All rights reserved.
-- See LICENSE.md in the distribution repository for permitted use.

local APP_NAME = "Region Sync Manager"
local APP_VERSION = "1.0.0"
local EXT_SECTION = "REGION_SYNC_MANAGER"
local PROJECT_SECTION = "REGION_SYNC_MANAGER_V2"
local SCHEMA_VERSION = "1"
local EPSILON = 0.0005

-- -----------------------------------------------------------------------------
-- Dependency check
-- -----------------------------------------------------------------------------
if not reaper or not reaper.ImGui_CreateContext then
  if reaper and reaper.MB then
    reaper.MB(
      "ReaImGui is required.\n\nInstall it with ReaPack:\nExtensions > ReaPack > Browse packages > ReaImGui",
      APP_NAME .. " - Missing dependency",
      0
    )
  end
  return
end

local has_js = reaper.JS_Dialog_BrowseForSaveFile ~= nil
local has_modern_region_api =
  reaper.GetNumRegionsOrMarkers ~= nil and
  reaper.GetRegionOrMarker ~= nil and
  reaper.GetRegionOrMarkerInfo_Value ~= nil and
  reaper.SetRegionOrMarkerInfo_Value ~= nil and
  reaper.GetSetRegionOrMarkerInfo_String ~= nil

local function parse_reaper_version()
  local text = tostring(reaper.GetAppVersion and reaper.GetAppVersion() or "0.0")
  local major, minor = text:match("^(%d+)%.(%d+)")
  return tonumber(major) or 0, tonumber(minor) or 0, text
end

local REAPER_MAJOR, REAPER_MINOR, REAPER_VERSION_TEXT = parse_reaper_version()
-- Native per-region B_HIDDEN writing is only available in REAPER 7.62+.
local has_native_region_hidden = has_modern_region_api and
  (REAPER_MAJOR > 7 or (REAPER_MAJOR == 7 and REAPER_MINOR >= 62))
-- Older REAPER versions use a reversible compatibility mode:
-- hiding removes the live region but stores every field in project ExtState.
local has_legacy_region_hidden =
  not has_native_region_hidden and reaper.AddProjectMarker2 ~= nil and reaper.DeleteProjectMarker ~= nil

local ctx = reaper.ImGui_CreateContext(APP_NAME)

-- ReaImGui changed BeginChild's fifth argument from a boolean border flag to
-- ChildFlags. Support both old and new ReaImGui builds without crashing.
local function imgui_begin_child(id, width, height, border, window_flags)
  local child_flags_fn = reaper.ImGui_ChildFlags_Borders or reaper.ImGui_ChildFlags_Border
  if child_flags_fn then
    return reaper.ImGui_BeginChild(
      ctx, id, width, height, border and child_flags_fn() or 0, window_flags or 0)
  end
  return reaper.ImGui_BeginChild(ctx, id, width, height, border and true or false, window_flags or 0)
end

-- -----------------------------------------------------------------------------
-- Localization
-- -----------------------------------------------------------------------------
local STRINGS = {
  en = {
    refresh = "Refresh",
    create_items = "Create from Items",
    import_csv = "Import CSV",
    export_csv = "Export CSV",
    apply_changes = "Apply Changes",
    discard_changes = "Discard Changes",
    bulk_rename = "Bulk Rename",
    settings = "Settings",
    help = "Help",
    regions = "Regions",
    import_preview = "Import Preview",
    report = "Change Report",
    search = "Search",
    status_filter = "Status",
    sort_by = "Sort",
    ascending = "Ascending",
    select_all = "Select all",
    selected = "Selected",
    status = "Status",
    id = "ID",
    enabled = "Enabled",
    hidden = "Hidden",
    hidden_failed = "Could not change the region hidden state.",
    number_format = "Number format",
    sequence_hint = "The end number follows the number of target rows automatically.",
    reset_01 = "Start at 01",
    name = "Name",
    start = "Start",
    finish = "End",
    length = "Length",
    owner = "Owner",
    note = "Note",
    delete = "Delete",
    go = "Go",
    dirty_banner = "There are unapplied edits.",
    external_banner = "The REAPER timeline changed outside this window.",
    reload = "Reload timeline",
    keep_edits = "Keep edits",
    no_regions = "No regions found.",
    page = "Page",
    of = "of",
    rows = "rows",
    import_mode = "Import mode",
    mode_name = "Names only",
    mode_merge = "Merge",
    mode_replace = "Replace all",
    choose_file = "Choose CSV",
    apply_selected = "Apply selected changes",
    select_valid = "Select valid",
    select_none = "Select none",
    source_file = "Source",
    project_mismatch = "CSV ProjectID differs from the current project.",
    validation_errors = "CSV contains validation errors. Invalid rows cannot be applied.",
    no_preview = "Choose a CSV file to create a diff preview.",
    current = "Current",
    incoming = "Incoming",
    action = "Action",
    issue = "Issue",
    valid = "Valid",
    added = "Added",
    modified = "Modified",
    unchanged = "Unchanged",
    conflict = "Conflict",
    deleted = "Delete candidate",
    invalid = "Invalid",
    timestamp = "Time",
    details = "Details",
    export_report = "Export report",
    clear_report = "Clear report",
    language = "Language",
    author = "Default owner",
    auto_refresh = "Auto-detect external timeline changes",
    utf8_bom = "Write UTF-8 BOM for Excel",
    page_size = "Rows per page",
    recent_files = "Recent files",
    clear_recent = "Clear recent files",
    dependency = "Dependency status",
    modern_api = "Modern region API",
    js_api = "js_ReaScriptAPI save dialog",
    installed = "Installed",
    missing_optional = "Not installed (optional)",
    save = "Save",
    close = "Close",
    cancel = "Cancel",
    export_example = "Export example CSV",
    about = "About",
    keyboard = "Keyboard shortcuts",
    shortcut_text = "Ctrl+S Apply edits  |  Ctrl+R Refresh  |  Ctrl+F Search  |  Delete Mark selected for deletion",
    help_text = "CSV workflow: export regions, edit collaboratively, import the CSV, review the diff, select actions, then apply. Replace mode can delete regions missing from the CSV, so a backup CSV is created before applying.",
    save_failed = "Could not save the file.",
    saved = "Saved",
    loaded = "Loaded",
    apply_failed = "Some operations failed. Review the Change Report.",
    apply_complete = "Changes applied.",
    confirm_replace = "Replace mode may delete current regions that are absent from the CSV. Continue?",
    invalid_time = "Invalid time",
    end_after_start = "End must be greater than Start",
    duplicate_uid = "Duplicate RegionUID",
    duplicate_number = "Duplicate RegionNumber",
    missing_required = "Missing required column",
    formula_warning = "Name begins with a spreadsheet formula character",
    rename_target = "Target",
    target_selected = "Selected rows",
    target_filtered = "Filtered rows",
    preset = "Preset",
    prefix = "Add prefix",
    suffix = "Add suffix",
    find_replace = "Find / Replace",
    sequential = "Sequential numbering",
    uppercase = "UPPERCASE",
    lowercase = "lowercase",
    spaces_underscore = "Spaces to underscores",
    template = "Template",
    value = "Value",
    find = "Find",
    replace = "Replace",
    digits = "Digits",
    start_number = "Start number",
    preview = "Preview",
    stage_rename = "Stage rename",
    nothing_selected = "No target rows.",
    project_id = "Project ID",
    csv_schema = "CSV Schema",
    pending = "Pending",
    count_summary = "Total %d · Selected %d · Modified %d · Errors %d",
    backup_created = "Backup CSV created",
    file_error = "File error",
    warning = "Warning",
    info = "Info",
    old_csv = "Legacy CSV detected and converted to Schema v2 in memory.",
    export_only_enabled = "Export enabled regions only",
    time_format = "Time display",
    time_project = "Project format",
    time_clock = "HH:MM:SS.mmm",
    time_seconds = "Seconds",
  },
  ko = {
    refresh = "새로고침",
    create_items = "선택 아이템으로 생성",
    import_csv = "CSV 가져오기",
    export_csv = "CSV 내보내기",
    apply_changes = "변경사항 적용",
    discard_changes = "변경 취소",
    bulk_rename = "일괄 이름 변경",
    settings = "설정",
    help = "도움말",
    regions = "리전",
    import_preview = "가져오기 미리보기",
    report = "변경 내역",
    search = "검색",
    status_filter = "상태",
    sort_by = "정렬",
    ascending = "오름차순",
    select_all = "전체 선택",
    selected = "선택",
    status = "상태",
    id = "번호",
    enabled = "사용",
    hidden = "숨김",
    hidden_failed = "리전 숨김 상태를 변경하지 못했습니다.",
    number_format = "번호 형식",
    sequence_hint = "끝 번호는 대상 행 개수에 맞춰 자동으로 정해집니다.",
    reset_01 = "01부터 시작",
    name = "이름",
    start = "시작",
    finish = "종료",
    length = "길이",
    owner = "담당자",
    note = "메모",
    delete = "삭제",
    go = "이동",
    dirty_banner = "아직 적용하지 않은 편집 내용이 있습니다.",
    external_banner = "이 창 밖에서 REAPER 타임라인이 변경되었습니다.",
    reload = "타임라인 다시 불러오기",
    keep_edits = "편집 유지",
    no_regions = "리전이 없습니다.",
    page = "페이지",
    of = "/",
    rows = "행",
    import_mode = "가져오기 방식",
    mode_name = "이름만 수정",
    mode_merge = "병합",
    mode_replace = "전체 교체",
    choose_file = "CSV 선택",
    apply_selected = "선택 변경 적용",
    select_valid = "유효 항목 선택",
    select_none = "선택 해제",
    source_file = "원본 파일",
    project_mismatch = "CSV ProjectID가 현재 프로젝트와 다릅니다.",
    validation_errors = "CSV에 오류가 있습니다. 잘못된 행은 적용할 수 없습니다.",
    no_preview = "CSV 파일을 선택하면 차이 미리보기가 생성됩니다.",
    current = "현재",
    incoming = "가져올 값",
    action = "작업",
    issue = "문제",
    valid = "정상",
    added = "추가",
    modified = "수정",
    unchanged = "동일",
    conflict = "충돌",
    deleted = "삭제 후보",
    invalid = "오류",
    timestamp = "시간",
    details = "상세 내용",
    export_report = "리포트 내보내기",
    clear_report = "리포트 지우기",
    language = "언어",
    author = "기본 담당자",
    auto_refresh = "외부 타임라인 변경 감지",
    utf8_bom = "Excel용 UTF-8 BOM 저장",
    page_size = "페이지당 행 수",
    recent_files = "최근 파일",
    clear_recent = "최근 파일 지우기",
    dependency = "의존성 상태",
    modern_api = "최신 리전 API",
    js_api = "js_ReaScriptAPI 저장 창",
    installed = "설치됨",
    missing_optional = "미설치 · 선택 사항",
    save = "저장",
    close = "닫기",
    cancel = "취소",
    export_example = "예제 CSV 내보내기",
    about = "정보",
    keyboard = "키보드 단축키",
    shortcut_text = "Ctrl+S 변경 적용  |  Ctrl+R 새로고침  |  Ctrl+F 검색  |  Delete 선택 행 삭제 표시",
    help_text = "CSV를 내보내 협업 편집한 뒤 다시 가져오고, 차이 미리보기에서 작업을 선택한 다음 적용합니다. 전체 교체는 CSV에 없는 현재 리전을 삭제할 수 있어 적용 전에 자동 백업 CSV를 생성합니다.",
    save_failed = "파일을 저장하지 못했습니다.",
    saved = "저장 완료",
    loaded = "불러오기 완료",
    apply_failed = "일부 작업에 실패했습니다. 변경 내역을 확인하세요.",
    apply_complete = "변경사항을 적용했습니다.",
    confirm_replace = "전체 교체는 CSV에 없는 현재 리전을 삭제할 수 있습니다. 계속할까요?",
    invalid_time = "잘못된 시간값",
    end_after_start = "종료 시간은 시작 시간보다 커야 합니다",
    duplicate_uid = "RegionUID 중복",
    duplicate_number = "RegionNumber 중복",
    missing_required = "필수 열이 없습니다",
    formula_warning = "이름이 스프레드시트 수식 문자로 시작합니다",
    rename_target = "적용 대상",
    target_selected = "선택한 행",
    target_filtered = "필터 결과",
    preset = "프리셋",
    prefix = "접두사 추가",
    suffix = "접미사 추가",
    find_replace = "찾기 / 바꾸기",
    sequential = "순번 붙이기",
    uppercase = "대문자로",
    lowercase = "소문자로",
    spaces_underscore = "공백을 밑줄로",
    template = "템플릿",
    value = "값",
    find = "찾기",
    replace = "바꾸기",
    digits = "자릿수",
    start_number = "시작 번호",
    preview = "미리보기",
    stage_rename = "이름 변경 임시 적용",
    nothing_selected = "적용할 행이 없습니다.",
    project_id = "프로젝트 ID",
    csv_schema = "CSV 스키마",
    pending = "미적용",
    count_summary = "전체 %d · 선택 %d · 수정 %d · 오류 %d",
    backup_created = "백업 CSV 생성",
    file_error = "파일 오류",
    warning = "경고",
    info = "정보",
    old_csv = "구형 CSV를 감지하여 메모리에서 Schema v2로 변환했습니다.",
    export_only_enabled = "사용 리전만 내보내기",
    time_format = "시간 표시",
    time_project = "프로젝트 형식",
    time_clock = "시:분:초.밀리초",
    time_seconds = "초",
  }
}

local settings = {
  language = "ko",
  author = "",
  auto_refresh = true,
  utf8_bom = true,
  page_size = 200,
  recent_files = {},
  last_csv_path = "",
  export_only_enabled = false,
  time_format = "clock",
}

local function T(key)
  local lang = STRINGS[settings.language] or STRINGS.en
  return lang[key] or STRINGS.en[key] or key
end

-- -----------------------------------------------------------------------------
-- Utility
-- -----------------------------------------------------------------------------
local function trim(s)
  return tostring(s or ""):match("^%s*(.-)%s*$") or ""
end

local function bool_from_string(v, default)
  if type(v) == "boolean" then return v end
  local s = trim(v):lower()
  if s == "true" or s == "1" or s == "yes" or s == "y" then return true end
  if s == "false" or s == "0" or s == "no" or s == "n" then return false end
  return default
end

local function shallow_copy(t)
  local n = {}
  for k, v in pairs(t or {}) do n[k] = v end
  return n
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function now_iso()
  return os.date("%Y-%m-%dT%H:%M:%S")
end

local function path_dir(path)
  return (path or ""):match("^(.*[\\/])") or ""
end

local function basename(path)
  return (path or ""):match("([^\\/]+)$") or path or ""
end

local function ensure_csv_extension(path)
  if not path:lower():match("%.csv$") then return path .. ".csv" end
  return path
end

local function generate_uid()
  if reaper.genGuid then
    local guid = reaper.genGuid("")
    if guid and guid ~= "" then return guid end
  end
  math.randomseed(os.time() + math.floor(reaper.time_precise() * 100000))
  return string.format("{%08x-%04x-%04x-%04x-%012x}",
    math.random(0, 0x7fffffff), math.random(0, 0xffff), math.random(0, 0xffff),
    math.random(0, 0xffff), math.random(0, 0x7fffffff))
end

local function key_from_guid(guid)
  return "REGION_" .. tostring(guid or ""):gsub("[^%w]", "")
end

local function url_encode(s)
  return tostring(s or ""):gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function url_decode(s)
  return tostring(s or ""):gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
end

local function serialize_meta(m)
  return table.concat({
    "uid=" .. url_encode(m.uid or ""),
    "owner=" .. url_encode(m.owner or ""),
    "note=" .. url_encode(m.note or ""),
    "updated_at=" .. url_encode(m.updated_at or ""),
    "enabled=" .. (m.enabled == false and "false" or "true")
  }, "\n")
end

local function deserialize_meta(s)
  local m = {}
  for line in tostring(s or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k then m[k] = url_decode(v) end
  end
  m.enabled = bool_from_string(m.enabled, true)
  return m
end

local function add_recent_file(path)
  if not path or path == "" then return end
  local next_list = {path}
  for _, p in ipairs(settings.recent_files) do
    if p ~= path and #next_list < 8 then table.insert(next_list, p) end
  end
  settings.recent_files = next_list
end

local function split_pipe(s)
  local out = {}
  for item in tostring(s or ""):gmatch("[^|]+") do
    -- string.gsub returns two values; keep only the decoded string.
    local decoded = url_decode(item)
    table.insert(out, decoded)
  end
  return out
end

local function join_pipe(t)
  local out = {}
  for _, item in ipairs(t or {}) do
    -- string.gsub returns both the encoded string and replacement count.
    -- Store only the first value so table.insert does not treat the string as
    -- a numeric position when recent files are saved after CSV export.
    local encoded = url_encode(item)
    table.insert(out, encoded)
  end
  return table.concat(out, "|")
end

local function load_settings()
  local function get(key, default)
    local v = reaper.GetExtState(EXT_SECTION, key)
    if v == "" then return default end
    return v
  end
  settings.language = get("language", settings.language)
  settings.author = get("author", settings.author)
  settings.auto_refresh = bool_from_string(get("auto_refresh", "true"), true)
  settings.utf8_bom = bool_from_string(get("utf8_bom", "true"), true)
  settings.page_size = clamp(tonumber(get("page_size", tostring(settings.page_size))) or 200, 25, 1000)
  settings.last_csv_path = get("last_csv_path", "")
  settings.recent_files = split_pipe(get("recent_files", ""))
  settings.export_only_enabled = bool_from_string(get("export_only_enabled", "false"), false)
  settings.time_format = get("time_format", "clock")
end

local function save_settings()
  reaper.SetExtState(EXT_SECTION, "language", settings.language, true)
  reaper.SetExtState(EXT_SECTION, "author", settings.author, true)
  reaper.SetExtState(EXT_SECTION, "auto_refresh", tostring(settings.auto_refresh), true)
  reaper.SetExtState(EXT_SECTION, "utf8_bom", tostring(settings.utf8_bom), true)
  reaper.SetExtState(EXT_SECTION, "page_size", tostring(settings.page_size), true)
  reaper.SetExtState(EXT_SECTION, "last_csv_path", settings.last_csv_path or "", true)
  reaper.SetExtState(EXT_SECTION, "recent_files", join_pipe(settings.recent_files), true)
  reaper.SetExtState(EXT_SECTION, "export_only_enabled", tostring(settings.export_only_enabled), true)
  reaper.SetExtState(EXT_SECTION, "time_format", settings.time_format, true)
end

load_settings()

-- -----------------------------------------------------------------------------
-- Time handling
-- -----------------------------------------------------------------------------
local function format_clock(sec)
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec - h * 3600) / 60)
  local s = sec - h * 3600 - m * 60
  return string.format("%02d:%02d:%06.3f", h, m, s)
end

local function format_time(sec)
  sec = tonumber(sec) or 0
  if settings.time_format == "seconds" then
    return string.format("%.6f", sec)
  elseif settings.time_format == "project" and reaper.format_timestr_pos then
    return reaper.format_timestr_pos(sec, "", -1)
  end
  return format_clock(sec)
end

local function parse_time_strict(value)
  if type(value) == "number" then
    if value >= 0 then return value, nil end
    return nil, T("invalid_time")
  end
  local s = trim(value):gsub('^"(.*)"$', '%1')
  if s == "" then return nil, T("invalid_time") end

  local n = tonumber(s)
  if n and n >= 0 then return n, nil end

  local h, m, sec = s:match("^(%d+):(%d+):([%d%.]+)$")
  if h and m and sec then
    h, m, sec = tonumber(h), tonumber(m), tonumber(sec)
    if m < 60 and sec < 60 then return h * 3600 + m * 60 + sec, nil end
  end

  local mm, ss = s:match("^(%d+):([%d%.]+)$")
  if mm and ss then
    mm, ss = tonumber(mm), tonumber(ss)
    if ss < 60 then return mm * 60 + ss, nil end
  end

  if reaper.parse_timestr_pos then
    local parsed = reaper.parse_timestr_pos(s, -1)
    if parsed and parsed >= 0 then
      -- parse_timestr_pos returns 0 both for valid zero and some invalid strings.
      if parsed > 0 or s:match("^0+([%:%.]0+)*$") then return parsed, nil end
    end
  end
  return nil, T("invalid_time")
end

-- -----------------------------------------------------------------------------
-- CSV codec (RFC 4180-style, multiline quoted fields supported)
-- -----------------------------------------------------------------------------
local function csv_escape(v)
  local s = tostring(v == nil and "" or v)
  if s:find('[,\r\n"]') then
    s = '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

local function parse_csv_document(text)
  text = tostring(text or ""):gsub("^\239\187\191", "")
  local rows, row, field = {}, {}, {}
  local in_quotes = false
  local i, len = 1, #text

  local function push_field()
    table.insert(row, table.concat(field))
    field = {}
  end
  local function push_row()
    push_field()
    local nonempty = false
    for _, v in ipairs(row) do if v ~= "" then nonempty = true break end end
    if nonempty then table.insert(rows, row) end
    row = {}
  end

  while i <= len do
    local c = text:sub(i, i)
    if in_quotes then
      if c == '"' then
        if text:sub(i + 1, i + 1) == '"' then
          table.insert(field, '"')
          i = i + 1
        else
          in_quotes = false
        end
      else
        table.insert(field, c)
      end
    else
      if c == '"' and #field == 0 then
        in_quotes = true
      elseif c == ',' then
        push_field()
      elseif c == '\n' then
        push_row()
      elseif c == '\r' then
        if text:sub(i + 1, i + 1) == '\n' then i = i + 1 end
        push_row()
      else
        table.insert(field, c)
      end
    end
    i = i + 1
  end
  if in_quotes then return nil, "Unclosed quoted CSV field" end
  if #field > 0 or #row > 0 then push_row() end
  return rows, nil
end

local CSV_HEADERS = {
  "SchemaVersion", "ProjectID", "RegionUID", "RegionNumber", "Name",
  "StartSec", "EndSec", "Enabled", "Hidden", "Color", "Status",
  "Note", "UpdatedBy", "UpdatedAt"
}

local function read_all(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local ok, data = pcall(function() return f:read("*a") end)
  f:close()
  if not ok then return nil, data end
  return data, nil
end

local function atomic_write(path, content)
  local temp = path .. ".tmp"
  local f, err = io.open(temp, "wb")
  if not f then return false, err end
  local ok, write_err = pcall(function() f:write(content) end)
  f:close()
  if not ok then os.remove(temp); return false, write_err end

  local old_backup = path .. ".bak"
  os.remove(old_backup)
  local existing = io.open(path, "rb")
  if existing then
    existing:close()
    os.rename(path, old_backup)
  end
  local renamed, rename_err = os.rename(temp, path)
  if not renamed then
    if io.open(old_backup, "rb") then os.rename(old_backup, path) end
    os.remove(temp)
    return false, rename_err
  end
  return true, nil
end

-- -----------------------------------------------------------------------------
-- Project metadata
-- -----------------------------------------------------------------------------
local function get_project_uid()
  local ok, uid = reaper.GetProjExtState(0, PROJECT_SECTION, "PROJECT_UID")
  if ok == 0 or uid == "" then
    uid = generate_uid()
    reaper.SetProjExtState(0, PROJECT_SECTION, "PROJECT_UID", uid)
  end
  return uid
end

local function load_region_meta(guid)
  if not guid or guid == "" then return {} end
  local ok, value = reaper.GetProjExtState(0, PROJECT_SECTION, key_from_guid(guid))
  if ok == 0 or value == "" then return {} end
  return deserialize_meta(value)
end

local function save_region_meta(guid, meta)
  if not guid or guid == "" then return end
  reaper.SetProjExtState(0, PROJECT_SECTION, key_from_guid(guid), serialize_meta(meta))
end

local function delete_region_meta(guid)
  if guid and guid ~= "" then
    reaper.SetProjExtState(0, PROJECT_SECTION, key_from_guid(guid), "")
  end
end

local SOFT_HIDDEN_KEY = "SOFT_HIDDEN_ROWS_V1"

local function serialize_soft_hidden_row(row)
  local values = {
    row.uid or "",
    tostring(math.floor(tonumber(row.number) or -1)),
    string.format("%.9f", tonumber(row.start_sec) or 0),
    string.format("%.9f", tonumber(row.end_sec) or 0),
    row.enabled == false and "false" or "true",
    tostring(math.floor(tonumber(row.color) or 0)),
    row.name or "",
    row.owner or "",
    row.note or "",
    row.updated_at or "",
    row.guid or "",
  }
  for i, value in ipairs(values) do values[i] = url_encode(value) end
  return table.concat(values, "|")
end

local function deserialize_soft_hidden_row(line)
  local values = {}
  for value in (tostring(line or "") .. "|"):gmatch("(.-)|") do
    values[#values + 1] = url_decode(value)
  end
  if #values < 10 or values[1] == "" then return nil end
  local start_sec, end_sec = tonumber(values[3]), tonumber(values[4])
  if not start_sec or not end_sec or end_sec <= start_sec then return nil end
  return {
    uid = values[1],
    number = tonumber(values[2]) or -1,
    start_sec = start_sec,
    end_sec = end_sec,
    enabled = bool_from_string(values[5], true),
    color = tonumber(values[6]) or 0,
    name = values[7] or "",
    owner = values[8] or "",
    note = values[9] or "",
    updated_at = values[10] or "",
    guid = values[11] or "",
    hidden = true,
    soft_hidden = true,
  }
end

local function load_soft_hidden_records()
  local ok, value = reaper.GetProjExtState(0, PROJECT_SECTION, SOFT_HIDDEN_KEY)
  if ok == 0 or value == "" then return {} end
  local records = {}
  for line in tostring(value):gmatch("[^\r\n]+") do
    local record = deserialize_soft_hidden_row(line)
    if record then records[#records + 1] = record end
  end
  return records
end

local function save_soft_hidden_records(records)
  local lines = {}
  table.sort(records, function(a, b)
    local an, bn = tonumber(a.number) or -1, tonumber(b.number) or -1
    if an == bn then return tostring(a.uid or "") < tostring(b.uid or "") end
    return an < bn
  end)
  for _, record in ipairs(records) do
    lines[#lines + 1] = serialize_soft_hidden_row(record)
  end
  reaper.SetProjExtState(0, PROJECT_SECTION, SOFT_HIDDEN_KEY, table.concat(lines, "\n"))
end

local function upsert_soft_hidden_record(row)
  local records = load_soft_hidden_records()
  local replaced = false
  for i, record in ipairs(records) do
    if record.uid == row.uid then
      records[i] = {
        uid = row.uid,
        number = row.number,
        start_sec = row.start_sec,
        end_sec = row.end_sec,
        enabled = row.enabled,
        color = row.color,
        name = row.name,
        owner = row.owner,
        note = row.note,
        updated_at = row.updated_at,
        guid = row.guid,
        hidden = true,
        soft_hidden = true,
      }
      replaced = true
      break
    end
  end
  if not replaced then
    records[#records + 1] = {
      uid = row.uid,
      number = row.number,
      start_sec = row.start_sec,
      end_sec = row.end_sec,
      enabled = row.enabled,
      color = row.color,
      name = row.name,
      owner = row.owner,
      note = row.note,
      updated_at = row.updated_at,
      guid = row.guid,
      hidden = true,
      soft_hidden = true,
    }
  end
  save_soft_hidden_records(records)
end

local function remove_soft_hidden_record(uid)
  local records = load_soft_hidden_records()
  local kept, removed = {}, false
  for _, record in ipairs(records) do
    if record.uid == uid then
      removed = true
    else
      kept[#kept + 1] = record
    end
  end
  if removed then save_soft_hidden_records(kept) end
  return removed
end

local project_uid = get_project_uid()

-- -----------------------------------------------------------------------------
-- Application state
-- -----------------------------------------------------------------------------
local state = {
  rows = {},
  filtered = {},
  filter_dirty = true,
  search = "",
  status_filter = "all",
  sort_by = "number",
  ascending = true,
  page = 1,
  selected_count = 0,
  dirty_count = 0,
  error_count = 0,
  last_project_change = reaper.GetProjectStateChangeCount(0),
  external_change = false,
  suppress_change_check_until = 0,
  active_tab = "regions",
  import = {
    path = "",
    mode = "merge",
    rows = {},
    diffs = {},
    issues = {},
    project_id = "",
    schema_version = "",
    legacy = false,
    project_mismatch = false,
  },
  report = {},
  message = "",
  message_kind = "info",
  focus_search = false,
  open_settings = false,
  open_help = false,
  open_bulk = false,
  open_import = false,
  open_about = false,
}

local function add_report(action, details, result)
  table.insert(state.report, 1, {
    time = now_iso(), action = action or "", details = details or "", result = result or "OK"
  })
end

local function set_message(text, kind)
  state.message = text or ""
  state.message_kind = kind or "info"
end

-- -----------------------------------------------------------------------------
-- Region API
-- -----------------------------------------------------------------------------
local function get_region_guid(pm, internal_index)
  if has_modern_region_api and pm then
    local ok, guid = reaper.GetSetRegionOrMarkerInfo_String(0, pm, "GUID", "", false)
    if ok and guid and guid ~= "" then return guid end
  end
  if reaper.GetSetProjectInfo_String and internal_index ~= nil then
    local ok, guid = reaper.GetSetProjectInfo_String(0, "MARKER_GUID:" .. tostring(internal_index), "", false)
    if ok and guid and guid ~= "" then return guid end
  end
  return ""
end

local function build_row(fields)
  local meta = fields.meta or {}
  local row = {
    pm = fields.pm,
    internal_index = fields.internal_index,
    guid = fields.guid or "",
    uid = meta.uid and meta.uid ~= "" and meta.uid or generate_uid(),
    number = tonumber(fields.number) or 0,
    name = fields.name or "",
    start_sec = tonumber(fields.start_sec) or 0,
    end_sec = tonumber(fields.end_sec) or 0,
    start_text = format_time(fields.start_sec),
    end_text = format_time(fields.end_sec),
    enabled = meta.enabled ~= false,
    hidden = fields.hidden == true,
    color = tonumber(fields.color) or 0,
    owner = meta.owner or "",
    note = meta.note or "",
    updated_at = meta.updated_at or "",
    soft_hidden = fields.soft_hidden == true,
    selected = false,
    pending_delete = false,
    dirty = false,
    status = "unchanged",
    errors = {},
  }
  row.original = {
    number = row.number, name = row.name, start_sec = row.start_sec, end_sec = row.end_sec,
    start_text = row.start_text, end_text = row.end_text, enabled = row.enabled,
    hidden = row.hidden, color = row.color, owner = row.owner, note = row.note,
    updated_at = row.updated_at
  }
  return row
end

local function save_row_meta(row)
  if row.soft_hidden then
    upsert_soft_hidden_record(row)
    return
  end
  save_region_meta(row.guid, {
    uid = row.uid,
    owner = row.owner,
    note = row.note,
    updated_at = row.updated_at,
    enabled = row.enabled,
  })
end

local function enumerate_regions()
  local rows = {}
  if has_modern_region_api then
    local count = reaper.GetNumRegionsOrMarkers(0)
    for i = 0, count - 1 do
      local pm = reaper.GetRegionOrMarker(0, i, "")
      if pm then
        local is_region = reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_ISREGION") > 0.5
        if is_region then
          local number = reaper.GetRegionOrMarkerInfo_Value(0, pm, "I_NUMBER")
          local start_sec = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS")
          local end_sec = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS")
          local color = reaper.GetRegionOrMarkerInfo_Value(0, pm, "I_CUSTOMCOLOR")
          local hidden = has_native_region_hidden and
            (reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_HIDDEN") > 0.5) or false
          local _, name = reaper.GetSetRegionOrMarkerInfo_String(0, pm, "P_NAME", "", false)
          local guid = get_region_guid(pm, i)
          if guid == "" then guid = "LEGACY_R" .. tostring(math.floor(number)) end
          local meta = load_region_meta(guid)
          local row = build_row({
            pm = pm, internal_index = i, guid = guid, number = number,
            name = name, start_sec = start_sec, end_sec = end_sec,
            hidden = hidden, color = color, meta = meta
          })
          save_row_meta(row)
          table.insert(rows, row)
        end
      end
    end
  else
    local _, markers, regions = reaper.CountProjectMarkers(0)
    for i = 0, markers + regions - 1 do
      local retval, isrgn, pos, rgnend, name, number, color = reaper.EnumProjectMarkers3(0, i)
      if retval > 0 and isrgn then
        local guid = get_region_guid(nil, i)
        if guid == "" then guid = "LEGACY_R" .. tostring(number) end
        local meta = load_region_meta(guid)
        local row = build_row({
          internal_index = i, guid = guid, number = number, name = name,
          start_sec = pos, end_sec = rgnend, hidden = false, color = color, meta = meta
        })
        save_row_meta(row)
        table.insert(rows, row)
      end
    end
  end
  -- regions in project ExtState and merge them into the manager's list.
  local actual_uids = {}
  for _, row in ipairs(rows) do actual_uids[row.uid] = true end
  local soft_records = load_soft_hidden_records()
  local kept_soft = {}
  for _, record in ipairs(soft_records) do
    if not actual_uids[record.uid] then
      kept_soft[#kept_soft + 1] = record
      local guid = record.guid ~= "" and record.guid or ("SOFT_" .. tostring(record.uid))
      local row = build_row({
        guid = guid,
        number = record.number,
        name = record.name,
        start_sec = record.start_sec,
        end_sec = record.end_sec,
        hidden = true,
        color = record.color,
        soft_hidden = true,
        meta = {
          uid = record.uid,
          owner = record.owner,
          note = record.note,
          updated_at = record.updated_at,
          enabled = record.enabled,
        }
      })
      row.soft_hidden = true
      row.hidden = true
      row.original.hidden = true
      rows[#rows + 1] = row
    end
  end
  -- If an actual region with the same collaboration UID exists, discard the
  -- stale compatibility record rather than showing a duplicate.
  if #kept_soft ~= #soft_records then save_soft_hidden_records(kept_soft) end

  table.sort(rows, function(a, b)
    if a.number == b.number then return tostring(a.uid) < tostring(b.uid) end
    return a.number < b.number
  end)
  return rows
end

local function row_has_errors(row)
  return row.errors and #row.errors > 0
end

local function validate_editor_row(row)
  row.errors = {}
  local s, e1 = parse_time_strict(row.start_text)
  local e, e2 = parse_time_strict(row.end_text)
  if e1 then table.insert(row.errors, T("invalid_time") .. ": " .. T("start")) end
  if e2 then table.insert(row.errors, T("invalid_time") .. ": " .. T("finish")) end
  if s and e and e <= s then table.insert(row.errors, T("end_after_start")) end
  if s then row.start_sec = s end
  if e then row.end_sec = e end
end

local function recompute_row_dirty(row)
  validate_editor_row(row)
  local o = row.original
  row.dirty = row.pending_delete or
    row.name ~= o.name or
    math.abs((row.start_sec or 0) - (o.start_sec or 0)) > EPSILON or
    math.abs((row.end_sec or 0) - (o.end_sec or 0)) > EPSILON or
    row.enabled ~= o.enabled or row.hidden ~= o.hidden or
    row.owner ~= o.owner or row.note ~= o.note
  if row.pending_delete then row.status = "deleted"
  elseif row_has_errors(row) then row.status = "invalid"
  elseif row.dirty then row.status = "modified"
  else row.status = "unchanged" end
  state.filter_dirty = true
end

local function recompute_counts()
  local selected, dirty, errors = 0, 0, 0
  for _, row in ipairs(state.rows) do
    if row.selected then selected = selected + 1 end
    if row.dirty then dirty = dirty + 1 end
    if row_has_errors(row) then errors = errors + 1 end
  end
  state.selected_count = selected
  state.dirty_count = dirty
  state.error_count = errors
end

local function refresh_regions(force)
  if state.dirty_count > 0 and not force then
    state.external_change = true
    return false
  end
  state.rows = enumerate_regions()
  state.filter_dirty = true
  state.page = 1
  recompute_counts()
  state.last_project_change = reaper.GetProjectStateChangeCount(0)
  state.external_change = false
  return true
end

local function find_row_by_guid(guid)
  for _, row in ipairs(state.rows) do if row.guid == guid then return row end end
end

local function find_region_after_add(number, start_sec, end_sec, name)
  local rows = enumerate_regions()
  local best = nil
  for _, row in ipairs(rows) do
    if not row.soft_hidden and row.number == number and
        math.abs(row.start_sec - start_sec) < EPSILON and
        math.abs(row.end_sec - end_sec) < EPSILON then
      if row.name == name then return row end
      best = best or row
    end
  end
  return best
end

-- Resolve a live ProjectMarker pointer every time. Stored pointers and internal
-- indices may become stale after regions are inserted, removed or re-sorted.
local function resolve_region_pm(row)
  if not has_modern_region_api or not row then return nil end

  if row.guid and row.guid ~= "" and not row.guid:match("^LEGACY_") then
    local pm = reaper.GetRegionOrMarker(0, -1, row.guid)
    if pm and reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_ISREGION") > 0.5 then
      return pm
    end
  end

  if row.internal_index ~= nil then
    local pm = reaper.GetRegionOrMarker(0, row.internal_index, "")
    if pm and reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_ISREGION") > 0.5 then
      local number = reaper.GetRegionOrMarkerInfo_Value(0, pm, "I_NUMBER")
      if math.floor(number + 0.5) == math.floor((row.number or -1) + 0.5) then return pm end
    end
  end

  local count = reaper.GetNumRegionsOrMarkers(0)
  local time_match = nil
  for i = 0, count - 1 do
    local pm = reaper.GetRegionOrMarker(0, i, "")
    if pm and reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_ISREGION") > 0.5 then
      local number = reaper.GetRegionOrMarkerInfo_Value(0, pm, "I_NUMBER")
      local start_sec = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS")
      local end_sec = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS")
      if math.floor(number + 0.5) == math.floor((row.number or -1) + 0.5) then return pm end
      if math.abs(start_sec - (row.start_sec or 0)) < EPSILON and
         math.abs(end_sec - (row.end_sec or 0)) < EPSILON then
        time_match = time_match or pm
      end
    end
  end
  return time_match
end

local function soft_hide_region_no_undo(row)
  if row.soft_hidden then
    row.hidden = true
    upsert_soft_hidden_record(row)
    return true
  end

  local old_guid = row.guid
  local ok = reaper.DeleteProjectMarker(0, row.number, true)
  if not ok then return false, "DeleteProjectMarker failed" end

  row.soft_hidden = true
  row.hidden = true
  row.pm = nil
  row.internal_index = nil
  row.updated_at = now_iso()
  upsert_soft_hidden_record(row)
  delete_region_meta(old_guid)
  return true
end

local function soft_show_region_no_undo(row)
  if not row.soft_hidden then
    row.hidden = false
    return true
  end

  local old_guid = row.guid
  local requested = tonumber(row.number) or -1
  local new_number = reaper.AddProjectMarker2(
    0, true, row.start_sec, row.end_sec, row.name or "", requested, row.color or 0)
  if not new_number or new_number < 0 then return false, "AddProjectMarker2 failed" end

  local live = find_region_after_add(new_number, row.start_sec, row.end_sec, row.name or "")
  if not live or live.soft_hidden then
    reaper.DeleteProjectMarker(0, new_number, true)
    return false, "Restored region could not be resolved"
  end

  remove_soft_hidden_record(row.uid)
  delete_region_meta(old_guid)

  row.number = live.number
  row.pm = live.pm
  row.internal_index = live.internal_index
  row.guid = live.guid
  row.soft_hidden = false
  row.hidden = false
  row.updated_at = now_iso()
  save_row_meta(row)
  return true
end

local function set_region_hidden_immediate(row, desired)
  desired = desired and true or false
  if not has_native_region_hidden and not has_legacy_region_hidden then
    set_message(T("hidden_failed") .. "  REAPER " .. REAPER_VERSION_TEXT, "error")
    return false
  end

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)

  local call_ok, success, detail = pcall(function()
    if has_native_region_hidden then
      local pm = resolve_region_pm(row)
      if not pm then return false, "region not found" end
      reaper.SetRegionOrMarkerInfo_Value(0, pm, "B_HIDDEN", desired and 1 or 0)
      local actual = reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_HIDDEN") > 0.5
      if actual ~= desired then return false, "B_HIDDEN was not changed" end
      row.hidden = actual
      row.soft_hidden = false
      return true
    end

    if desired then
      return soft_hide_region_no_undo(row)
    end
    return soft_show_region_no_undo(row)
  end)

  reaper.PreventUIRefresh(-1)
  if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  if reaper.UpdateArrange then reaper.UpdateArrange() end

  if not call_ok then
    local lua_error = success
    success = false
    detail = tostring(lua_error or detail or "unknown error")
  end

  reaper.Undo_EndBlock2(
    0,
    desired and "Region Sync Manager: hide region" or "Region Sync Manager: show region",
    -1)

  if not success then
    set_message(T("hidden_failed") .. " " .. tostring(detail or ""), "error")
    return false
  end

  row.hidden = desired
  row.original.hidden = desired
  row.original.number = row.number
  recompute_row_dirty(row)
  recompute_counts()
  add_report(
    desired and "Hide" or "Show",
    string.format("R%d %s%s", row.number, row.name, has_native_region_hidden and "" or ""),
    "OK")
  state.last_project_change = reaper.GetProjectStateChangeCount(0)
  state.suppress_change_check_until = reaper.time_precise() + 0.8
  set_message(
    desired and ("R" .. tostring(row.number) .. " hidden") or
      ("R" .. tostring(row.number) .. " shown"),
    "info")
  return true
end

local function update_region_row(row, undo_label)
  validate_editor_row(row)
  if row_has_errors(row) then return false, table.concat(row.errors, "; ") end

  -- A compatibility-hidden row has no live REAPER region. Editing while it is
  -- hidden updates the project-side record; clearing Hidden restores it.
  if row.soft_hidden then
    row.updated_at = now_iso()
    if row.owner == "" then row.owner = settings.author end
    if row.hidden then
      upsert_soft_hidden_record(row)
      add_report(undo_label or "Update", string.format("R%d %s [hidden]", row.number, row.name), "OK")
      return true
    end
    local shown, show_err = soft_show_region_no_undo(row)
    if not shown then return false, show_err end
    add_report(undo_label or "Update", string.format("R%d %s", row.number, row.name), "OK")
    return true
  end

  local ok = false
  if has_modern_region_api then
    local pm = resolve_region_pm(row)
    if pm then
      local old_start = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS")
      local old_end = reaper.GetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS")
      -- Avoid a temporary inverted range while moving a region far left/right.
      if row.start_sec >= old_end then
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS", row.end_sec)
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS", row.start_sec)
      elseif row.end_sec <= old_start then
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS", row.start_sec)
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS", row.end_sec)
      else
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "D_STARTPOS", row.start_sec)
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "D_ENDPOS", row.end_sec)
      end

      local hidden_ok = true
      if has_native_region_hidden then
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "B_HIDDEN", row.hidden and 1 or 0)
        hidden_ok =
          (reaper.GetRegionOrMarkerInfo_Value(0, pm, "B_HIDDEN") > 0.5) ==
          (row.hidden and true or false)
      end
      if row.color ~= nil then
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "I_CUSTOMCOLOR", row.color)
      end
      local name_ok =
        reaper.GetSetRegionOrMarkerInfo_String(0, pm, "P_NAME", row.name or "", true)
      ok = (name_ok and true or false) and hidden_ok
    end
  else
    local flags = row.name == "" and 1 or 0
    ok = reaper.SetProjectMarker4(
      0, row.number, true, row.start_sec, row.end_sec,
      row.name or "", row.color or 0, flags)
  end

  -- REAPER 7.56 compatibility hiding: commit the edited live values first,
  -- then remove the live region and store the complete reversible record.
  if ok and not has_native_region_hidden and row.hidden then
    local hidden_ok, hidden_err = soft_hide_region_no_undo(row)
    if not hidden_ok then return false, hidden_err end
  end

  if ok then
    row.updated_at = now_iso()
    if row.owner == "" then row.owner = settings.author end
    save_row_meta(row)
    add_report(
      undo_label or "Update",
      string.format("R%d %s", row.number, row.name),
      "OK")
    return true
  end
  return false, "REAPER rejected the region update"
end

local function apply_staged_changes()
  recompute_counts()
  if state.dirty_count == 0 then return end
  if state.error_count > 0 then
    set_message(T("validation_errors"), "error")
    return
  end

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  local failed = 0

  -- Delete from highest number first to minimize index churn.
  local deletes = {}
  for _, row in ipairs(state.rows) do if row.pending_delete then table.insert(deletes, row) end end
  table.sort(deletes, function(a, b) return a.number > b.number end)
  for _, row in ipairs(deletes) do
    local ok
    if row.soft_hidden then
      remove_soft_hidden_record(row.uid)
      ok = true
    else
      ok = reaper.DeleteProjectMarker(0, row.number, true)
    end
    if ok then
      delete_region_meta(row.guid)
      add_report("Delete", string.format("R%d %s", row.number, row.name), "OK")
    else
      failed = failed + 1
      add_report("Delete", string.format("R%d %s", row.number, row.name), "FAILED")
    end
  end

  for _, row in ipairs(state.rows) do
    if row.dirty and not row.pending_delete then
      local ok, err = update_region_row(row, "Edit")
      if not ok then
        failed = failed + 1
        add_report("Edit", string.format("R%d %s - %s", row.number, row.name, err or ""), "FAILED")
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock2(0, "Region Sync Manager: apply staged changes", -1)
  state.suppress_change_check_until = reaper.time_precise() + 0.6
  refresh_regions(true)
  set_message(failed > 0 and T("apply_failed") or T("apply_complete"), failed > 0 and "error" or "info")
end

local function discard_changes()
  for _, row in ipairs(state.rows) do
    local o = row.original
    row.name, row.start_sec, row.end_sec = o.name, o.start_sec, o.end_sec
    row.start_text, row.end_text = o.start_text, o.end_text
    row.enabled, row.hidden, row.color = o.enabled, o.hidden, o.color
    row.owner, row.note, row.updated_at = o.owner, o.note, o.updated_at
    row.pending_delete, row.dirty, row.errors, row.status = false, false, {}, "unchanged"
  end
  state.filter_dirty = true
  recompute_counts()
end

local function create_regions_from_selected_items()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return end
  reaper.Undo_BeginBlock2(0)
  local name_counts, current_idx = {}, {}
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    local name = take and reaper.GetTakeName(take) or "Region"
    name = name:gsub("%.%w+$", "")
    if not name:match("_%d+$") then name_counts[name] = (name_counts[name] or 0) + 1 end
  end
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local take = reaper.GetActiveTake(item)
    local name = take and reaper.GetTakeName(take) or "Region"
    name = name:gsub("%.%w+$", "")
    if not name:match("_%d+$") and (name_counts[name] or 0) > 1 then
      current_idx[name] = (current_idx[name] or 0) + 1
      name = string.format("%s_%02d", name, current_idx[name])
    end
    local new_number = reaper.AddProjectMarker2(0, true, pos, pos + len, name, -1, 0)
    if new_number >= 0 then
      local new_row = find_region_after_add(new_number, pos, pos + len, name)
      if new_row then
        new_row.owner = settings.author
        new_row.updated_at = now_iso()
        save_row_meta(new_row)
      end
      add_report("Create", string.format("R%d %s", new_number, name), "OK")
    end
  end
  reaper.Undo_EndBlock2(0, "Region Sync Manager: create regions from selected items", -1)
  reaper.UpdateTimeline()
  state.suppress_change_check_until = reaper.time_precise() + 0.6
  refresh_regions(true)
end

-- -----------------------------------------------------------------------------
-- Export
-- -----------------------------------------------------------------------------
local function region_rows_to_csv(rows, only_enabled)
  local lines = {}
  table.insert(lines, table.concat(CSV_HEADERS, ","))
  for _, row in ipairs(rows) do
    if not only_enabled or row.enabled then
      local values = {
        SCHEMA_VERSION,
        project_uid,
        row.uid,
        tostring(row.number),
        row.name,
        string.format("%.9f", row.start_sec),
        string.format("%.9f", row.end_sec),
        row.enabled and "true" or "false",
        row.hidden and "true" or "false",
        tostring(math.floor(row.color or 0)),
        row.status or "",
        row.note or "",
        row.owner or "",
        row.updated_at or ""
      }
      for i, v in ipairs(values) do values[i] = csv_escape(v) end
      table.insert(lines, table.concat(values, ","))
    end
  end
  local content = table.concat(lines, "\r\n") .. "\r\n"
  if settings.utf8_bom then content = "\239\187\191" .. content end
  return content
end

local function save_regions_csv(path, rows, only_enabled)
  path = ensure_csv_extension(path)
  local ok, err = atomic_write(path, region_rows_to_csv(rows, only_enabled))
  if ok then
    settings.last_csv_path = path
    add_recent_file(path)
    save_settings()
  end
  return ok, err, path
end

local function default_csv_save_path(default_name)
  local dir = ""
  if settings.last_csv_path ~= "" then
    dir = path_dir(settings.last_csv_path)
  end
  if dir == "" and reaper.GetProjectPathEx then
    dir = reaper.GetProjectPathEx(0) or ""
  end
  if dir == "" and reaper.GetResourcePath then
    dir = reaper.GetResourcePath() or ""
  end
  local sep = package.config:sub(1, 1)
  if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. sep end
  return dir .. (default_name or "Regions.csv")
end

local function prompt_save_path(default_name, js_error)
  local default_path = default_csv_save_path(default_name)
  local title = "Save CSV"
  if js_error and js_error ~= "" then title = title .. " (compatibility mode)" end
  local ok, value = reaper.GetUserInputs(title, 1, "Full file path:", default_path)
  if not ok then return false, "" end
  value = trim(value)
  if value == "" then return false, "" end
  return true, value
end

local function choose_save_path(default_name)
  local initial = settings.last_csv_path ~= "" and path_dir(settings.last_csv_path) or ""
  if has_js then
    local call_ok, retval, path = pcall(
      reaper.JS_Dialog_BrowseForSaveFile,
      "Save CSV",
      initial,
      default_name or "Regions.csv",
      "CSV files (*.csv)\0*.csv\0All files (*.*)\0*.*\0\0"
    )
    if call_ok then
      if (retval == 1 or retval == true) and path and path ~= "" then
        return true, path
      end
      -- A normal Cancel must not open a second dialog.
      if retval == 0 or retval == false then return false, "" end
    else
      return prompt_save_path(default_name, tostring(retval or "js_ReaScriptAPI error"))
    end
  end
  return prompt_save_path(default_name, "")
end

local function export_current_csv()
  local ok, path = choose_save_path("Regions.csv")
  if not ok or path == "" then return end
  local saved, err, final_path = save_regions_csv(path, state.rows, settings.export_only_enabled)
  if saved then
    set_message(T("saved") .. ": " .. final_path, "info")
    add_report("Export", final_path, "OK")
  else
    set_message(T("save_failed") .. " " .. tostring(err or ""), "error")
    reaper.MB(T("save_failed") .. "\n\n" .. tostring(err or ""), APP_NAME, 0)
  end
end

local function create_backup_csv()
  local _, project_path = reaper.EnumProjects(-1, "")
  local dir = project_path and project_path ~= "" and path_dir(project_path) or reaper.GetProjectPathEx(0)
  if not dir or dir == "" then return nil, "Project path is unavailable" end
  local sep = dir:match("[\\/]$") and "" or package.config:sub(1, 1)
  local stamp = os.date("%Y%m%d_%H%M%S")
  local path = dir .. sep .. "RegionSync_Backup_" .. stamp .. ".csv"
  local ok, err = atomic_write(path, region_rows_to_csv(state.rows, false))
  if ok then add_report(T("backup_created"), path, "OK"); return path end
  return nil, err
end

-- -----------------------------------------------------------------------------
-- Import validation and diff
-- -----------------------------------------------------------------------------
local HEADER_ALIASES = {
  ["#"] = "RegionNumber", ["ID"] = "RegionNumber", ["Region"] = "RegionNumber",
  ["Start"] = "StartSec", ["End"] = "EndSec", ["Visible"] = "Visible",
  ["Name"] = "Name"
}

local function normalize_header(h)
  h = trim(h):gsub("^\239\187\191", "")
  return HEADER_ALIASES[h] or h
end

local function add_issue(issues, severity, row_index, column, message)
  table.insert(issues, {
    severity = severity, row = row_index or 0, column = column or "", message = message or ""
  })
end

local function parse_import_file(path)
  local text, file_err = read_all(path)
  if not text then return nil, {{severity="error", row=0, column="", message=tostring(file_err)}} end
  local matrix, parse_err = parse_csv_document(text)
  if not matrix then return nil, {{severity="error", row=0, column="", message=parse_err}} end
  if #matrix < 1 then return nil, {{severity="error", row=0, column="", message="Empty CSV"}} end

  local headers, index = {}, {}
  for i, h in ipairs(matrix[1]) do
    headers[i] = normalize_header(h)
    index[headers[i]] = i
  end
  local legacy = index["SchemaVersion"] == nil
  local issues = {}
  if not index["Name"] then add_issue(issues, "error", 1, "Name", T("missing_required") .. ": Name") end
  if not index["StartSec"] then add_issue(issues, "error", 1, "StartSec", T("missing_required") .. ": StartSec/Start") end
  if not index["EndSec"] then add_issue(issues, "error", 1, "EndSec", T("missing_required") .. ": EndSec/End") end

  local parsed = {}
  local seen_uid, seen_number = {}, {}
  local project_id, schema_version = "", legacy and "1" or ""

  for r = 2, #matrix do
    local src = matrix[r]
    local function val(key)
      local idx = index[key]
      return idx and (src[idx] or "") or ""
    end
    local row = {
      csv_row = r,
      schema_version = trim(val("SchemaVersion")),
      project_id = trim(val("ProjectID")),
      uid = trim(val("RegionUID")),
      number = tonumber(trim(val("RegionNumber")):match("%d+")),
      name = val("Name") or "",
      enabled = bool_from_string(val("Enabled"), true),
      hidden = bool_from_string(val("Hidden"), false),
      color = tonumber(trim(val("Color"))) or 0,
      note = val("Note") or "",
      owner = val("UpdatedBy") or "",
      updated_at = val("UpdatedAt") or "",
      errors = {}, warnings = {}, valid = true,
    }
    if legacy then
      local visible = bool_from_string(val("Visible"), true)
      row.hidden = not visible
      row.uid = ""
      row.project_id = ""
      row.schema_version = "1"
    end
    local s, s_err = parse_time_strict(val("StartSec"))
    local e, e_err = parse_time_strict(val("EndSec"))
    if s_err then table.insert(row.errors, T("invalid_time") .. ": " .. T("start")) end
    if e_err then table.insert(row.errors, T("invalid_time") .. ": " .. T("finish")) end
    if s and e and e <= s then table.insert(row.errors, T("end_after_start")) end
    row.start_sec, row.end_sec = s, e
    if row.uid ~= "" then
      if seen_uid[row.uid] then table.insert(row.errors, T("duplicate_uid")) else seen_uid[row.uid] = r end
    end
    if row.number then
      if seen_number[row.number] then table.insert(row.warnings, T("duplicate_number")) else seen_number[row.number] = r end
    end
    if row.name:match("^[=+%-@]") then table.insert(row.warnings, T("formula_warning")) end
    if #row.errors > 0 then row.valid = false end
    for _, msg in ipairs(row.errors) do add_issue(issues, "error", r, "", msg) end
    for _, msg in ipairs(row.warnings) do add_issue(issues, "warning", r, "", msg) end
    if row.project_id ~= "" and project_id == "" then project_id = row.project_id end
    if row.schema_version ~= "" and schema_version == "" then schema_version = row.schema_version end
    table.insert(parsed, row)
  end

  if legacy then add_issue(issues, "info", 0, "", T("old_csv")) end
  return {
    rows = parsed, issues = issues, project_id = project_id,
    schema_version = schema_version, legacy = legacy
  }, nil
end

local function values_equal(a, b)
  return a.name == b.name and
    math.abs((a.start_sec or 0) - (b.start_sec or 0)) <= EPSILON and
    math.abs((a.end_sec or 0) - (b.end_sec or 0)) <= EPSILON and
    a.enabled == b.enabled and a.hidden == b.hidden and
    (tonumber(a.color) or 0) == (tonumber(b.color) or 0) and
    (a.owner or "") == (b.owner or "") and (a.note or "") == (b.note or "")
end

local function build_import_diff()
  local imp = state.import
  imp.diffs = {}
  local by_uid, by_number = {}, {}
  for _, row in ipairs(state.rows) do
    if row.uid and row.uid ~= "" then by_uid[row.uid] = row end
    by_number[row.number] = row
  end
  local matched = {}

  for _, incoming in ipairs(imp.rows) do
    local current_by_uid = incoming.uid ~= "" and by_uid[incoming.uid] or nil
    local current_by_number = incoming.number and by_number[incoming.number] or nil
    local current = current_by_uid or current_by_number
    local status, reason = "added", ""
    if imp.mode == "name" and not current then
      status = "conflict"
      reason = "Names-only mode requires a matching RegionUID or RegionNumber"
    elseif not incoming.valid then
      status = "invalid"
      reason = table.concat(incoming.errors, "; ")
    elseif current_by_uid and current_by_number and current_by_uid ~= current_by_number then
      status = "conflict"
      reason = "RegionUID and RegionNumber point to different current regions"
    elseif current then
      matched[current.uid] = true
      if incoming.uid ~= "" and current.uid ~= incoming.uid and current_by_number == current then
        status = "conflict"
        reason = "RegionNumber exists but RegionUID differs"
      elseif imp.mode == "name" then
        status = current.name == incoming.name and "unchanged" or "modified"
      else
        status = values_equal(current, incoming) and "unchanged" or "modified"
      end
    end
    local selected = incoming.valid and status ~= "unchanged" and status ~= "conflict"
    table.insert(imp.diffs, {
      status = status, reason = reason, current = current, incoming = incoming,
      selected = selected, valid = incoming.valid and status ~= "conflict"
    })
  end

  if imp.mode == "replace" then
    for _, current in ipairs(state.rows) do
      if not matched[current.uid] then
        table.insert(imp.diffs, {
          status = "deleted", reason = "Missing from incoming CSV",
          current = current, incoming = nil, selected = true, valid = true
        })
      end
    end
  end

  table.sort(imp.diffs, function(a, b)
    local an = a.incoming and a.incoming.number or (a.current and a.current.number or 0)
    local bn = b.incoming and b.incoming.number or (b.current and b.current.number or 0)
    return an < bn
  end)
end

local function load_import_path(path)
  local parsed, err_issues = parse_import_file(path)
  if not parsed then
    state.import.issues = err_issues or {}
    state.import.rows = {}
    state.import.diffs = {}
    set_message(T("file_error") .. ": " .. path, "error")
    return false
  end
  state.import.path = path
  state.import.rows = parsed.rows
  state.import.issues = parsed.issues
  state.import.project_id = parsed.project_id
  state.import.schema_version = parsed.schema_version
  state.import.legacy = parsed.legacy
  state.import.project_mismatch = parsed.project_id ~= "" and parsed.project_id ~= project_uid
  settings.last_csv_path = path
  add_recent_file(path)
  save_settings()
  build_import_diff()
  state.active_tab = "import"
  set_message(T("loaded") .. ": " .. basename(path), "info")
  return true
end

local function choose_import_file()
  local initial = settings.last_csv_path ~= "" and settings.last_csv_path or ""
  local ok, path = reaper.GetUserFileNameForRead(initial, "Select Region CSV", "csv")
  if ok and path and path ~= "" then load_import_path(path) end
end

local function add_import_region(incoming)
  local requested = incoming.number or -1

  -- On REAPER 7.56, create an ExtState-backed hidden record directly instead
  -- of briefly adding and deleting a live region.
  if incoming.hidden == true and not has_native_region_hidden and has_legacy_region_hidden then
    local uid = incoming.uid ~= "" and incoming.uid or generate_uid()
    local row = build_row({
      guid = "SOFT_" .. tostring(uid),
      number = requested,
      name = incoming.name or "",
      start_sec = incoming.start_sec,
      end_sec = incoming.end_sec,
      hidden = true,
      color = incoming.color or 0,
      soft_hidden = true,
      meta = {
        uid = uid,
        enabled = incoming.enabled ~= false,
        owner = incoming.owner ~= "" and incoming.owner or settings.author,
        note = incoming.note or "",
        updated_at = incoming.updated_at ~= "" and incoming.updated_at or now_iso(),
      }
    })
    row.soft_hidden = true
    row.hidden = true
    row.original.hidden = true
    upsert_soft_hidden_record(row)
    return true, row
  end

  local new_number = reaper.AddProjectMarker2(
    0, true, incoming.start_sec, incoming.end_sec,
    incoming.name or "", requested, incoming.color or 0)
  if new_number < 0 then return false, "AddProjectMarker2 failed" end

  local new_row =
    find_region_after_add(new_number, incoming.start_sec, incoming.end_sec, incoming.name or "")
  if not new_row or new_row.soft_hidden then
    return false, "Created region could not be resolved"
  end

  new_row.uid = incoming.uid ~= "" and incoming.uid or generate_uid()
  new_row.enabled = incoming.enabled ~= false
  new_row.hidden = incoming.hidden == true
  new_row.owner = incoming.owner ~= "" and incoming.owner or settings.author
  new_row.note = incoming.note or ""
  new_row.updated_at =
    incoming.updated_at ~= "" and incoming.updated_at or now_iso()

  if has_modern_region_api and new_row.guid ~= "" and
      not new_row.guid:match("^LEGACY_") then
    local pm = reaper.GetRegionOrMarker(0, -1, new_row.guid)
    if pm and has_native_region_hidden then
      reaper.SetRegionOrMarkerInfo_Value(
        0, pm, "B_HIDDEN", new_row.hidden and 1 or 0)
    end
  end

  save_row_meta(new_row)
  return true, new_row
end

local function apply_import_diff()
  local imp = state.import
  local selected_count = 0
  for _, d in ipairs(imp.diffs) do if d.selected and d.valid then selected_count = selected_count + 1 end end
  if selected_count == 0 then return end

  if imp.mode == "replace" then
    local answer = reaper.MB(T("confirm_replace"), APP_NAME, 4)
    if answer ~= 6 then return end
    local backup, backup_err = create_backup_csv()
    if not backup then
      local cont = reaper.MB(T("save_failed") .. "\n" .. tostring(backup_err or "") .. "\n\nContinue without backup?", APP_NAME, 4)
      if cont ~= 6 then return end
    end
  end

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  local failed = 0

  -- Deletes first, descending numbers.
  local deletions = {}
  for _, d in ipairs(imp.diffs) do
    if d.selected and d.valid and d.status == "deleted" then table.insert(deletions, d) end
  end
  table.sort(deletions, function(a, b) return a.current.number > b.current.number end)
  for _, d in ipairs(deletions) do
    local row = d.current
    local ok
    if row.soft_hidden then
      remove_soft_hidden_record(row.uid)
      ok = true
    else
      ok = reaper.DeleteProjectMarker(0, row.number, true)
    end
    if ok then
      delete_region_meta(row.guid)
      add_report("Import Delete", string.format("R%d %s", row.number, row.name), "OK")
    else
      failed = failed + 1
      add_report("Import Delete", string.format("R%d %s", row.number, row.name), "FAILED")
    end
  end

  for _, d in ipairs(imp.diffs) do
    if d.selected and d.valid and d.status ~= "deleted" and d.status ~= "unchanged" then
      if d.status == "added" then
        local ok, result = add_import_region(d.incoming)
        if ok then add_report("Import Add", string.format("R%d %s", result.number, result.name), "OK")
        else failed = failed + 1; add_report("Import Add", tostring(result), "FAILED") end
      elseif d.status == "modified" and d.current then
        local row, incoming = d.current, d.incoming
        row.name = incoming.name
        if imp.mode ~= "name" then
          row.start_sec, row.end_sec = incoming.start_sec, incoming.end_sec
          row.start_text, row.end_text = format_time(row.start_sec), format_time(row.end_sec)
          row.enabled, row.hidden, row.color = incoming.enabled, incoming.hidden, incoming.color
          row.note = incoming.note or row.note
          row.owner = incoming.owner ~= "" and incoming.owner or row.owner
        end
        if incoming.uid ~= "" then row.uid = incoming.uid end
        local ok, err = update_region_row(row, "Import Update")
        if not ok then failed = failed + 1; add_report("Import Update", tostring(err), "FAILED") end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock2(0, "Region Sync Manager: apply CSV import", -1)
  state.suppress_change_check_until = reaper.time_precise() + 0.8
  refresh_regions(true)
  -- Keep the preview but rebuild against the new current state.
  build_import_diff()
  set_message(failed > 0 and T("apply_failed") or T("apply_complete"), failed > 0 and "error" or "info")
end

-- -----------------------------------------------------------------------------
-- Filtering, sorting and pagination
-- -----------------------------------------------------------------------------
local STATUS_ORDER = {invalid=1, conflict=2, modified=3, added=4, deleted=5, unchanged=6}

local function rebuild_filtered()
  if not state.filter_dirty then return end
  state.filtered = {}
  local q = state.search:lower()
  for _, row in ipairs(state.rows) do
    local match_text = q == "" or
      row.name:lower():find(q, 1, true) or
      row.owner:lower():find(q, 1, true) or
      row.note:lower():find(q, 1, true) or
      tostring(row.number):find(q, 1, true)
    local match_status = state.status_filter == "all" or row.status == state.status_filter
    if match_text and match_status then table.insert(state.filtered, row) end
  end

  local key = state.sort_by
  table.sort(state.filtered, function(a, b)
    local av, bv
    if key == "name" then av, bv = a.name:lower(), b.name:lower()
    elseif key == "start" then av, bv = a.start_sec, b.start_sec
    elseif key == "end" then av, bv = a.end_sec, b.end_sec
    elseif key == "status" then av, bv = STATUS_ORDER[a.status] or 99, STATUS_ORDER[b.status] or 99
    else av, bv = a.number, b.number end
    if av == bv then return a.number < b.number end
    if state.ascending then return av < bv else return av > bv end
  end)

  local pages = math.max(1, math.ceil(#state.filtered / settings.page_size))
  state.page = clamp(state.page, 1, pages)
  state.filter_dirty = false
end

local function current_page_rows()
  rebuild_filtered()
  local from = (state.page - 1) * settings.page_size + 1
  local to = math.min(#state.filtered, from + settings.page_size - 1)
  local out = {}
  for i = from, to do if state.filtered[i] then table.insert(out, state.filtered[i]) end end
  return out, from, to
end

-- -----------------------------------------------------------------------------
-- Bulk rename
-- -----------------------------------------------------------------------------
local bulk = {
  target = "selected",
  preset = "prefix",
  value = "",
  find = "",
  replace = "",
  digits = 2,
  start_number = 1,
  template = "{name}_{index}",
}

local function bulk_target_rows()
  local out = {}
  if bulk.target == "selected" then
    for _, row in ipairs(state.rows) do if row.selected then table.insert(out, row) end end
  else
    rebuild_filtered()
    for _, row in ipairs(state.filtered) do table.insert(out, row) end
  end
  table.sort(out, function(a, b) return a.number < b.number end)
  return out
end

local function format_sequence_number(index)
  local digits = clamp(math.floor(tonumber(bulk.digits) or 2), 1, 6)
  local start_number = math.max(0, math.floor(tonumber(bulk.start_number) or 1))
  return string.format("%0" .. tostring(digits) .. "d", start_number + index - 1)
end

local function renamed_value(row, index)
  local name = row.name
  if bulk.preset == "prefix" then return bulk.value .. name end
  if bulk.preset == "suffix" then return name .. bulk.value end
  if bulk.preset == "find_replace" then
    if bulk.find == "" then return name end
    return name:gsub(bulk.find:gsub("([^%w])", "%%%1"), bulk.replace)
  end
  if bulk.preset == "sequential" then
    return name .. "_" .. format_sequence_number(index)
  end
  if bulk.preset == "uppercase" then return name:upper() end
  if bulk.preset == "lowercase" then return name:lower() end
  if bulk.preset == "spaces_underscore" then return name:gsub("%s+", "_") end
  if bulk.preset == "template" then
    local result = bulk.template
    local seq = format_sequence_number(index)
    result = result:gsub("{name}", name)
    result = result:gsub("{index}", seq)
    result = result:gsub("{number}", tostring(row.number))
    result = result:gsub("{owner}", row.owner or "")
    return result
  end
  return name
end

local function stage_bulk_rename()
  local targets = bulk_target_rows()
  if #targets == 0 then set_message(T("nothing_selected"), "warning"); return end
  for i, row in ipairs(targets) do
    row.name = renamed_value(row, i)
    recompute_row_dirty(row)
  end
  recompute_counts()
  state.open_bulk = false
end

-- -----------------------------------------------------------------------------
-- Report export and example file
-- -----------------------------------------------------------------------------
local function export_report()
  local ok, path = choose_save_path("RegionSync_ChangeReport.csv")
  if not ok or path == "" then return end
  path = ensure_csv_extension(path)
  local lines = {"Time,Action,Details,Result"}
  for i = #state.report, 1, -1 do
    local r = state.report[i]
    table.insert(lines, table.concat({csv_escape(r.time), csv_escape(r.action), csv_escape(r.details), csv_escape(r.result)}, ","))
  end
  local content = table.concat(lines, "\r\n") .. "\r\n"
  if settings.utf8_bom then content = "\239\187\191" .. content end
  local saved, err = atomic_write(path, content)
  set_message(saved and (T("saved") .. ": " .. path) or (T("save_failed") .. " " .. tostring(err or "")), saved and "info" or "error")
end

local function export_example_csv()
  local ok, path = choose_save_path("RegionSync_Example.csv")
  if not ok or path == "" then return end
  path = ensure_csv_extension(path)
  local sample = {
    CSV_HEADERS,
    {SCHEMA_VERSION, project_uid, generate_uid(), "1", "SFX_Door_Close", "0.000000000", "1.250000000", "true", "false", "0", "Review", "Check tail", settings.author, now_iso()},
    {SCHEMA_VERSION, project_uid, generate_uid(), "2", "AMB_Forest_Night", "2.000000000", "12.000000000", "true", "false", "0", "Approved", "Loop point checked", settings.author, now_iso()},
  }
  local lines = {}
  for _, row in ipairs(sample) do
    local out = {}
    for i, v in ipairs(row) do out[i] = csv_escape(v) end
    table.insert(lines, table.concat(out, ","))
  end
  local content = table.concat(lines, "\r\n") .. "\r\n"
  if settings.utf8_bom then content = "\239\187\191" .. content end
  local saved, err = atomic_write(path, content)
  set_message(saved and (T("saved") .. ": " .. path) or (T("save_failed") .. " " .. tostring(err or "")), saved and "info" or "error")
end

-- -----------------------------------------------------------------------------
-- ReaImGui helpers
-- -----------------------------------------------------------------------------
local function combo(ctx2, label, current, choices)
  local changed, value = false, current
  local preview = choices[current] or current
  if reaper.ImGui_BeginCombo(ctx2, label, preview) then
    for key, text in pairs(choices) do
      local selected = key == current
      if reaper.ImGui_Selectable(ctx2, text, selected) then value, changed = key, true end
      if selected then reaper.ImGui_SetItemDefaultFocus(ctx2) end
    end
    reaper.ImGui_EndCombo(ctx2)
  end
  return changed, value
end

local function status_text(status)
  return T(status or "unchanged")
end

local function render_message_bar()
  if state.message ~= "" then
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, state.message)
  end
  if state.external_change then
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, T("external_banner"))
    if reaper.ImGui_Button(ctx, T("reload")) then refresh_regions(true) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("keep_edits")) then state.external_change = false end
  end
end

local function render_toolbar()
  if reaper.ImGui_Button(ctx, T("refresh")) then refresh_regions(false) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("create_items")) then create_regions_from_selected_items() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("import_csv")) then choose_import_file() end
  if #settings.recent_files > 0 then
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "▼##recent") then reaper.ImGui_OpenPopup(ctx, "RecentFiles") end
    if reaper.ImGui_BeginPopup(ctx, "RecentFiles") then
      reaper.ImGui_Text(ctx, T("recent_files"))
      reaper.ImGui_Separator(ctx)
      for _, path in ipairs(settings.recent_files) do
        if reaper.ImGui_Selectable(ctx, basename(path), false) then load_import_path(path) end
        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, path) end
      end
      reaper.ImGui_EndPopup(ctx)
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("export_csv")) then export_current_csv() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("bulk_rename")) then state.open_bulk = true end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("apply_changes") .. " (" .. tostring(state.dirty_count) .. ")") then apply_staged_changes() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("discard_changes")) then discard_changes() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("settings")) then state.open_settings = true end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("help")) then state.open_help = true end
end

local function render_filters()
  reaper.ImGui_SetNextItemWidth(ctx, 260)
  if state.focus_search then reaper.ImGui_SetKeyboardFocusHere(ctx); state.focus_search = false end
  local changed, value = reaper.ImGui_InputText(ctx, T("search") .. "##search", state.search)
  if changed then state.search = value; state.filter_dirty = true; state.page = 1 end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 140)
  local sc, sv = combo(ctx, T("status_filter") .. "##status", state.status_filter, {
    all = "All", unchanged = T("unchanged"), modified = T("modified"), invalid = T("invalid"), deleted = T("deleted")
  })
  if sc then state.status_filter = sv; state.filter_dirty = true; state.page = 1 end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 130)
  local cc, cv = combo(ctx, T("sort_by") .. "##sort", state.sort_by, {
    number=T("id"), name=T("name"), start=T("start"), ["end"]=T("finish"), status=T("status")
  })
  if cc then state.sort_by = cv; state.filter_dirty = true end
  reaper.ImGui_SameLine(ctx)
  local ac, av = reaper.ImGui_Checkbox(ctx, T("ascending"), state.ascending)
  if ac then state.ascending = av; state.filter_dirty = true end
end

local function render_regions_tab()
  render_filters()
  rebuild_filtered()

  local summary = string.format(T("count_summary"), #state.rows, state.selected_count, state.dirty_count, state.error_count)
  reaper.ImGui_Text(ctx, summary)
  if state.dirty_count > 0 then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "| " .. T("dirty_banner"))
  end

  local page_rows, from, to = current_page_rows()
  local pages = math.max(1, math.ceil(#state.filtered / settings.page_size))
  if reaper.ImGui_Button(ctx, "<##prev") and state.page > 1 then state.page = state.page - 1 end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, string.format("%s %d %s %d  (%d-%d / %d)", T("page"), state.page, T("of"), pages, from, to, #state.filtered))
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, ">##next") and state.page < pages then state.page = state.page + 1 end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("select_all") .. "##page") then
    for _, row in ipairs(page_rows) do row.selected = true end
    recompute_counts()
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("select_none") .. "##page") then
    for _, row in ipairs(page_rows) do row.selected = false end
    recompute_counts()
  end

  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() |
    reaper.ImGui_TableFlags_ScrollX() | reaper.ImGui_TableFlags_ScrollY() |
    reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_Reorderable()
  if reaper.ImGui_BeginTable(ctx, "RegionsTable", 13, flags, -1, -1) then
    reaper.ImGui_TableSetupColumn(ctx, "✓", reaper.ImGui_TableColumnFlags_WidthFixed(), 28)
    reaper.ImGui_TableSetupColumn(ctx, T("status"), reaper.ImGui_TableColumnFlags_WidthFixed(), 75)
    reaper.ImGui_TableSetupColumn(ctx, T("go"), reaper.ImGui_TableColumnFlags_WidthFixed(), 38)
    reaper.ImGui_TableSetupColumn(ctx, T("id"), reaper.ImGui_TableColumnFlags_WidthFixed(), 45)
    reaper.ImGui_TableSetupColumn(ctx, T("enabled"), reaper.ImGui_TableColumnFlags_WidthFixed(), 55)
    reaper.ImGui_TableSetupColumn(ctx, T("hidden"), reaper.ImGui_TableColumnFlags_WidthFixed(), 50)
    reaper.ImGui_TableSetupColumn(ctx, T("name"), reaper.ImGui_TableColumnFlags_WidthFixed(), 210)
    reaper.ImGui_TableSetupColumn(ctx, T("start"), reaper.ImGui_TableColumnFlags_WidthFixed(), 110)
    reaper.ImGui_TableSetupColumn(ctx, T("finish"), reaper.ImGui_TableColumnFlags_WidthFixed(), 110)
    reaper.ImGui_TableSetupColumn(ctx, T("length"), reaper.ImGui_TableColumnFlags_WidthFixed(), 80)
    reaper.ImGui_TableSetupColumn(ctx, T("owner"), reaper.ImGui_TableColumnFlags_WidthFixed(), 100)
    reaper.ImGui_TableSetupColumn(ctx, T("note"), reaper.ImGui_TableColumnFlags_WidthFixed(), 180)
    reaper.ImGui_TableSetupColumn(ctx, T("delete"), reaper.ImGui_TableColumnFlags_WidthFixed(), 48)
    reaper.ImGui_TableHeadersRow(ctx)

    for _, row in ipairs(page_rows) do
      reaper.ImGui_PushID(ctx, row.uid)
      reaper.ImGui_TableNextRow(ctx)

      reaper.ImGui_TableNextColumn(ctx)
      local c, v = reaper.ImGui_Checkbox(ctx, "##sel", row.selected)
      if c then row.selected = v; recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, status_text(row.status))
      if row_has_errors(row) and reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, table.concat(row.errors, "\n"))
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, "▶##go") then reaper.SetEditCurPos(row.start_sec, true, false) end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, "R" .. tostring(row.number))

      reaper.ImGui_TableNextColumn(ctx)
      local ec, ev = reaper.ImGui_Checkbox(ctx, "##enabled", row.enabled)
      if ec then row.enabled = ev; recompute_row_dirty(row); recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      if has_native_region_hidden or has_legacy_region_hidden then
        local hc, hv = reaper.ImGui_Checkbox(ctx, "##hidden", row.hidden)
        if hc then
          local previous = row.hidden
          if not set_region_hidden_immediate(row, hv) then row.hidden = previous end
        end
        if not has_native_region_hidden and reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, T("hidden_requires") .. "\nCurrent: " .. REAPER_VERSION_TEXT)
        end
      else
        reaper.ImGui_Text(ctx, "N/A")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, T("hidden_failed") .. "\nCurrent: " .. REAPER_VERSION_TEXT)
        end
      end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local nc, nv = reaper.ImGui_InputText(ctx, "##name", row.name)
      if nc then row.name = nv; recompute_row_dirty(row); recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local sc, sv = reaper.ImGui_InputText(ctx, "##start", row.start_text)
      if sc then row.start_text = sv; recompute_row_dirty(row); recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local fc, fv = reaper.ImGui_InputText(ctx, "##end", row.end_text)
      if fc then row.end_text = fv; recompute_row_dirty(row); recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, format_clock(math.max(0, row.end_sec - row.start_sec)):sub(4))

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local oc, ov = reaper.ImGui_InputText(ctx, "##owner", row.owner)
      if oc then row.owner = ov; recompute_row_dirty(row); recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local mc, mv = reaper.ImGui_InputText(ctx, "##note", row.note)
      if mc then row.note = mv; recompute_row_dirty(row); recompute_counts() end

      reaper.ImGui_TableNextColumn(ctx)
      local label = row.pending_delete and "↶##delete" or "X##delete"
      if reaper.ImGui_Button(ctx, label) then
        row.pending_delete = not row.pending_delete
        recompute_row_dirty(row)
        recompute_counts()
      end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end
end

local function import_counts()
  local counts = {added=0, modified=0, unchanged=0, conflict=0, deleted=0, invalid=0, selected=0}
  for _, d in ipairs(state.import.diffs) do
    counts[d.status] = (counts[d.status] or 0) + 1
    if d.selected then counts.selected = counts.selected + 1 end
  end
  return counts
end

local function render_import_tab()
  if reaper.ImGui_Button(ctx, T("choose_file")) then choose_import_file() end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 170)
  local changed, mode = combo(ctx, T("import_mode") .. "##mode", state.import.mode, {
    name=T("mode_name"), merge=T("mode_merge"), replace=T("mode_replace")
  })
  if changed then state.import.mode = mode; build_import_diff() end

  if state.import.path == "" then
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, T("no_preview"))
    return
  end

  reaper.ImGui_Text(ctx, T("source_file") .. ": " .. state.import.path)
  reaper.ImGui_Text(ctx, T("csv_schema") .. ": " .. (state.import.schema_version or "") .. "  |  " .. T("project_id") .. ": " .. (state.import.project_id ~= "" and state.import.project_id or "Legacy/None"))
  if state.import.project_mismatch then reaper.ImGui_TextWrapped(ctx, T("project_mismatch")) end

  local counts = import_counts()
  reaper.ImGui_Text(ctx, string.format("%s %d  |  %s %d  |  %s %d  |  %s %d  |  %s %d  |  %s %d",
    T("added"), counts.added, T("modified"), counts.modified, T("deleted"), counts.deleted,
    T("conflict"), counts.conflict, T("invalid"), counts.invalid, T("selected"), counts.selected))

  if reaper.ImGui_Button(ctx, T("select_valid")) then
    for _, d in ipairs(state.import.diffs) do d.selected = d.valid and d.status ~= "unchanged" end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("select_none")) then for _, d in ipairs(state.import.diffs) do d.selected = false end end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("apply_selected")) then apply_import_diff() end

  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() |
    reaper.ImGui_TableFlags_ScrollX() | reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_Resizable()
  if reaper.ImGui_BeginTable(ctx, "ImportDiffTable", 9, flags, -1, 420) then
    reaper.ImGui_TableSetupColumn(ctx, "✓", reaper.ImGui_TableColumnFlags_WidthFixed(), 28)
    reaper.ImGui_TableSetupColumn(ctx, T("status"), reaper.ImGui_TableColumnFlags_WidthFixed(), 85)
    reaper.ImGui_TableSetupColumn(ctx, T("id"), reaper.ImGui_TableColumnFlags_WidthFixed(), 45)
    reaper.ImGui_TableSetupColumn(ctx, T("current"), reaper.ImGui_TableColumnFlags_WidthFixed(), 180)
    reaper.ImGui_TableSetupColumn(ctx, T("incoming"), reaper.ImGui_TableColumnFlags_WidthFixed(), 180)
    reaper.ImGui_TableSetupColumn(ctx, T("start"), reaper.ImGui_TableColumnFlags_WidthFixed(), 105)
    reaper.ImGui_TableSetupColumn(ctx, T("finish"), reaper.ImGui_TableColumnFlags_WidthFixed(), 105)
    reaper.ImGui_TableSetupColumn(ctx, T("owner"), reaper.ImGui_TableColumnFlags_WidthFixed(), 95)
    reaper.ImGui_TableSetupColumn(ctx, T("issue"), reaper.ImGui_TableColumnFlags_WidthFixed(), 220)
    reaper.ImGui_TableHeadersRow(ctx)

    for i, d in ipairs(state.import.diffs) do
      reaper.ImGui_PushID(ctx, i)
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_TableNextColumn(ctx)
      local c, v = reaper.ImGui_Checkbox(ctx, "##select", d.selected)
      if c and d.valid then d.selected = v end
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, status_text(d.status))
      local num = d.incoming and d.incoming.number or (d.current and d.current.number or 0)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, num and ("R" .. tostring(num)) or "-")
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, d.current and d.current.name or "-")
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, d.incoming and d.incoming.name or "-")
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, d.incoming and d.incoming.start_sec and format_time(d.incoming.start_sec) or (d.current and format_time(d.current.start_sec) or "-"))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, d.incoming and d.incoming.end_sec and format_time(d.incoming.end_sec) or (d.current and format_time(d.current.end_sec) or "-"))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, d.incoming and d.incoming.owner or (d.current and d.current.owner or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, d.reason or "")
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end

  if #state.import.issues > 0 then
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, T("issue") .. " (" .. tostring(#state.import.issues) .. ")")
    local issues_visible = imgui_begin_child("Issues", -1, 130, true, 0)
    if issues_visible then
      for _, issue in ipairs(state.import.issues) do
        reaper.ImGui_TextWrapped(ctx, string.format("[%s] Row %s %s", issue.severity, tostring(issue.row), issue.message))
      end
      reaper.ImGui_EndChild(ctx)
    end
  end
end

local function render_report_tab()
  if reaper.ImGui_Button(ctx, T("export_report")) then export_report() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("clear_report")) then state.report = {} end
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_BeginTable(ctx, "ReportTable", 4, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_ScrollY(), -1, -1) then
    reaper.ImGui_TableSetupColumn(ctx, T("timestamp"), reaper.ImGui_TableColumnFlags_WidthFixed(), 145)
    reaper.ImGui_TableSetupColumn(ctx, T("action"), reaper.ImGui_TableColumnFlags_WidthFixed(), 110)
    reaper.ImGui_TableSetupColumn(ctx, T("details"), reaper.ImGui_TableColumnFlags_WidthFixed(), 400)
    reaper.ImGui_TableSetupColumn(ctx, "Result", reaper.ImGui_TableColumnFlags_WidthFixed(), 70)
    reaper.ImGui_TableHeadersRow(ctx)
    for _, r in ipairs(state.report) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, r.time)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, r.action)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, r.details)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, r.result)
    end
    reaper.ImGui_EndTable(ctx)
  end
end

local function render_bulk_popup()
  if state.open_bulk then reaper.ImGui_OpenPopup(ctx, "BulkRenameModal"); state.open_bulk = false end
  if reaper.ImGui_BeginPopupModal(ctx, "BulkRenameModal", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_SetNextItemWidth(ctx, 180)
    local tc, tv = combo(ctx, T("rename_target") .. "##target", bulk.target, {selected=T("target_selected"), filtered=T("target_filtered")})
    if tc then bulk.target = tv end
    reaper.ImGui_SetNextItemWidth(ctx, 220)
    local pc, pv = combo(ctx, T("preset") .. "##preset", bulk.preset, {
      prefix=T("prefix"), suffix=T("suffix"), find_replace=T("find_replace"), sequential=T("sequential"),
      uppercase=T("uppercase"), lowercase=T("lowercase"), spaces_underscore=T("spaces_underscore"), template=T("template")
    })
    if pc then
      bulk.preset = pv
      -- Sequential numbering always opens in the common 01, 02, 03 format.
      if pv == "sequential" then
        bulk.start_number = 1
        bulk.digits = 2
      end
    end

    if bulk.preset == "prefix" or bulk.preset == "suffix" then
      local c, v = reaper.ImGui_InputText(ctx, T("value") .. "##value", bulk.value); if c then bulk.value = v end
    elseif bulk.preset == "find_replace" then
      local c1, v1 = reaper.ImGui_InputText(ctx, T("find") .. "##find", bulk.find); if c1 then bulk.find = v1 end
      local c2, v2 = reaper.ImGui_InputText(ctx, T("replace") .. "##replace", bulk.replace); if c2 then bulk.replace = v2 end
    elseif bulk.preset == "sequential" or bulk.preset == "template" then
      local c1, v1 = reaper.ImGui_InputInt(ctx, T("start_number"), bulk.start_number)
      if c1 then bulk.start_number = math.max(0, v1) end
      reaper.ImGui_Text(ctx, T("number_format"))
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "1##digits1") then bulk.digits = 1 end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "01##digits2") then bulk.digits = 2 end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "001##digits3") then bulk.digits = 3 end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, T("reset_01") .. "##reset01") then
        bulk.start_number, bulk.digits = 1, 2
      end
      reaper.ImGui_TextDisabled(ctx, T("sequence_hint"))
      local number_targets = bulk_target_rows()
      local first_number = format_sequence_number(1)
      local last_number = #number_targets > 0 and format_sequence_number(#number_targets) or first_number
      reaper.ImGui_Text(ctx, "Range: " .. first_number .. " ~ " .. last_number)
      reaper.ImGui_Text(ctx, "Preview: " .. first_number .. ", " ..
        format_sequence_number(2) .. ", " .. format_sequence_number(3) .. " ...")
      if bulk.preset == "template" then
        local c3, v3 = reaper.ImGui_InputText(ctx, T("template") .. "##template", bulk.template); if c3 then bulk.template = v3 end
        reaper.ImGui_TextWrapped(ctx, "Tokens: {name} {index} {number} {owner}")
      end
    end

    local targets = bulk_target_rows()
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, T("preview") .. " (" .. tostring(#targets) .. ")")
    local preview_visible = imgui_begin_child("BulkPreview", 520, 180, true, 0)
    if preview_visible then
      for i = 1, math.min(#targets, 30) do
        reaper.ImGui_Text(ctx, targets[i].name .. "  →  " .. renamed_value(targets[i], i))
      end
      if #targets > 30 then reaper.ImGui_Text(ctx, "…") end
      reaper.ImGui_EndChild(ctx)
    end
    if reaper.ImGui_Button(ctx, T("stage_rename")) then stage_bulk_rename(); reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("cancel")) then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function render_settings_popup()
  if state.open_settings then reaper.ImGui_OpenPopup(ctx, "SettingsModal"); state.open_settings = false end
  if reaper.ImGui_BeginPopupModal(ctx, "SettingsModal", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_SetNextItemWidth(ctx, 180)
    local lc, lv = combo(ctx, T("language") .. "##lang", settings.language, {ko="한국어", en="English"})
    if lc then settings.language = lv end
    local ac, av = reaper.ImGui_InputText(ctx, T("author") .. "##author", settings.author)
    if ac then settings.author = av end
    local rc, rv = reaper.ImGui_Checkbox(ctx, T("auto_refresh"), settings.auto_refresh); if rc then settings.auto_refresh = rv end
    local bc, bv = reaper.ImGui_Checkbox(ctx, T("utf8_bom"), settings.utf8_bom); if bc then settings.utf8_bom = bv end
    local ec, ev = reaper.ImGui_Checkbox(ctx, T("export_only_enabled"), settings.export_only_enabled); if ec then settings.export_only_enabled = ev end
    local pc, pv = reaper.ImGui_InputInt(ctx, T("page_size"), settings.page_size)
    if pc then settings.page_size = clamp(pv, 25, 1000); state.filter_dirty = true end
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local tc, tv = combo(ctx, T("time_format") .. "##timeformat", settings.time_format, {
      project=T("time_project"), clock=T("time_clock"), seconds=T("time_seconds")
    })
    if tc then
      settings.time_format = tv
      for _, row in ipairs(state.rows) do
        row.start_text, row.end_text = format_time(row.start_sec), format_time(row.end_sec)
        row.original.start_text, row.original.end_text = row.start_text, row.end_text
      end
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, T("dependency"))
    reaper.ImGui_Text(ctx, T("modern_api") .. ": " .. (has_modern_region_api and T("installed") or "Fallback mode"))
    reaper.ImGui_Text(ctx, T("js_api") .. ": " .. (has_js and T("installed") or T("missing_optional")))
    reaper.ImGui_Text(ctx, "REAPER: " .. tostring(reaper.GetAppVersion()))
    reaper.ImGui_Text(ctx, "ReaImGui: " .. tostring(reaper.ImGui_GetVersion and reaper.ImGui_GetVersion() or "Installed"))

    if #settings.recent_files > 0 and reaper.ImGui_Button(ctx, T("clear_recent")) then settings.recent_files = {} end
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, T("save")) then save_settings(); reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("cancel")) then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function render_help_popup()
  if state.open_help then reaper.ImGui_OpenPopup(ctx, "HelpModal"); state.open_help = false end
  if reaper.ImGui_BeginPopupModal(ctx, "HelpModal", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_Text(ctx, APP_NAME .. " v" .. APP_VERSION)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, T("help_text"))
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, T("keyboard"))
    reaper.ImGui_TextWrapped(ctx, T("shortcut_text"))
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, T("project_id") .. ": " .. project_uid)
    reaper.ImGui_Text(ctx, T("csv_schema") .. ": " .. SCHEMA_VERSION)
    if reaper.ImGui_Button(ctx, T("export_example")) then export_example_csv() end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("close")) then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function handle_shortcuts()
  if not reaper.ImGui_IsKeyPressed or not reaper.ImGui_GetKeyMods then return end
  local ok_mods, mods = pcall(reaper.ImGui_GetKeyMods, ctx)
  if not ok_mods then ok_mods, mods = pcall(reaper.ImGui_GetKeyMods) end
  if not ok_mods then return end
  local ctrl = reaper.ImGui_Mod_Ctrl and ((mods & reaper.ImGui_Mod_Ctrl()) ~= 0)
  if ctrl and reaper.ImGui_Key_S and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) then apply_staged_changes() end
  if ctrl and reaper.ImGui_Key_R and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_R()) then refresh_regions(false) end
  if ctrl and reaper.ImGui_Key_F and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F()) then state.focus_search = true end
  if reaper.ImGui_Key_Delete and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) then
    for _, row in ipairs(state.rows) do
      if row.selected then row.pending_delete = true; recompute_row_dirty(row) end
    end
    recompute_counts()
  end
end

-- -----------------------------------------------------------------------------
-- Main loop
-- -----------------------------------------------------------------------------
refresh_regions(true)
if not has_native_region_hidden and has_legacy_region_hidden then
  set_message(T("hidden_requires") .. "  Current: " .. REAPER_VERSION_TEXT, "warning")
elseif not has_native_region_hidden then
  set_message(T("hidden_failed") .. "  Current: " .. REAPER_VERSION_TEXT, "error")
end

local function main_loop()
  local visible, open = reaper.ImGui_Begin(ctx, APP_NAME .. " v" .. APP_VERSION, true,
    reaper.ImGui_WindowFlags_MenuBar())
  if visible then
    handle_shortcuts()

    if reaper.ImGui_BeginMenuBar(ctx) then
      if reaper.ImGui_BeginMenu(ctx, "File") then
        if reaper.ImGui_MenuItem(ctx, T("import_csv")) then choose_import_file() end
        if reaper.ImGui_MenuItem(ctx, T("export_csv")) then export_current_csv() end
        if reaper.ImGui_MenuItem(ctx, T("export_report")) then export_report() end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_MenuItem(ctx, T("close")) then open = false end
        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, "Edit") then
        if reaper.ImGui_MenuItem(ctx, T("apply_changes"), "Ctrl+S") then apply_staged_changes() end
        if reaper.ImGui_MenuItem(ctx, T("discard_changes")) then discard_changes() end
        if reaper.ImGui_MenuItem(ctx, T("bulk_rename")) then state.open_bulk = true end
        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, T("help")) then
        if reaper.ImGui_MenuItem(ctx, T("help")) then state.open_help = true end
        if reaper.ImGui_MenuItem(ctx, T("settings")) then state.open_settings = true end
        reaper.ImGui_EndMenu(ctx)
      end
      reaper.ImGui_EndMenuBar(ctx)
    end

    render_toolbar()
    render_message_bar()
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then
      if reaper.ImGui_BeginTabItem(ctx, T("regions")) then
        state.active_tab = "regions"
        render_regions_tab()
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, T("import_preview")) then
        state.active_tab = "import"
        render_import_tab()
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, T("report") .. " (" .. tostring(#state.report) .. ")") then
        state.active_tab = "report"
        render_report_tab()
        reaper.ImGui_EndTabItem(ctx)
      end
      reaper.ImGui_EndTabBar(ctx)
    end

    render_bulk_popup()
    render_settings_popup()
    render_help_popup()
    reaper.ImGui_End(ctx)
  end

  if settings.auto_refresh and reaper.time_precise() > state.suppress_change_check_until then
    local change = reaper.GetProjectStateChangeCount(0)
    if change ~= state.last_project_change then
      if state.dirty_count == 0 then refresh_regions(true) else state.external_change = true end
      state.last_project_change = change
    end
  end

  if open then
    reaper.defer(main_loop)
  else
    save_settings()
    if reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
  end
end

reaper.defer(main_loop)
