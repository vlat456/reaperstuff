-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UIRenderer = {}

UIRenderer.MODE_TAKE_OFFSET = 0
UIRenderer.MODE_TRACK_OFFSET = 1
UIRenderer.MODE_ITEM_POSITION = 2

function UIRenderer.draw_mode_selector(ctx, gui_state, has_notes)
    if has_notes then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.8, 0.5, 1.0))
        reaper.ImGui_Text(ctx, "Offsetting selected MIDI notes (modes disabled):")
        reaper.ImGui_PopStyleColor(ctx)
    else
        reaper.ImGui_Text(ctx, "Offset Mode:")
    end
    
    local mode_changed = false
    reaper.ImGui_BeginDisabled(ctx, has_notes)
    
    local rb_a = reaper.ImGui_RadioButton(ctx, "Take Start Offset", gui_state.adjust_mode == UIRenderer.MODE_TAKE_OFFSET)
    if rb_a then
        gui_state.adjust_mode = UIRenderer.MODE_TAKE_OFFSET
        mode_changed = true
    end
    
    reaper.ImGui_SameLine(ctx)
    local rb_b = reaper.ImGui_RadioButton(ctx, "Track Playback Offset", gui_state.adjust_mode == UIRenderer.MODE_TRACK_OFFSET)
    if rb_b then
        gui_state.adjust_mode = UIRenderer.MODE_TRACK_OFFSET
        mode_changed = true
    end
    
    reaper.ImGui_SameLine(ctx)
    local rb_c = reaper.ImGui_RadioButton(ctx, "Move Item Position", gui_state.adjust_mode == UIRenderer.MODE_ITEM_POSITION)
    if rb_c then
        gui_state.adjust_mode = UIRenderer.MODE_ITEM_POSITION
        mode_changed = true
    end
    
    reaper.ImGui_EndDisabled(ctx)
    return mode_changed
end

function UIRenderer.draw_offset_slider(ctx, gui_state, fixed_range, callbacks, theme_apply_btn, show_info, show_settings)
    reaper.ImGui_Text(ctx, "Offset:")
    reaper.ImGui_SameLine(ctx, 90)
    
    reaper.ImGui_SetNextItemWidth(ctx, 220)
    local slider_changed, new_slider_val = reaper.ImGui_SliderDouble(ctx, "##slider", gui_state.slider_value, -fixed_range, fixed_range, "%.1f ms")
    local is_slider_active = reaper.ImGui_IsItemActive(ctx)
    local is_slider_activated = reaper.ImGui_IsItemActivated(ctx)
    local is_slider_deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    if is_slider_activated or is_slider_active then
        gui_state.is_dragging = true
    end

    if slider_changed then
        gui_state.slider_value = new_slider_val
        callbacks.apply_offset_to_targets(new_slider_val)
        local eff_mode = callbacks.get_effective_mode()
        if eff_mode == 1 then -- UIRenderer.MODE_TRACK_OFFSET
            reaper.TrackList_AdjustWindows(false)
        end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 80)
    local input_changed, new_input_val = reaper.ImGui_InputDouble(ctx, "ms", gui_state.slider_value, 0.0, 0.0, "%.1f")
    if input_changed then
        gui_state.slider_value = new_input_val
        if callbacks.on_input_changed then
            callbacks.on_input_changed(new_input_val)
        end
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        callbacks.adjust_offset_to_value(gui_state.slider_value)
    end

    -- Explicit Apply Button
    reaper.ImGui_SameLine(ctx)
    local ap = theme_apply_btn
    local apH = {math.min(ap[1] + 0.15, 1.0), math.min(ap[2] + 0.15, 1.0), math.min(ap[3] + 0.15, 1.0)}
    local apA = {ap[1] * 0.80, ap[2] * 0.80, ap[3] * 0.80}
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(ap[1], ap[2], ap[3], 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(apH[1], apH[2], apH[3], 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(apA[1], apA[2], apA[3], 1.0))
    if reaper.ImGui_Button(ctx, "Apply") then
        callbacks.adjust_offset_to_value(gui_state.slider_value)
    end
    reaper.ImGui_PopStyleColor(ctx, 3)

    -- Information Button
    reaper.ImGui_SameLine(ctx)
    local info_active = show_info
    if info_active then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button, reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.3, 0.6, 1.0))
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.4, 0.75, 1.0))
    end
    if reaper.ImGui_Button(ctx, "Information") then
        show_info = not show_info
    end
    if info_active then
        reaper.ImGui_PopStyleColor(ctx, 2)
    end

    -- Settings Button
    reaper.ImGui_SameLine(ctx)
    local settings_active = show_settings
    if settings_active then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.3, 0.6, 1.0))
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.4, 0.75, 1.0))
    end
    if reaper.ImGui_Button(ctx, "Settings") then
        show_settings = not show_settings
    end
    if settings_active then
        reaper.ImGui_PopStyleColor(ctx, 2)
    end

    return show_info, show_settings, is_slider_deactivated
