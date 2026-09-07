local MOD_NAME = "OctopathDialogueAssistant"
local VERSION = "1.0.0"
local MAX_HISTORY = 12
local MENU_GUIDE_PACKAGE = "/Game/UserInterface/Common/BP/MenuGuideItem"
local MENU_GUIDE_CLASS = MENU_GUIDE_PACKAGE .. ".MenuGuideItem_C"
local KEY_CONVERTER_PACKAGE = "/Game/UserInterface/Option/BP/KeyConfigButton1WBP"
local KEY_CONVERTER_CLASS = KEY_CONVERTER_PACKAGE .. ".KeyConfigButton1WBP_C"
local TOGGLE_BUTTON_PACKAGE = "/Game/UserInterface/Option/BP/ToggleButtonWBP"
local TOGGLE_BUTTON_CLASS = TOGGLE_BUTTON_PACKAGE .. ".ToggleButtonWBP_C"
local LANGUAGE_BUTTON_PACKAGE = "/Game/UserInterface/Option/BP/LanguageButtonWBP"
local LANGUAGE_BUTTON_CLASS = LANGUAGE_BUTTON_PACKAGE .. ".LanguageButtonWBP_C"
local OPTION_ROW_PACKAGE = "/Game/UserInterface/Option/BP/ListItemWidget_Opt1"
local OPTION_ROW_CLASS = OPTION_ROW_PACKAGE .. ".ListItemWidget_Opt1_C"
local OPTION_MENU_CLASS_NAME = "OptionMenuWBP_C"
local EVENT_SKIP_CLASS_NAME = "UIEventSkip_C"
local HELP_WINDOW_PACKAGE = "/Game/UserInterface/Common/BP/HelpWindowWBP"
local HELP_WINDOW_CLASS = HELP_WINDOW_PACKAGE .. ".HelpWindowWBP_C"
local TALK_FONT_TYPE_ENUM = "EKSFontType::Talk"
local HELP_TEXT_TEMPLATE_PATHS = {
    "/Game/UserInterface/Common/BP/HelpWindowWBP.Default__HelpWindowWBP_C:WidgetTree.HelpText",
    "/Game/UserInterface/Common/BP/HelpWindowWBP.HelpWindowWBP_C:WidgetTree.HelpText",
}
local MOD_CATEGORY_ID = 6
local MOD_CATEGORY_LABEL = "DIALOGUE ASSISTANT"
local MOD_ROW_COUNT = 8
local ANALYSIS_DATA_FILE = "analysis_ja.tsv"
local ANALYSIS_IMPLEMENTED_LANGUAGE = "JA"
local ANALYSIS_TEXT_LANGUAGE = "ZH_CN"
local ALLOWED_SHORTCUT_KEYS = {
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
}
local TRANSLATION_LANGUAGES = {
    {
        code = "JA",
        enum = "EKSLanguage::eJA",
        data_file = "official_ja.tsv",
        font = "FONT_KS_NewCinema_PC",
    },
    {
        code = "EN",
        enum = "EKSLanguage::eEN",
        data_file = "official_en.tsv",
        font = "FONT_KS_Skech_PC",
    },
    {
        code = "IT",
        enum = "EKSLanguage::eIT",
        data_file = "official_it.tsv",
        font = "FONT_KS_Skech_PC",
    },
    {
        code = "FR",
        enum = "EKSLanguage::eFR",
        data_file = "official_fr.tsv",
        font = "FONT_KS_Skech_PC",
    },
    {
        code = "DE",
        enum = "EKSLanguage::eDE",
        data_file = "official_de.tsv",
        font = "FONT_KS_Skech_PC",
    },
    {
        code = "ES",
        enum = "EKSLanguage::eES",
        data_file = "official_es.tsv",
        font = "FONT_KS_Skech_PC",
    },
    {
        code = "ZH_TW",
        enum = "EKSLanguage::eZH_TW",
        data_file = "official_zh_tw.tsv",
        font = "FONT_MJ_TW_FangSong_PC",
    },
    {
        code = "ZH_CN",
        enum = "EKSLanguage::eZH_CN",
        data_file = "official_zh_cn.tsv",
        font = "FONT_MJ_CN_WeiBei_PC",
    },
    {
        code = "KR",
        enum = "EKSLanguage::eKR",
        data_file = "official_kr.tsv",
        font = "FONT_KR_YDHopeL_PC",
    },
}
local TRANSLATION_LANGUAGE_BY_CODE = {}
for index, language in ipairs(TRANSLATION_LANGUAGES) do
    language.index = index - 1
    language.font_package = "/Game/UserInterface/Common/Font/PC_Font/" .. language.font
    language.font_object = language.font_package .. "." .. language.font
    TRANSLATION_LANGUAGE_BY_CODE[language.code] = language
end
local DEFAULT_CONFIG = {
    enabled = true,
    replay_current_key = "R",
    replay_previous_key = "G",
    translation_enabled = true,
    translation_key = "T",
    translation_language = "ZH_CN",
    analysis_language = "JA",
    analysis_key = "V",
}

local script_source = debug.getinfo(1, "S").source or ""
local script_path = script_source:gsub("^@", "")
local script_dir = script_path:match("^(.*)[/\\]") or "."
local config_path = script_dir .. "\\config.lua"
local config = {}

local installed_hooks = {}
local dumped_classes = {}
local state = {
    current = nil,
    previous = nil,
    history = {},
    history_index = 0,
    manual_replay = nil,
    live_talk_text = nil,
    live_balloon = nil,
    event_ui = nil,
    sequence_snapshot = nil,
    shortcut_hint_items = {},
    shortcut_hint_owner = "",
    shortcut_hint_error = "",
    translation_visible = false,
    translation_widget = nil,
    translation_owner = "",
    translation_label = "",
    translation_data = {},
    translation_data_errors = {},
    translation_ui_error = "",
    analysis_visible = false,
    analysis_widget = nil,
    analysis_slot = nil,
    analysis_owner = "",
    analysis_label = "",
    analysis_data = nil,
    analysis_data_error = nil,
    analysis_ui_error = "",
    ui_assets = {},
    option_menu = nil,
    option_menu_open = false,
    mod_tab_active = false,
    mod_tab_items_focused = false,
    mod_tab_cursor = 0,
    mod_tab_rows = {},
    mod_tab_controls = {},
    mod_chrome_snapshot = nil,
    settings_capture = nil,
    option_ui_error = "",
    last_speed_change = "",
}

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, message))
end

local function normalized_key(value, fallback)
    local key_name = string.upper(tostring(value or ""))
    for _, allowed in ipairs(ALLOWED_SHORTCUT_KEYS) do
        if key_name == allowed then
            return key_name
        end
    end
    return fallback
end

local function normalized_language(value, fallback)
    local code = string.upper(tostring(value or ""))
    if TRANSLATION_LANGUAGE_BY_CODE[code] ~= nil then
        return code
    end
    return fallback
end

local function normalized_bool(value, fallback)
    if type(value) == "boolean" then
        return value
    end
    return fallback
end

local function normalize_config(value)
    value = type(value) == "table" and value or {}
    local normalized = {
        enabled = normalized_bool(value.enabled, DEFAULT_CONFIG.enabled),
        replay_current_key = normalized_key(value.replay_current_key, DEFAULT_CONFIG.replay_current_key),
        replay_previous_key = normalized_key(value.replay_previous_key, DEFAULT_CONFIG.replay_previous_key),
        translation_enabled = normalized_bool(value.translation_enabled, DEFAULT_CONFIG.translation_enabled),
        translation_key = normalized_key(value.translation_key, DEFAULT_CONFIG.translation_key),
        translation_language = normalized_language(value.translation_language, DEFAULT_CONFIG.translation_language),
        analysis_language = normalized_language(value.analysis_language, DEFAULT_CONFIG.analysis_language),
        analysis_key = normalized_key(value.analysis_key, DEFAULT_CONFIG.analysis_key),
    }
    local used = {}
    for _, field in ipairs({ "replay_current_key", "replay_previous_key", "translation_key", "analysis_key" }) do
        local key_name = normalized[field]
        if used[key_name] then
            local preferred = DEFAULT_CONFIG[field]
            if not used[preferred] then
                key_name = preferred
            else
                for _, candidate in ipairs(ALLOWED_SHORTCUT_KEYS) do
                    if not used[candidate] then
                        key_name = candidate
                        break
                    end
                end
            end
            normalized[field] = key_name
        end
        used[key_name] = true
    end
    return normalized
end

local function load_config()
    local ok, loaded = pcall(dofile, config_path)
    if not ok then
        log("config_defaulted reason=" .. tostring(loaded))
        return normalize_config(DEFAULT_CONFIG)
    end
    return normalize_config(loaded)
end

local function save_config()
    local file, open_error = io.open(config_path, "wb")
    if file == nil then
        log("config_save_failed reason=" .. tostring(open_error))
        return false
    end
    local content = table.concat({
        "return {",
        string.format("    enabled = %s,", tostring(config.enabled)),
        string.format("    replay_current_key = %q,", config.replay_current_key),
        string.format("    replay_previous_key = %q,", config.replay_previous_key),
        string.format("    translation_enabled = %s,", tostring(config.translation_enabled)),
        string.format("    translation_key = %q,", config.translation_key),
        string.format("    translation_language = %q,", config.translation_language),
        string.format("    analysis_language = %q,", config.analysis_language),
        string.format("    analysis_key = %q,", config.analysis_key),
        "}",
        "",
    }, "\r\n")
    local ok, write_error = pcall(function()
        file:write(content)
        file:flush()
        file:close()
    end)
    if not ok then
        pcall(function()
            file:close()
        end)
        log("config_save_failed reason=" .. tostring(write_error))
        return false
    end
    log(string.format(
        "config_saved replay=%s current=%s previous=%s translation=%s translation_key=%s translation_language=%s analysis_language=%s analysis_key=%s",
        tostring(config.enabled),
        config.replay_current_key,
        config.replay_previous_key,
        tostring(config.translation_enabled),
        config.translation_key,
        config.translation_language,
        config.analysis_language,
        config.analysis_key
    ))
    return true
end

config = load_config()
save_config()

local function compact(value)
    local text = tostring(value or "")
    text = text:gsub("[\r\n\t]+", " ")
    if #text > 480 then
        return text:sub(1, 477) .. "..."
    end
    return text
end

local function unwrap(value)
    if type(value) ~= "userdata" then
        return value
    end
    -- Only parameter wrappers expose get(); probing it on a UObject invokes
    -- reflected property lookup, potentially through a destroyed object.
    local typed, kind = pcall(function() return value:type() end)
    if not typed then
        return nil
    end
    if kind ~= "RemoteUnrealParam" and kind ~= "LocalUnrealParam" then
        return value
    end
    local ok, result = pcall(function() return value:get() end)
    if ok then
        return result
    end
    return nil
end

local function remote_type(value)
    value = unwrap(value)
    if value == nil then
        return "nil"
    end
    local ok, result = pcall(function()
        return value:type()
    end)
    if ok and result ~= nil then
        return tostring(result)
    end
    return type(value)
end

