-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UIMemory = {}

function UIMemory.draw_memory_window(ctx, gui_state, callbacks)
    local stack = gui_state.memory_stack or {}
    local selected_idx = gui_state.selected_memory_index or -1
    
    -- ListBox
    local listbox_w = -1
    local listbox_h = -30 -- leave space for buttons at the bottom
    
    if reaper.ImGui_BeginListBox(ctx, "##memory_list", listbox_w, listbox_h) then
        local flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
        for i, val in ipairs(stack) do
            local label = string.format("%d:  %.1f ms", i, val)
            local is_selected = (selected_idx == i)
            local clicked, _ = reaper.ImGui_Selectable(ctx, label, is_selected, flags)
            if clicked then
                gui_state.selected_memory_index = i
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                callbacks.adjust_offset_to_value(val)
            end
        end
        reaper.ImGui_EndListBox(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- "-" Button to remove the selected value
    local has_selection = (selected_idx >= 1 and selected_idx <= #stack)
    reaper.ImGui_BeginDisabled(ctx, not has_selection)
    if reaper.ImGui_Button(ctx, "-") then
        table.remove(stack, selected_idx)
        -- adjust selection index
        if selected_idx > #stack then
            gui_state.selected_memory_index = #stack
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
        local val = stack[selected_idx]
        if val then
            callbacks.adjust_offset_to_value(val)
        end
    end
    reaper.ImGui_EndDisabled(ctx)
    
    -- Clear all button
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_BeginDisabled(ctx, #stack == 0)
    if reaper.ImGui_Button(ctx, "Clear All") then
        gui_state.memory_stack = {}
        gui_state.selected_memory_index = -1
        if callbacks.on_memory_changed then
            callbacks.on_memory_changed()
        end
    end
    reaper.ImGui_EndDisabled(ctx)
end

return UIMemory