end

function UIRenderer.draw_preset_board(ctx, gui_state, preset_keys, presets_show_in_grid, presets, theme_accent, theme_bg, theme_inactive_btn, theme_inactive_btn_text, current_preset_name, adjust_offset_to_value_cb)
    reaper.ImGui_Text(ctx, "Preset Board:")
    reaper.ImGui_Spacing(ctx)
    
    -- Prepare grouped data: libs[lib][instr] = list of {name, art, offset}
    -- Instrument key "" is used for legacy 2-part presets
    local libs = {}
    local lib_names = {}
    for _, name in ipairs(preset_keys) do
        if presets_show_in_grid[name] ~= false then
            local lib, instr, art = name:match("^(.-)%s*-%s*(.-)%s*-%s*(.-)$")
            if not (lib and lib ~= "" and instr ~= "" and art ~= "") then
                -- 2-part or unstructured
                lib, art = name:match("^(.-)%s*-%s*(.-)$")
                instr = ""
                if not lib then
                    lib = "Other"
                    art = name
                end
            end
            if not libs[lib] then
                libs[lib] = {}
                table.insert(lib_names, lib)
            end
            if not libs[lib][instr] then
                libs[lib][instr] = {}
            end
            table.insert(libs[lib][instr], { name = name, art = art, offset = presets[name] })
        end
    end
    
    table.sort(lib_names)
    for lib in pairs(libs) do
        local instr_names = {}
        for k in pairs(libs[lib]) do table.insert(instr_names, k) end
        table.sort(instr_names)
        libs[lib]._instr_names = instr_names
        for instr in pairs(libs[lib]) do
            if instr ~= "_instr_names" and type(libs[lib][instr]) == "table" then
                table.sort(libs[lib][instr], function(a, b) return a.art < b.art end)
            end
        end
    end
    
    if #lib_names > 0 then
        -- Keep selected library valid
        if not gui_state.selected_library or not libs[gui_state.selected_library] then
            gui_state.selected_library = lib_names[1]
        end
        
        -- Libraries Row
        reaper.ImGui_TextDisabled(ctx, "Libraries:")
        reaper.ImGui_Spacing(ctx)
        
        local window_w = reaper.ImGui_GetWindowWidth(ctx)
        local wrap_w = window_w - 24.0
        if wrap_w < 400.0 then wrap_w = 400.0 end
        
        local pad_x, _ = reaper.ImGui_GetStyleVar(ctx, imgui.StyleVar_FramePadding)
        local space_x, _ = reaper.ImGui_GetStyleVar(ctx, imgui.StyleVar_ItemSpacing)
        
        -- Uniform button size for all library buttons
        local lib_btn_h = 24
        local max_lib_w = 0
        for _, lib_name in ipairs(lib_names) do
            local text_w, _ = reaper.ImGui_CalcTextSize(ctx, lib_name)
            if text_w > max_lib_w then max_lib_w = text_w end
        end
        local lib_btn_w = max_lib_w + pad_x * 2
        
        local current_x = 0.0
        for i, lib_name in ipairs(lib_names) do
            if i > 1 then
                if current_x + lib_btn_w + space_x < wrap_w then
                    reaper.ImGui_SameLine(ctx, nil, space_x)
                    current_x = current_x + lib_btn_w + space_x
                else
                    current_x = lib_btn_w
                end
            else
                current_x = lib_btn_w
            end
            
            local is_active = (gui_state.selected_library == lib_name)
            if is_active then
                local a = theme_accent
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(a[1]*0.90, a[2]*0.50, a[3]*0.82, 1.0))
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(a[1]*1.10 > 1 and 1 or a[1]*1.10, a[2]*0.70, a[3]*0.94, 1.0))
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(a[1]*0.70, a[2]*0.30, a[3]*0.69, 1.0))
            else
                local ib = theme_inactive_btn
                local it = theme_inactive_btn_text
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(ib[1], ib[2], ib[3], 1.0))
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(math.min(ib[1]+0.08, 1), math.min(ib[2]+0.08, 1), math.min(ib[3]+0.08, 1), 1.0))
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(math.max(ib[1]-0.04, 0), math.max(ib[2]-0.04, 0), math.max(ib[3]-0.04, 0), 1.0))
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text,          reaper.ImGui_ColorConvertDouble4ToU32(it[1], it[2], it[3], 1.0))
            end
            
            if reaper.ImGui_Button(ctx, lib_name .. "##lib_" .. i, lib_btn_w, lib_btn_h) then
                gui_state.selected_library = lib_name
            end
            
            if is_active then
                reaper.ImGui_PopStyleColor(ctx, 3)
            else
                reaper.ImGui_PopStyleColor(ctx, 4)
            end
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Instruments row for selected library
        local cur_lib_data = libs[gui_state.selected_library] or {}
        local instr_names = cur_lib_data._instr_names or {}
        
        if #instr_names > 0 then
            -- Keep selected instrument valid for current library
            if not gui_state.selected_instrument or not cur_lib_data[gui_state.selected_instrument] then
                gui_state.selected_instrument = instr_names[1]
            end
            
            reaper.ImGui_TextDisabled(ctx, "Instruments:")
            reaper.ImGui_Spacing(ctx)
            
            -- Uniform button size matching fine-tuning button style (24px height)
            local instr_btn_h = 24
            local max_text_w = 0
            for _, instr in ipairs(instr_names) do
                local display_name = (instr ~= "" and instr) or "Uncategorized"
                local text_w, _ = reaper.ImGui_CalcTextSize(ctx, display_name)
                if text_w > max_text_w then max_text_w = text_w end
            end
            local instr_btn_w = max_text_w + pad_x * 2
            
            local instr_current_x = 0.0
            for i, instr in ipairs(instr_names) do
                local display_name = (instr ~= "" and instr) or "Uncategorized"
                
                if i > 1 then
                    if instr_current_x + instr_btn_w + space_x < wrap_w then
                        reaper.ImGui_SameLine(ctx, nil, space_x)
                        instr_current_x = instr_current_x + instr_btn_w + space_x
                    else
                        instr_current_x = instr_btn_w
                    end
                else
                    instr_current_x = instr_btn_w
                end
                
                local is_active = (gui_state.selected_instrument == instr)
                if is_active then
                    local a = theme_accent
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(a[1]*0.90, a[2]*0.50, a[3]*0.82, 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(a[1]*1.10 > 1 and 1 or a[1]*1.10, a[2]*0.70, a[3]*0.94, 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(a[1]*0.70, a[2]*0.30, a[3]*0.69, 1.0))
                else
                    local ib = theme_inactive_btn
                    local it = theme_inactive_btn_text
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(ib[1], ib[2], ib[3], 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(math.min(ib[1]+0.08, 1), math.min(ib[2]+0.08, 1), math.min(ib[3]+0.08, 1), 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(math.max(ib[1]-0.04, 0), math.max(ib[2]-0.04, 0), math.max(ib[3]-0.04, 0), 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text,          reaper.ImGui_ColorConvertDouble4ToU32(it[1], it[2], it[3], 1.0))
                end
                
                if reaper.ImGui_Button(ctx, display_name .. "##instr_" .. i, instr_btn_w, instr_btn_h) then
                    gui_state.selected_instrument = instr
                end
                
                if is_active then
                    reaper.ImGui_PopStyleColor(ctx, 3)
                else
                    reaper.ImGui_PopStyleColor(ctx, 4)
                end
            end
            
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Spacing(ctx)
        end
        
        -- Articulations section for selected instrument only
        local selected_instr = gui_state.selected_instrument or ""
        local arts = cur_lib_data[selected_instr] or {}
        
        if #arts > 0 then
            if selected_instr ~= "" then
                reaper.ImGui_TextDisabled(ctx, selected_instr .. ":")
            else
                reaper.ImGui_TextDisabled(ctx, "Articulations (" .. gui_state.selected_library .. "):")
            end
            reaper.ImGui_Spacing(ctx)
            
            -- Uniform button size for all articulation buttons
            local art_btn_h = 24
            local max_art_w = 0
            for _, art_data in ipairs(arts) do
                local text_w, _ = reaper.ImGui_CalcTextSize(ctx, art_data.art)
                if text_w > max_art_w then max_art_w = text_w end
            end
            local art_btn_w = max_art_w + pad_x * 2
            
            local current_art_x = 0.0
            for i, art_data in ipairs(arts) do
                if i > 1 then
                    if current_art_x + art_btn_w + space_x < wrap_w then
                        reaper.ImGui_SameLine(ctx, nil, space_x)
                        current_art_x = current_art_x + art_btn_w + space_x
                    else
                        current_art_x = art_btn_w
                    end
                else
                    current_art_x = art_btn_w
                end
                
                local is_current = (current_preset_name == art_data.name)
                if is_current then
                    local a = theme_accent
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(a[1], a[2], a[3], 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(math.min(a[1]+0.10, 1), math.min(a[2]+0.10, 1), math.min(a[3]+0.10, 1), 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(a[1]*0.80, a[2]*0.71, a[3]*0.88, 1.0))
                else
                    local ib = theme_inactive_btn
                    local it = theme_inactive_btn_text
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,        reaper.ImGui_ColorConvertDouble4ToU32(ib[1], ib[2], ib[3], 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(math.min(ib[1]+0.08, 1), math.min(ib[2]+0.08, 1), math.min(ib[3]+0.08, 1), 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,  reaper.ImGui_ColorConvertDouble4ToU32(math.max(ib[1]-0.04, 0), math.max(ib[2]-0.04, 0), math.max(ib[3]-0.04, 0), 1.0))
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text,          reaper.ImGui_ColorConvertDouble4ToU32(it[1], it[2], it[3], 1.0))
                end
                
                if reaper.ImGui_Button(ctx, art_data.art .. "##art_" .. i, art_btn_w, art_btn_h) then
                    current_preset_name = art_data.name
                    adjust_offset_to_value_cb(art_data.offset, art_data.name)
                end
                
                if is_current then
                    reaper.ImGui_PopStyleColor(ctx, 3)
                else
                    reaper.ImGui_PopStyleColor(ctx, 4)
                end
                
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, string.format("%s\nOffset: %.1f ms", art_data.name, art_data.offset))
                end
            end
            reaper.ImGui_Spacing(ctx)
        else
            reaper.ImGui_TextDisabled(ctx, "No articulations for this instrument.")
        end
    else
        reaper.ImGui_TextDisabled(ctx, "No presets configured to show in grid.")
    end
    return current_preset_name
end

return UIRenderer