local function scalar_string(value)
    value = unwrap(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        return compact(value)
    end
    local ok, result = pcall(function()
        return value:ToString()
    end)
    if ok and result ~= nil then
        return compact(result)
    end
    ok, result = pcall(function()
        return value:GetFullName()
    end)
    if ok and result ~= nil then
        return compact(result)
    end
    return compact(value)
end

local function exact_string(value)
    value = unwrap(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    local ok, result = pcall(function()
        return value:ToString()
    end)
    if ok and result ~= nil then
        return tostring(result)
    end
    return tostring(value)
end

local function describe_array(value)
    local array = unwrap(value)
    if array == nil then
        return nil
    end
    local ok, count = pcall(function()
        return array:GetArrayNum()
    end)
    if not ok or count == nil then
        return nil
    end

    local items = {}
    local iterated = pcall(function()
        array:ForEach(function(index, element)
            if #items >= 16 then
                return true
            end
            table.insert(items, string.format("%s=%s", tostring(index), scalar_string(element)))
            return false
        end)
    end)
    if not iterated then
        return string.format("TArray[%s]", tostring(count))
    end
    return string.format("TArray[%s]{%s}", tostring(count), table.concat(items, ","))
end

local function describe_nested(value, depth, seen)
    if type(value) ~= "table" then
        local array = describe_array(value)
        if array ~= nil then
            return array
        end
        return scalar_string(value)
    end
    if depth >= 4 then
        return "{...}"
    end
    if seen[value] then
        return "{cycle}"
    end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    local items = {}
    for _, key in ipairs(keys) do
        if #items >= 24 then
            table.insert(items, "...")
            break
        end
        table.insert(items, string.format(
            "%s=%s",
            tostring(key),
            describe_nested(value[key], depth + 1, seen)
        ))
    end
    seen[value] = nil
    return "{" .. table.concat(items, ",") .. "}"
end

local function describe_value(value)
    return compact(describe_nested(value, 0, {}))
end

local function read_raw_field(object, field)
    object = unwrap(object)
    if object == nil then
        return nil
    end
    local ok, result = pcall(function()
        return object[field]
    end)
    if not ok then
        return nil
    end
    return result
end

local function read_field(object, field)
    return describe_value(read_raw_field(object, field))
end

local function full_name(object)
    object = unwrap(object)
    if object == nil then
        return ""
    end
    local ok, result = pcall(function()
        return object:GetFullName()
    end)
    if ok and result ~= nil then
        return compact(result)
    end
    return ""
end

local function class_name(object)
    object = unwrap(object)
    if object == nil then
        return ""
    end
    local ok, result = pcall(function()
        return object:GetClass():GetFullName()
    end)
    if ok and result ~= nil then
        return compact(result)
    end
    return ""
end

local function outer_chain(object)
    local names = {}
    local current = unwrap(object)
    for _ = 1, 4 do
        if current == nil then
            break
        end
        local ok, outer = pcall(function()
            return current:GetOuter()
        end)
        outer = unwrap(outer)
        if not ok or outer == nil then
            break
        end
        local name = full_name(outer)
        if name == "" then
            break
        end
        table.insert(names, name)
        current = outer
    end
    return table.concat(names, " <- ")
end

local candidate_keywords = {
    "voice",
    "sound",
    "audio",
    "text",
    "talk",
    "speaker",
    "target",
    "balloon",
    "sequence",
    "player",
    "frame",
    "position",
    "event",
    "index",
    "owner",
}

local function is_candidate_property(name)
    local lowered = string.lower(name or "")
    for _, keyword in ipairs(candidate_keywords) do
        if string.find(lowered, keyword, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function dump_candidate_properties(context, source)
    local object = unwrap(context)
    if object == nil then
        return
    end
    local object_class = class_name(object)
    if object_class == "" or dumped_classes[object_class] then
        return
    end
    dumped_classes[object_class] = true

    log(string.format(
        "object source=%s name=%s class=%s outer=%s",
        source,
        full_name(object),
        object_class,
        outer_chain(object)
    ))

    local ok, current_class = pcall(function()
        return object:GetClass()
    end)
    if not ok or current_class == nil then
        return
    end

    local seen = {}
    local emitted = 0
    for _ = 1, 8 do
        local class_full_name = full_name(current_class)
        if class_full_name == "" then
            break
        end
        pcall(function()
            current_class:ForEachProperty(function(property)
                local property_name = scalar_string(property:GetFName())
                if is_candidate_property(property_name) and not seen[property_name] then
                    seen[property_name] = true
                    emitted = emitted + 1
                    local raw_value = read_raw_field(object, property_name)
                    log(string.format(
                        "field source=%s owner=%s name=%s type=%s value=%s",
                        source,
                        class_full_name,
                        property_name,
                        remote_type(raw_value),
                        describe_value(raw_value)
                    ))
                    if emitted >= 48 then
                        return true
                    end
                end
                return false
            end)
        end)
        if emitted >= 48 then
            break
        end
        local super_ok, super_class = pcall(function()
            return current_class:GetSuperStruct()
        end)
        if not super_ok or super_class == nil or full_name(super_class) == "" then
            break
        end
        current_class = super_class
    end
    log(string.format("field_dump_end source=%s class=%s count=%d", source, object_class, emitted))
end

local function call_no_arg_raw(object, method_name)
    object = unwrap(object)
    if object == nil then
        return nil
    end
    local ok, method = pcall(function()
        return object[method_name]
    end)
    if not ok or method == nil then
        return nil
    end
    ok, method = pcall(function()
        return method(object)
    end)
    if not ok then
        return nil
    end
    return method
end

local function call_no_arg(object, method_name)
    return describe_value(call_no_arg_raw(object, method_name))
end

local function read_nested_number(value, ...)
    local current = value
    for index = 1, select("#", ...) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[select(index, ...)]
    end
    current = unwrap(current)
    if type(current) == "number" then
        return current
    end
    return tonumber(scalar_string(current))
end

local function direct_outer(object)
    object = unwrap(object)
    if object == nil then
        return nil
    end
    local ok, outer = pcall(function()
        return object:GetOuter()
    end)
    if not ok then
        return nil
    end
    return unwrap(outer)
end

local function is_valid_object(object)
    object = unwrap(object)
    if object == nil then
        return false
    end
    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    if ok then
        return valid == true
    end
    return false
end

local function balloon_from_talk_text(talk_text)
    return direct_outer(direct_outer(talk_text))
end

local function report_shortcut_hint_error(reason)
    reason = compact(reason)
    if reason ~= state.shortcut_hint_error then
        state.shortcut_hint_error = reason
        log("shortcut_hint_failed reason=" .. reason)
    end
end

local function report_option_ui_error(reason)
    reason = compact(reason)
    if reason ~= state.option_ui_error then
        state.option_ui_error = reason
        log("option_tab_failed reason=" .. reason)
    end
end

local function report_translation_ui_error(reason)
    reason = compact(reason)
    if reason ~= state.translation_ui_error then
        state.translation_ui_error = reason
        log("translation_ui_failed reason=" .. reason)
    end
end

local function report_analysis_ui_error(reason)
    reason = compact(reason)
    if reason ~= state.analysis_ui_error then
        state.analysis_ui_error = reason
        log("analysis_ui_failed reason=" .. reason)
    end
end

local function unescape_data_text(value)
    return (value:gsub("\\(.)", function(code)
        if code == "n" then
            return "\n"
        end
        if code == "r" then
            return "\r"
        end
        if code == "t" then
            return "\t"
        end
        return code
    end))
end

local function current_translation_language()
    return TRANSLATION_LANGUAGE_BY_CODE[config.translation_language]
        or TRANSLATION_LANGUAGE_BY_CODE[DEFAULT_CONFIG.translation_language]
end

local function current_analysis_language()
    return TRANSLATION_LANGUAGE_BY_CODE[config.analysis_language]
        or TRANSLATION_LANGUAGE_BY_CODE[DEFAULT_CONFIG.analysis_language]
end

local function analysis_available()
    return config.translation_enabled and config.analysis_language == ANALYSIS_IMPLEMENTED_LANGUAGE
end

local function load_official_translation_data(language)
    language = language or current_translation_language()
    local code = language.code
    if state.translation_data[code] ~= nil then
        return state.translation_data[code]
    end
    if state.translation_data_errors[code] ~= nil then
        return nil
    end

    local translation_data_path = script_dir .. "\\" .. language.data_file
    local file, open_error = io.open(translation_data_path, "rb")
    if file == nil then
        state.translation_data_errors[code] = compact(open_error or "official_translation_file_missing")
        log(string.format("translation_data_failed language=%s reason=%s", code, state.translation_data_errors[code]))
        return nil
    end

    local data = {}
    local row_count = 0
    local text_count = 0
    local loaded, load_error = pcall(function()
        local header = file:read("*l")
        local expected_header = "# OctopathDialogueAssistant official " .. code .. " dialogue v1"
        if header ~= expected_header then
            error("official_translation_header_mismatch")
        end
        for line in file:lines() do
            local row_name, index_text, escaped_text = line:match("^([^\t]+)\t(%d+)\t(.*)$")
            if row_name ~= nil then
                local row = data[row_name]
                if row == nil then
                    row = {}
                    data[row_name] = row
                    row_count = row_count + 1
                end
                row[tonumber(index_text) + 1] = unescape_data_text(escaped_text)
                text_count = text_count + 1
            end
        end
    end)
    file:close()

    if not loaded or row_count < 30000 then
        state.translation_data_errors[code] = compact(load_error or "official_translation_data_incomplete")
        log(string.format("translation_data_failed language=%s reason=%s", code, state.translation_data_errors[code]))
        return nil
    end

    state.translation_data[code] = data
    log(string.format("translation_data_ready language=%s rows=%d texts=%d", code, row_count, text_count))
    return data
end

local function load_analysis_data()
    if state.analysis_data ~= nil then
        return state.analysis_data
    end
    if state.analysis_data_error ~= nil then
        return nil
    end

    local analysis_data_path = script_dir .. "\\" .. ANALYSIS_DATA_FILE
    local file, open_error = io.open(analysis_data_path, "rb")
    if file == nil then
        state.analysis_data_error = compact(open_error or "analysis_file_missing")
        log("analysis_data_failed reason=" .. state.analysis_data_error)
        return nil
    end

    local data = {}
    local row_count = 0
    local text_count = 0
    local loaded, load_error = pcall(function()
        local header = file:read("*l")
        if header ~= "# OctopathDialogueAssistant analysis JA dialogue v1" then
            error("analysis_header_mismatch")
        end
        for line in file:lines() do
            local row_name, index_text, escaped_text = line:match("^([^\t]+)\t(%d+)\t(.*)$")
            if row_name ~= nil then
                local row = data[row_name]
                if row == nil then
                    row = {}
                    data[row_name] = row
                    row_count = row_count + 1
                end
                row[tonumber(index_text) + 1] = unescape_data_text(escaped_text)
                text_count = text_count + 1
            end
        end
    end)
    file:close()

    if not loaded or text_count < 1 then
        state.analysis_data_error = compact(load_error or "analysis_data_empty")
        log("analysis_data_failed reason=" .. state.analysis_data_error)
        return nil
    end

    state.analysis_data = data
    log(string.format("analysis_data_ready rows=%d texts=%d", row_count, text_count))
    return data
end

local function record_dialogue_identity(record)
    if record == nil or record.voice_name_values == nil then
        return nil, nil, "dialogue_label_unavailable"
    end

    local label_index = (tonumber(record.text_index_number) or 0) + 1
    local label = exact_string(record.voice_name_values[label_index] or record.voice_name_values[1])
    if label == "" then
        return nil, nil, "dialogue_label_unavailable"
    end
    return label, (tonumber(record.text_index_number) or 0) + 1, nil
end

local function translation_for_record(record)
    local label, text_index, identity_error = record_dialogue_identity(record)
    if identity_error ~= nil then
        return nil, identity_error, ""
    end

    local language = current_translation_language()
    local data = load_official_translation_data(language)
    if data == nil then
        return nil, state.translation_data_errors[language.code], label
    end
    local translated_row = data[label]
    if translated_row == nil then
        return nil, "official_translation_row_missing", label
    end

    local text = translated_row[text_index] or translated_row[1]
    if text == nil or text == "" then
        return nil, "official_translation_text_missing", label
    end
    return text, nil, label
end

local function analysis_for_record(record)
    local label, text_index, identity_error = record_dialogue_identity(record)
    if identity_error ~= nil then
        return nil, identity_error, ""
    end
    local data = load_analysis_data()
    if data == nil then
        return nil, state.analysis_data_error, label
    end
    local row = data[label]
    if row == nil then
        return nil, "analysis_row_missing", label
    end
    local text = row[text_index]
    if text == nil or text == "" then
        return nil, "analysis_text_missing", label
    end
    return text, nil, label
end

local function write_raw_field(object, field, value)
    object = unwrap(object)
    if object == nil then
        return false
    end
    local ok = pcall(function()
        object[field] = value
    end)
    return ok
end

local function load_blueprint_class(cache_key, package_path, class_path)
    local cached = unwrap(state.ui_assets[cache_key])
    if is_valid_object(cached) then
        return cached
    end
    pcall(function()
        LoadAsset(package_path)
    end)
    local ok, class = pcall(function()
        return StaticFindObject(class_path)
    end)
    class = unwrap(class)
    if not ok or not is_valid_object(class) then
        return nil
    end
    state.ui_assets[cache_key] = class
    return class
end

local function load_asset_object(cache_key, package_path, object_path)
    local cached = unwrap(state.ui_assets[cache_key])
    if is_valid_object(cached) then
        return cached
    end
    pcall(function()
        LoadAsset(package_path)
    end)
    local ok, object = pcall(function()
        return StaticFindObject(object_path)
    end)
    object = unwrap(object)
    if not ok or not is_valid_object(object) then
        return nil
    end
    state.ui_assets[cache_key] = object
    return object
end

local function widget_blueprint_library()
    local cached = unwrap(state.ui_assets.widget_library)
    if is_valid_object(cached) then
        return cached
    end
    local ok, library = pcall(function()
        return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    end)
    library = unwrap(library)
    if not ok or not is_valid_object(library) then
        return nil
    end
    state.ui_assets.widget_library = library
    return library
end

local function create_blueprint_widget(context, cache_key, package_path, class_path)
    context = unwrap(context)
    local library = widget_blueprint_library()
    local class = load_blueprint_class(cache_key, package_path, class_path)
    if not is_valid_object(context) or not is_valid_object(library) or not is_valid_object(class) then
        return nil, "native_widget_dependency_unavailable"
    end
    local ok, widget = pcall(function()
        return library:Create(context, class, nil)
    end)
    widget = unwrap(widget)
    if not ok or not is_valid_object(widget) then
        return nil, ok and "native_widget_create_returned_invalid" or widget
    end
    return widget, nil
end

local function create_key_converter(context)
    return create_blueprint_widget(
        context,
        "key_converter_class",
        KEY_CONVERTER_PACKAGE,
        KEY_CONVERTER_CLASS
    )
end

local function native_key_text(context, key_name)
    local converter, converter_error = create_key_converter(context)
    if not is_valid_object(converter) then
        return nil, converter_error
    end
    local converted, converted_error = pcall(function()
        converter.TextText = FName(key_name)
        converter:UpdateText()
        local text_widget = unwrap(converter.Text)
        return text_widget:GetText()
    end)
    if not converted then
        return nil, converted_error
    end
    return converted_error, nil
end

local function refresh_guide_item(context, item, key_name, label)
    item = unwrap(item)
    if not is_valid_object(item) then
        return false, "invalid_guide_item"
    end
    local key_text, key_error = native_key_text(context, key_name)
    if key_text == nil then
        return false, key_error
    end
    local ok, update_error = pcall(function()
        item.ButtonText:SetText(key_text)
        item.ButtonText:SetVisibility(0)
        item.GuideText_00:SetText(FText(label))
        item.GuideText_00:SetVisibility(0)
        item.Icon_00:SetVisibility(1)
        item.GuideBox_00:SetVisibility(0)
        item:SetVisibility(0)
    end)
    if not ok then
        return false, update_error
    end
    return true, nil
end

local function create_guide_item(context, key_name, label)
    local item, item_error = create_blueprint_widget(
        context,
        "menu_guide_class",
        MENU_GUIDE_PACKAGE,
        MENU_GUIDE_CLASS
    )
    if not is_valid_object(item) then
        return nil, item_error
    end
    local refreshed, refresh_error = refresh_guide_item(context, item, key_name, label)
    if not refreshed then
        return nil, refresh_error
    end
    return item, nil
end

local function widget_parent(widget)
    widget = unwrap(widget)
    if not is_valid_object(widget) then
        return nil
    end
    local ok, parent = pcall(function()
        return widget:GetParent()
    end)
    if not ok then
        return nil
    end
    return unwrap(parent)
end

local function set_slot_padding(slot, margin)
    slot = unwrap(slot)
    if not is_valid_object(slot) then
        return
    end
    pcall(function()
        slot:SetPadding(margin)
    end)
end

local function collapse_guide_item(item)
    item = unwrap(item)
    if not is_valid_object(item) then
        return
    end
    pcall(function()
        item:SetVisibility(1)
    end)
    for _, field in ipairs({ "ButtonText", "GuideText_00", "Icon_00", "GuideBox_00" }) do
        local child = unwrap(read_raw_field(item, field))
        if is_valid_object(child) then
            pcall(function()
                child:SetVisibility(1)
            end)
        end
    end
end

local function detach_guide_items(items)
    for _, item in ipairs(items) do
        collapse_guide_item(item)
        local parent = widget_parent(item)
        if is_valid_object(parent) then
            pcall(function()
                parent:RemoveChild(item)
            end)
        end
    end
end

local function configure_shortcut_hint_slot(slot, right_offset)
    slot = unwrap(slot)
    if not is_valid_object(slot) then
        return false, "invalid_slot"
    end

    local slot_class = class_name(slot)
    if string.find(slot_class, "CanvasPanelSlot", 1, true) ~= nil then
        local ok, slot_error = pcall(function()
            slot:SetAnchors({
                Minimum = { X = 1.0, Y = 0.0 },
                Maximum = { X = 1.0, Y = 0.0 },
            })
            slot:SetAlignment({ X = 1.0, Y = 0.0 })
            slot:SetPosition({ X = -right_offset, Y = 24.0 })
            slot:SetAutoSize(true)
            slot:SetZOrder(1000)
        end)
        if not ok then
            return false, slot_error
        end
        return true, nil
    end

    if string.find(slot_class, "OverlaySlot", 1, true) ~= nil then
        local ok, slot_error = pcall(function()
            slot:SetHorizontalAlignment(3)
            slot:SetVerticalAlignment(1)
            slot:SetPadding({
                Left = 0.0,
                Top = 24.0,
                Right = right_offset,
                Bottom = 0.0,
            })
        end)
        if not ok then
            return false, slot_error
        end
        return true, nil
    end

    return false, "unsupported_slot=" .. slot_class
end

local function shortcut_hint_specs()
    local specs = {}
    local analysis_hint = analysis_available()
    local analysis_width = analysis_hint and 170.0 or 0.0
    if config.enabled then
        table.insert(specs, { key = config.replay_current_key, label = "REPLAY", right = 420.0 + analysis_width })
        table.insert(specs, { key = config.replay_previous_key, label = "PREVIOUS", right = 250.0 + analysis_width })
    end
    if config.translation_enabled then
        table.insert(specs, { key = config.translation_key, label = "TRANSLATION", right = 24.0 + analysis_width })
    end
    if analysis_hint then
        table.insert(specs, { key = config.analysis_key, label = "ANALYSIS", right = 24.0 })
    end
    return specs
end

local function clear_shortcut_hint()
    detach_guide_items(state.shortcut_hint_items)
    state.shortcut_hint_items = {}
    state.shortcut_hint_owner = ""
end

local function shortcut_hint_items_valid(specs)
    if #state.shortcut_hint_items ~= #specs then
        return false
    end
    for _, item in ipairs(state.shortcut_hint_items) do
        if not is_valid_object(item) then
            return false
        end
    end
    return true
end

local function refresh_shortcut_hint_items(owner, specs)
    if #state.shortcut_hint_items ~= #specs then
        return false
    end
    for index, spec in ipairs(specs) do
        local item = state.shortcut_hint_items[index]
        local refreshed = refresh_guide_item(owner, item, spec.key, spec.label)
        if not refreshed then
            return false
        end
    end
    return true
end

local function find_event_ui()
    local owner = unwrap(state.event_ui)
    if is_valid_object(owner) then
        return owner
    end
    local found, candidate = pcall(function()
        return FindFirstOf(EVENT_SKIP_CLASS_NAME)
    end)
    candidate = unwrap(candidate)
    if found and is_valid_object(candidate) then
        state.event_ui = candidate
        return candidate
    end
    return nil
end

local function detach_translation_widget()
    local widget = unwrap(state.translation_widget)
    if is_valid_object(widget) then
        pcall(function()
            widget:SetVisibility(1)
        end)
        local parent = widget_parent(widget)
        if is_valid_object(parent) then
            pcall(function()
                parent:RemoveChild(widget)
            end)
        end
    end
    state.translation_widget = nil
    state.translation_owner = ""
    state.translation_label = ""
end

local function hide_translation_overlay()
    state.translation_visible = false
    detach_translation_widget()
end

local function configure_translation_slot(slot)
    slot = unwrap(slot)
    if not is_valid_object(slot) then
        return false, "invalid_translation_slot"
    end

    local slot_class = class_name(slot)
    if string.find(slot_class, "CanvasPanelSlot", 1, true) ~= nil then
        local ok, slot_error = pcall(function()
            slot:SetAnchors({
                Minimum = { X = 1.0, Y = 0.0 },
                Maximum = { X = 1.0, Y = 0.0 },
            })
            slot:SetAlignment({ X = 1.0, Y = 0.0 })
            slot:SetPosition({ X = -24.0, Y = 68.0 })
            slot:SetAutoSize(true)
            slot:SetZOrder(999)
        end)
        if not ok then
            return false, slot_error
        end
        return true, nil
    end

    if string.find(slot_class, "OverlaySlot", 1, true) ~= nil then
        local ok, slot_error = pcall(function()
            slot:SetHorizontalAlignment(3)
            slot:SetVerticalAlignment(1)
            slot:SetPadding({ Left = 0.0, Top = 68.0, Right = 24.0, Bottom = 0.0 })
        end)
        if not ok then
            return false, slot_error
        end
        return true, nil
    end

    return false, "unsupported_translation_slot=" .. slot_class
end

local function overlay_font_values(help_text, language)
    language = language or current_translation_language()
    local language_font = load_asset_object(
        "translation_talk_font_" .. language.code,
        language.font_package,
        language.font_object
    )
    if not is_valid_object(language_font) then
        return nil, nil, nil, "translation_font_unavailable"
    end

    read_raw_field(help_text, "m_Language")
    local language_values = rawget(_G, "Enum_m_Language")
    local language_value = type(language_values) == "table"
        and (language_values[language.enum] or language_values["e" .. language.code])
        or nil
    if type(language_value) ~= "number" then
        return nil, nil, nil, "translation_language_enum_unavailable"
    end

    read_raw_field(help_text, "m_FontType")
    local font_type_values = rawget(_G, "Enum_m_FontType")
    local font_type_value = type(font_type_values) == "table"
        and (font_type_values[TALK_FONT_TYPE_ENUM] or font_type_values.Talk)
        or nil
    if type(font_type_value) ~= "number" then
        return nil, nil, nil, "talk_font_type_enum_unavailable"
    end
    return language_font, language_value, font_type_value, nil
end

local function capture_overlay_font_fields(help_text)
    local font = read_raw_field(help_text, "Font")
    if font == nil then
        return nil
    end
    return {
        help_text = help_text,
        font_object = unwrap(read_raw_field(font, "FontObject")),
        size = read_raw_field(font, "Size"),
        letter_spacing = read_raw_field(font, "LetterSpacing"),
        language = read_raw_field(help_text, "m_Language"),
        font_type = read_raw_field(help_text, "m_FontType"),
        disable_refresh_font = read_raw_field(help_text, "DisableRefreshFont"),
    }
end

local function apply_overlay_font_fields(help_text, language, font_size)
    help_text = unwrap(help_text)
    if not is_valid_object(help_text) then
        return false, "translation_text_unavailable"
    end
    local language_font, language_value, font_type_value, value_error = overlay_font_values(help_text, language)
    if value_error ~= nil then
        return false, value_error
    end
    local refresh_locked = write_raw_field(help_text, "DisableRefreshFont", true)
    local applied, apply_error = pcall(function()
        help_text.m_Language = language_value
        help_text.m_FontType = font_type_value
        local font = read_raw_field(help_text, "Font")
        font.FontObject = language_font
        font.Size = font_size or 15
        font.LetterSpacing = 0
    end)
    if applied and not refresh_locked then
        log("translation_font_refresh_lock_unavailable")
    end
    return applied, applied and nil or compact(apply_error)
end

local function restore_overlay_font_fields(snapshot)
    if snapshot == nil or not is_valid_object(snapshot.help_text) then
        return
    end
    pcall(function()
        snapshot.help_text.m_Language = snapshot.language
        snapshot.help_text.m_FontType = snapshot.font_type
        if snapshot.disable_refresh_font ~= nil then
            snapshot.help_text.DisableRefreshFont = snapshot.disable_refresh_font
        end
        local font = read_raw_field(snapshot.help_text, "Font")
        font.FontObject = snapshot.font_object
        font.Size = snapshot.size
        font.LetterSpacing = snapshot.letter_spacing
    end)
end

local function find_overlay_text_template()
    for _, path in ipairs(HELP_TEXT_TEMPLATE_PATHS) do
        local found, template = pcall(function()
            return StaticFindObject(path)
        end)
        template = unwrap(template)
        if found and is_valid_object(template) then
            return template
        end
    end

    local found, objects = pcall(function()
        return FindAllOf("KSTextBlock")
    end)
    if found and objects ~= nil then
        for _, candidate in ipairs(objects) do
            local name = full_name(candidate)
            if string.find(name, "/Game/UserInterface/Common/BP/HelpWindowWBP.", 1, true) ~= nil
                and string.find(name, "WidgetTree.HelpText", 1, true) ~= nil
                and string.find(name, "/Engine/Transient", 1, true) == nil then
                return unwrap(candidate)
            end
        end
    end
    return nil
end

local function create_overlay_widget(context, language, log_prefix)
    load_blueprint_class("help_window_class", HELP_WINDOW_PACKAGE, HELP_WINDOW_CLASS)
    local template = find_overlay_text_template()
    local snapshot = capture_overlay_font_fields(template)
    local template_applied = false
    local template_error = "template_unavailable"
    if snapshot ~= nil then
        template_applied, template_error = apply_overlay_font_fields(template, language)
    end

    local widget, widget_error = create_blueprint_widget(
        context,
        "help_window_class",
        HELP_WINDOW_PACKAGE,
        HELP_WINDOW_CLASS
    )
    restore_overlay_font_fields(snapshot)
    log_prefix = log_prefix or "overlay"
    if template_applied then
        log(log_prefix .. "_template_font_ready object=" .. full_name(template))
    else
        log(log_prefix .. "_template_font_unavailable reason=" .. compact(template_error))
    end
    return widget, widget_error
end

local function find_named_widget(owner, name)
    owner = unwrap(owner)
    if not is_valid_object(owner) then
        return nil
    end
    local direct = unwrap(read_raw_field(owner, name))
    if is_valid_object(direct) then
        return direct
    end
    local tree = unwrap(read_raw_field(owner, "WidgetTree"))
    if not is_valid_object(tree) then
        return nil
    end
    local ok, widget = pcall(function()
        return tree:FindWidget(FName(name))
    end)
    widget = unwrap(widget)
    if not ok or not is_valid_object(widget) then
        return nil
    end
    return widget
end

local function prepare_overlay_widget(widget, text, initialize_font, language, layout)
    widget = unwrap(widget)
    if not is_valid_object(widget) then
        return false, "invalid_translation_widget"
    end

    local help_text = unwrap(read_raw_field(widget, "HelpText"))
    if not is_valid_object(help_text) then
        return false, "translation_text_unavailable"
    end

    layout = layout or {}
    local width = tonumber(layout.width) or 500.0
    local wrap = tonumber(layout.wrap) or (width - 20.0)
    local max_height = tonumber(layout.max_height) or 800.0
    local font_size = tonumber(layout.font_size) or 15

    if initialize_font then
        local font_ready, font_error = apply_overlay_font_fields(help_text, language, font_size)
        if not font_ready then
            return false, "initialize_translation_font=" .. compact(font_error)
        end
    end

    local prepared, prepare_error = pcall(function()
        for _, field in ipairs({ "ButtonText", "RStrickIcon", "ScrollBottomSpacer" }) do
            local child = unwrap(read_raw_field(widget, field))
            if is_valid_object(child) then
                child:SetVisibility(1)
            end
        end

        for _, field in ipairs({ "BG_Root", "BodyRootBorder", "HelpText" }) do
            local child = unwrap(read_raw_field(widget, field))
            if is_valid_object(child) then
                child:SetVisibility(0)
            end
        end

        local clipping_box = find_named_widget(widget, "SizeBox_Clipping")
        if is_valid_object(clipping_box) then
            clipping_box:SetMaxDesiredHeight(max_height)
        end
        local text_size_box = find_named_widget(widget, "TextSizeBox")
        if is_valid_object(text_size_box) then
            text_size_box:SetWidthOverride(width)
            text_size_box:SetMaxDesiredHeight(max_height)
        end
        help_text:SetWrapTextAt(wrap)
        help_text:SetText(FText(text))
        local text_scroll_box = find_named_widget(widget, "TextScrollBox")
        if is_valid_object(text_scroll_box) then
            text_scroll_box:SetScrollOffset(0.0)
            text_scroll_box:SetScrollBarVisibility(1)
        end
        write_raw_field(widget, "IsScrollable", false)
        widget:SetVisibility(3)
    end)
    if not prepared then
        return false, "prepare_overlay_widget=" .. compact(prepare_error)
    end
    return true, nil
end

local function refresh_translation_overlay(record)
    if not state.translation_visible then
        detach_translation_widget()
        return false
    end

    local text, translation_error, label = translation_for_record(record)
    if text == nil then
        detach_translation_widget()
        report_translation_ui_error(translation_error)
        return false
    end

    local owner = find_event_ui()
    local owner_name = full_name(owner)
    if not is_valid_object(owner) or owner_name == "" then
        detach_translation_widget()
        report_translation_ui_error("event_ui_unavailable")
        return false
    end

    local widget = unwrap(state.translation_widget)
    if state.translation_owner == owner_name and is_valid_object(widget) then
        local prepared, prepare_error = prepare_overlay_widget(
            widget,
            text,
            false,
            current_translation_language()
        )
        if prepared then
            state.translation_label = label
            state.translation_ui_error = ""
            return true
        end
        detach_translation_widget()
        report_translation_ui_error(prepare_error)
    end

    local widget_tree = unwrap(read_raw_field(owner, "WidgetTree"))
    local root_widget = unwrap(read_raw_field(widget_tree, "RootWidget"))
    if not is_valid_object(widget_tree) or not is_valid_object(root_widget) then
        report_translation_ui_error("event_ui_widget_tree_unavailable")
        return false
    end

    local new_widget, widget_error = create_overlay_widget(owner, current_translation_language(), "translation")
    if not is_valid_object(new_widget) then
        report_translation_ui_error("create_overlay_widget=" .. compact(widget_error))
        return false
    end

    local prepared, prepare_error = prepare_overlay_widget(
        new_widget,
        text,
        false,
        current_translation_language()
    )
    if not prepared then
        report_translation_ui_error(prepare_error)
        return false
    end

    local added, slot = pcall(function()
        return root_widget:AddChild(new_widget)
    end)
    if not added then
        report_translation_ui_error("attach_translation_widget=" .. compact(slot))
        return false
    end
    local configured, slot_error = configure_translation_slot(slot)
    if not configured then
        pcall(function()
            root_widget:RemoveChild(new_widget)
        end)
        report_translation_ui_error("layout_translation_widget=" .. compact(slot_error))
        return false
    end

    local font_applied, font_error = prepare_overlay_widget(
        new_widget,
        text,
        true,
        current_translation_language()
    )
    if not font_applied then
        pcall(function()
            root_widget:RemoveChild(new_widget)
        end)
        report_translation_ui_error(font_error)
        return false
    end

    state.translation_widget = new_widget
    state.translation_owner = owner_name
    state.translation_label = label
    state.translation_ui_error = ""
    log(string.format("translation_ready label=%s owner=%s", label, owner_name))
    return true
end

local function detach_analysis_widget()
    local widget = unwrap(state.analysis_widget)
    if is_valid_object(widget) then
        pcall(function()
            widget:SetVisibility(1)
        end)
        local parent = widget_parent(widget)
        if is_valid_object(parent) then
            pcall(function()
                parent:RemoveChild(widget)
            end)
        end
    end
    state.analysis_widget = nil
    state.analysis_slot = nil
    state.analysis_owner = ""
    state.analysis_label = ""
end

local function hide_analysis_overlay()
    state.analysis_visible = false
    detach_analysis_widget()
end

local function configure_analysis_slot(slot)
    slot = unwrap(slot)
    if not is_valid_object(slot) then
        return false, "invalid_analysis_slot"
    end
    local bottom_offset = 24.0
    local slot_class = class_name(slot)
    if string.find(slot_class, "CanvasPanelSlot", 1, true) ~= nil then
        local ok, slot_error = pcall(function()
            slot:SetAnchors({
                Minimum = { X = 0.0, Y = 1.0 },
                Maximum = { X = 0.0, Y = 1.0 },
            })
            slot:SetAlignment({ X = 0.0, Y = 1.0 })
            slot:SetPosition({ X = 24.0, Y = -bottom_offset })
            slot:SetAutoSize(true)
            slot:SetZOrder(998)
        end)
        if not ok then
            return false, slot_error
        end
        return true, nil
    end
    if string.find(slot_class, "OverlaySlot", 1, true) ~= nil then
        local ok, slot_error = pcall(function()
            slot:SetHorizontalAlignment(1)
            slot:SetVerticalAlignment(3)
            slot:SetPadding({ Left = 24.0, Top = 0.0, Right = 0.0, Bottom = bottom_offset })
        end)
        if not ok then
            return false, slot_error
        end
        return true, nil
    end
    return false, "unsupported_analysis_slot=" .. slot_class
end

local function prepare_analysis_widget(widget, text, initialize_font)
    return prepare_overlay_widget(
        widget,
        text,
        initialize_font,
        TRANSLATION_LANGUAGE_BY_CODE[ANALYSIS_TEXT_LANGUAGE],
        {
            width = 650.0,
            wrap = 630.0,
            max_height = 760.0,
            font_size = 14,
        }
    )
end

local function refresh_analysis_overlay(record)
    if not state.analysis_visible or not analysis_available() then
        detach_analysis_widget()
        return false
    end

    local text, analysis_error, label = analysis_for_record(record)
    if text == nil then
        if analysis_error == "analysis_row_missing" or analysis_error == "analysis_text_missing" then
            text = "当前台词暂无解析。"
        else
            detach_analysis_widget()
            report_analysis_ui_error(analysis_error)
            return false
        end
    end

    local owner = find_event_ui()
    local owner_name = full_name(owner)
    if not is_valid_object(owner) or owner_name == "" then
        detach_analysis_widget()
        report_analysis_ui_error("event_ui_unavailable")
        return false
    end

    local widget = unwrap(state.analysis_widget)
    local slot = unwrap(state.analysis_slot)
    if state.analysis_owner == owner_name and is_valid_object(widget) and is_valid_object(slot) then
        local prepared, prepare_error = prepare_analysis_widget(widget, text, false)
        local configured, slot_error = configure_analysis_slot(slot)
        if prepared and configured then
            state.analysis_label = label
            state.analysis_ui_error = ""
            return true
        end
        detach_analysis_widget()
        report_analysis_ui_error(prepared and slot_error or prepare_error)
    end

    local widget_tree = unwrap(read_raw_field(owner, "WidgetTree"))
    local root_widget = unwrap(read_raw_field(widget_tree, "RootWidget"))
    if not is_valid_object(widget_tree) or not is_valid_object(root_widget) then
        report_analysis_ui_error("event_ui_widget_tree_unavailable")
        return false
    end

    local new_widget, widget_error = create_overlay_widget(
        owner,
        TRANSLATION_LANGUAGE_BY_CODE[ANALYSIS_TEXT_LANGUAGE],
        "analysis"
    )
    if not is_valid_object(new_widget) then
        report_analysis_ui_error("create_overlay_widget=" .. compact(widget_error))
        return false
    end
    local prepared, prepare_error = prepare_analysis_widget(new_widget, text, false)
    if not prepared then
        report_analysis_ui_error(prepare_error)
        return false
    end

    local added, new_slot = pcall(function()
        return root_widget:AddChild(new_widget)
    end)
    if not added then
        report_analysis_ui_error("attach_analysis_widget=" .. compact(new_slot))
        return false
    end
    local configured, slot_error = configure_analysis_slot(new_slot)
    if not configured then
        pcall(function()
            root_widget:RemoveChild(new_widget)
        end)
        report_analysis_ui_error("layout_analysis_widget=" .. compact(slot_error))
        return false
    end

    local font_applied, font_error = prepare_analysis_widget(new_widget, text, true)
    if not font_applied then
        pcall(function()
            root_widget:RemoveChild(new_widget)
        end)
        report_analysis_ui_error(font_error)
        return false
    end

    state.analysis_widget = new_widget
    state.analysis_slot = unwrap(new_slot)
    state.analysis_owner = owner_name
    state.analysis_label = label
    state.analysis_ui_error = ""
    log(string.format("analysis_ready label=%s owner=%s", label, owner_name))
    return true
end

local function toggle_analysis_overlay()
    if not analysis_available() then
        hide_analysis_overlay()
        return
    end
    if state.analysis_visible then
        hide_analysis_overlay()
        log("analysis_hidden")
        return
    end
    state.analysis_visible = true
    if not refresh_analysis_overlay(state.current) then
        state.analysis_visible = false
        detach_analysis_widget()
    end
end

local function toggle_translation_overlay()
    if not config.translation_enabled then
        hide_translation_overlay()
        return
    end
    if state.translation_visible then
        hide_translation_overlay()
        if state.analysis_visible then
            refresh_analysis_overlay(state.current)
        end
        log("translation_hidden")
        return
    end
    state.translation_visible = true
    if not refresh_translation_overlay(state.current) then
        state.translation_visible = false
        detach_translation_widget()
    end
    if state.analysis_visible then
        refresh_analysis_overlay(state.current)
    end
end

local function ensure_shortcut_hint(talk_text)
    local specs = shortcut_hint_specs()
    if #specs == 0 then
        clear_shortcut_hint()
        return
    end

    local owner = find_event_ui()
    local owner_name = full_name(owner)
    if not is_valid_object(owner) or owner_name == "" then
        report_shortcut_hint_error("event_ui_unavailable")
        return
    end

    if state.shortcut_hint_owner == owner_name and shortcut_hint_items_valid(specs) then
        if refresh_shortcut_hint_items(owner, specs) then
            return
        end
        clear_shortcut_hint()
    end

    local widget_tree = unwrap(read_raw_field(owner, "WidgetTree"))
    local root_widget = unwrap(read_raw_field(widget_tree, "RootWidget"))
    if not is_valid_object(widget_tree) or not is_valid_object(root_widget) then
        report_shortcut_hint_error("event_ui_widget_tree_unavailable")
        return
    end

    local items = {}
    for index, spec in ipairs(specs) do
        local item, item_error = create_guide_item(owner, spec.key, spec.label)
        if not is_valid_object(item) then
            detach_guide_items(items)
            report_shortcut_hint_error(item_error)
            return
        end
        table.insert(items, item)
        local added_item, item_slot = pcall(function()
            return root_widget:AddChild(item)
        end)
        if not added_item then
            detach_guide_items(items)
            report_shortcut_hint_error(item_slot)
            return
        end
        local configured, slot_error = configure_shortcut_hint_slot(item_slot, spec.right)
        if not configured then
            pcall(function()
                root_widget:RemoveChild(item)
            end)
            detach_guide_items(items)
            report_shortcut_hint_error(slot_error)
            return
        end
    end

    state.shortcut_hint_items = items
    state.shortcut_hint_owner = owner_name
    state.shortcut_hint_error = ""
    log(string.format(
        "shortcut_hint_ready current=%s previous=%s translation=%s analysis=%s owner=%s root=%s",
        config.replay_current_key,
        config.replay_previous_key,
        config.translation_key,
        config.analysis_key,
        owner_name,
        class_name(root_widget)
    ))
end

local function refresh_live_shortcut_hint()
    clear_shortcut_hint()
    if is_valid_object(state.live_talk_text) then
        ensure_shortcut_hint(state.live_talk_text)
    end
end

local function widget_visibility(widget)
    widget = unwrap(widget)
    if not is_valid_object(widget) then
        return nil
    end
    return tonumber(scalar_string(call_no_arg_raw(widget, "GetVisibility")))
end

local function set_widget_visibility(widget, visibility)
    widget = unwrap(widget)
    if not is_valid_object(widget) or visibility == nil then
        return
    end
    pcall(function()
        widget:SetVisibility(visibility)
    end)
end

local function option_category_index(menu)
    return tonumber(scalar_string(read_raw_field(menu, "CategoryCursorPos")))
end

local function option_menu_is_active(menu)
    menu = unwrap(menu)
    if not is_valid_object(menu) then
        return false
    end
    local active = unwrap(read_raw_field(menu, "IsActive"))
    return active == true or scalar_string(active) == "true" or scalar_string(active) == "1"
end

local function detach_mod_controls()
    for _, entry in ipairs(state.mod_tab_controls) do
        local widget = unwrap(entry.widget)
        if is_valid_object(widget) then
            set_widget_visibility(widget, 1)
            local parent = widget_parent(widget)
            if is_valid_object(parent) then
                pcall(function()
                    parent:RemoveChild(widget)
                end)
            end
        end
    end
    state.mod_tab_controls = {}
end

local function detach_mod_rows()
    for _, row in ipairs(state.mod_tab_rows) do
        row = unwrap(row)
        if is_valid_object(row) then
            set_widget_visibility(row, 1)
            local parent = widget_parent(row)
            if is_valid_object(parent) then
                pcall(function()
                    parent:RemoveChild(row)
                end)
            end
        end
    end
    state.mod_tab_rows = {}
end

local function restore_mod_chrome()
    local saved = state.mod_chrome_snapshot
    if saved == nil then
        return
    end
    set_widget_visibility(saved.title_image, saved.title_image_visibility)
    set_widget_visibility(saved.help_text, saved.help_text_visibility)
    state.mod_chrome_snapshot = nil
end

local function clear_mod_tab_state()
    state.mod_tab_controls = {}
    state.mod_tab_rows = {}
    state.mod_tab_active = false
    state.mod_tab_items_focused = false
    state.mod_tab_cursor = 0
    state.settings_capture = nil
end

local function restore_mod_tab()
    detach_mod_controls()
    detach_mod_rows()
    restore_mod_chrome()
    clear_mod_tab_state()
end

local function leave_mod_tab_after_native_rebuild()
    -- UE4SS invokes this Blueprint callback after ChangeCategory, when the
    -- game has already replaced or destroyed the old rows.
    -- Only the menu-owned chrome is still safe to restore here.
    restore_mod_chrome()
    clear_mod_tab_state()
end

local function forget_closed_mod_tab()
    state.mod_chrome_snapshot = nil
    clear_mod_tab_state()
end

local function attach_mod_control(parent, control, kind, row_index, padding, backing_widget)
    parent = unwrap(parent)
    control = unwrap(control)
    if not is_valid_object(parent) or not is_valid_object(control) then
        return false, "mod_control_parent_unavailable"
    end
    local added, slot = pcall(function()
        return parent:AddChild(control)
    end)
    slot = unwrap(slot)
    if not added or not is_valid_object(slot) then
        return false, added and "mod_control_add_returned_invalid" or slot
    end
    if kind == "label" then
        set_slot_padding(slot, padding or { Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    else
        local layout_ok, layout_error = pcall(function()
            -- The native ExWidget occupies a Fill/right/center HorizontalBox slot.
            -- AddChild creates an Automatic/left slot, so restore the native layout
            -- contract or the toggle and keycap widgets are clipped by the row label.
            slot:SetSize({ Value = 1.0, SizeRule = 1 })
            slot:SetHorizontalAlignment(3)
            slot:SetVerticalAlignment(2)
            slot:SetPadding(padding or { Left = 18.0, Top = 0.0, Right = 8.0, Bottom = 0.0 })
        end)
        if not layout_ok then
            pcall(function()
                parent:RemoveChild(control)
            end)
            return false, "mod_control_slot_layout_failed:" .. tostring(layout_error)
        end
    end
    set_widget_visibility(control, 0)
    table.insert(state.mod_tab_controls, {
        widget = control,
        parent = parent,
        kind = kind,
        row_index = row_index,
        backing_widget = backing_widget,
    })
    return true, nil
end

local function configure_key_control(control, key_name)
    control = unwrap(control)
    if not is_valid_object(control) then
        return false
    end
    local ok = pcall(function()
        control.TextText = FName(key_name)
        control.DescText = FName("None")
        control:UpdateText()
        local key_text = unwrap(control.Text)
        if is_valid_object(key_text) then
            key_text:SetRenderOpacity(1.0)
            key_text:SetVisibility(0)
        end
    end)
    return ok
end

local function create_mod_keycap(context, key_name)
    local converter, converter_error = create_key_converter(context)
    if not is_valid_object(converter) then
        return nil, converter_error
    end
    if not configure_key_control(converter, key_name) then
        return nil, "mod_keycap_configure_failed"
    end
    local key_text = unwrap(converter.Text)
    local original_parent = widget_parent(key_text)
    if not is_valid_object(key_text) or not is_valid_object(original_parent) then
        return nil, "mod_keycap_text_unavailable"
    end
    local removed, remove_result = pcall(function()
        return original_parent:RemoveChild(key_text)
    end)
    local removed_value = scalar_string(remove_result)
    if not removed or not (remove_result == true or removed_value == "true" or removed_value == "1") then
        return nil, "mod_keycap_detach_failed"
    end
    set_widget_visibility(key_text, 0)
    return {
        widget = key_text,
        backing_widget = converter,
    }, nil
end

local function set_literal_widget_text(widget, text)
    widget = unwrap(widget)
    if not is_valid_object(widget) then
        return false
    end
    local value = FText(text)
    local property_written = write_raw_field(widget, "Text", value)
    local method_called = pcall(function()
        widget:SetText(value)
    end)
    set_widget_visibility(widget, 0)
    return property_written or method_called
end

local function configure_toggle_control(control, value)
    control = unwrap(control)
    if not is_valid_object(control) then
        return false
    end
    local first_item = find_named_widget(control, "ToggleButtonItem_01")
    local second_item = find_named_widget(control, "ToggleButtonItem_02")
    if not is_valid_object(first_item) or not is_valid_object(second_item) then
        return false
    end
    local ok = pcall(function()
        local background = find_named_widget(control, "BottunBg")
        if is_valid_object(background) then
            background:SetVisibility(1)
        end
        second_item:SetVisibility(1)
        first_item:SetVisibility(0)

        local root_size = find_named_widget(first_item, "SizeBox_1")
        if is_valid_object(root_size) then
            root_size:SetWidthOverride(140.0)
            root_size:SetHeightOverride(40.0)
        end
        local item_size = find_named_widget(first_item, "SizeBox_3")
        if is_valid_object(item_size) then
            item_size:SetWidthOverride(140.0)
            item_size:SetHeightOverride(40.0)
        end

        local state_text = find_named_widget(first_item, "Text_False")
        if is_valid_object(state_text) then
            state_text:SetText(FText(value and "ON" or "OFF"))
            state_text:SetRenderOpacity(1.0)
            state_text:SetVisibility(0)
        end
        local check = find_named_widget(first_item, "Check_False")
        if is_valid_object(check) then
            check:SetRenderOpacity(value and 1.0 or 0.0)
            check:SetVisibility(0)
        end
        control:SetRenderOpacity(1.0)
        control:SetVisibility(0)
    end)
    return ok
end

local function configure_language_control(control, language, initialize)
    control = unwrap(control)
    if not is_valid_object(control) then
        return false
    end
    local ok, configure_error = pcall(function()
        if initialize then
            control:InitExWidget()
        end
        control:SetIndex(language.index)
        control:SetRenderOpacity(1.0)
        control:SetVisibility(0)
    end)
    return ok, ok and nil or compact(configure_error)
end

local function mod_row_available(index)
    if index == 0 or index == 3 then
        return true
    end
    if index == 1 or index == 2 then
        return config.enabled
    end
    if index == 4 or index == 5 or index == 6 then
        return config.translation_enabled
    end
    return analysis_available()
end

local function apply_mod_row_availability()
    for index, row in ipairs(state.mod_tab_rows) do
        row = unwrap(row)
        if is_valid_object(row) then
            local enabled = mod_row_available(index - 1)
            pcall(function()
                row:SetRenderOpacity(enabled and 1.0 or 0.38)
            end)
        end
    end
end

local function configure_mod_label(text_widget, text)
    text_widget = unwrap(text_widget)
    if not is_valid_object(text_widget) then
        return false
    end
    local ok = pcall(function()
        text_widget:SetText(FText(text))
        text_widget:SetRenderOpacity(1.0)
        text_widget:SetVisibility(0)
    end)
    return ok
end

local function create_mod_label(context, text)
    local backing_widget, label_error = create_blueprint_widget(
        context,
        "menu_guide_class",
        MENU_GUIDE_PACKAGE,
        MENU_GUIDE_CLASS
    )
    if not is_valid_object(backing_widget) then
        return nil, label_error
    end
    local text_widget = find_named_widget(backing_widget, "GuideText_00")
    local original_parent = widget_parent(text_widget)
    if not is_valid_object(text_widget) or not is_valid_object(original_parent) then
        return nil, "mod_row_label_text_unavailable"
    end
    local removed, remove_result = pcall(function()
        return original_parent:RemoveChild(text_widget)
    end)
    local removed_value = scalar_string(remove_result)
    if not removed or not (remove_result == true or removed_value == "true" or removed_value == "1") then
        return nil, "mod_row_label_text_detach_failed"
    end
    if not configure_mod_label(text_widget, text) then
        return nil, "mod_row_label_configure_failed"
    end
    return {
        widget = text_widget,
        backing_widget = backing_widget,
    }, nil
end

local function set_mod_header(menu)
    menu = unwrap(menu)
    if not is_valid_object(menu) or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    local title = find_named_widget(menu, "TitleText")
    if is_valid_object(title) then
        pcall(function()
            title:SetText(FText(MOD_CATEGORY_LABEL))
        end)
    end
end

local function mod_help_text()
    if state.settings_capture ~= nil then
        return "Press a letter key to assign this shortcut."
    end
    if not state.mod_tab_items_focused then
        return "Press confirm to configure the mod."
    end
    if state.mod_tab_cursor == 0 then
        return "Press left/right or confirm to enable or disable dialogue replay."
    end
    if state.mod_tab_cursor == 1 then
        return "Press confirm, then press a letter key for replaying the current line."
    end
    if state.mod_tab_cursor == 2 then
        return "Press confirm, then press a letter key for replaying the previous line."
    end
    if state.mod_tab_cursor == 3 then
        return "Press left/right or confirm to enable or disable translation and analysis."
    end
    if state.mod_tab_cursor == 4 then
        return "Press left/right to choose the translation language."
    end
    if state.mod_tab_cursor == 5 then
        return "Press confirm, then press a letter key for showing or hiding translation."
    end
    if state.mod_tab_cursor == 6 then
        return "Press left/right to choose the analysis language. Only Japanese is implemented."
    end
    return "Press confirm, then press a letter key for showing or hiding analysis."
end

local function apply_mod_chrome(menu)
    menu = unwrap(menu)
    if not is_valid_object(menu) or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    if state.mod_chrome_snapshot == nil then
        local title_image = find_named_widget(menu, "TitleImage")
        local footer = unwrap(read_raw_field(menu, "MainMenuFooter"))
        local help_text = find_named_widget(footer, "HelpText")
        state.mod_chrome_snapshot = {
            title_image = title_image,
            title_image_visibility = widget_visibility(title_image),
            footer = footer,
            help_text = help_text,
            help_text_visibility = widget_visibility(help_text),
        }
    end
    set_mod_header(menu)
    set_widget_visibility(state.mod_chrome_snapshot.title_image, 1)
    set_widget_visibility(state.mod_chrome_snapshot.help_text, 0)
    local help_value = FText(mod_help_text())
    local footer = unwrap(state.mod_chrome_snapshot.footer)
    local updated = false
    if is_valid_object(footer) then
        updated = pcall(function()
            footer:SetHelpText(help_value)
        end)
    end
    if not updated then
        set_literal_widget_text(state.mod_chrome_snapshot.help_text, mod_help_text())
    end
end

local function set_mod_cursor(menu, index, update_focus, direction)
    menu = unwrap(menu)
    if not is_valid_object(menu) or #state.mod_tab_rows < MOD_ROW_COUNT then
        return
    end
    direction = direction == -1 and -1 or 1
    index = ((tonumber(index) or 0) % MOD_ROW_COUNT + MOD_ROW_COUNT) % MOD_ROW_COUNT
    local attempts = 0
    while not mod_row_available(index) and attempts < MOD_ROW_COUNT do
        index = (index + direction + MOD_ROW_COUNT) % MOD_ROW_COUNT
        attempts = attempts + 1
    end
    state.mod_tab_cursor = index
    write_raw_field(menu, "CursorIndex", index)
    if update_focus ~= false then
        for row_index, row in ipairs(state.mod_tab_rows) do
            if is_valid_object(row) then
                pcall(function()
                    if state.mod_tab_items_focused and row_index - 1 == index then
                        row:Focus(true)
                    else
                        row:OutFocus(true)
                    end
                end)
            end
        end
    end
    apply_mod_chrome(menu)
end

local function mod_row_label(index)
    if index == 1 then
        return "DIALOGUE REPLAY"
    end
    if index == 2 then
        return "REPLAY CURRENT KEY"
    end
    if index == 3 then
        return "PREVIOUS LINE KEY"
    end
    if index == 4 then
        return "TRANSLATION"
    end
    if index == 5 then
        return "TRANSLATION LANGUAGE"
    end
    if index == 6 then
        return "TRANSLATION KEY"
    end
    if index == 7 then
        return "ANALYSIS LANGUAGE"
    end
    return "ANALYSIS KEY"
end

local function refresh_mod_tab(menu)
    menu = unwrap(menu)
    if not state.mod_tab_active or not is_valid_object(menu) then
        return false
    end
    set_mod_cursor(menu, state.mod_tab_cursor)
    for _, entry in ipairs(state.mod_tab_controls) do
        if entry.kind == "label" then
            configure_mod_label(entry.widget, mod_row_label(entry.row_index))
        elseif entry.kind == "replay_toggle" then
            configure_toggle_control(entry.widget, config.enabled)
        elseif entry.kind == "current_key" then
            configure_key_control(entry.backing_widget, config.replay_current_key)
        elseif entry.kind == "previous_key" then
            configure_key_control(entry.backing_widget, config.replay_previous_key)
        elseif entry.kind == "translation_toggle" then
            configure_toggle_control(entry.widget, config.translation_enabled)
        elseif entry.kind == "translation_language" then
            local configured, configure_error = configure_language_control(
                entry.widget,
                current_translation_language(),
                not entry.initialized
            )
            if configured then
                entry.initialized = true
            else
                report_option_ui_error("translation_language_control=" .. tostring(configure_error))
            end
        elseif entry.kind == "translation_key" then
            configure_key_control(entry.backing_widget, config.translation_key)
        elseif entry.kind == "analysis_language" then
            local configured, configure_error = configure_language_control(
                entry.widget,
                current_analysis_language(),
                not entry.initialized
            )
            if configured then
                entry.initialized = true
            else
                report_option_ui_error("analysis_language_control=" .. tostring(configure_error))
            end
        elseif entry.kind == "analysis_key" then
            configure_key_control(entry.backing_widget, config.analysis_key)
        end
    end
    apply_mod_row_availability()
    apply_mod_chrome(menu)
    state.option_ui_error = ""
    return true
end

local function create_mod_option_rows(menu)
    local vertical_box = find_named_widget(menu, "OptItemVerticalBox")
    if not is_valid_object(vertical_box) then
        return nil, "option_vertical_box_unavailable"
    end
    pcall(function()
        vertical_box:ClearChildren()
    end)
    local rows = {}
    local parents = {}
    local label_parents = {}
    for index = 1, MOD_ROW_COUNT do
        local row, row_error = create_blueprint_widget(
            menu,
            "option_row_class",
            OPTION_ROW_PACKAGE,
            OPTION_ROW_CLASS
        )
        if not is_valid_object(row) then
            return nil, row_error
        end
        pcall(function()
            row:InitInstance()
        end)
        local added, slot = pcall(function()
            return vertical_box:AddChild(row)
        end)
        if not added then
            return nil, slot
        end
        set_slot_padding(slot, { Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        set_widget_visibility(row, 0)
        for _, child_name in ipairs({ "Icon", "Border_Icon" }) do
            set_widget_visibility(find_named_widget(row, child_name), 1)
        end
        local ex_widget = find_named_widget(row, "ExWidget")
        local parent = widget_parent(ex_widget)
        if not is_valid_object(parent) then
            parent = find_named_widget(row, "HorizontalBox_1")
        end
        if not is_valid_object(parent) then
            return nil, "mod_row_control_parent_unavailable"
        end
        if is_valid_object(ex_widget) then
            set_widget_visibility(ex_widget, 1)
            pcall(function()
                parent:RemoveChild(ex_widget)
            end)
        end
        local param_name = find_named_widget(row, "ParamName")
        local label_parent = widget_parent(param_name)
        if not is_valid_object(param_name) or not is_valid_object(label_parent) then
            return nil, "mod_row_label_parent_unavailable"
        end
        local removed, remove_result = pcall(function()
            return label_parent:RemoveChild(param_name)
        end)
        local removed_value = scalar_string(remove_result)
        if not removed or not (remove_result == true or removed_value == "true" or removed_value == "1") then
            return nil, "mod_row_native_label_remove_failed"
        end
        set_widget_visibility(param_name, 1)
        rows[index] = row
        state.mod_tab_rows = rows
        parents[index] = parent
        label_parents[index] = label_parent
    end
    return {
        rows = rows,
        parents = parents,
        label_parents = label_parents,
    }, nil
end

local function build_mod_tab(menu)
    menu = unwrap(menu)
    if not is_valid_object(menu) then
        return false
    end
    restore_mod_tab()
    apply_mod_chrome(menu)

    local created, rows_error = create_mod_option_rows(menu)
    if created == nil or #created.rows ~= MOD_ROW_COUNT then
        restore_mod_tab()
        report_option_ui_error(rows_error or "mod_option_rows_create_failed")
        return false
    end

    state.mod_tab_rows = created.rows

    for index = 1, MOD_ROW_COUNT do
        local label, label_error = create_mod_label(menu, mod_row_label(index))
        if label == nil or not is_valid_object(label.widget) then
            report_option_ui_error(label_error)
            restore_mod_tab()
            return false
        end
        local attached, attach_error = attach_mod_control(
            created.label_parents[index],
            label.widget,
            "label",
            index,
            { Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 },
            label.backing_widget
        )
        if not attached then
            report_option_ui_error(attach_error)
            restore_mod_tab()
            return false
        end
    end

    local controls = {
        {
            kind = "replay_toggle",
            cache_key = "toggle_button_class",
            package = TOGGLE_BUTTON_PACKAGE,
            class = TOGGLE_BUTTON_CLASS,
        },
        {
            kind = "current_key",
            cache_key = "key_converter_class",
            package = KEY_CONVERTER_PACKAGE,
            class = KEY_CONVERTER_CLASS,
        },
        {
            kind = "previous_key",
            cache_key = "key_converter_class",
            package = KEY_CONVERTER_PACKAGE,
            class = KEY_CONVERTER_CLASS,
        },
        {
            kind = "translation_toggle",
            cache_key = "toggle_button_class",
            package = TOGGLE_BUTTON_PACKAGE,
            class = TOGGLE_BUTTON_CLASS,
        },
        {
            kind = "translation_language",
            cache_key = "language_button_class",
            package = LANGUAGE_BUTTON_PACKAGE,
            class = LANGUAGE_BUTTON_CLASS,
        },
        {
            kind = "translation_key",
            cache_key = "key_converter_class",
            package = KEY_CONVERTER_PACKAGE,
            class = KEY_CONVERTER_CLASS,
        },
        {
            kind = "analysis_language",
            cache_key = "language_button_class",
            package = LANGUAGE_BUTTON_PACKAGE,
            class = LANGUAGE_BUTTON_CLASS,
        },
        {
            kind = "analysis_key",
            cache_key = "key_converter_class",
            package = KEY_CONVERTER_PACKAGE,
            class = KEY_CONVERTER_CLASS,
        },
    }
    for index, spec in ipairs(controls) do
        local parent = created.parents[index]
        local control = nil
        local backing_widget = nil
        local control_error = nil
        if spec.kind == "current_key"
            or spec.kind == "previous_key"
            or spec.kind == "translation_key"
            or spec.kind == "analysis_key" then
            local key_name = config.translation_key
            if spec.kind == "current_key" then
                key_name = config.replay_current_key
            elseif spec.kind == "previous_key" then
                key_name = config.replay_previous_key
            elseif spec.kind == "analysis_key" then
                key_name = config.analysis_key
            end
            local keycap = nil
            keycap, control_error = create_mod_keycap(menu, key_name)
            if keycap ~= nil then
                control = keycap.widget
                backing_widget = keycap.backing_widget
            end
        else
            control, control_error = create_blueprint_widget(
                menu,
                spec.cache_key,
                spec.package,
                spec.class
            )
        end
        if not is_valid_object(control) then
            report_option_ui_error(control_error)
            restore_mod_tab()
            return false
        end
        local attached, attach_error = attach_mod_control(
            parent,
            control,
            spec.kind,
            index,
            nil,
            backing_widget
        )
        if not attached then
            report_option_ui_error(attach_error)
            restore_mod_tab()
            return false
        end
    end

    state.mod_tab_active = true
    state.mod_tab_items_focused = false
    state.mod_tab_cursor = 0
    state.settings_capture = nil
    refresh_mod_tab(menu)
    log("mod_tab_content_ready rows=" .. tostring(MOD_ROW_COUNT))
    return true
end

local function handle_category_changed(context)
    local menu = unwrap(context)
    if not is_valid_object(menu) then
        return
    end
    state.option_menu = menu
    state.option_menu_open = true
    local category = option_category_index(menu)
    log("option_category_changed index=" .. tostring(category))
    if category == MOD_CATEGORY_ID then
        apply_mod_chrome(menu)
        if not state.mod_tab_active then
            build_mod_tab(menu)
        end
        apply_mod_chrome(menu)
    elseif state.mod_tab_active then
        leave_mod_tab_after_native_rebuild()
    end
end

local function find_active_option_menu()
    local menu = unwrap(state.option_menu)
    if state.option_menu_open and is_valid_object(menu) and option_menu_is_active(menu) then
        return menu
    end
    if state.mod_tab_active then
        forget_closed_mod_tab()
    end
    state.option_menu_open = false
    local found, candidate = pcall(function()
        return FindFirstOf(OPTION_MENU_CLASS_NAME)
    end)
    candidate = unwrap(candidate)
    if found and is_valid_object(candidate) and option_menu_is_active(candidate) then
        state.option_menu = candidate
        state.option_menu_open = true
        return candidate
    end
    return nil
end

local function mark_option_menu_closed(context)
    local menu = unwrap(context)
    if not is_valid_object(state.option_menu) or full_name(menu) == full_name(state.option_menu) then
        forget_closed_mod_tab()
        state.option_menu_open = false
        state.option_menu = nil
    end
end

local function settings_field_available(field)
    if field == "replay_current_key" or field == "replay_previous_key" then
        return config.enabled
    end
    if field == "translation_key" then
        return config.translation_enabled
    end
    if field == "analysis_key" then
        return analysis_available()
    end
    return false
end

local function begin_settings_capture(field)
    local menu = find_active_option_menu()
    if not settings_field_available(field)
        or not state.mod_tab_active
        or not state.mod_tab_items_focused
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return false
    end
    state.settings_capture = field
    refresh_mod_tab(menu)
    return true
end

local function capture_settings_key(key_name)
    local menu = find_active_option_menu()
    if not state.mod_tab_active
        or state.settings_capture == nil
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return false
    end
    local field = state.settings_capture
    if not settings_field_available(field) then
        state.settings_capture = nil
        refresh_mod_tab(menu)
        return false
    end
    local old_key = config[field]
    for _, other in ipairs({ "replay_current_key", "replay_previous_key", "translation_key", "analysis_key" }) do
        if other ~= field and config[other] == key_name then
            config[other] = old_key
            break
        end
    end
    config[field] = key_name
    state.settings_capture = nil
    save_config()
    refresh_live_shortcut_hint()
    refresh_mod_tab(menu)
    log(string.format("settings_key_changed field=%s key=%s", field, key_name))
    return true
end

local function apply_translation_enabled(value)
    config.translation_enabled = value == true
    if not config.translation_enabled then
        hide_translation_overlay()
        hide_analysis_overlay()
    end
    save_config()
    refresh_live_shortcut_hint()
end

local function change_translation_language(delta, menu)
    local language = current_translation_language()
    local index = (language.index + delta) % #TRANSLATION_LANGUAGES
    config.translation_language = TRANSLATION_LANGUAGES[index + 1].code
    detach_translation_widget()
    save_config()
    if state.translation_visible then
        refresh_translation_overlay(state.current)
    end
    refresh_mod_tab(menu)
    log("settings_translation_language_changed language=" .. config.translation_language)
end

local function change_analysis_language(delta, menu)
    local language = current_analysis_language()
    local index = (language.index + delta) % #TRANSLATION_LANGUAGES
    config.analysis_language = TRANSLATION_LANGUAGES[index + 1].code
    if not analysis_available() then
        hide_analysis_overlay()
    end
    state.settings_capture = nil
    save_config()
    refresh_live_shortcut_hint()
    refresh_mod_tab(menu)
    log("settings_analysis_language_changed language=" .. config.analysis_language)
end

local function activate_mod_setting(menu)
    menu = unwrap(menu)
    if not state.mod_tab_active
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    local cursor = state.mod_tab_cursor
    state.mod_tab_cursor = cursor
    if cursor == 0 then
        config.enabled = not config.enabled
        state.settings_capture = nil
        save_config()
        refresh_live_shortcut_hint()
        refresh_mod_tab(menu)
    elseif cursor == 1 then
        begin_settings_capture("replay_current_key")
    elseif cursor == 2 then
        begin_settings_capture("replay_previous_key")
    elseif cursor == 3 then
        state.settings_capture = nil
        apply_translation_enabled(not config.translation_enabled)
        refresh_mod_tab(menu)
    elseif cursor == 5 then
        begin_settings_capture("translation_key")
    elseif cursor == 7 then
        begin_settings_capture("analysis_key")
    end
end

local function parameter_bool(value)
    value = unwrap(value)
    if type(value) == "boolean" then
        return value
    end
    local text = string.lower(scalar_string(value))
    return text == "true" or text == "1"
end

local function handle_mod_cursor_move(context, to_up)
    local menu = unwrap(context)
    if not state.mod_tab_active
        or not state.mod_tab_items_focused
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    local delta = parameter_bool(to_up) and -1 or 1
    set_mod_cursor(menu, state.mod_tab_cursor + delta, true, delta)
end

local function handle_mod_decide_menu(context)
    local menu = unwrap(context)
    if not state.mod_tab_active
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    if not state.mod_tab_items_focused then
        state.mod_tab_items_focused = true
        state.settings_capture = nil
        set_mod_cursor(menu, 0)
        log("settings_content_entered")
        return
    end
    log("settings_decide cursor=" .. tostring(state.mod_tab_cursor))
    activate_mod_setting(menu)
end

local function handle_mod_left_right(context, is_left)
    local menu = unwrap(context)
    if not state.mod_tab_active
        or not state.mod_tab_items_focused
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    if state.mod_tab_cursor == 0 or state.mod_tab_cursor == 3 then
        log("settings_toggle direction=" .. (parameter_bool(is_left) and "left" or "right"))
        activate_mod_setting(menu)
    elseif state.mod_tab_cursor == 4 and config.translation_enabled then
        change_translation_language(parameter_bool(is_left) and -1 or 1, menu)
    elseif state.mod_tab_cursor == 6 and config.translation_enabled then
        change_analysis_language(parameter_bool(is_left) and -1 or 1, menu)
    end
end

local function handle_mod_cancel(context)
    local menu = unwrap(context)
    if not state.mod_tab_active
        or not is_valid_object(menu)
        or option_category_index(menu) ~= MOD_CATEGORY_ID then
        return
    end
    if state.settings_capture ~= nil then
        state.settings_capture = nil
        refresh_mod_tab(menu)
        return
    end
    if state.mod_tab_items_focused then
        state.mod_tab_items_focused = false
        set_mod_cursor(menu, state.mod_tab_cursor)
        log("settings_content_left")
    end
end

local function keep_mod_footer_text()
    if not state.option_menu_open or not state.mod_tab_active then
        return
    end
    local menu = state.option_menu
    if is_valid_object(menu)
        and option_category_index(menu) == MOD_CATEGORY_ID then
        apply_mod_chrome(menu)
    end
end

local function copy_array_values(value, value_kind)
    local array = unwrap(value)
    if array == nil then
        return nil, "missing_array"
    end
    local ok, count = pcall(function()
        return array:GetArrayNum()
    end)
    if not ok or count == nil then
        return nil, "not_array"
    end

    local values = {}
    local copied, copy_error = pcall(function()
        array:ForEach(function(_, element)
            local item = unwrap(element)
            if value_kind == "string" then
                -- DrawTexts may contain explicit line breaks. Logging can compact them,
                -- but the replay snapshot must preserve the exact string.
                table.insert(values, exact_string(item))
            else
                -- FName returned by RemoteUnrealParam:get() is a Lua-owned copy.
                table.insert(values, item)
            end
            return false
        end)
    end)
    if not copied or #values ~= count then
        return nil, compact(copy_error or "array_count_mismatch")
    end
    return values, nil
end

local function replace_array_values(value, values)
    local array = unwrap(value)
    if array == nil or values == nil then
        return false, "missing_array_values"
    end
    local ok, count = pcall(function()
        return array:GetArrayNum()
    end)
    if not ok or count ~= #values then
        return false, string.format("array_size live=%s saved=%s", tostring(count), tostring(#values))
    end

    local written = 0
    local replaced, replace_error = pcall(function()
        array:ForEach(function(_, element)
            written = written + 1
            element:set(values[written])
            return false
        end)
    end)
    if not replaced or written ~= #values then
        return false, compact(replace_error or "array_write_mismatch")
    end
    return true, nil
end

local speaker_widget_fields = {
    "Name",
    "Name_02",
    "NameTextBlock",
    "NameTextBlock_02",
}

local function snapshot_speaker_widgets(balloon)
    local snapshot = {}
    balloon = unwrap(balloon)
    if not is_valid_object(balloon) then
        return snapshot
    end
    for _, field in ipairs(speaker_widget_fields) do
        local widget = unwrap(read_raw_field(balloon, field))
        if is_valid_object(widget) then
            local item = {
                widget = widget,
                visibility = tonumber(scalar_string(call_no_arg_raw(widget, "GetVisibility"))),
            }
            if field == "NameTextBlock" or field == "NameTextBlock_02" then
                item.text = call_no_arg_raw(widget, "GetText")
            end
            snapshot[field] = item
        end
    end
    return snapshot
end

local function apply_speaker_snapshot(balloon, snapshot)
    balloon = unwrap(balloon)
    if not is_valid_object(balloon) or snapshot == nil then
        return
    end
    for _, field in ipairs(speaker_widget_fields) do
        local saved = snapshot[field]
        local widget = unwrap(read_raw_field(balloon, field))
        if saved ~= nil and is_valid_object(widget) then
            if saved.text ~= nil then
                pcall(function()
                    widget:SetText(saved.text)
                end)
            end
            if saved.visibility ~= nil then
                pcall(function()
                    widget:SetVisibility(saved.visibility)
                end)
            end
        end
    end
end

local function snapshot_vector2d(value)
    value = unwrap(value)
    if value == nil then
        return nil
    end
    local x = tonumber(exact_string(read_raw_field(value, "X")))
    local y = tonumber(exact_string(read_raw_field(value, "Y")))
    if x == nil or y == nil then
        return nil
    end
    return { X = x, Y = y }
end

local function write_field(object, field, value)
    object = unwrap(object)
    if object == nil then
        return false, "missing_" .. field
    end
    local ok, write_error = pcall(function()
        object[field] = value
    end)
    if not ok then
        return false, compact(write_error)
    end
    return true, nil
end

local function snapshot_balloon_state(balloon)
    balloon = unwrap(balloon)
    local param = unwrap(read_raw_field(balloon, "BalloonParam"))
    if not is_valid_object(balloon) or param == nil then
        return nil, "missing_balloon_param"
    end

    local text_param = unwrap(read_raw_field(param, "Text"))
    local name_values = nil
    local name_error = "missing_text_param"
    if text_param ~= nil then
        name_values, name_error = copy_array_values(read_raw_field(text_param, "Names"), "name")
    end

    return {
        target_actor = unwrap(read_raw_field(param, "TargetActor")),
        balloon_dir = unwrap(read_raw_field(param, "BalloonDir")),
        enable_tail = unwrap(read_raw_field(param, "EnableTail")),
        balloon_offset_scale = unwrap(read_raw_field(param, "BalloonOffsetScale")),
        offset = snapshot_vector2d(read_raw_field(param, "Offset")),
        under_offset = snapshot_vector2d(read_raw_field(param, "UnderOffset")),
        offset_param = snapshot_vector2d(read_raw_field(balloon, "OffsetParam")),
        text_type = text_param and unwrap(read_raw_field(text_param, "Type")) or nil,
        name_values = name_values,
        name_error = name_error,
    }, nil
end

local function apply_balloon_state(balloon, snapshot)
    balloon = unwrap(balloon)
    if not is_valid_object(balloon) or snapshot == nil then
        return false, "missing_balloon_snapshot"
    end
    local param = unwrap(read_raw_field(balloon, "BalloonParam"))
    local text_param = param and unwrap(read_raw_field(param, "Text")) or nil
    if param == nil or text_param == nil then
        return false, "missing_live_balloon_param"
    end

    local errors = {}
    local function write(object, field, value)
        local ok, write_error = write_field(object, field, value)
        if not ok then
            table.insert(errors, field .. "=" .. tostring(write_error))
        end
    end

    -- TargetActor and OffsetParam are both consumed by UpdateTranslation.
    -- Restore the complete positioning inputs before rebuilding the balloon.
    write(param, "TargetActor", snapshot.target_actor)
    if snapshot.balloon_dir ~= nil then
        write(param, "BalloonDir", snapshot.balloon_dir)
    end
    if snapshot.enable_tail ~= nil then
        write(param, "EnableTail", snapshot.enable_tail)
    end
    if snapshot.balloon_offset_scale ~= nil then
        write(param, "BalloonOffsetScale", snapshot.balloon_offset_scale)
    end
    if snapshot.offset ~= nil then
        write(param, "Offset", snapshot.offset)
    end
    if snapshot.under_offset ~= nil then
        write(param, "UnderOffset", snapshot.under_offset)
    end
    if snapshot.offset_param ~= nil then
        write(balloon, "OffsetParam", snapshot.offset_param)
    end
    if snapshot.text_type ~= nil then
        write(text_param, "Type", snapshot.text_type)
    end
    if snapshot.name_values ~= nil then
        local names_written, names_error = replace_array_values(
            read_raw_field(text_param, "Names"),
            snapshot.name_values
        )
        if not names_written then
            table.insert(errors, "Names=" .. tostring(names_error))
        end
    end

    return #errors == 0, table.concat(errors, ";")
end

local function apply_native_speaker_label(balloon, balloon_snapshot, speaker_snapshot)
    apply_speaker_snapshot(balloon, speaker_snapshot)
    if balloon_snapshot == nil or balloon_snapshot.name_values == nil then
        return
    end
    local label = balloon_snapshot.name_values[1]
    local label_text = exact_string(label)
    if label == nil or label_text == "" or label_text == "None" then
        return
    end
    for _, field in ipairs({"NameTextBlock", "NameTextBlock_02"}) do
        local widget = unwrap(read_raw_field(balloon, field))
        if is_valid_object(widget) then
            pcall(function()
                widget:SetGameText(label)
            end)
        end
    end
end

local function rebuild_balloon_layout(talk_text, balloon, balloon_snapshot, speaker_snapshot, finish_text)
    local state_applied, state_error = apply_balloon_state(balloon, balloon_snapshot)
    if not state_applied then
        return false, "balloon_state=" .. tostring(state_error)
    end

    local prepared, prepare_error = pcall(function()
        if balloon_snapshot.text_type ~= nil then
            balloon:SetTypeImageFromTalkChara(0, balloon_snapshot.text_type)
        end
        apply_native_speaker_label(balloon, balloon_snapshot, speaker_snapshot)
        talk_text.TextIndex = 0
        talk_text:InitAnim()
        if finish_text then
            talk_text:EndAnimation()
        else
            talk_text.Animation = false
        end
        balloon:InitSize(0)
        balloon:SetupBalloonTair()
        -- InitSize and tail setup change name widget state. Restore it last so
        -- repeated replay keeps the same native name label and visibility.
        apply_native_speaker_label(balloon, balloon_snapshot, speaker_snapshot)
        if balloon_snapshot.target_actor ~= nil and is_valid_object(balloon_snapshot.target_actor) then
            balloon:UpdateTranslation()
        else
            balloon:SetTranslation()
        end
    end)
    if not prepared then
        return false, compact(prepare_error)
    end
    return true, nil
end

local function sequence_info(query, player)
    local actor = direct_outer(player)
    local current_raw = call_no_arg_raw(player, "GetCurrentTime")
    local start_raw = call_no_arg_raw(player, "GetStartTime")
    local finish_raw = call_no_arg_raw(player, "GetEndTime")
    local status_field = read_field(player, "Status")
    return {
        query = query,
        object = full_name(player),
        current = describe_value(current_raw),
        start = describe_value(start_raw),
        finish = describe_value(finish_raw),
        frame = read_nested_number(current_raw, "Time", "FrameNumber", "Value"),
        subframe = read_nested_number(current_raw, "Time", "SubFrame"),
        rate_numerator = read_nested_number(current_raw, "Rate", "Numerator"),
        rate_denominator = read_nested_number(current_raw, "Rate", "Denominator"),
        start_frame = read_nested_number(start_raw, "Time", "FrameNumber", "Value"),
        finish_frame = read_nested_number(finish_raw, "Time", "FrameNumber", "Value"),
        rate = call_no_arg(player, "GetPlayRate"),
        playing = call_no_arg(player, "IsPlaying"),
        status = call_no_arg(player, "GetPlaybackStatus"),
        status_field = status_field,
        status_number = tonumber(status_field),
        sequence = read_field(player, "Sequence"),
        actor_asset = read_field(actor, "LevelSequenceAsset"),
        player = player,
    }
end

local function is_rich_event(info)
    return info ~= nil
        and info.frame ~= nil
        and info.sequence ~= nil
        and string.find(info.sequence, "/Game/Event/RichEvent/", 1, true) ~= nil
end

local function apply_sequence_binding(record, info)
    if record == nil or info == nil then
        return
    end
    record.sequence_player = info.player
    record.sequence_object = info.object
    record.sequence_name = info.sequence
    record.sequence_frame = info.frame
    record.sequence_subframe = info.subframe or 0
    record.sequence_rate_numerator = info.rate_numerator
    record.sequence_rate_denominator = info.rate_denominator
    record.sequence_start_frame = info.start_frame
    record.sequence_finish_frame = info.finish_frame
end

local function collect_sequence_players()
    local snapshot = {}
    local order = {}
    local seen = {}
    for _, query in ipairs({"LevelSequencePlayer", "MovieSceneSequencePlayer"}) do
        local ok, players = pcall(function()
            return FindAllOf(query)
        end)
        if ok and players ~= nil then
            for _, player in ipairs(players) do
                local name = full_name(player)
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    snapshot[name] = sequence_info(query, player)
                    table.insert(order, name)
                    if #order >= 16 then
                        break
                    end
                end
            end
        end
        if #order >= 16 then
            break
        end
    end
    table.sort(order)
    return snapshot, order
end

local function log_sequence(prefix, info)
    log(string.format(
        "%s object=%s current=%s start=%s end=%s rate=%s playing=%s status=%s status_field=%s sequence=%s actor_asset=%s",
        prefix,
        info.object,
        info.current,
        info.start,
        info.finish,
        info.rate,
        info.playing,
        info.status,
        info.status_field,
        info.sequence,
        info.actor_asset
    ))
end

local function capture_sequence_delta(voice_label)
    local snapshot, order = collect_sequence_players()
    local previous = state.sequence_snapshot
    local emitted = 0
    local candidates = {}
    if previous == nil then
        for _, name in ipairs(order) do
            local current = snapshot[name]
            log_sequence("sequence_baseline voice=" .. voice_label, current)
            emitted = emitted + 1
            if is_rich_event(current) and current.status_number == 5 and current.frame > 0 then
                table.insert(candidates, { before = current, current = current })
            end
        end
    else
        for _, name in ipairs(order) do
            local current = snapshot[name]
            local before = previous[name]
            if before ~= nil and before.current ~= current.current then
                log(string.format(
                    "sequence_delta voice=%s object=%s from=%s to=%s sequence=%s actor_asset=%s",
                    voice_label,
                    current.object,
                    before.current,
                    current.current,
                    current.sequence,
                    current.actor_asset
                ))
                emitted = emitted + 1
                if is_rich_event(current)
                    and before.sequence == current.sequence
                    and current.status_number == 5 then
                    table.insert(candidates, { before = before, current = current })
                end
            end
        end
    end
    state.sequence_snapshot = snapshot
    log(string.format("sequence_talk_snapshot voice=%s players=%d emitted=%d", voice_label, #order, emitted))
    if #candidates == 1 then
        local binding = candidates[1]
        log(string.format(
            "line_binding voice=%s object=%s from_frame=%s to_frame=%s rate=%s/%s",
            voice_label,
            binding.current.object,
            tostring(binding.before.frame),
            tostring(binding.current.frame),
            tostring(binding.current.rate_numerator),
            tostring(binding.current.rate_denominator)
        ))
        return binding
    end
    if #candidates > 1 then
        log(string.format("line_binding_skipped voice=%s reason=ambiguous candidates=%d", voice_label, #candidates))
    end
    return nil
end

local function dump_sequence_players()
    local snapshot, order = collect_sequence_players()
    for index, name in ipairs(order) do
        local info = snapshot[name]
        log_sequence("sequence_player query=" .. info.query, info)
        if index <= 3 then
            dump_candidate_properties(info.player, "sequence_player")
        end
    end
    log(string.format("sequence_player_dump_end count=%d", #order))
end

local function set_history_index(index)
    if index == nil or index < 1 or index > #state.history then
        return
    end
    state.history_index = index
    state.current = state.history[index]
    state.previous = state.history[index - 1]
    refresh_translation_overlay(state.current)
    refresh_analysis_overlay(state.current)
end

local function find_history_index(record)
    if record.sequence_object == nil or record.sequence_frame == nil then
        return nil
    end
    for index = #state.history, 1, -1 do
        local existing = state.history[index]
        if existing.sequence_object == record.sequence_object
            and existing.sequence_frame == record.sequence_frame
            and existing.voice_label == record.voice_label then
            return index
        end
    end
    return nil
end

local function append_history(record)
    while state.history_index > 0 and #state.history > state.history_index do
        table.remove(state.history)
    end
    table.insert(state.history, record)
    if #state.history > MAX_HISTORY then
        table.remove(state.history, 1)
    end
    set_history_index(#state.history)
end

local function capture_talk_text(context)
    local object = unwrap(context)
    if object == nil then
        return
    end

    local balloon = balloon_from_talk_text(object)
    ensure_shortcut_hint(object)
    local draw_text_values, draw_text_error = copy_array_values(read_raw_field(object, "DrawTexts"), "string")
    local voice_name_values, voice_name_error = copy_array_values(read_raw_field(object, "VoiceLabel"), "name")
    local record = {
        object_name = full_name(object),
        object_class = class_name(object),
        outer = outer_chain(object),
        talk_text = object,
        balloon = balloon,
        voice_label = read_field(object, "VoiceLabel"),
        text_index = read_field(object, "TextIndex"),
        text_index_number = tonumber(scalar_string(read_raw_field(object, "TextIndex"))) or 0,
        origin_text = read_field(object, "OriginText"),
        texts = read_field(object, "DrawTexts"),
        draw_text_values = draw_text_values,
        draw_text_error = draw_text_error,
        voice_name_values = voice_name_values,
        voice_name_error = voice_name_error,
        speaker_snapshot = snapshot_speaker_widgets(balloon),
        balloon_snapshot = select(1, snapshot_balloon_state(balloon)),
        captured_at = os.time(),
    }

    log(string.format(
        "talk voice=%s text_index=%s text=%s object=%s",
        record.voice_label,
        record.text_index,
        record.origin_text,
        record.object_name
    ))
    local pending = state.manual_replay
    if pending ~= nil and pending.object_name == record.object_name then
        state.manual_replay = nil
        set_history_index(pending.history_index)
        log(string.format(
            "in_place_replay_voice label=%s history_index=%d voice=%s",
            pending.label,
            pending.history_index,
            record.voice_label
        ))
        return
    end

    state.live_talk_text = object
    state.live_balloon = balloon

    local binding = capture_sequence_delta(record.voice_label)
    if binding ~= nil then
        if state.current ~= nil then
            apply_sequence_binding(state.current, binding.before)
        end
        apply_sequence_binding(record, binding.current)
    end

    local existing_index = find_history_index(record)
    if existing_index ~= nil then
        state.history[existing_index] = record
        set_history_index(existing_index)
        log(string.format("line_history_revisit index=%d voice=%s", existing_index, record.voice_label))
    else
        append_history(record)
        log(string.format("line_history_append index=%d voice=%s", state.history_index, record.voice_label))
    end
    dump_candidate_properties(object, "talk")
end

local hook_specs = {
    {
        name = "PlayVoice",
        path = "/Game/UserInterface/Balloon/BP/TalkText.TalkText_C:PlayVoice",
        callback = function(context)
            capture_talk_text(context)
        end,
    },
    {
        name = "OnEventSpeedChange",
        path = "/Game/UserInterface/Event/BP/UIEventSkip.UIEventSkip_C:OnEventSpeedChange",
        callback = function(context)
            state.event_ui = unwrap(context)
            state.last_speed_change = tostring(os.time())
            log("speed mode changed")
            dump_candidate_properties(context, "speed")
        end,
    },
    {
        name = "OptionCloseMenu",
        path = "/Game/UserInterface/Option/BP/OptionMenuWBP.OptionMenuWBP_C:CloseMenu",
        callback = function(context)
            mark_option_menu_closed(context)
        end,
    },
    {
        name = "OptionChangeCategory",
        path = "/Game/UserInterface/Option/BP/OptionMenuWBP.OptionMenuWBP_C:ChangeCategory",
        callback = function(context)
            handle_category_changed(context)
        end,
    },
    {
        name = "OptionMoveCursor",
        path = "/Game/UserInterface/Option/BP/OptionMenuWBP.OptionMenuWBP_C:MoveCursor",
        callback = function(context, to_up)
            handle_mod_cursor_move(context, to_up)
        end,
    },
    {
        name = "OptionOnDecideOption",
        path = "/Game/UserInterface/Option/BP/OptionMenuWBP.OptionMenuWBP_C:OnDecideOption",
        callback = function(context)
            handle_mod_decide_menu(context)
        end,
    },
    {
        name = "OptionSendLRToExWidget",
        path = "/Game/UserInterface/Option/BP/OptionMenuWBP.OptionMenuWBP_C:SendLRToExWidget",
        callback = function(context, is_left)
            handle_mod_left_right(context, is_left)
        end,
    },
    {
        name = "OptionOnCancel",
        path = "/Game/UserInterface/Option/BP/OptionMenuWBP.OptionMenuWBP_C:OnCancel",
        callback = function(context)
            handle_mod_cancel(context)
        end,
    },
    {
        name = "OptionFooterHelp",
        path = "/Game/UserInterface/Common/BP/MenuFooter.MenuFooter_C:SetHelpGameTextLabel",
        callback = function()
            keep_mod_footer_text()
        end,
    },
}

local function install_pending_hooks()
    local pending = 0
    for _, spec in ipairs(hook_specs) do
        if not installed_hooks[spec.name] then
            local ok, pre_id, post_id = pcall(function()
                return RegisterHook(spec.path, spec.callback)
            end)
            if ok and pre_id ~= nil then
                installed_hooks[spec.name] = {
                    path = spec.path,
                    pre_id = pre_id,
                    post_id = post_id,
                }
                log("hooked " .. spec.name)
            else
                pending = pending + 1
            end
        end
    end
    return pending == 0
end

local function dump_state()
    local current = state.current or {}
    local previous = state.previous or {}
    log(string.format(
        "state version=%s history=%d history_index=%d current_voice=%s current_index=%s current_text=%s previous_voice=%s previous_index=%s previous_text=%s",
        VERSION,
        #state.history,
        state.history_index,
        current.voice_label or "",
        current.text_index or "",
        current.origin_text or "",
        previous.voice_label or "",
        previous.text_index or "",
        previous.origin_text or ""
    ))
    dump_sequence_players()
end


local function replay_history_line(index, label)
    local record = state.history[index]
    if record == nil then
        log("native_replay_unavailable label=" .. label .. " reason=no_line")
        return
    end
    if not is_valid_object(record.sequence_player) then
        log("native_replay_unavailable label=" .. label .. " reason=stale_player")
        return
    end
    if record.sequence_name == nil
        or string.find(record.sequence_name, "/Game/Event/RichEvent/", 1, true) == nil then
        log("native_replay_unavailable label=" .. label .. " reason=not_rich_event")
        return
    end
    if record.sequence_frame == nil
        or record.sequence_rate_numerator == nil
        or record.sequence_rate_denominator == nil
        or record.sequence_rate_denominator == 0 then
        log("native_replay_unavailable label=" .. label .. " reason=missing_frame")
        return
    end

    local player = unwrap(record.sequence_player)
    local live = sequence_info("replay", player)
    if live.object ~= record.sequence_object or live.sequence ~= record.sequence_name then
        log("native_replay_unavailable label=" .. label .. " reason=sequence_changed")
        return
    end
    if live.status_number ~= 5 then
        log(string.format(
            "native_replay_unavailable label=%s reason=sequence_not_paused status=%s",
            label,
            tostring(live.status_field)
        ))
        return
    end
    local talk_text = unwrap(state.live_talk_text or record.talk_text)
    local balloon = unwrap(state.live_balloon or record.balloon)
    if not is_valid_object(talk_text) or not is_valid_object(balloon) then
        log("native_replay_unavailable label=" .. label .. " reason=no_live_dialogue")
        return
    end
    if record.draw_text_values == nil or record.voice_name_values == nil then
        log(string.format(
            "native_replay_unavailable label=%s reason=missing_dialogue_data text=%s voice=%s",
            label,
            tostring(record.draw_text_error),
            tostring(record.voice_name_error)
        ))
        return
    end

    local live_draw_texts = read_raw_field(talk_text, "DrawTexts")
    local live_voice_names = read_raw_field(talk_text, "VoiceLabel")
    local current_draw_values = copy_array_values(live_draw_texts, "string")
    local current_voice_values = copy_array_values(live_voice_names, "name")
    local current_speaker_snapshot = snapshot_speaker_widgets(balloon)
    local current_balloon_snapshot = select(1, snapshot_balloon_state(balloon))
    if current_draw_values == nil or current_voice_values == nil
        or #current_draw_values ~= #record.draw_text_values
        or #current_voice_values ~= #record.voice_name_values
        or current_balloon_snapshot == nil
        or record.balloon_snapshot == nil then
        log("native_replay_unavailable label=" .. label .. " reason=array_shape_changed")
        return
    end

    local frames_per_second = record.sequence_rate_numerator / record.sequence_rate_denominator
    local target_seconds = (record.sequence_frame + (record.sequence_subframe or 0)) / frames_per_second
    local restore_seconds = nil
    if live.frame ~= nil and live.rate_numerator ~= nil and live.rate_denominator ~= nil
        and live.rate_denominator ~= 0 then
        restore_seconds = (live.frame + (live.subframe or 0)) / (live.rate_numerator / live.rate_denominator)
    end
    local function restore_sequence_time()
        if restore_seconds ~= nil then
            pcall(function()
                player:JumpToSeconds(restore_seconds)
            end)
        end
        state.sequence_snapshot = select(1, collect_sequence_players())
    end

    local jumped, jump_error = pcall(function()
        player:JumpToSeconds(target_seconds)
    end)
    if not jumped then
        log(string.format("native_replay_failed label=%s step=jump error=%s", label, compact(jump_error)))
        return
    end

    state.sequence_snapshot = select(1, collect_sequence_players())

    pcall(function()
        talk_text:StopVoice()
    end)
    local text_replaced, text_error = replace_array_values(live_draw_texts, record.draw_text_values)
    local voice_replaced, voice_error = replace_array_values(live_voice_names, record.voice_name_values)
    if not text_replaced or not voice_replaced then
        replace_array_values(live_draw_texts, current_draw_values)
        replace_array_values(live_voice_names, current_voice_values)
        restore_sequence_time()
        log(string.format(
            "native_replay_failed label=%s step=replace text=%s voice=%s",
            label,
            tostring(text_error),
            tostring(voice_error)
        ))
        return
    end

    local prepared, prepare_error = rebuild_balloon_layout(
        talk_text,
        balloon,
        record.balloon_snapshot,
        record.speaker_snapshot,
        false
    )
    if not prepared then
        replace_array_values(live_draw_texts, current_draw_values)
        replace_array_values(live_voice_names, current_voice_values)
        rebuild_balloon_layout(
            talk_text,
            balloon,
            current_balloon_snapshot,
            current_speaker_snapshot,
            true
        )
        restore_sequence_time()
        log(string.format("native_replay_failed label=%s step=prepare error=%s", label, compact(prepare_error)))
        return
    end

    state.manual_replay = {
        label = label,
        history_index = index,
        object_name = full_name(talk_text),
    }
    local started, start_error = pcall(function()
        talk_text:StartAnimation()
    end)
    if not started then
        state.manual_replay = nil
        replace_array_values(live_draw_texts, current_draw_values)
        replace_array_values(live_voice_names, current_voice_values)
        rebuild_balloon_layout(
            talk_text,
            balloon,
            current_balloon_snapshot,
            current_speaker_snapshot,
            true
        )
        restore_sequence_time()
        log(string.format("native_replay_failed label=%s step=start error=%s", label, compact(start_error)))
        return
    end
    state.manual_replay = nil
    set_history_index(index)
    pcall(function()
        balloon.CurrentPlayVoice = read_raw_field(talk_text, "Play Voice") == true
    end)

    log(string.format(
        "native_replay_in_place label=%s history_index=%d object=%s frame=%s voice=%s balloon=%s",
        label,
        index,
        record.sequence_object,
        tostring(record.sequence_frame),
        record.voice_label,
        full_name(balloon)
    ))
end

local function replay_current_line()
    replay_history_line(state.history_index, "current")
end

local function replay_previous_line()
    replay_history_line(state.history_index - 1, "previous")
end

log("loaded version=" .. VERSION .. "; in-place native replay, official translation, and dialogue analysis")
local hooks_ready = install_pending_hooks()
local hook_retry_queued = false
LoopAsync(2000, function()
    if hooks_ready then return true end
    if not hook_retry_queued then
        hook_retry_queued = true
        ExecuteInGameThread(function()
            hooks_ready = install_pending_hooks()
            hook_retry_queued = false
        end)
    end
    return false
end)

RegisterKeyBind(Key.F6, {ModifierKey.CONTROL, ModifierKey.SHIFT}, function()
    ExecuteInGameThread(dump_state)
end)

for _, key_name in ipairs(ALLOWED_SHORTCUT_KEYS) do
    local captured_key_name = key_name
    RegisterKeyBind(Key[captured_key_name], function()
        ExecuteInGameThread(function()
            if state.mod_tab_active then
                if state.settings_capture ~= nil then
                    capture_settings_key(captured_key_name)
                end
                return
            end
            if analysis_available() and captured_key_name == config.analysis_key then
                toggle_analysis_overlay()
                return
            end
            if config.translation_enabled and captured_key_name == config.translation_key then
                toggle_translation_overlay()
                return
            end
            if config.enabled and captured_key_name == config.replay_current_key then
                replay_current_line()
                return
            end
            if config.enabled and captured_key_name == config.replay_previous_key then
                replay_previous_line()
            end
        end)
    end)
end
