-- @description Region Sync Manager - CSV collaboration tool
-- @version 1.0.3
-- @author Yoon-Soo Lee
-- @changelog
--   + 1.0.3: enables ReaImGui docking, removes forced undock resize, and narrows the Note column/default width.
--   + 1.0.2: opens wide enough to show the Note column and preserves safe floating geometry.
--   + Dock/undock transitions no longer save unstable dock-node dimensions.
--   + 1.0.1: fixed repeated numeric suffixes, added selected-region bulk delete,
--     and replaced the fragile recent-files arrow popup with a sanitized button.
--   + Verified compatibility target: REAPER 7.76.
--   + 1.0.0 maintenance: restored the proven crash-safe Apply path.
--   + Soft orange highlight for modified region rows.
--   + Keeps staged region editing, CSV workflows, Region QC, 3-way merge,
--     automatic backups, recovery drafts, bilingual UI, and diagnostics.
-- @about
--   # Region Sync Manager
--   Manage and collaborate on REAPER regions with staged editing and CSV workflows.
--   ## Features
--   - Safe staged region editing
--   - CSV import and export
--   - UID-based diff and 3-way merge
--   - Region QC and bulk tools
--   - Automatic backups and crash-recovery drafts
--   - Saved window geometry and diagnostic logs
--   - English and Korean interface
--   ## Requirements
--   - REAPER
--   - ReaImGui
--   - js_ReaScriptAPI is optional for native file dialogs
--   - REAPER 7.62 or newer is recommended for native hidden-region support
--   - Tested target: REAPER 7.76
--   ## License
--   Copyright (c) 2026 Yoon-Soo Lee. All rights reserved.
--   Redistribution, resale, or secondary distribution requires written permission.
-- @provides
--   [main] .
--
-- Copyright (C) 2026 Yoon-Soo Lee. All rights reserved.
-- See LICENSE.md in the distribution repository for permitted use.

local APP_NAME = "Region Sync Manager"
local APP_VERSION = "1.0.3"
local EXT_SECTION = "REGION_SYNC_MANAGER"
local PROJECT_SECTION = "REGION_SYNC_MANAGER_V2"
local SCHEMA_VERSION = "2"
local EPSILON = 0.0005
local MODIFIED_ROW_COLOR = 0xD3945238 -- muted orange, low alpha
local DEFAULT_WINDOW_W = 1120
local DEFAULT_WINDOW_H = 780
local WINDOW_GEOMETRY_VERSION = 4

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

-- Stability mode: use numeric marker/region APIs for both reading and writing.
-- ProjectMarker userdata remains detected for diagnostics but is intentionally
-- not used because a native pointer failure can terminate the REAPER process.
local SAFE_NUMERIC_REGION_MODE = true
local use_pointer_region_api = has_modern_region_api and not SAFE_NUMERIC_REGION_MODE

local function parse_reaper_version()
  local text = tostring(reaper.GetAppVersion and reaper.GetAppVersion() or "0.0")
  local major, minor = text:match("^(%d+)%.(%d+)")
  return tonumber(major) or 0, tonumber(minor) or 0, text
end

local REAPER_MAJOR, REAPER_MINOR, REAPER_VERSION_TEXT = parse_reaper_version()
-- Native per-region B_HIDDEN writing is only available in REAPER 7.62+.
local has_native_region_hidden = use_pointer_region_api and
  (REAPER_MAJOR > 7 or (REAPER_MAJOR == 7 and REAPER_MINOR >= 62))
-- Older REAPER versions use a reversible compatibility mode:
-- hiding removes the live region but stores every field in project ExtState.
local has_legacy_region_hidden =
  not has_native_region_hidden and reaper.AddProjectMarker2 ~= nil and reaper.DeleteProjectMarker ~= nil

local context_flags = 0
if reaper.ImGui_ConfigFlags_DockingEnable then
  context_flags = context_flags | reaper.ImGui_ConfigFlags_DockingEnable()
end
local ctx = reaper.ImGui_CreateContext(APP_NAME, context_flags)

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
    create_items = "Create Regions from Items",
    import_csv = "Import CSV",
    export_csv = "Export CSV",
    apply_changes = "Apply",
    discard_changes = "Discard",
    bulk_rename = "Rename",
    settings = "Settings",
    help = "Help",
    regions = "Regions",
    import_preview = "Preview",
    report = "Report",
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
    hidden_failed = "Could not update the hidden state.",
    hidden_requires = "REAPER 7.62+ is required for native hidden-state support. Compatibility mode is active.",
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
    dirty_banner = "You have unapplied changes.",
    external_banner = "The REAPER timeline changed.",
    reload = "Reload",
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
    apply_selected = "Apply selected",
    select_valid = "Select valid",
    select_none = "Select none",
    mark_selected_delete = "Mark selected for deletion",
    unmark_selected_delete = "Cancel selected deletion",
    source_file = "Source",
    project_mismatch = "CSV ProjectID differs from the current project.",
    validation_errors = "Some CSV rows are invalid and cannot be applied.",
    no_preview = "Choose a CSV file to preview changes.",
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
    clear_report = "Clear",
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
    shortcut_text = "Ctrl+Enter Apply  |  Ctrl+S Save REAPER project  |  Ctrl+R Refresh  |  Ctrl+F Search  |  Delete Mark selected rows for deletion",
    help_text = "Export regions to CSV, edit the file, import it, review the changes, and apply them. Replace All can delete regions missing from the CSV, so a backup is created first.",
    save_failed = "Could not save the file.",
    saved = "Saved",
    ctrl_s_reserved = "Ctrl+S is reserved for saving the REAPER project. Use Ctrl+Enter or the Apply button for region edits.",
    loaded = "Loaded",
    apply_failed = "Some operations failed. Review the report.",
    apply_complete = "Changes applied.",
    confirm_replace = "Replace All may delete current regions missing from the CSV. Continue?",
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
    stage_rename = "Stage Rename",
    nothing_selected = "No target rows.",
    project_id = "Project ID",
    csv_schema = "CSV Schema",
    pending = "Pending",
    count_summary = "Total %d · Selected %d · Modified %d · Errors %d",
    backup_created = "Backup CSV created",
    file_error = "File error",
    warning = "Warning",
    info = "Info",
    old_csv = "Legacy CSV detected. It was converted to Schema v2 in memory.",
    export_only_enabled = "Export enabled regions only",
    time_format = "Time display",
    time_project = "Project format",
    time_clock = "HH:MM:SS.mmm",
    time_seconds = "Seconds",
    language = "Language",
    file_menu = "File",
    edit_menu = "Edit",
    all = "All",
    fallback_mode = "Fallback mode",
    current_version = "Current",
    tokens = "Tokens",
    legacy_none = "Legacy / None",
    continue_without_backup = "Continue without a backup?",
    result = "Result",
    range = "Range",
    export_diagnostics = "Export Diagnostic Log",
    diagnostics_saved = "Diagnostic log saved",
    diagnostics_failed = "Could not save diagnostic log",
    backup_required_failed = "Automatic backup failed. Apply was canceled.",
    transaction_rolled_back = "The operation failed and all changes were rolled back.",
    recovery_title = "Recover Unapplied Edits",
    recovery_found = "Unapplied edits from a previous interrupted session were found.",
    restore_edits = "Restore edits",
    discard_recovery = "Discard recovery",
    recovery_restored = "Recovered unapplied edits.",
    recovery_no_match = "No matching regions were found for the recovery data.",
    finish_staged_first = "Apply or discard the current staged edits first.",
    qc = "Region QC",
    run_qc = "Run QC",
    fix_safe = "Fix safe issues",
    fix = "Fix",
    qc_no_issues = "No QC issues found.",
    qc_summary = "Errors %d · Warnings %d · Info %d",
    qc_overlap = "Region overlap",
    qc_gap = "Gap between regions",
    qc_short = "Region is shorter than the minimum length",
    qc_duplicate_name = "Duplicate region name",
    qc_duplicate_number = "Duplicate region number",
    qc_missing_owner = "Owner is empty",
    qc_missing_note = "Note is empty",
    qc_outside = "Region is outside the project range",
    qc_off_grid = "Start or end is off grid",
    qc_thresholds = "QC thresholds",
    min_length = "Minimum length",
    gap_threshold = "Gap threshold",
    check_notes = "Require notes",
    check_grid = "Check grid alignment",
    three_way = "3-Way Merge",
    three_way_active = "Baseline data found. Non-conflicting changes are merged automatically.",
    three_way_conflict = "Both the project and CSV changed the same field",
    merged = "Auto-merged",
    baseline = "Baseline",

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
    mark_selected_delete = "선택 리전 삭제 표시",
    unmark_selected_delete = "선택 리전 삭제 취소",
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
    shortcut_text = "Ctrl+Enter 변경 적용  |  Ctrl+S REAPER 프로젝트 저장  |  Ctrl+R 새로고침  |  Ctrl+F 검색  |  Delete 선택 행 삭제 표시",
    help_text = "CSV를 내보내 협업 편집한 뒤 다시 가져오고, 차이 미리보기에서 작업을 선택한 다음 적용합니다. 전체 교체는 CSV에 없는 현재 리전을 삭제할 수 있어 적용 전에 자동 백업 CSV를 생성합니다.",
    save_failed = "파일을 저장하지 못했습니다.",
    saved = "저장 완료",
    ctrl_s_reserved = "Ctrl+S는 REAPER 프로젝트 저장용입니다. 리전 변경 적용은 Ctrl+Enter 또는 Apply 버튼을 사용하세요.",
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
    hidden_requires = "기본 숨김 상태 지원에는 REAPER 7.62 이상이 필요합니다. 현재 호환 모드로 작동합니다.",
    file_menu = "파일",
    edit_menu = "편집",
    all = "전체",
    fallback_mode = "호환 모드",
    current_version = "현재 버전",
    tokens = "토큰",
    legacy_none = "구형 형식 / 없음",
    continue_without_backup = "백업 없이 계속할까요?",
    result = "결과",
    range = "범위",
    export_diagnostics = "진단 로그 내보내기",
    diagnostics_saved = "진단 로그를 저장했습니다",
    diagnostics_failed = "진단 로그를 저장하지 못했습니다",
    backup_required_failed = "자동 백업에 실패하여 적용을 취소했습니다.",
    transaction_rolled_back = "작업 중 오류가 발생해 모든 변경사항을 되돌렸습니다.",
    recovery_title = "미적용 편집 복구",
    recovery_found = "이전 비정상 종료에서 적용하지 못한 편집 내용을 찾았습니다.",
    restore_edits = "편집 복구",
    discard_recovery = "복구 데이터 삭제",
    recovery_restored = "미적용 편집 내용을 복구했습니다.",
    recovery_no_match = "복구 데이터와 일치하는 리전을 찾지 못했습니다.",
    finish_staged_first = "현재 미적용 편집을 먼저 적용하거나 취소해주세요.",
    qc = "리전 QC",
    run_qc = "QC 검사",
    fix_safe = "안전 항목 일괄 수정",
    fix = "수정",
    qc_no_issues = "QC 문제가 없습니다.",
    qc_summary = "오류 %d · 경고 %d · 정보 %d",
    qc_overlap = "리전 겹침",
    qc_gap = "리전 사이 빈 구간",
    qc_short = "리전 길이가 최소 기준보다 짧습니다",
    qc_duplicate_name = "리전 이름 중복",
    qc_duplicate_number = "리전 번호 중복",
    qc_missing_owner = "담당자가 비어 있습니다",
    qc_missing_note = "메모가 비어 있습니다",
    qc_outside = "리전이 프로젝트 범위를 벗어났습니다",
    qc_off_grid = "시작 또는 종료 지점이 그리드에서 벗어났습니다",
    qc_thresholds = "QC 기준",
    min_length = "최소 리전 길이",
    gap_threshold = "빈 구간 기준",
    check_notes = "메모 필수 검사",
    check_grid = "그리드 정렬 검사",
    three_way = "3-Way 병합",
    three_way_active = "기준 데이터가 있습니다. 충돌하지 않는 변경은 자동 병합됩니다.",
    three_way_conflict = "프로젝트와 CSV가 같은 항목을 서로 다르게 수정했습니다",
    merged = "자동 병합",
    baseline = "기준값",

  }
}

