-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UITriggerEditor = {}

-- human-readable MIDI note name helper
local function get_note_name(pitch)
    if pitch < 0 or pitch > 127 then return "Disabled" end
    local notes = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    local octave = math.floor(pitch / 12) - 1
    local note = notes[(pitch % 12) + 1]
    return string.format("%s%d", note, octave)
end

-- Helper to determine Trigger Mode from trigger values
local function get_preset_trigger_mode(name, presets_state)
    local ks_pitch = presets_state.presets_ks_pitch[name] or -1
    local note_vel_min = presets_state.presets_note_vel_min[name] or -1
    local note_vel_max = presets_state.presets_note_vel_max[name] or -1
    
    if ks_pitch >= 0 and note_vel_min >= 0 and note_vel_max >= 0 then
        return "Note + Velocity"
    elseif ks_pitch >= 0 then
        return "Note"
    elseif note_vel_min >= 0 and note_vel_max >= 0 then
        return "Velocity"
    else
        return "None"
    end
end

function UITriggerEditor.draw_trigger_editor(ctx, combo_preset_name, presets_state, callbacks)
    if combo_preset_name == "" or presets_state.presets[combo_preset_name] == nil then
        return
    end

    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_CollapsingHeader(ctx, "MIDI Triggers: " .. combo_preset_name) then
        reaper.ImGui_Spacing(ctx)
        
        local current_mode = get_preset_trigger_mode(combo_preset_name, presets_state)
        
        reaper.ImGui_Text(ctx, "Trigger Mode:")
        reaper.ImGui_SameLine(ctx, 150)
        reaper.ImGui_SetNextItemWidth(ctx, 180)
        if reaper.ImGui_BeginCombo(ctx, "##trigger_mode", current_mode) then
            local modes = {"None", "Note", "Velocity", "Note + Velocity"}
            for _, m in ipairs(modes) do
                local is_sel = (m == current_mode)
                if reaper.ImGui_Selectable(ctx, m, is_sel) then
                    if m == "None" then
                        presets_state.presets_ks_pitch[combo_preset_name] = -1
                        presets_state.presets_note_vel_min[combo_preset_name] = -1
                        presets_state.presets_note_vel_max[combo_preset_name] = -1
                    elseif m == "Note" then
                        if (presets_state.presets_ks_pitch[combo_preset_name] or -1) < 0 then
                            presets_state.presets_ks_pitch[combo_preset_name] = 24 -- default C0
                        end
                        presets_state.presets_note_vel_min[combo_preset_name] = -1
                        presets_state.presets_note_vel_max[combo_preset_name] = -1
                    elseif m == "Velocity" then
                        presets_state.presets_ks_pitch[combo_preset_name] = -1
                        if (presets_state.presets_note_vel_min[combo_preset_name] or -1) < 0 then
                            presets_state.presets_note_vel_min[combo_preset_name] = 1
                            presets_state.presets_note_vel_max[combo_preset_name] = 127
                        end
                    elseif m == "Note + Velocity" then
                        if (presets_state.presets_ks_pitch[combo_preset_name] or -1) < 0 then
                            presets_state.presets_ks_pitch[combo_preset_name] = 24
                        end
                        if (presets_state.presets_note_vel_min[combo_preset_name] or -1) < 0 then
                            presets_state.presets_note_vel_min[combo_preset_name] = 1
                            presets_state.presets_note_vel_max[combo_preset_name] = 127
                        end
                    end
                    callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- Render Note dropdown if mode is Note or Note + Velocity
        if current_mode == "Note" or current_mode == "Note + Velocity" then
            local pitch_val = presets_state.presets_ks_pitch[combo_preset_name] or 24
            if pitch_val < 0 then pitch_val = 24 end
            reaper.ImGui_Text(ctx, "Keyswitch Note:")
            reaper.ImGui_SameLine(ctx, 150)
            reaper.ImGui_SetNextItemWidth(ctx, 180)
            
            local ks_preview = get_note_name(pitch_val) .. " (" .. tostring(pitch_val) .. ")"
            if reaper.ImGui_BeginCombo(ctx, "##ks_pitch_combo", ks_preview) then
                for p = 0, 127 do
                    local is_sel = (p == pitch_val)
                    local label = get_note_name(p) .. " (" .. tostring(p) .. ")"
                    if reaper.ImGui_Selectable(ctx, label, is_sel) then
                        presets_state.presets_ks_pitch[combo_preset_name] = p
                        callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
                    end
                    if is_sel then
                        reaper.ImGui_SetItemDefaultFocus(ctx)
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
        end
        
        -- Render Played Note Velocity Range drag if mode is Velocity or Note + Velocity
        if current_mode == "Velocity" or current_mode == "Note + Velocity" then
            local min_val = presets_state.presets_note_vel_min[combo_preset_name] or 1
            local max_val = presets_state.presets_note_vel_max[combo_preset_name] or 127
            if min_val < 0 then min_val = 1 end
            if max_val < 0 then max_val = 127 end
            
            reaper.ImGui_Text(ctx, "Played Note Vel:")
            reaper.ImGui_SameLine(ctx, 150)
            reaper.ImGui_SetNextItemWidth(ctx, 180)
            local changed_range, new_min, new_max = reaper.ImGui_DragIntRange2(ctx, "##note_vel_range", min_val, max_val, 1.0, 1, 127, "Min: %d", "Max: %d")
            if changed_range then
                presets_state.presets_note_vel_min[combo_preset_name] = new_min
                presets_state.presets_note_vel_max[combo_preset_name] = new_max
                callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
            end
        end
        
        reaper.ImGui_Spacing(ctx)
    end
end

return UITriggerEditor
