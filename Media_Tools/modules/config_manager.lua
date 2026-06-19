-- @noindex

local reaper = reaper

local ConfigManager = {}

ConfigManager.DEFAULTS = {
    theme_bg              = {0.08, 0.08, 0.10},
    theme_accent          = {0.50, 0.35, 0.80},
    theme_text            = {0.92, 0.92, 0.95},
    theme_danger          = {0.65, 0.25, 0.25},
    theme_positive        = {0.25, 0.55, 0.28},
    theme_slider_grab     = {0.50, 0.35, 0.80},
    theme_apply_btn       = {0.35, 0.14, 0.88},
    theme_frame_bg        = {0.15, 0.15, 0.17},
    theme_check_mark      = {0.50, 0.35, 0.80},
    theme_inactive_btn    = {0.16, 0.16, 0.20},
    theme_inactive_btn_text = {0.55, 0.55, 0.60},
    theme_active_btn      = {0.45, 0.25, 0.73},
    settings_write_keyswitches = false
}

function ConfigManager.get_settings_file_path()
    local sep = package.config:sub(1,1)
    return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "Walter_MediaOffset_Settings.txt"
end

function ConfigManager.load_settings()
    -- Start with a copy of defaults
    local themes = {}
    for k, v in pairs(ConfigManager.DEFAULTS) do
        if type(v) == "table" then
            themes[k] = {v[1], v[2], v[3]}
        end
    end
    local settings_write_keyswitches = ConfigManager.DEFAULTS.settings_write_keyswitches

    local path = ConfigManager.get_settings_file_path()
    local f = io.open(path, "r")
    if not f then
        return themes, settings_write_keyswitches
    end

    for line in f:lines() do
        line = line:gsub("[\r\n]", "")
        local key, val = line:match("^([^=]+)=(.+)$")
        if key and val then
            local parts = {}
            for v in val:gmatch("[^,]+") do
                parts[#parts+1] = tonumber(v)
            end
            if key == "bg" and #parts == 3 then
                themes.theme_bg = {parts[1], parts[2], parts[3]}
            elseif key == "accent" and #parts == 3 then
                themes.theme_accent = {parts[1], parts[2], parts[3]}
            elseif key == "text" and #parts == 3 then
                themes.theme_text = {parts[1], parts[2], parts[3]}
            elseif key == "danger" and #parts == 3 then
                themes.theme_danger = {parts[1], parts[2], parts[3]}
            elseif key == "positive" and #parts == 3 then
                themes.theme_positive = {parts[1], parts[2], parts[3]}
            elseif key == "slider_grab" and #parts == 3 then
                themes.theme_slider_grab = {parts[1], parts[2], parts[3]}
            elseif key == "apply_btn" and #parts == 3 then
                themes.theme_apply_btn = {parts[1], parts[2], parts[3]}
            elseif key == "frame_bg" and #parts == 3 then
                themes.theme_frame_bg = {parts[1], parts[2], parts[3]}
            elseif key == "check_mark" and #parts == 3 then
                themes.theme_check_mark = {parts[1], parts[2], parts[3]}
            elseif key == "inactive_btn" and #parts == 3 then
                themes.theme_inactive_btn = {parts[1], parts[2], parts[3]}
            elseif key == "inactive_btn_text" and #parts == 3 then
                themes.theme_inactive_btn_text = {parts[1], parts[2], parts[3]}
            elseif key == "active_btn" and #parts == 3 then
                themes.theme_active_btn = {parts[1], parts[2], parts[3]}
            elseif key == "write_keyswitches" or key == "settings_write_keyswitches" then
                settings_write_keyswitches = (val == "1" or val == "true")
            end
        end
    end
    f:close()
    return themes, settings_write_keyswitches
end

function ConfigManager.save_settings(themes, settings_write_keyswitches)
    local path = ConfigManager.get_settings_file_path()
    local f = io.open(path, "w")
    if not f then return end

    local bg = themes.theme_bg or ConfigManager.DEFAULTS.theme_bg
    local accent = themes.theme_accent or ConfigManager.DEFAULTS.theme_accent
    local text = themes.theme_text or ConfigManager.DEFAULTS.theme_text
    local danger = themes.theme_danger or ConfigManager.DEFAULTS.theme_danger
    local positive = themes.theme_positive or ConfigManager.DEFAULTS.theme_positive
    local slider_grab = themes.theme_slider_grab or ConfigManager.DEFAULTS.theme_slider_grab
    local apply_btn = themes.theme_apply_btn or ConfigManager.DEFAULTS.theme_apply_btn
    local frame_bg = themes.theme_frame_bg or ConfigManager.DEFAULTS.theme_frame_bg
    local check_mark = themes.theme_check_mark or ConfigManager.DEFAULTS.theme_check_mark
    local inactive_btn = themes.theme_inactive_btn or ConfigManager.DEFAULTS.theme_inactive_btn
    local inactive_btn_text = themes.theme_inactive_btn_text or ConfigManager.DEFAULTS.theme_inactive_btn_text
    local active_btn = themes.theme_active_btn or ConfigManager.DEFAULTS.theme_active_btn

    -- Support passing settings_write_keyswitches as direct boolean argument, or as key inside themes
    local write_ks = false
    if settings_write_keyswitches ~= nil then
        write_ks = settings_write_keyswitches
    elseif themes.settings_write_keyswitches ~= nil then
        write_ks = themes.settings_write_keyswitches
    end

    f:write(string.format("bg=%.4f,%.4f,%.4f\n",          bg[1],          bg[2],          bg[3]))
    f:write(string.format("accent=%.4f,%.4f,%.4f\n",      accent[1],      accent[2],      accent[3]))
    f:write(string.format("text=%.4f,%.4f,%.4f\n",        text[1],        text[2],        text[3]))
    f:write(string.format("danger=%.4f,%.4f,%.4f\n",      danger[1],      danger[2],      danger[3]))
    f:write(string.format("positive=%.4f,%.4f,%.4f\n",    positive[1],    positive[2],    positive[3]))
    f:write(string.format("slider_grab=%.4f,%.4f,%.4f\n", slider_grab[1], slider_grab[2], slider_grab[3]))
    f:write(string.format("apply_btn=%.4f,%.4f,%.4f\n",   apply_btn[1],   apply_btn[2],   apply_btn[3]))
    f:write(string.format("frame_bg=%.4f,%.4f,%.4f\n",    frame_bg[1],    frame_bg[2],    frame_bg[3]))
    f:write(string.format("check_mark=%.4f,%.4f,%.4f\n",        check_mark[1],        check_mark[2],        check_mark[3]))
    f:write(string.format("inactive_btn=%.4f,%.4f,%.4f\n",      inactive_btn[1],      inactive_btn[2],      inactive_btn[3]))
    f:write(string.format("inactive_btn_text=%.4f,%.4f,%.4f\n", inactive_btn_text[1], inactive_btn_text[2], inactive_btn_text[3]))
    f:write(string.format("active_btn=%.4f,%.4f,%.4f\n",        active_btn[1],        active_btn[2],        active_btn[3]))
    f:write(string.format("write_keyswitches=%s\n",             write_ks and "1" or "0"))
    f:close()
end

return ConfigManager
