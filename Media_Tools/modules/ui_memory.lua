-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UIMemory = {}

function UIMemory.draw_memory_window(ctx, gui_state, callbacks)
    local stack = gui_state.memory_stack or {}
    local selected_idx = gui_state.selected_memory_index or -1
    local has_selection = (selected_idx >= 1 and selected_idx <= #stack)
    
    -- ListBox
    local listbox_w = -1
    local listbox_h = has_selection and -70 or -35 -- leave extra space if rename section is shown
    
    if reaper.ImGui_BeginListBox(ctx, "##memory_list", listbox_w, listbox_h) then
        local flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
        for i, item in ipairs(stack) do
            local label
            if item.name and item.name ~= "" then
                label = string.format("%d:  %s (%.1f ms)", i, item.name, item.value)
            else
                label = string.format("%d:  %.1f ms", i, item.value)
            end
            local is_selected = (selected_idx == i)
            local clicked, _ = reaper.ImGui_Selectable(ctx, label, is_selected, flags)
            if clicked then
                gui_state.selected_memory_index = i
                gui_state.rename_input_buffer = item.name or ""
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                callbacks.adjust_offset_to_value(item.value)
            end
        end
        reaper.ImGui_EndListBox(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Rename section (only when an item is selected)
    if has_selection then
        local selected_item = stack[selected_idx]
        gui_state.rename_input_buffer = gui_state.rename_input_buffer or selected_item.name or ""
        
        local avail_w, _ = reaper.ImGui_GetContentRegionAvail(ctx)
        local input_w = avail_w - 90
        if input_w < 100 then input_w = 100 end
        
        reaper.ImGui_SetNextItemWidth(ctx, input_w)
        local changed, new_text = reaper.ImGui_InputText(ctx, "##rename_buf", gui_state.rename_input_buffer)
        if changed then
            gui_state.rename_input_buffer = new_text
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Set Name", 80) then
            selected_item.name = gui_state.rename_input_buffer
            if callbacks.on_memory_changed then
                callbacks.on_memory_changed()
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Assign name to selected memory slot")
        end
        
        reaper.ImGui_Spacing(ctx)
    end
    
    -- Row of action buttons
    -- "-" Button to remove the selected value
    reaper.ImGui_BeginDisabled(ctx, not has_selection)
    if reaper.ImGui_Button(ctx, "-") then
        table.remove(stack, selected_idx)
        -- adjust selection index
        if selected_idx > #stack then
            gui_state.selected_memory_index = #stack
        else
            gui_state.selected_memory_index = selected_idx
        end
        
        -- update rename input buffer to new selection
        local new_idx = gui_state.selected_memory_index
        if new_idx >= 1 and new_idx <= #stack then
            gui_state.rename_input_buffer = stack[new_idx].name or ""
        else
            gui_state.selected_memory_index = -1
            gui_state.rename_input_buffer = ""
        end
        
        if callbacks.on_memory_changed then
            callbacks.on_memory_changed()
        end
    end
    reaper.ImGui_EndDisabled(ctx)
    if reaper.ImGui_IsItemHovered(ctx) and has_selection then
        reaper.ImGui_SetTooltip(ctx, "Remove selected value from memory")
    end
    
    -- Apply button (convenience)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_BeginDisabled(ctx, not has_selection)
    if reaper.ImGui_Button(ctx, "Apply Selected") then
        local item = stack[selected_idx]
        if item then
            callbacks.adjust_offset_to_value(item.value)
        end
    end
    reaper.ImGui_EndDisabled(ctx)
    
    -- Clear all button
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_BeginDisabled(ctx, #stack == 0)
    if reaper.ImGui_Button(ctx, "Clear All") then
        gui_state.memory_stack = {}
        gui_state.selected_memory_index = -1
        gui_state.rename_input_buffer = ""
        if callbacks.on_memory_changed then
            callbacks.on_memory_changed()
        end
    end
    reaper.ImGui_EndDisabled(ctx)
end

return UIMemory