local settings = {
  language = "en",
  author = "",
  auto_refresh = true,
  utf8_bom = true,
  page_size = 200,
  recent_files = {},
  last_csv_path = "",
  export_only_enabled = false,
  time_format = "clock",
  window_x = nil,
  window_y = nil,
  window_w = DEFAULT_WINDOW_W,
  window_h = DEFAULT_WINDOW_H,
  qc_min_length = 0.100,
  qc_gap_threshold = 0.050,
  qc_require_notes = false,
  qc_check_grid = true,
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
  if type(t) ~= "table" then return "" end
  for _, item in ipairs(t) do
    -- string.gsub returns both the encoded string and replacement count.
    -- Keep only the encoded string, and ignore malformed non-string entries.
    if item ~= nil then
      local encoded = url_encode(tostring(item))
      out[#out + 1] = encoded
    end
  end
  return table.concat(out, "|")
end

local function sanitize_recent_files()
  local clean, seen = {}, {}
  if type(settings.recent_files) ~= "table" then settings.recent_files = {} end
  for _, raw_path in ipairs(settings.recent_files) do
    local path = trim(raw_path)
    local key = path:lower()
    if path ~= "" and not seen[key] then
      seen[key] = true
      clean[#clean + 1] = path
      if #clean >= 8 then break end
    end
  end
  settings.recent_files = clean
end

local function load_settings()
  local function get(key, default)
    local v = reaper.GetExtState(EXT_SECTION, key)
    if v == "" then return default end
    return v
  end
  settings.language = get("language", settings.language)
  if settings.language ~= "ko" then settings.language = "en" end
  settings.author = get("author", settings.author)
  settings.auto_refresh = bool_from_string(get("auto_refresh", "true"), true)
  settings.utf8_bom = bool_from_string(get("utf8_bom", "true"), true)
  settings.page_size = clamp(tonumber(get("page_size", tostring(settings.page_size))) or 200, 25, 1000)
  settings.last_csv_path = get("last_csv_path", "")
  settings.recent_files = split_pipe(get("recent_files", ""))
  settings.export_only_enabled = bool_from_string(get("export_only_enabled", "false"), false)
  settings.time_format = get("time_format", "clock")
  settings.window_x = tonumber(get("window_x", ""))
  settings.window_y = tonumber(get("window_y", ""))
  local stored_geometry_version = tonumber(get("window_geometry_version", "0")) or 0
  local stored_window_w = tonumber(get("window_w", tostring(settings.window_w))) or DEFAULT_WINDOW_W
  local stored_window_h = tonumber(get("window_h", tostring(settings.window_h))) or DEFAULT_WINDOW_H
  if stored_geometry_version < WINDOW_GEOMETRY_VERSION then
    settings.window_w = DEFAULT_WINDOW_W
    settings.window_h = math.max(stored_window_h, DEFAULT_WINDOW_H)
  else
    settings.window_w = clamp(stored_window_w, DEFAULT_WINDOW_W, 4000)
    settings.window_h = clamp(stored_window_h, 520, 3000)
  end
  settings.qc_min_length = clamp(tonumber(get("qc_min_length", tostring(settings.qc_min_length))) or 0.1, 0, 3600)
  settings.qc_gap_threshold = clamp(tonumber(get("qc_gap_threshold", tostring(settings.qc_gap_threshold))) or 0.05, 0, 3600)
  settings.qc_require_notes = bool_from_string(get("qc_require_notes", "false"), false)
  settings.qc_check_grid = bool_from_string(get("qc_check_grid", "true"), true)
  sanitize_recent_files()
end

local diagnostic_add

local function save_settings()
  -- Normalize all persisted values so a malformed runtime value cannot abort
  -- the whole ReaScript while the Settings popup is being saved.
  if type(settings.recent_files) ~= "table" then settings.recent_files = {} end
  settings.language = settings.language == "ko" and "ko" or "en"
  settings.author = tostring(settings.author or "")
  settings.last_csv_path = tostring(settings.last_csv_path or "")
  settings.time_format = tostring(settings.time_format or "clock")
  settings.page_size = clamp(tonumber(settings.page_size) or 200, 25, 1000)
  settings.window_w = clamp(tonumber(settings.window_w) or DEFAULT_WINDOW_W, DEFAULT_WINDOW_W, 4000)
  settings.window_h = clamp(tonumber(settings.window_h) or DEFAULT_WINDOW_H, 520, 3000)
  settings.qc_min_length = clamp(tonumber(settings.qc_min_length) or 0.1, 0, 3600)
  settings.qc_gap_threshold = clamp(tonumber(settings.qc_gap_threshold) or 0.05, 0, 3600)

  reaper.SetExtState(EXT_SECTION, "language", settings.language, true)
  reaper.SetExtState(EXT_SECTION, "author", settings.author, true)
  reaper.SetExtState(EXT_SECTION, "auto_refresh", tostring(settings.auto_refresh == true), true)
  reaper.SetExtState(EXT_SECTION, "utf8_bom", tostring(settings.utf8_bom == true), true)
  reaper.SetExtState(EXT_SECTION, "page_size", tostring(settings.page_size), true)
  reaper.SetExtState(EXT_SECTION, "last_csv_path", settings.last_csv_path, true)
  reaper.SetExtState(EXT_SECTION, "recent_files", join_pipe(settings.recent_files), true)
  reaper.SetExtState(EXT_SECTION, "export_only_enabled", tostring(settings.export_only_enabled == true), true)
  reaper.SetExtState(EXT_SECTION, "time_format", settings.time_format, true)
  if tonumber(settings.window_x) then reaper.SetExtState(EXT_SECTION, "window_x", tostring(math.floor(settings.window_x)), true) end
  if tonumber(settings.window_y) then reaper.SetExtState(EXT_SECTION, "window_y", tostring(math.floor(settings.window_y)), true) end
  reaper.SetExtState(EXT_SECTION, "window_w", tostring(math.floor(settings.window_w)), true)
  reaper.SetExtState(EXT_SECTION, "window_h", tostring(math.floor(settings.window_h)), true)
  reaper.SetExtState(EXT_SECTION, "window_geometry_version", tostring(WINDOW_GEOMETRY_VERSION), true)
  reaper.SetExtState(EXT_SECTION, "qc_min_length", tostring(settings.qc_min_length), true)
  reaper.SetExtState(EXT_SECTION, "qc_gap_threshold", tostring(settings.qc_gap_threshold), true)
  reaper.SetExtState(EXT_SECTION, "qc_require_notes", tostring(settings.qc_require_notes == true), true)
  reaper.SetExtState(EXT_SECTION, "qc_check_grid", tostring(settings.qc_check_grid == true), true)
  return true
end

local function try_save_settings()
  local ok, result = xpcall(save_settings, debug.traceback)
  if not ok then
    if diagnostic_add then diagnostic_add("ERROR", "Settings save failed: " .. tostring(result)) end
    return false, tostring(result)
  end
  return result ~= false, nil
end

local function close_current_popup_safe()
  local fn = reaper.ImGui_CloseCurrentPopup
  if type(fn) ~= "function" then return false end
  local ok = pcall(fn, ctx)
  if not ok then ok = pcall(fn) end
  return ok
end

load_settings()

-- -----------------------------------------------------------------------------
-- Diagnostics and window state
-- -----------------------------------------------------------------------------
local diagnostic_events = {}
local last_window_state_save = 0
local window_state_applied = false
local current_window_docked = false
local previous_window_docked = nil
local dock_transition_until = 0
local pending_float_resize_frames = 0
local clean_shutdown = false
local project_uid
local state

diagnostic_add = function(level, message)
  diagnostic_events[#diagnostic_events + 1] = {
    time = now_iso(), level = tostring(level or "INFO"), message = tostring(message or "")
  }
  if #diagnostic_events > 200 then table.remove(diagnostic_events, 1) end
end

local function diagnostic_directory()
  local sep = package.config:sub(1, 1)
  local root = reaper.GetResourcePath and reaper.GetResourcePath() or "."
  local dir = root .. sep .. "Data" .. sep .. "YSL_RegionSyncManager" .. sep .. "Logs"
  if reaper.RecursiveCreateDirectory then reaper.RecursiveCreateDirectory(dir, 0) end
  return dir, sep
end

local apply_trace_path = nil

local function reset_apply_trace(label)
  local dir, sep = diagnostic_directory()
  apply_trace_path = dir .. sep .. "RegionSync_LastApplyTrace.log"
  local file = io.open(apply_trace_path, "wb")
  if not file then return end
  file:write("Region Sync Manager apply trace\r\n")
  file:write("Generated: ", now_iso(), "\r\n")
  file:write("Version: ", APP_VERSION, "\r\n")
  file:write("Operation: ", tostring(label or ""), "\r\n\r\n")
  file:flush()
  file:close()
end

local function append_apply_trace(message)
  if not apply_trace_path then return end
  local file = io.open(apply_trace_path, "ab")
  if not file then return end
  file:write("[", now_iso(), "] ", tostring(message or ""), "\r\n")
  file:flush()
  file:close()
end

local function export_diagnostic_log(reason)
  local dir, sep = diagnostic_directory()
  local stem = dir .. sep .. "RegionSync_Diagnostic_" .. os.date("%Y%m%d_%H%M%S")
  local path, suffix = stem .. ".log", 1
  while true do
    local existing = io.open(path, "rb")
    if not existing then break end
    existing:close()
    path = stem .. "_" .. tostring(suffix) .. ".log"
    suffix = suffix + 1
  end
  local _, project_path = reaper.EnumProjects(-1, "")
  local lines = {
    "Region Sync Manager Diagnostic Log",
    "Generated: " .. now_iso(),
    "Reason: " .. tostring(reason or "manual"),
    "App version: " .. APP_VERSION,
    "REAPER: " .. tostring(reaper.GetAppVersion and reaper.GetAppVersion() or "unknown"),
    "ReaImGui: " .. tostring(reaper.ImGui_GetVersion and reaper.ImGui_GetVersion() or "unknown"),
    "OS: " .. tostring(reaper.GetOS and reaper.GetOS() or "unknown"),
    "Project: " .. tostring(project_path or ""),
    "Project ID: " .. tostring(project_uid or "not initialized"),
    "",
    "Events:"
  }
  for _, event in ipairs(diagnostic_events) do
    lines[#lines + 1] = string.format("[%s] [%s] %s", event.time, event.level, event.message)
  end
  if state then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("State: rows=%d selected=%d dirty=%d errors=%d", #state.rows, state.selected_count, state.dirty_count, state.error_count)
    lines[#lines + 1] = "Recent report:"
    for i = 1, math.min(#state.report, 50) do
      local r = state.report[i]
      lines[#lines + 1] = string.format("[%s] %s | %s | %s", r.time or "", r.action or "", r.result or "", r.details or "")
    end
  end
  local file, err = io.open(path, "wb")
  if not file then return nil, err end
  file:write(table.concat(lines, "\r\n"), "\r\n")
  file:close()
  return path
end

local function update_window_state(force)
  if not reaper.ImGui_GetWindowPos or not reaper.ImGui_GetWindowSize then return end
  local now = reaper.time_precise()
  -- Dock nodes briefly report unstable positions and dimensions while a tab is
  -- being detached or reattached. Never persist geometry from those frames.
  if current_window_docked or now < dock_transition_until then return end
  if not force and now - last_window_state_save < 1.0 then return end
  local ok_pos, x, y = pcall(reaper.ImGui_GetWindowPos, ctx)
  local ok_size, w, h = pcall(reaper.ImGui_GetWindowSize, ctx)
  if ok_pos and ok_size and w and h and w >= 100 and h >= 100 then
    settings.window_x, settings.window_y = x, y
    settings.window_w = clamp(w, DEFAULT_WINDOW_W, 4000)
    settings.window_h = clamp(h, 520, 3000)
    save_settings()
    last_window_state_save = now
  end
end

local function update_dock_transition_state()
  local docked = false
  if reaper.ImGui_IsWindowDocked then
    local ok, value = pcall(reaper.ImGui_IsWindowDocked, ctx)
    docked = ok and value == true or false
  end
  current_window_docked = docked
  if previous_window_docked == nil then
    previous_window_docked = docked
    return
  end
  if docked ~= previous_window_docked then
    previous_window_docked = docked
    dock_transition_until = reaper.time_precise() + 0.8
    pending_float_resize_frames = 0
  end
end

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
  "Note", "UpdatedBy", "UpdatedAt",
  "BaseName", "BaseStartSec", "BaseEndSec", "BaseEnabled", "BaseHidden",
  "BaseColor", "BaseNote", "BaseUpdatedBy", "BaseUpdatedAt"
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
  path = trim(path)
  if path == "" then return false, "Empty file path" end
  content = tostring(content or "")

  local parent = path_dir(path)
  if parent ~= "" and reaper.RecursiveCreateDirectory then
    pcall(reaper.RecursiveCreateDirectory, parent, 0)
  end

  local temp = path .. ".tmp"
  local f, err = io.open(temp, "wb")
  if not f then return false, tostring(err or "Could not open temporary file") end
  local ok, write_err = pcall(function()
    f:write(content)
    f:flush()
  end)
  f:close()
  if not ok then os.remove(temp); return false, tostring(write_err) end

  local old_backup = path .. ".bak"
  os.remove(old_backup)
  local had_existing = false
  local existing = io.open(path, "rb")
  if existing then
    had_existing = true
    existing:close()
    local backed_up, backup_err = os.rename(path, old_backup)
    if not backed_up then
      os.remove(temp)
      return false, "Could not create backup: " .. tostring(backup_err or "unknown error")
    end
  end

  local renamed, rename_err = os.rename(temp, path)
  if renamed then return true, nil end

  -- Some Windows environments reject rename even in the same directory.
  -- Fall back to a direct write, while keeping the previous file in .bak.
  local direct, direct_err = io.open(path, "wb")
  if direct then
    local copied, copy_err = pcall(function()
      direct:write(content)
      direct:flush()
    end)
    direct:close()
    if copied then
      os.remove(temp)
      return true, nil
    end
    direct_err = copy_err
    os.remove(path)
  end

  if had_existing then
    local backup_check = io.open(old_backup, "rb")
    if backup_check then
      backup_check:close()
      os.rename(old_backup, path)
    end
  end
  os.remove(temp)
  return false, tostring(rename_err or direct_err or "Could not replace destination file")
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

project_uid = get_project_uid()

-- -----------------------------------------------------------------------------
-- Application state
-- -----------------------------------------------------------------------------
state = {
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
  pending_apply = false,
  pending_apply_frames = 0,
  pending_refresh_frames = 0,
  open_settings = false,
  open_help = false,
  open_bulk = false,
  open_import = false,
  open_about = false,
  recovery_blob = nil,
  open_recovery = false,
  recovery_last_blob = nil,
  qc = {issues = {}, last_run = 0, counts = {error=0, warning=0, info=0}},
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


local RECOVERY_KEY = "STAGED_RECOVERY_V1"
local SESSION_KEY = "SESSION_ACTIVE_V1"

local function project_ext_get(key)
  local ok, value = reaper.GetProjExtState(0, PROJECT_SECTION, key)
  return ok == 1 and value or ""
end

local function project_ext_set(key, value)
  reaper.SetProjExtState(0, PROJECT_SECTION, key, value or "")
end

local function serialize_recovery_draft()
  if state.dirty_count == 0 then return "" end
  local lines = {"version=1", "project=" .. url_encode(project_uid), "saved=" .. url_encode(now_iso())}
  for _, row in ipairs(state.rows) do
    if row.dirty then
      local values = {
        row.uid, row.name, row.start_text, row.end_text,
        row.enabled and "1" or "0", row.hidden and "1" or "0",
        row.owner, row.note, row.pending_delete and "1" or "0"
      }
      for i, value in ipairs(values) do values[i] = url_encode(value) end
      lines[#lines + 1] = "row=" .. table.concat(values, "|")
    end
  end
  return table.concat(lines, "\n")
end

local function parse_recovery_draft(blob)
  local result = {project = "", rows = {}}
  for line in tostring(blob or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key == "project" then
      result.project = url_decode(value)
    elseif key == "row" then
      local fields = {}
      for part in (value .. "|"):gmatch("(.-)|") do fields[#fields + 1] = url_decode(part) end
      if #fields >= 9 then
        result.rows[#result.rows + 1] = {
          uid = fields[1], name = fields[2], start_text = fields[3], end_text = fields[4],
          enabled = fields[5] == "1", hidden = fields[6] == "1",
          owner = fields[7], note = fields[8], pending_delete = fields[9] == "1"
        }
      end
    end
  end
  return result
end

local function persist_recovery_draft()
  local blob = serialize_recovery_draft()
  if blob ~= state.recovery_last_blob then
    project_ext_set(RECOVERY_KEY, blob)
    state.recovery_last_blob = blob
  end
end

local function clear_recovery_draft()
  project_ext_set(RECOVERY_KEY, "")
  state.recovery_last_blob = ""
  state.recovery_blob = nil
end

-- -----------------------------------------------------------------------------
-- Region API
-- -----------------------------------------------------------------------------
local function get_region_guid(pm, internal_index)
  if use_pointer_region_api and pm then
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
  if use_pointer_region_api then
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


local function restore_recovery_draft(blob)
  local parsed = parse_recovery_draft(blob)
  if parsed.project ~= "" and parsed.project ~= project_uid then
    set_message(T("recovery_no_match"), "warning")
    return false
  end
  local by_uid = {}
  for _, row in ipairs(state.rows) do by_uid[row.uid] = row end
  local restored = 0
  for _, saved in ipairs(parsed.rows) do
    local row = by_uid[saved.uid]
    if row then
      row.name = saved.name
      row.start_text = saved.start_text
      row.end_text = saved.end_text
      row.enabled = saved.enabled
      row.hidden = saved.hidden
      row.owner = saved.owner
      row.note = saved.note
      row.pending_delete = saved.pending_delete
      recompute_row_dirty(row)
      restored = restored + 1
    end
  end
  recompute_counts()
  state.filter_dirty = true
  if restored > 0 then
    state.recovery_last_blob = serialize_recovery_draft()
    project_ext_set(RECOVERY_KEY, state.recovery_last_blob)
    set_message(T("recovery_restored"), "info")
    diagnostic_add("INFO", "Recovered " .. tostring(restored) .. " staged row(s)")
    return true
  end
  set_message(T("recovery_no_match"), "warning")
  return false
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

local function find_legacy_region_by_number(number)
  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = 0, markers + regions - 1 do
    local retval, isrgn, pos, rgnend, name, region_number, color =
      reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn and
        math.floor((region_number or -1) + 0.5) == math.floor((number or -2) + 0.5) then
      return {
        internal_index = i,
        number = region_number,
        start_sec = pos,
        end_sec = rgnend,
        name = name or "",
        color = color or 0,
      }
    end
  end
  return nil
end

local function find_region_after_add(number, start_sec, end_sec, name)
  -- Do not use ProjectMarker userdata here. A newly added region can invalidate
  -- cached native pointers on some REAPER builds. Resolve it by numeric ID and
  -- the long-standing EnumProjectMarkers3 API instead.
  local exact, fallback = nil, nil
  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = 0, markers + regions - 1 do
    local retval, isrgn, pos, rgnend, region_name, region_number, color =
      reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn then
      local same_number =
        math.floor((region_number or -1) + 0.5) == math.floor((number or -2) + 0.5)
      local same_range =
        math.abs((pos or 0) - (start_sec or 0)) < EPSILON and
        math.abs((rgnend or 0) - (end_sec or 0)) < EPSILON
      if same_number or same_range then
        local guid = get_region_guid(nil, i)
        if guid == "" then guid = "LEGACY_R" .. tostring(region_number) end
        local meta = load_region_meta(guid)
        local row = build_row({
          internal_index = i,
          guid = guid,
          number = region_number,
          name = region_name or "",
          start_sec = pos,
          end_sec = rgnend,
          hidden = false,
          color = color or 0,
          meta = meta,
        })
        if same_number and same_range and row.name == (name or "") then return row end
        fallback = fallback or row
      end
    end
  end
  return fallback
end

-- Resolve a live ProjectMarker pointer every time. Stored pointers and internal
-- indices may become stale after regions are inserted, removed or re-sorted.
local function resolve_region_pm(row)
  if not use_pointer_region_api or not row then return nil end

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

local create_backup_csv

local function snapshot_project_extstate()
  if not reaper.EnumProjExtState then return nil end
  local snapshot, index = {}, 0
  while true do
    local retval, key, value = reaper.EnumProjExtState(0, PROJECT_SECTION, index)
    if retval == 0 then break end
    snapshot[key] = value
    index = index + 1
  end
  return snapshot
end

local function restore_project_extstate(snapshot)
  if not snapshot or not reaper.EnumProjExtState then return end
  local keys, index = {}, 0
  while true do
    local retval, key = reaper.EnumProjExtState(0, PROJECT_SECTION, index)
    if retval == 0 then break end
    keys[#keys + 1] = key
    index = index + 1
  end
  for _, key in ipairs(keys) do reaper.SetProjExtState(0, PROJECT_SECTION, key, "") end
  for key, value in pairs(snapshot) do reaper.SetProjExtState(0, PROJECT_SECTION, key, value) end
end

local function enumerate_regions_numeric_snapshot()
  -- Build the pre-apply backup with numeric marker enumeration only. This keeps
  -- the entire Apply path free of ProjectMarker userdata.
  local rows = {}
  local by_number = {}
  for _, row in ipairs(state.rows or {}) do
    if not row.soft_hidden then by_number[math.floor((row.number or 0) + 0.5)] = row end
  end

  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = 0, markers + regions - 1 do
    local retval, isrgn, pos, rgnend, name, number, color = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn then
      local ref = by_number[math.floor((number or 0) + 0.5)]
      local original = ref and ref.original or nil
      rows[#rows + 1] = {
        uid = ref and ref.uid or generate_uid(),
        number = number,
        name = name or "",
        start_sec = pos or 0,
        end_sec = rgnend or 0,
        enabled = (original ~= nil and original.enabled ~= false) or
          (original == nil and (ref == nil or ref.enabled ~= false)),
        hidden = original and original.hidden == true or false,
        color = color or 0,
        status = "backup",
        note = original and original.note or (ref and ref.note or ""),
        owner = original and original.owner or (ref and ref.owner or ""),
        updated_at = original and original.updated_at or (ref and ref.updated_at or ""),
      }
    end
  end

  for _, row in ipairs(state.rows or {}) do
    if row.soft_hidden then
      local original = row.original or row
      rows[#rows + 1] = {
        uid = row.uid,
        number = original.number or row.number,
        name = original.name or row.name or "",
        start_sec = original.start_sec or row.start_sec or 0,
        end_sec = original.end_sec or row.end_sec or 0,
        enabled = original.enabled ~= false,
        hidden = true,
        color = original.color or row.color or 0,
        status = "backup",
        note = original.note or row.note or "",
        owner = original.owner or row.owner or "",
        updated_at = original.updated_at or row.updated_at or "",
      }
    end
  end

  table.sort(rows, function(a, b)
    if a.start_sec == b.start_sec then return a.number < b.number end
    return a.start_sec < b.start_sec
  end)
  return rows
end

local transaction_active = false
local ui_refresh_locked = false

local function finish_transaction_ui()
  if ui_refresh_locked then
    pcall(reaper.PreventUIRefresh, -1)
    ui_refresh_locked = false
  end
  pcall(reaper.UpdateTimeline)
  pcall(reaper.UpdateArrange)
end

local function run_safe_transaction(label, operation)
  -- Crash-safe mode: do not wrap marker edits in Undo_BeginBlock2 or
  -- PreventUIRefresh. On some REAPER/ReaImGui combinations that wrapper can
  -- terminate the host process when an InputText edit is committed and marker
  -- data is changed in the same deferred script session.
  reset_apply_trace(label)
  append_apply_trace("crash-safe transaction start")

  local actual_rows = enumerate_regions_numeric_snapshot()
  append_apply_trace("numeric region snapshot complete: " .. tostring(#actual_rows))
  local backup_path, backup_error = create_backup_csv(actual_rows)
  append_apply_trace("backup result: " .. tostring(backup_path or backup_error or "unknown"))
  if not backup_path then
    local message = T("backup_required_failed") .. " " .. tostring(backup_error or "")
    set_message(message, "error")
    diagnostic_add("ERROR", message)
    return false
  end

  local report_count = #state.report
  local call_ok, result, detail = xpcall(function()
    return operation()
  end, debug.traceback)
  local success = call_ok and result ~= false
  local error_text = call_ok and tostring(detail or "") or tostring(result)

  pcall(reaper.UpdateTimeline)
  pcall(reaper.UpdateArrange)

  if not success then
    while #state.report > report_count do table.remove(state.report, 1) end
    add_report("Apply failed", label .. " - " .. error_text, "FAILED")
    set_message(T("apply_failed") .. " " .. error_text, "error")
    append_apply_trace("crash-safe apply failed: " .. error_text)
    diagnostic_add("ERROR", label .. " failed: " .. error_text)
    return false
  end

  -- Add one normal REAPER undo point after the completed edits without keeping
  -- an open undo block around native marker API calls.
  if reaper.Undo_OnStateChangeEx2 then
    pcall(reaper.Undo_OnStateChangeEx2, 0, label, -1, -1)
  elseif reaper.Undo_OnStateChange2 then
    pcall(reaper.Undo_OnStateChange2, 0, label)
  elseif reaper.Undo_OnStateChange then
    pcall(reaper.Undo_OnStateChange, label)
  end

  append_apply_trace("crash-safe transaction complete")
  diagnostic_add("INFO", label .. " completed; backup=" .. tostring(backup_path))
  state.suppress_change_check_until = reaper.time_precise() + 1.0
  clear_recovery_draft()
  return true
end

local function update_region_row(row, undo_label)
  validate_editor_row(row)
  if row_has_errors(row) then return false, table.concat(row.errors, "; ") end

  if row.soft_hidden then
    row.updated_at = now_iso()
    if row.owner == "" then row.owner = settings.author end
    if row.hidden then
      upsert_soft_hidden_record(row)
      add_report(undo_label or "Update", string.format("R%d %s [hidden]", row.number, row.name), "OK")
      return true
    end
    append_apply_trace(string.format("R%d restore hidden region", row.number))
    local shown, show_err = soft_show_region_no_undo(row)
    if not shown then return false, show_err end
    add_report(undo_label or "Update", string.format("R%d %s", row.number, row.name), "OK")
    return true
  end

  local region_number = math.floor((tonumber(row.number) or 0) + 0.5)
  local start_sec = tonumber(row.start_sec) or 0
  local end_sec = tonumber(row.end_sec) or 0
  local name = tostring(row.name or "")
  local color = tonumber(row.color) or 0
  append_apply_trace(string.format(
    "R%d before legacy marker update name=%q start=%.9f end=%.9f",
    region_number, name, start_sec, end_sec))

  -- Prefer the long-established SetProjectMarker3 path for normal names. It
  -- avoids ProjectMarker userdata and avoids SetProjectMarker4 unless the name
  -- must be explicitly cleared.
  local ok = false
  if name ~= "" and reaper.SetProjectMarker3 then
    ok = reaper.SetProjectMarker3(0, region_number, true, start_sec, end_sec, name, color)
    append_apply_trace(string.format("R%d SetProjectMarker3 returned %s", region_number, tostring(ok)))
  elseif reaper.SetProjectMarker4 then
    ok = reaper.SetProjectMarker4(0, region_number, true, start_sec, end_sec, name, color, 1)
    append_apply_trace(string.format("R%d SetProjectMarker4(clear-name) returned %s", region_number, tostring(ok)))
  end
  if not ok then return false, "REAPER rejected the region update" end

  local original_hidden = row.original and row.original.hidden == true or false
  if row.hidden ~= original_hidden then
    if row.hidden then
      append_apply_trace(string.format("R%d soft hide", region_number))
      local hidden_ok, hidden_err = soft_hide_region_no_undo(row)
      if not hidden_ok then return false, hidden_err end
    elseif original_hidden then
      append_apply_trace(string.format("R%d recreate visible", region_number))
      local old_guid = row.guid
      local deleted = reaper.DeleteProjectMarker(0, region_number, true)
      if not deleted then return false, "Could not remove hidden region before restoring it" end
      local new_number = reaper.AddProjectMarker2(
        0, true, start_sec, end_sec, name, region_number, color)
      if not new_number or new_number < 0 then return false, "Could not recreate visible region" end
      local live = find_region_after_add(new_number, start_sec, end_sec, name)
      if not live then return false, "Recreated region could not be resolved" end
      delete_region_meta(old_guid)
      row.number = live.number
      row.internal_index = live.internal_index
      row.guid = live.guid
      row.soft_hidden = false
      row.hidden = false
    end
  end

  row.updated_at = now_iso()
  if row.owner == "" then row.owner = settings.author end
  save_row_meta(row)
  add_report(undo_label or "Update", string.format("R%d %s", row.number, row.name), "OK")
  return true
end

local function apply_staged_changes()
  recompute_counts()
  if state.dirty_count == 0 then
    set_message(T("unchanged"), "info")
    return
  end
  if state.error_count > 0 then
    set_message(T("validation_errors"), "error")
    return
  end

  local success = run_safe_transaction("Region Sync Manager: apply staged changes", function()
    local deletes = {}
    for _, row in ipairs(state.rows) do
      if row.pending_delete then deletes[#deletes + 1] = row end
    end
    table.sort(deletes, function(a, b) return a.number > b.number end)

    for _, row in ipairs(deletes) do
      local ok
      if row.soft_hidden then
        ok = remove_soft_hidden_record(row.uid)
      else
        ok = reaper.DeleteProjectMarker(0, math.floor((tonumber(row.number) or 0) + 0.5), true)
      end
      if not ok then
        error(string.format("Delete failed: R%d %s", row.number, row.name))
      end
      delete_region_meta(row.guid)
      add_report("Delete", string.format("R%d %s", row.number, row.name), "OK")
    end

    for _, row in ipairs(state.rows) do
      if row.dirty and not row.pending_delete then
        append_apply_trace(string.format("apply dirty row R%d", row.number))
        local ok, err = update_region_row(row, "Edit")
        if not ok then
          error(string.format("Edit failed: R%d %s - %s", row.number, row.name, tostring(err or "")))
        end
      end
    end
    return true
  end)

  if success then
    -- Do not rebuild the table in the same frame as native marker edits.
    state.pending_refresh_frames = 2
    set_message(T("apply_complete"), "info")
  end
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
  clear_recovery_draft()
end

local function create_regions_from_selected_items()
  recompute_counts()
  if state.dirty_count > 0 then set_message(T("finish_staged_first"), "warning"); return end
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return end

  local success = run_safe_transaction("Region Sync Manager: create regions from selected items", function()
    local item_names, plain_counts, used_names, used_sequence_indices = {}, {}, {}, {}
    local function selected_item_region_name(index)
      local item = reaper.GetSelectedMediaItem(0, index)
      local take = reaper.GetActiveTake(item)
      local name = take and reaper.GetTakeName(take) or "Region"
      return tostring(name or "Region"):gsub("%.%w+$", "")
    end
    local function split_sequence_suffix(name)
      local base, digits = tostring(name or ""):match("^(.-)_(%d+)$")
      if base and base ~= "" then return base, tonumber(digits) end
      return tostring(name or ""), nil
    end
    local function reserve_name(name)
      used_names[name] = true
      local base, sequence_index = split_sequence_suffix(name)
      if sequence_index then
        used_sequence_indices[base] = used_sequence_indices[base] or {}
        used_sequence_indices[base][sequence_index] = true
      end
    end
    local function next_sequence_name(base)
      used_sequence_indices[base] = used_sequence_indices[base] or {}
      local index = 1
      while true do
        local candidate = string.format("%s_%02d", base, index)
        if not used_names[candidate] and not used_sequence_indices[base][index] then
          reserve_name(candidate)
          return candidate
        end
        index = index + 1
      end
    end

    for i = 0, count - 1 do
      local name = selected_item_region_name(i)
      item_names[i + 1] = name
      reserve_name(name)
      local _, sequence_index = split_sequence_suffix(name)
      if not sequence_index then plain_counts[name] = (plain_counts[name] or 0) + 1 end
    end
    for i = 0, count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local name = item_names[i + 1] or "Region"
      local _, sequence_index = split_sequence_suffix(name)
      if not sequence_index and (plain_counts[name] or 0) > 1 then
        name = next_sequence_name(name)
      end
      local new_number = reaper.AddProjectMarker2(0, true, pos, pos + len, name, -1, 0)
      if not new_number or new_number < 0 then error("AddProjectMarker2 failed for " .. name) end
      local new_row = find_region_after_add(new_number, pos, pos + len, name)
      if not new_row then error("Created region could not be resolved: " .. name) end
      new_row.owner = settings.author
      new_row.updated_at = now_iso()
      save_row_meta(new_row)
      add_report("Create", string.format("R%d %s", new_number, name), "OK")
    end
    return true
  end)

  if success then refresh_regions(true); set_message(T("apply_complete"), "info") end
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
        row.updated_at or "",
        row.name,
        string.format("%.9f", row.start_sec),
        string.format("%.9f", row.end_sec),
        row.enabled and "true" or "false",
        row.hidden and "true" or "false",
        tostring(math.floor(row.color or 0)),
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

create_backup_csv = function(rows)
  local _, project_path = reaper.EnumProjects(-1, "")
  local dir = project_path and project_path ~= "" and path_dir(project_path) or reaper.GetProjectPathEx(0)
  if not dir or dir == "" then return nil, "Project path is unavailable" end
  local sep = dir:match("[\\/]$") and "" or package.config:sub(1, 1)
  local stem = dir .. sep .. "RegionSync_Backup_" .. os.date("%Y%m%d_%H%M%S")
  local path, suffix = stem .. ".csv", 1
  while true do
    local f = io.open(path, "rb")
    if not f then break end
    f:close()
    path = stem .. "_" .. tostring(suffix) .. ".csv"
    suffix = suffix + 1
  end
  local ok, err = atomic_write(path, region_rows_to_csv(rows or enumerate_regions(), false))
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
      base = nil,
      errors = {}, warnings = {}, valid = true,
    }
    if index["BaseName"] then
      local bs, bs_err = parse_time_strict(val("BaseStartSec"))
      local be, be_err = parse_time_strict(val("BaseEndSec"))
      if not bs_err and not be_err then
        row.base = {
          name = val("BaseName") or "",
          start_sec = bs,
          end_sec = be,
          enabled = bool_from_string(val("BaseEnabled"), true),
          hidden = bool_from_string(val("BaseHidden"), false),
          color = tonumber(trim(val("BaseColor"))) or 0,
          note = val("BaseNote") or "",
          owner = val("BaseUpdatedBy") or "",
          updated_at = val("BaseUpdatedAt") or "",
        }
      end
    end
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

local MERGE_FIELDS = {"name", "start_sec", "end_sec", "enabled", "hidden", "color", "note", "owner"}

local function merge_field_equal(field, a, b)
  if field == "start_sec" or field == "end_sec" then
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= EPSILON
  end
  if field == "color" then return (tonumber(a) or 0) == (tonumber(b) or 0) end
  return a == b
end

local function three_way_merge(current, incoming)
  if not current or not incoming or not incoming.base then return incoming, {}, false end
  local merged = shallow_copy(incoming)
  merged.base = incoming.base
  local conflicts, auto_merged = {}, false
  for _, field in ipairs(MERGE_FIELDS) do
    local base_value = incoming.base[field]
    local current_value = current[field]
    local incoming_value = incoming[field]
    local current_changed = not merge_field_equal(field, current_value, base_value)
    local incoming_changed = not merge_field_equal(field, incoming_value, base_value)
    if current_changed and incoming_changed and not merge_field_equal(field, current_value, incoming_value) then
      conflicts[#conflicts + 1] = field
    elseif current_changed and not incoming_changed then
      merged[field] = current_value
      auto_merged = true
    end
  end
  return merged, conflicts, auto_merged
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

  for _, source_incoming in ipairs(imp.rows) do
    local incoming = source_incoming
    local current_by_uid = incoming.uid ~= "" and by_uid[incoming.uid] or nil
    local current_by_number = incoming.number and by_number[incoming.number] or nil
    local current = current_by_uid or current_by_number
    if current then matched[current.uid] = true end
    local merge_conflicts, auto_merged = {}, false
    if current and incoming.base and imp.mode ~= "name" then
      incoming, merge_conflicts, auto_merged = three_way_merge(current, incoming)
    end
    local status, reason = "added", ""
    if imp.mode == "name" and not current then
      status = "conflict"
      reason = "Names-only mode requires a matching RegionUID or RegionNumber"
    elseif not incoming.valid then
      status = "invalid"
      reason = table.concat(incoming.errors, "; ")
    elseif #merge_conflicts > 0 then
      status = "conflict"
      reason = T("three_way_conflict") .. ": " .. table.concat(merge_conflicts, ", ")
    elseif current_by_uid and current_by_number and current_by_uid ~= current_by_number then
      status = "conflict"
      reason = "RegionUID and RegionNumber point to different current regions"
    elseif current then
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
      source_incoming = source_incoming, auto_merged = auto_merged,
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

  if new_row.hidden then
    append_apply_trace(string.format("R%d imported as soft hidden", new_row.number))
    local hidden_ok, hidden_err = soft_hide_region_no_undo(new_row)
    if not hidden_ok then return false, hidden_err end
  else
    save_row_meta(new_row)
  end
  return true, new_row
end

local function apply_import_diff()
  recompute_counts()
  if state.dirty_count > 0 then set_message(T("finish_staged_first"), "warning"); return end
  local imp = state.import
  local selected_valid = 0
  for _, d in ipairs(imp.diffs) do if d.selected and d.valid then selected_valid = selected_valid + 1 end end
  if selected_valid == 0 then set_message(T("nothing_selected"), "warning"); return end

  if imp.project_mismatch then
    local answer = reaper.MB(T("project_mismatch") .. "\n\n" .. T("warning"), APP_NAME, 4)
    if answer ~= 6 then return end
  end
  if imp.mode == "replace" then
    local answer = reaper.MB(T("confirm_replace"), APP_NAME, 4)
    if answer ~= 6 then return end
  end

  local success = run_safe_transaction("Region Sync Manager: apply CSV import", function()
    local deletes = {}
    for _, d in ipairs(imp.diffs) do
      if d.selected and d.valid and d.status == "deleted" and d.current then deletes[#deletes + 1] = d.current end
    end
    table.sort(deletes, function(a, b) return a.number > b.number end)
    for _, row in ipairs(deletes) do
      local ok
      if row.soft_hidden then ok = remove_soft_hidden_record(row.uid)
      else ok = reaper.DeleteProjectMarker(0, row.number, true) end
      if not ok then error(string.format("Import delete failed: R%d %s", row.number, row.name)) end
      delete_region_meta(row.guid)
      add_report("Import Delete", string.format("R%d %s", row.number, row.name), "OK")
    end

    for _, d in ipairs(imp.diffs) do
      if d.selected and d.valid and d.status ~= "deleted" and d.status ~= "unchanged" then
        if d.status == "added" then
          local ok, result = add_import_region(d.incoming)
          if not ok then error("Import add failed: " .. tostring(result)) end
          add_report("Import Add", string.format("R%d %s", result.number, result.name), "OK")
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
          if not ok then error("Import update failed: " .. tostring(err)) end
        end
      end
    end
    return true
  end)

  if success then
    refresh_regions(true)
    build_import_diff()
    set_message(T("apply_complete"), "info")
  end
end

-- -----------------------------------------------------------------------------
-- Region QC
-- -----------------------------------------------------------------------------
local function qc_add(severity, kind, row, message, fix)
  state.qc.issues[#state.qc.issues + 1] = {severity=severity, kind=kind, row=row, message=message, fix=fix}
  state.qc.counts[severity] = (state.qc.counts[severity] or 0) + 1
end

local function run_region_qc()
  state.qc.issues = {}
  state.qc.counts = {error=0, warning=0, info=0}
  local rows = {}
  for _, row in ipairs(state.rows) do if not row.pending_delete then rows[#rows + 1] = row end end
  table.sort(rows, function(a,b) if a.start_sec == b.start_sec then return a.end_sec < b.end_sec end return a.start_sec < b.start_sec end)
  local names, numbers = {}, {}
  local project_length = reaper.GetProjectLength(0)
  for i, row in ipairs(rows) do
    validate_editor_row(row)
    local duration = (row.end_sec or 0) - (row.start_sec or 0)
    if duration < settings.qc_min_length then qc_add("warning", "short", row, T("qc_short") .. string.format(" (%.3fs)", duration)) end
    if row.start_sec < -EPSILON or row.end_sec > project_length + EPSILON then qc_add("error", "outside", row, T("qc_outside")) end
    local nk = trim(row.name):lower()
    if nk ~= "" then
      if names[nk] then qc_add("warning", "duplicate_name", row, T("qc_duplicate_name") .. ": " .. row.name) else names[nk] = row end
    end
    if numbers[row.number] then qc_add("error", "duplicate_number", row, T("qc_duplicate_number") .. ": R" .. tostring(row.number)) else numbers[row.number] = row end
    if trim(row.owner) == "" then qc_add("warning", "owner", row, T("qc_missing_owner"), "owner") end
    if settings.qc_require_notes and trim(row.note) == "" then qc_add("info", "note", row, T("qc_missing_note")) end
    if settings.qc_check_grid and reaper.SnapToGrid then
      local ss, se = reaper.SnapToGrid(0, row.start_sec), reaper.SnapToGrid(0, row.end_sec)
      if math.abs(ss-row.start_sec) > EPSILON or math.abs(se-row.end_sec) > EPSILON then qc_add("warning", "grid", row, T("qc_off_grid"), "grid") end
    end
    if i > 1 then
      local prev = rows[i-1]
      if row.start_sec < prev.end_sec - EPSILON then
        qc_add("error", "overlap", row, T("qc_overlap") .. string.format(" · R%d / R%d", prev.number, row.number))
      else
        local gap = row.start_sec - prev.end_sec
        if gap > settings.qc_gap_threshold then qc_add("info", "gap", row, T("qc_gap") .. string.format(" (%.3fs)", gap)) end
      end
    end
  end
  state.qc.last_run = reaper.time_precise()
end

local function fix_qc_issue(issue)
  local row = issue and issue.row
  if not row or not issue.fix then return false end
  if issue.fix == "owner" then
    if trim(settings.author) == "" then set_message(T("author") .. " " .. T("missing_required"), "warning"); return false end
    row.owner = settings.author
  elseif issue.fix == "grid" and reaper.SnapToGrid then
    row.start_sec = reaper.SnapToGrid(0, row.start_sec)
    row.end_sec = reaper.SnapToGrid(0, row.end_sec)
    if row.end_sec <= row.start_sec then row.end_sec = row.start_sec + math.max(settings.qc_min_length, 0.001) end
    row.start_text, row.end_text = format_time(row.start_sec), format_time(row.end_sec)
  end
  recompute_row_dirty(row); recompute_counts(); run_region_qc(); return true
end

local function fix_all_safe_qc()
  local copy = {}
  for _, issue in ipairs(state.qc.issues) do if issue.fix then copy[#copy+1] = issue end end
  for _, issue in ipairs(copy) do
    local row = issue.row
    if issue.fix == "owner" and trim(settings.author) ~= "" then row.owner = settings.author
    elseif issue.fix == "grid" and reaper.SnapToGrid then
      row.start_sec, row.end_sec = reaper.SnapToGrid(0, row.start_sec), reaper.SnapToGrid(0, row.end_sec)
      if row.end_sec <= row.start_sec then row.end_sec = row.start_sec + math.max(settings.qc_min_length, 0.001) end
      row.start_text, row.end_text = format_time(row.start_sec), format_time(row.end_sec)
    end
    recompute_row_dirty(row)
  end
  recompute_counts(); run_region_qc()
end

local function render_qc_tab()
  if reaper.ImGui_Button(ctx, T("run_qc")) then run_region_qc() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("fix_safe")) then fix_all_safe_qc() end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, string.format(T("qc_summary"), state.qc.counts.error or 0, state.qc.counts.warning or 0, state.qc.counts.info or 0))
  reaper.ImGui_SetNextItemWidth(ctx, 130)
  local c1,v1 = reaper.ImGui_InputDouble(ctx, T("min_length") .. "##qcmin", settings.qc_min_length, 0.01, 0.1, "%.3f")
  if c1 then settings.qc_min_length = clamp(v1,0,3600); save_settings() end
  reaper.ImGui_SameLine(ctx); reaper.ImGui_SetNextItemWidth(ctx, 130)
  local c2,v2 = reaper.ImGui_InputDouble(ctx, T("gap_threshold") .. "##qcgap", settings.qc_gap_threshold, 0.01, 0.1, "%.3f")
  if c2 then settings.qc_gap_threshold = clamp(v2,0,3600); save_settings() end
  reaper.ImGui_SameLine(ctx)
  local c3,v3 = reaper.ImGui_Checkbox(ctx, T("check_notes"), settings.qc_require_notes); if c3 then settings.qc_require_notes=v3; save_settings() end
  reaper.ImGui_SameLine(ctx)
  local c4,v4 = reaper.ImGui_Checkbox(ctx, T("check_grid"), settings.qc_check_grid); if c4 then settings.qc_check_grid=v4; save_settings() end
  reaper.ImGui_Separator(ctx)
  if #state.qc.issues == 0 then reaper.ImGui_TextDisabled(ctx, T("qc_no_issues")); return end
  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_Resizable()
  if reaper.ImGui_BeginTable(ctx, "QCTable", 5, flags, -1, -1) then
    reaper.ImGui_TableSetupColumn(ctx, T("status"), reaper.ImGui_TableColumnFlags_WidthFixed(), 70)
    reaper.ImGui_TableSetupColumn(ctx, T("id"), reaper.ImGui_TableColumnFlags_WidthFixed(), 55)
    reaper.ImGui_TableSetupColumn(ctx, T("name"), reaper.ImGui_TableColumnFlags_WidthFixed(), 200)
    reaper.ImGui_TableSetupColumn(ctx, T("issue"), reaper.ImGui_TableColumnFlags_WidthStretch())
    reaper.ImGui_TableSetupColumn(ctx, T("action"), reaper.ImGui_TableColumnFlags_WidthFixed(), 105)
    reaper.ImGui_TableHeadersRow(ctx)
    for i,issue in ipairs(state.qc.issues) do
      reaper.ImGui_PushID(ctx,i); reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, issue.severity:upper())
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, issue.row and ("R"..tostring(issue.row.number)) or "-")
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, issue.row and issue.row.name or "-")
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, issue.message)
      reaper.ImGui_TableNextColumn(ctx)
      if issue.row and reaper.ImGui_Button(ctx,T("go").."##qcgo") then reaper.SetEditCurPos2(0,issue.row.start_sec,true,false) end
      if issue.fix then reaper.ImGui_SameLine(ctx); if reaper.ImGui_Button(ctx,T("fix").."##qcfix") then fix_qc_issue(issue) end end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end
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

local function strip_trailing_sequence_suffixes(name, max_digits)
  local result = tostring(name or "")
  max_digits = clamp(math.floor(tonumber(max_digits) or 2), 1, 6)
  while true do
    local parent, number_text = result:match("^(.-)_(%d+)$")
    if not parent or parent == "" or #number_text > max_digits then break end
    result = parent
  end
  return result
end

local function renamed_value(row, index)
  local name = row.name
  if bulk.preset == "prefix" then return bulk.value .. name end
  if bulk.preset == "suffix" then
    local numeric_suffix = tostring(bulk.value or ""):match("^_?(%d+)$")
    if numeric_suffix then
      local base = strip_trailing_sequence_suffixes(name, #numeric_suffix)
      return base .. "_" .. numeric_suffix
    end
    if bulk.value ~= "" and name:sub(-#bulk.value) == bulk.value then return name end
    return name .. bulk.value
  end
  if bulk.preset == "find_replace" then
    if bulk.find == "" then return name end
    return name:gsub(bulk.find:gsub("([^%w])", "%%%1"), bulk.replace)
  end
  if bulk.preset == "sequential" then
    local digits = clamp(math.floor(tonumber(bulk.digits) or 2), 1, 6)
    local base = strip_trailing_sequence_suffixes(name, digits)
    return base .. "_" .. format_sequence_number(index)
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
  local sample_time = now_iso()
  local sample = {
    CSV_HEADERS,
    {SCHEMA_VERSION, project_uid, generate_uid(), "1", "SFX_Door_Close", "0.000000000", "1.250000000", "true", "false", "0", "Review", "Check tail", settings.author, sample_time,
      "SFX_Door_Close", "0.000000000", "1.250000000", "true", "false", "0", "Check tail", settings.author, sample_time},
    {SCHEMA_VERSION, project_uid, generate_uid(), "2", "AMB_Forest_Night", "2.000000000", "12.000000000", "true", "false", "0", "Approved", "Loop point checked", settings.author, sample_time,
      "AMB_Forest_Night", "2.000000000", "12.000000000", "true", "false", "0", "Loop point checked", settings.author, sample_time},
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
  local language_label = settings.language == "ko" and "언어: 한국어" or "Language: English"
  if reaper.ImGui_Button(ctx, language_label .. "##language_button") then
    reaper.ImGui_OpenPopup(ctx, "LanguagePopup")
  end
  if reaper.ImGui_BeginPopup(ctx, "LanguagePopup") then
    if reaper.ImGui_Selectable(ctx, "English", settings.language == "en") then
      settings.language = "en"
      save_settings()
    end
    if reaper.ImGui_Selectable(ctx, "한국어", settings.language == "ko") then
      settings.language = "ko"
      save_settings()
    end
    reaper.ImGui_EndPopup(ctx)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("refresh")) then refresh_regions(false) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("create_items")) then create_regions_from_selected_items() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("import_csv")) then choose_import_file() end
  sanitize_recent_files()
  if #settings.recent_files > 0 then
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("recent_files") .. "##recent_files_button") then
      reaper.ImGui_OpenPopup(ctx, "RecentFilesPopup")
    end
    if reaper.ImGui_BeginPopup(ctx, "RecentFilesPopup") then
      reaper.ImGui_Text(ctx, T("recent_files"))
      reaper.ImGui_Separator(ctx)
      for index, raw_path in ipairs(settings.recent_files) do
        local path = tostring(raw_path or "")
        local label = basename(path)
        if label == "" then label = path end
        if reaper.ImGui_Selectable(ctx, label .. "##recent_" .. tostring(index), false) then
          load_import_path(path)
        end
        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, path) end
      end
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, T("clear_recent")) then
        settings.recent_files = {}
        try_save_settings()
        close_current_popup_safe()
      end
      reaper.ImGui_EndPopup(ctx)
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("export_csv")) then export_current_csv() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("bulk_rename")) then state.open_bulk = true end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("apply_changes") .. " (" .. tostring(state.dirty_count) .. ")") then state.pending_apply_frames = 2 end
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
    all = T("all"), unchanged = T("unchanged"), modified = T("modified"), invalid = T("invalid"), deleted = T("deleted")
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

local function set_selected_delete_state(pending_delete)
  local changed = 0
  for _, row in ipairs(state.rows) do
    if row.selected then
      row.pending_delete = pending_delete == true
      recompute_row_dirty(row)
      changed = changed + 1
    end
  end
  recompute_counts()
  if changed == 0 then set_message(T("nothing_selected"), "warning") end
end

local selection_drag = { active = false, value = false }

local function set_row_selected(row, value)
  value = value == true
  if row.selected ~= value then
    row.selected = value
    recompute_counts()
  end
end

local function handle_selection_checkbox(row)
  local mouse_down = reaper.ImGui_IsMouseDown and reaper.ImGui_IsMouseDown(ctx, 0) or false
  local hovered = reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) or false
  local clicked = reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx, 0) or false

  if clicked or (hovered and mouse_down and not selection_drag.active and not reaper.ImGui_IsItemClicked) then
    selection_drag.active = true
    selection_drag.value = not row.selected
    set_row_selected(row, selection_drag.value)
    return
  end

  if hovered and mouse_down and selection_drag.active then
    set_row_selected(row, selection_drag.value)
  elseif not mouse_down then
    selection_drag.active = false
  end
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
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("mark_selected_delete") .. " (" .. tostring(state.selected_count) .. ")##bulk_delete") then
    set_selected_delete_state(true)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, T("unmark_selected_delete") .. "##bulk_undelete") then
    set_selected_delete_state(false)
  end

  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() |
    reaper.ImGui_TableFlags_ScrollX() | reaper.ImGui_TableFlags_ScrollY() |
    reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_Reorderable()
  if reaper.ImGui_BeginTable(ctx, "RegionsTable", 13, flags, -1, -1) then
    reaper.ImGui_TableSetupColumn(ctx, "✓", reaper.ImGui_TableColumnFlags_WidthFixed(), 28)
    reaper.ImGui_TableSetupColumn(ctx, T("delete"), reaper.ImGui_TableColumnFlags_WidthFixed(), 48)
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
    reaper.ImGui_TableSetupColumn(ctx, T("note"), reaper.ImGui_TableColumnFlags_WidthFixed(), 130)
    reaper.ImGui_TableHeadersRow(ctx)

    for _, row in ipairs(page_rows) do
      reaper.ImGui_PushID(ctx, row.uid)
      reaper.ImGui_TableNextRow(ctx)
      if (row.status == "modified" or row.status == "deleted") and
          reaper.ImGui_TableSetBgColor and reaper.ImGui_TableBgTarget_RowBg0 then
        reaper.ImGui_TableSetBgColor(
          ctx, reaper.ImGui_TableBgTarget_RowBg0(), MODIFIED_ROW_COLOR
        )
      end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Checkbox(ctx, "##sel", row.selected)
      handle_selection_checkbox(row)

      reaper.ImGui_TableNextColumn(ctx)
      local delete_label = row.pending_delete and "↶##delete" or "X##delete"
      if reaper.ImGui_Button(ctx, delete_label) then
        row.pending_delete = not row.pending_delete
        recompute_row_dirty(row)
        recompute_counts()
      end

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
          row.hidden = hv
          recompute_row_dirty(row)
          recompute_counts()
        end
        if not has_native_region_hidden and reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, T("hidden_requires") .. "\n" .. T("current_version") .. ": " .. REAPER_VERSION_TEXT)
        end
      else
        reaper.ImGui_Text(ctx, "N/A")
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, T("hidden_failed") .. "\n" .. T("current_version") .. ": " .. REAPER_VERSION_TEXT)
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
  reaper.ImGui_Text(ctx, T("csv_schema") .. ": " .. (state.import.schema_version or "") .. "  |  " .. T("project_id") .. ": " .. (state.import.project_id ~= "" and state.import.project_id or T("legacy_none")))
  if state.import.project_mismatch then reaper.ImGui_TextWrapped(ctx, T("project_mismatch")) end
  local has_baseline = false
  for _, row in ipairs(state.import.rows) do if row.base then has_baseline = true; break end end
  if has_baseline then reaper.ImGui_TextColored(ctx, 0x74D69BFF, T("three_way_active")) end

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
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, ((d.auto_merged and (T("merged") .. ". ") or "") .. (d.reason or "")))
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
    reaper.ImGui_TableSetupColumn(ctx, T("result"), reaper.ImGui_TableColumnFlags_WidthFixed(), 70)
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
  local popup_name = T("bulk_rename") .. "##BulkRenameModal"
  if state.open_bulk then reaper.ImGui_OpenPopup(ctx, popup_name); state.open_bulk = false end
  if reaper.ImGui_BeginPopupModal(ctx, popup_name, nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
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
      reaper.ImGui_Text(ctx, T("range") .. ": " .. first_number .. " ~ " .. last_number)
      reaper.ImGui_Text(ctx, T("preview") .. ": " .. first_number .. ", " ..
        format_sequence_number(2) .. ", " .. format_sequence_number(3) .. " ...")
      if bulk.preset == "template" then
        local c3, v3 = reaper.ImGui_InputText(ctx, T("template") .. "##template", bulk.template); if c3 then bulk.template = v3 end
        reaper.ImGui_TextWrapped(ctx, T("tokens") .. ": {name} {index} {number} {owner}")
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
    if reaper.ImGui_Button(ctx, T("stage_rename")) then stage_bulk_rename(); close_current_popup_safe() end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("cancel")) then close_current_popup_safe() end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function render_settings_popup()
  local popup_name = T("settings") .. "##SettingsModal"
  if state.open_settings then reaper.ImGui_OpenPopup(ctx, popup_name); state.open_settings = false end
  if reaper.ImGui_BeginPopupModal(ctx, popup_name, nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
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
    reaper.ImGui_Text(ctx, T("modern_api") .. ": " .. (use_pointer_region_api and T("installed") or T("fallback_mode")))
    reaper.ImGui_Text(ctx, T("js_api") .. ": " .. (has_js and T("installed") or T("missing_optional")))
    reaper.ImGui_Text(ctx, "REAPER: " .. tostring(reaper.GetAppVersion()))
    reaper.ImGui_Text(ctx, "ReaImGui: " .. tostring(reaper.ImGui_GetVersion and reaper.ImGui_GetVersion() or T("installed")))

    if #settings.recent_files > 0 and reaper.ImGui_Button(ctx, T("clear_recent")) then settings.recent_files = {} end
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, T("save")) then
      local saved_ok, saved_err = try_save_settings()
      if saved_ok then
        set_message(T("saved"), "info")
        close_current_popup_safe()
      else
        set_message(T("save_failed") .. " " .. tostring(saved_err or ""), "error")
      end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("cancel")) then close_current_popup_safe() end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function render_help_popup()
  local popup_name = T("help") .. "##HelpModal"
  if state.open_help then reaper.ImGui_OpenPopup(ctx, popup_name); state.open_help = false end
  if reaper.ImGui_BeginPopupModal(ctx, popup_name, nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
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
    if reaper.ImGui_Button(ctx, T("close")) then close_current_popup_safe() end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function render_recovery_popup()
  local popup_name = T("recovery_title") .. "##RecoveryModal"
  if state.open_recovery then reaper.ImGui_OpenPopup(ctx, popup_name); state.open_recovery = false end
  if reaper.ImGui_BeginPopupModal(ctx, popup_name, nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_TextWrapped(ctx, T("recovery_found"))
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, T("restore_edits"), 150, 28) then
      restore_recovery_draft(state.recovery_blob)
      state.recovery_blob = nil
      close_current_popup_safe()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, T("discard_recovery"), 150, 28) then
      clear_recovery_draft()
      close_current_popup_safe()
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function handle_shortcuts()
  if not reaper.ImGui_IsKeyPressed or not reaper.ImGui_GetKeyMods then return end

  -- Only react while this tool owns keyboard focus. The old global Ctrl+S
  -- handler could run at the same time as REAPER's Save Project action.
  if reaper.ImGui_IsWindowFocused then
    local focus_flags = reaper.ImGui_FocusedFlags_RootAndChildWindows and
      reaper.ImGui_FocusedFlags_RootAndChildWindows() or 0
    local focus_ok, focused = pcall(reaper.ImGui_IsWindowFocused, ctx, focus_flags)
    if not focus_ok or not focused then return end
  end

  local ok_mods, mods = pcall(reaper.ImGui_GetKeyMods, ctx)
  if not ok_mods then ok_mods, mods = pcall(reaper.ImGui_GetKeyMods) end
  if not ok_mods then return end

  local ctrl = reaper.ImGui_Mod_Ctrl and ((mods & reaper.ImGui_Mod_Ctrl()) ~= 0)
  local item_active = false
  if reaper.ImGui_IsAnyItemActive then
    local active_ok, active = pcall(reaper.ImGui_IsAnyItemActive, ctx)
    item_active = active_ok and active or false
  end

  -- Ctrl+Enter is deliberately queued. Applying after ImGui_End prevents the
  -- region list from being rebuilt while an InputText widget is still active.
  local enter_pressed =
    (reaper.ImGui_Key_Enter and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())) or
    (reaper.ImGui_Key_KeypadEnter and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter()))
  if ctrl and enter_pressed then
    state.pending_apply_frames = 2
  end

  -- Ctrl+S remains REAPER's project-save shortcut and never applies regions.
  if ctrl and reaper.ImGui_Key_S and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) then
    set_message(T("ctrl_s_reserved"), "warning")
  end

  if ctrl and not item_active and reaper.ImGui_Key_R and
      reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_R()) then
    refresh_regions(false)
  end
  if ctrl and reaper.ImGui_Key_F and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F()) then
    state.focus_search = true
  end

  -- Never treat Delete as a row-delete command while editing text.
  if not ctrl and not item_active and reaper.ImGui_Key_Delete and
      reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) then
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
local previous_session_active = project_ext_get(SESSION_KEY) == "1"
local previous_recovery_blob = project_ext_get(RECOVERY_KEY)
if previous_session_active and previous_recovery_blob ~= "" then
  state.recovery_blob = previous_recovery_blob
  state.open_recovery = true
