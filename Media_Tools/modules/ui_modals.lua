-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UIModals = {}

function UIModals.draw_modals(ctx, modal_state, gui_state, presets_state, callbacks)
    -- 1. New Preset Modal
    if modal_state.open_new then
        reaper.ImGui_OpenPopup(ctx, "New Preset")
        modal_state.open_new = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "New Preset", nil, imgui.WindowFlags_AlwaysAutoResize) then
        reaper.ImGui_Text(ctx, "Library Name:")
        if modal_state.focus_new then
            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            modal_state.focus_new = false
        end
        local changed_lib, new_lib = reaper.ImGui_InputText(ctx, "##new_lib", modal_state.new_lib)
        if changed_lib then
            modal_state.new_lib = new_lib
        end
        
        reaper.ImGui_Text(ctx, "Instrument Name (optional):")
        local changed_instr, new_instr = reaper.ImGui_InputText(ctx, "##new_instr", modal_state.new_instr or "")
        if changed_instr then
            modal_state.new_instr = new_instr
        end
        
        reaper.ImGui_Text(ctx, "Articulation Name:")
        local changed_art, new_art = reaper.ImGui_InputText(ctx, "##new_art", modal_state.new_art)
        if changed_art then
            modal_state.new_art = new_art
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local cb_changed, new_cb_val = reaper.ImGui_Checkbox(ctx, "Show in Preset Grid", modal_state.new_show_grid)
        if cb_changed then
            modal_state.new_show_grid = new_cb_val
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local lib_trimmed = modal_state.new_lib:gsub("^%s*(.-)%s*$", "%1")
        local instr_trimmed = (modal_state.new_instr or ""):gsub("^%s*(.-)%s*$", "%1")
        local art_trimmed = modal_state.new_art:gsub("^%s*(.-)%s*$", "%1")
        local can_save = (lib_trimmed ~= "" and art_trimmed ~= "")
        
        if not can_save then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_Button(ctx, "OK", 80) then
            local combined_name = callbacks.join_preset_name(lib_trimmed, instr_trimmed, art_trimmed)
            presets_state.presets[combined_name] = gui_state.slider_value
            presets_state.presets_show_in_grid[combined_name] = modal_state.new_show_grid
            presets_state.presets_ks_pitch[combined_name] = -1
            presets_state.presets_note_vel_min[combined_name] = -1
            presets_state.presets_note_vel_max[combined_name] = -1
            
            callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
            
            local p, pk, ps, pksp, pmin, pmax = callbacks.load_presets()
            presets_state.presets = p
            presets_state.preset_keys = pk
            presets_state.presets_show_in_grid = ps
            presets_state.presets_ks_pitch = pksp
            presets_state.presets_note_vel_min = pmin
            presets_state.presets_note_vel_max = pmax

            callbacks.save_preset_name_to_targets(combined_name)
            presets_state.current_preset_name = combined_name
            presets_state.combo_preset_name = combined_name
            modal_state.new_lib = ""
            modal_state.new_instr = ""
            modal_state.new_art = ""
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if not can_save then
            reaper.ImGui_EndDisabled(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    -- 2. Rename Preset Modal
    if modal_state.open_rename then
        local lib, instr, art = callbacks.split_preset_name(presets_state.combo_preset_name)
        modal_state.rename_lib = lib
        modal_state.rename_instr = instr
        modal_state.rename_art = art
        modal_state.rename_show_grid = (presets_state.presets_show_in_grid[presets_state.combo_preset_name] ~= false)
        reaper.ImGui_OpenPopup(ctx, "Rename Preset")
        modal_state.open_rename = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "Rename Preset", nil, imgui.WindowFlags_AlwaysAutoResize) then
        reaper.ImGui_Text(ctx, "Library Name:")
        if modal_state.focus_rename then
            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            modal_state.focus_rename = false
        end
        local changed_lib, new_lib = reaper.ImGui_InputText(ctx, "##rename_lib", modal_state.rename_lib)
        if changed_lib then
            modal_state.rename_lib = new_lib
        end
        
        reaper.ImGui_Text(ctx, "Instrument Name (optional):")
        local changed_instr, new_instr = reaper.ImGui_InputText(ctx, "##rename_instr", modal_state.rename_instr or "")
        if changed_instr then
            modal_state.rename_instr = new_instr
        end
        
        reaper.ImGui_Text(ctx, "Articulation Name:")
        local changed_art, new_art = reaper.ImGui_InputText(ctx, "##rename_art", modal_state.rename_art)
        if changed_art then
            modal_state.rename_art = new_art
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local cb_changed, new_cb_val = reaper.ImGui_Checkbox(ctx, "Show in Preset Grid", modal_state.rename_show_grid)
        if cb_changed then
            modal_state.rename_show_grid = new_cb_val
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local lib_trimmed = modal_state.rename_lib:gsub("^%s*(.-)%s*$", "%1")
        local instr_trimmed = (modal_state.rename_instr or ""):gsub("^%s*(.-)%s*$", "%1")
        local art_trimmed = modal_state.rename_art:gsub("^%s*(.-)%s*$", "%1")
        local combined_name = callbacks.join_preset_name(lib_trimmed, instr_trimmed, art_trimmed)
        local can_save = (lib_trimmed ~= "" and art_trimmed ~= "" and (combined_name ~= presets_state.combo_preset_name or modal_state.rename_show_grid ~= (presets_state.presets_show_in_grid[presets_state.combo_preset_name] ~= false)))
        
        if not can_save then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_Button(ctx, "OK", 80) then
            local val = presets_state.presets[presets_state.combo_preset_name]
            local ks_pitch = presets_state.presets_ks_pitch[presets_state.combo_preset_name] or -1
            local note_vel_min = presets_state.presets_note_vel_min[presets_state.combo_preset_name] or -1
            local note_vel_max = presets_state.presets_note_vel_max[presets_state.combo_preset_name] or -1

            presets_state.presets[presets_state.combo_preset_name] = nil
            presets_state.presets_show_in_grid[presets_state.combo_preset_name] = nil
            presets_state.presets_ks_pitch[presets_state.combo_preset_name] = nil
            presets_state.presets_note_vel_min[presets_state.combo_preset_name] = nil
            presets_state.presets_note_vel_max[presets_state.combo_preset_name] = nil
            
            presets_state.presets[combined_name] = val
            presets_state.presets_show_in_grid[combined_name] = modal_state.rename_show_grid
            presets_state.presets_ks_pitch[combined_name] = ks_pitch
            presets_state.presets_note_vel_min[combined_name] = note_vel_min
            presets_state.presets_note_vel_max[combined_name] = note_vel_max

            callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
            
            local p, pk, ps, pksp, pmin, pmax = callbacks.load_presets()
            presets_state.presets = p
            presets_state.preset_keys = pk
            presets_state.presets_show_in_grid = ps
            presets_state.presets_ks_pitch = pksp
            presets_state.presets_note_vel_min = pmin
            presets_state.presets_note_vel_max = pmax

            if presets_state.current_preset_name == presets_state.combo_preset_name then
                presets_state.current_preset_name = combined_name
                callbacks.save_preset_name_to_targets(combined_name)
            end
            presets_state.combo_preset_name = combined_name
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if not can_save then
            reaper.ImGui_EndDisabled(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    -- 3. Delete Preset Modal
    if modal_state.open_delete then
        reaper.ImGui_OpenPopup(ctx, "Delete Preset?")
        modal_state.open_delete = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "Delete Preset?", nil, imgui.WindowFlags_AlwaysAutoResize) then
        reaper.ImGui_Text(ctx, string.format("Are you sure you want to delete '%s'?", presets_state.combo_preset_name))
        
        reaper.ImGui_Spacing(ctx)
        
        if reaper.ImGui_Button(ctx, "Yes", 80) then
            presets_state.presets[presets_state.combo_preset_name] = nil
            presets_state.presets_show_in_grid[presets_state.combo_preset_name] = nil
            presets_state.presets_ks_pitch[presets_state.combo_preset_name] = nil
            presets_state.presets_note_vel_min[presets_state.combo_preset_name] = nil
            presets_state.presets_note_vel_max[presets_state.combo_preset_name] = nil
            
            callbacks.save_presets(presets_state.presets, presets_state.presets_show_in_grid)
            
            local p, pk, ps, pksp, pmin, pmax = callbacks.load_presets()
            presets_state.presets = p
            presets_state.preset_keys = pk
            presets_state.presets_show_in_grid = ps
            presets_state.presets_ks_pitch = pksp
            presets_state.presets_note_vel_min = pmin
            presets_state.presets_note_vel_max = pmax

            if presets_state.current_preset_name == presets_state.combo_preset_name then
                presets_state.current_preset_name = ""
                callbacks.save_preset_name_to_targets("")
            end
            presets_state.combo_preset_name = ""
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "No", 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

return UIModals
