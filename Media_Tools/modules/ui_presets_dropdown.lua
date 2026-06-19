-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UIPresetsDropdown = {}

function UIPresetsDropdown.draw_presets_dropdown(ctx, gui_state, presets_state, modal_state, callbacks)
    reaper.ImGui_Text(ctx, "Preset:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 220)
    
    local combo_preview = presets_state.combo_preset_name
    if combo_preview == "" then
        combo_preview = "-- Select Preset --"
    end
    
    if reaper.ImGui_BeginCombo(ctx, "##presets_combo", combo_preview) then
        for _, name in ipairs(presets_state.preset_keys) do
            local is_selected = (name == presets_state.combo_preset_name)
            if reaper.ImGui_Selectable(ctx, name, is_selected) then
                presets_state.combo_preset_name = name
                gui_state.slider_value = presets_state.presets[name]
                local lib, instr, art = callbacks.split_preset_name(name)
                if lib ~= "" then
                    gui_state.selected_library = lib
                end
                callbacks.adjust_offset_to_value(presets_state.presets[name], name)
            end
            if is_selected then
                reaper.ImGui_SetItemDefaultFocus(ctx)
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Save Button
    local has_selected_preset = (presets_state.combo_preset_name ~= "" and presets_state.presets[presets_state.combo_preset_name] ~= nil)
    if not has_selected_preset then
        reaper.ImGui_BeginDisabled(ctx)
    end
    if reaper.ImGui_Button(ctx, "Save") then
        presets_state.presets[presets_state.combo_preset_name] = gui_state.slider_value
        callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
        
        local p, pk, ps, pksp, pmin, pmax = callbacks.load_presets()
        presets_state.presets = p
        presets_state.preset_keys = pk
        presets_state.presets_show_in_grid = ps
        presets_state.presets_ks_pitch = pksp
        presets_state.presets_note_vel_min = pmin
        presets_state.presets_note_vel_max = pmax
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Overwrite the selected preset with the current offset.")
    end
    if not has_selected_preset then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Save As Button
    if reaper.ImGui_Button(ctx, "Save As") then
        local lib, art = callbacks.split_preset_name(presets_state.combo_preset_name)
        modal_state.new_preset_lib_input = lib
        modal_state.new_preset_art_input = ""
        modal_state.new_preset_show_in_grid = true
        modal_state.open_new_preset_modal = true
        modal_state.open_new_preset_focus = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Save the current offset as a new preset.")
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Rename Button (Rn)
    if not has_selected_preset then
        reaper.ImGui_BeginDisabled(ctx)
    end
    if reaper.ImGui_Button(ctx, "Rn") then
        modal_state.open_rename_preset_modal = true
        modal_state.open_rename_preset_focus = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Rename selected preset.")
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Delete Button (Dl)
    if reaper.ImGui_Button(ctx, "Dl") then
        modal_state.open_delete_preset_modal = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Delete selected preset.")
    end
    
    if not has_selected_preset then
        reaper.ImGui_EndDisabled(ctx)
    end
end

return UIPresetsDropdown
