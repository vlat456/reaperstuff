-- @noindex

local reaper = reaper

local PresetManager = {}

-- Split a preset name into (lib, instr, art).
-- Format: "Library - Instrument - Articulation"  (3-part, new)
-- Legacy:  "Library - Articulation"              (2-part, old)
-- Unknown: "SomeName"                            → lib=SomeName, instr="", art=""
function PresetManager.split_preset_name(name)
    if not name or name == "" then
        return "", "", ""
    end
    -- Try 3-part: "A - B - C"
    local lib, instr, art = name:match("^(.-)%s*-%s*(.-)%s*-%s*(.-)$")
    if lib and lib ~= "" and instr and instr ~= "" and art and art ~= "" then
        return lib, instr, art
    end
    -- Try 2-part legacy: "A - B"
    local lib2, art2 = name:match("^(.-)%s*-%s*(.-)$")
    if lib2 and lib2 ~= "" and art2 and art2 ~= "" then
        return lib2, "", art2
    end
    -- Single word / unstructured
    return name, "", ""
end

-- Build a preset name from (lib, instr, art), skipping empty instr for legacy compat
function PresetManager.join_preset_name(lib, instr, art)
    lib = (lib or ""):gsub("^%s*(.-)%s*$", "%1")
    instr = (instr or ""):gsub("^%s*(.-)%s*$", "%1")
    art = (art or ""):gsub("^%s*(.-)%s*$", "%1")
    if instr ~= "" then
        return lib .. " - " .. instr .. " - " .. art
    else
        return lib .. " - " .. art
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
    local lib_order_map = {}
    local instr_order_map = {}
    local art_order_map = {}
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
                
                local lib_order = tonumber(parts[8]) or 0
                local instr_order = tonumber(parts[9]) or 0
                local art_order = tonumber(parts[10]) or 0

                loaded_presets[name] = val
                show_in_grid[name] = show
                ks_pitch_tbl[name] = ks_pitch
                note_vel_min_tbl[name] = note_vel_min
                note_vel_max_tbl[name] = note_vel_max
                
                local lib, instr, art = PresetManager.split_preset_name(name)
                if lib_order > 0 then
                    lib_order_map[lib] = lib_order
                end
                if instr_order > 0 then
                    instr_order_map[lib .. "\0" .. instr] = instr_order
                end
                if art_order > 0 then
                    art_order_map[name] = art_order
                end
                
                table.insert(keys, name)
            end
        end
        f:close()
    end
    table.sort(keys)
    return loaded_presets, keys, show_in_grid, ks_pitch_tbl, note_vel_min_tbl, note_vel_max_tbl, lib_order_map, instr_order_map, art_order_map
end

function PresetManager.save_presets(presets_table, show_in_grid_table, ks_pitch_tbl, note_vel_min_tbl, note_vel_max_tbl, lib_order_map, instr_order_map, art_order_map)
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
            
            local lib, instr, art = PresetManager.split_preset_name(k)
            local lib_order = (lib_order_map and lib_order_map[lib]) or 0
            local instr_order = (instr_order_map and instr_order_map[lib .. "\0" .. instr]) or 0
            local art_order = (art_order_map and art_order_map[k]) or 0
            
            f:write(string.format("%s=%s|%d|%d|%d|%d|%d|%d|%d|%d|%d\n", 
                k, 
                tostring(presets_table[k]), 
                show and 1 or 0,
                ks_pitch,
                -1,
                -1,
                note_vel_min,
                note_vel_max,
                lib_order,
                instr_order,
                art_order
            ))
        end
        f:close()
    end
end

return PresetManager