else
  clear_recovery_draft()
end
project_ext_set(SESSION_KEY, "1")
state.recovery_last_blob = project_ext_get(RECOVERY_KEY)
diagnostic_add("INFO", "Application started")
if not has_native_region_hidden and has_legacy_region_hidden then
  set_message(T("hidden_requires") .. "  " .. T("current_version") .. ": " .. REAPER_VERSION_TEXT, "warning")
elseif not has_native_region_hidden then
  set_message(T("hidden_failed") .. "  " .. T("current_version") .. ": " .. REAPER_VERSION_TEXT, "error")
end

local function run_frame()
  -- Commit native region edits only after two complete UI frames have passed.
  -- This ensures the name InputText and the Apply button are no longer active.
  if state.pending_apply_frames and state.pending_apply_frames > 0 then
    state.pending_apply_frames = state.pending_apply_frames - 1
    if state.pending_apply_frames == 0 then
      apply_staged_changes()
    end
  end

  if state.pending_refresh_frames and state.pending_refresh_frames > 0 then
    state.pending_refresh_frames = state.pending_refresh_frames - 1
    if state.pending_refresh_frames == 0 then
      refresh_regions(true)
    end
  end
  if not window_state_applied then
    local first_use = reaper.ImGui_Cond_FirstUseEver and reaper.ImGui_Cond_FirstUseEver()
      or (reaper.ImGui_Cond_Once and reaper.ImGui_Cond_Once()) or 0
    if reaper.ImGui_SetNextWindowDockID then
      local always = reaper.ImGui_Cond_Always and reaper.ImGui_Cond_Always() or 0
      pcall(reaper.ImGui_SetNextWindowDockID, ctx, 0, always)
    end
    if settings.window_x and settings.window_y and reaper.ImGui_SetNextWindowPos then
      reaper.ImGui_SetNextWindowPos(ctx, settings.window_x, settings.window_y, first_use)
    end
    if reaper.ImGui_SetNextWindowSize then
      reaper.ImGui_SetNextWindowSize(ctx, settings.window_w, settings.window_h, first_use)
    end
    window_state_applied = true
  elseif pending_float_resize_frames > 0 then
    pending_float_resize_frames = 0
  end

  local visible, open = reaper.ImGui_Begin(ctx, APP_NAME .. " v" .. APP_VERSION, true,
    reaper.ImGui_WindowFlags_MenuBar())
  if visible then
    update_dock_transition_state()
    handle_shortcuts()

    if reaper.ImGui_BeginMenuBar(ctx) then
      if reaper.ImGui_BeginMenu(ctx, T("file_menu")) then
        if reaper.ImGui_MenuItem(ctx, T("import_csv")) then choose_import_file() end
        if reaper.ImGui_MenuItem(ctx, T("export_csv")) then export_current_csv() end
        if reaper.ImGui_MenuItem(ctx, T("export_report")) then export_report() end
        if reaper.ImGui_MenuItem(ctx, T("export_diagnostics")) then
          local path, err = export_diagnostic_log("manual")
          if path then set_message(T("diagnostics_saved") .. ": " .. path, "info")
          else set_message(T("diagnostics_failed") .. ": " .. tostring(err or ""), "error") end
        end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_MenuItem(ctx, T("close")) then open = false end
        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, T("edit_menu")) then
        if reaper.ImGui_MenuItem(ctx, T("apply_changes"), "Ctrl+Enter") then state.pending_apply_frames = 2 end
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
      if reaper.ImGui_BeginTabItem(ctx, T("regions")) then state.active_tab = "regions"; render_regions_tab(); reaper.ImGui_EndTabItem(ctx) end
      if reaper.ImGui_BeginTabItem(ctx, T("qc") .. " (" .. tostring(#state.qc.issues) .. ")") then state.active_tab = "qc"; render_qc_tab(); reaper.ImGui_EndTabItem(ctx) end
      if reaper.ImGui_BeginTabItem(ctx, T("import_preview")) then state.active_tab = "import"; render_import_tab(); reaper.ImGui_EndTabItem(ctx) end
      if reaper.ImGui_BeginTabItem(ctx, T("report") .. " (" .. tostring(#state.report) .. ")") then state.active_tab = "report"; render_report_tab(); reaper.ImGui_EndTabItem(ctx) end
      reaper.ImGui_EndTabBar(ctx)
    end

    render_bulk_popup()
    render_settings_popup()
    render_help_popup()
    render_recovery_popup()
    update_window_state(false)
    reaper.ImGui_End(ctx)
  end


  persist_recovery_draft()
  if settings.auto_refresh and reaper.time_precise() > state.suppress_change_check_until then
    local change = reaper.GetProjectStateChangeCount(0)
    if change ~= state.last_project_change then
      if state.dirty_count == 0 then refresh_regions(true) else state.external_change = true end
      state.last_project_change = change
    end
  end
  return open ~= false
end

local function shutdown_cleanly()
  clean_shutdown = true
  -- Window geometry is only queried inside an active Begin/End frame.
  try_save_settings()
  clear_recovery_draft()
  project_ext_set(SESSION_KEY, "")
  diagnostic_add("INFO", "Application closed normally")
  if reaper.ImGui_DestroyContext then pcall(reaper.ImGui_DestroyContext, ctx) end
end

local function main_loop()
  local ok, should_continue = xpcall(run_frame, debug.traceback)
  if not ok then
      pcall(finish_transaction_ui)
    if transaction_active then
      pcall(reaper.Undo_EndBlock2, 0, "Region Sync Manager: interrupted transaction", -1)
      transaction_active = false
    end
    pcall(persist_recovery_draft)
    diagnostic_add("FATAL", tostring(should_continue))
    local log_path = export_diagnostic_log("fatal error")
    reaper.MB(
      "Region Sync Manager encountered an error and closed safely.\n\n" ..
      tostring(should_continue) .. (log_path and ("\n\nDiagnostic log:\n" .. log_path) or ""),
      APP_NAME, 0)
    return
  end
  if should_continue then reaper.defer(main_loop) else shutdown_cleanly() end
end

reaper.atexit(function()
  if not clean_shutdown then
    pcall(persist_recovery_draft)
    pcall(try_save_settings)
  end
end)

reaper.defer(main_loop)
