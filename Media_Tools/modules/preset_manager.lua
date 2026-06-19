-- @noindex

local PresetManager = {}

function PresetManager.split_preset_name(name)
    if not name or name == "" then
        return "", ""
    end
    local lib, art = name:match("^(.-)%s*-%s*(.-)$")
    if lib and art then
        return lib, art
    else
        return name, ""
    end
end

function PresetManager.split_string(inputstr, sep)
    local t = {}
    local i = 1
    while true do
        local start_pos, end_pos = string.find(inputstr, sep, i, true)
        if not start_pos then
            table.insert(t, string.sub(inputstr, i))
            break
        end
        table.insert(t, string.sub(inputstr, i, start_pos - 1))
        i = end_pos + 1
    end
    return t
end

function PresetManager.get_presets_file_path()
    local sep = package.config:sub(1,1)
    return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "Walter_MediaOffset_Presets.txt"
end

function PresetManager.load_presets()
    local path = PresetManager.get_presets_file_path()
    local loaded_presets = {}
    local show_in_grid = {}
    local ks_pitch_tbl = {}
    local note_vel_min_tbl = {}
    local note_vel_max_tbl = {}
    local keys = {}
    local f = io.open(path, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("[\r\n]", "")
            local name, rest = line:match("^(.-)=([^=]+)$")
            if name and rest then
                local parts = PresetManager.split_string(rest, "|")
                local val = tonumber(parts[1]) or 0.0
                local show = true
                if parts[2] ~= nil then
                    show = (parts[2] == "1")
                end
                local ks_pitch = tonumber(parts[3]) or -1
                local note_vel_min = tonumber(parts[6]) or -1
                local note_vel_max = tonumber(parts[7]) or -1

                loaded_presets[name] = val
                show_in_grid[name] = show
                ks_pitch_tbl[name] = ks_pitch
                note_vel_min_tbl[name] = note_vel_min
                note_vel_max_tbl[name] = note_vel_max
                table.insert(keys, name)
            end
        end
        f:close()
    end
    table.sort(keys)
    return loaded_presets, keys, show_in_grid, ks_pitch_tbl, note_vel_min_tbl, note_vel_max_tbl
end

function PresetManager.save_presets(presets_table, show_in_grid_table, ks_pitch_tbl, note_vel_min_tbl, note_vel_max_tbl)
    local path = PresetManager.get_presets_file_path()
    local f = io.open(path, "w")
    if f then
        local sorted_keys = {}
        for k in pairs(presets_table) do
            table.insert(sorted_keys, k)
        end
        table.sort(sorted_keys)
        for _, k in ipairs(sorted_keys) do
            local show = true
            if show_in_grid_table and show_in_grid_table[k] ~= nil then
                show = show_in_grid_table[k]
            end
            local ks_pitch = (ks_pitch_tbl and ks_pitch_tbl[k]) or -1
            local note_vel_min = (note_vel_min_tbl and note_vel_min_tbl[k]) or -1
            local note_vel_max = (note_vel_max_tbl and note_vel_max_tbl[k]) or -1
            
            f:write(string.format("%s=%s|%d|%d|%d|%d|%d|%d\n", 
                k, 
                tostring(presets_table[k]), 
                show and 1 or 0,
                ks_pitch,
                -1,
                -1,
                note_vel_min,
                note_vel_max
            ))
        end
        f:close()
    end
end

return PresetManager
