-- @description Media Offset Tool
-- @author drvlat
-- @version 1.0.0
-- @about
--   An ImGui-based utility for adjusting the media start offset (positive and negative) of selected items/takes.
--   Features a relative slider centered at 0ms, fine-tuning buttons, absolute offset reset, and a real-time list of offsets.
-- @provides
--   [main] Media_Offset_Tool.lua

local reaper = reaper

-- Check for reaimgui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load the ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

-- Script variables
local script_name = "Media Offset Tool"
local ctx = reaper.ImGui_CreateContext(script_name)
local script_running = true

-- Slider ranges
local RANGE_OPTIONS = {100, 500, 1000, 5000, 10000}
local RANGE_LABELS = "±100 ms\0±500 ms\0±1000 ms\0±5000 ms\0±10000 ms\0"

-- Unified GUI State
local gui_state = {
    selected_takes = {},
    slider_value = 0.0,
    range_idx = 2, -- Default to ±1000 ms (index 2 in 0-indexed combo)
    custom_delta = 5.0,
    last_selection_state = "",
}

-- Check selection signature to detect change
local function get_selection_signature()
    local num_items = reaper.CountSelectedMediaItems(0)
    if num_items > 10000 then num_items = 10000 end -- Safety limit
    local sig = {}
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            local take = reaper.GetActiveTake(item)
            if take then
                table.insert(sig, tostring(take))
            end
        end
    end
    return table.concat(sig, ";")
end

-- Populate selection info
local function update_takes_list()
    local current_sig = get_selection_signature()
    local selection_changed = current_sig ~= gui_state.last_selection_state
    
    if selection_changed then
        gui_state.last_selection_state = current_sig
        gui_state.selected_takes = {}
        
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 10000 then num_items = 10000 end -- Safety limit
        for i = 0, num_items - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            if item then
                local take = reaper.GetActiveTake(item)
                if take then
                    local name = reaper.GetTakeName(take) or "Unnamed Take"
                    local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                    table.insert(gui_state.selected_takes, {
                        item = item,
                        take = take,
                        name = name,
                        baseline_offset = cur_offset
                    })
                end
            end
        end
    else
        -- Sync baseline offsets with REAPER's actual offsets if we are NOT dragging the slider
        local is_slider_active = reaper.ImGui_IsAnyItemActive(ctx)
        if not is_slider_active then
            for _, info in ipairs(gui_state.selected_takes) do
                if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                    info.baseline_offset = reaper.GetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS")
                end
            end
        end
    end
end

-- Helper to apply offset by delta (from buttons or text box)
local function adjust_offset_by_delta(delta_ms)
    if #gui_state.selected_takes == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    local delta_sec = delta_ms / 1000.0
    for _, info in ipairs(gui_state.selected_takes) do
        if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
            local new_offset = info.baseline_offset + delta_sec
            reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", new_offset)
            reaper.UpdateItemInProject(info.item)
            info.baseline_offset = new_offset
        end
    end
    reaper.Undo_EndBlock2(0, string.format("Adjust media offset by %.1f ms", delta_ms), -1)
    reaper.UpdateArrange()
end

-- Helper to reset offsets to 0
local function reset_offsets_to_zero()
    if #gui_state.selected_takes == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    for _, info in ipairs(gui_state.selected_takes) do
        if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
            reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", 0.0)
            reaper.UpdateItemInProject(info.item)
            info.baseline_offset = 0.0
        end
    end
    reaper.Undo_EndBlock2(0, "Reset media offsets to 0", -1)
    reaper.UpdateArrange()
end

-- Push Theme Custom Colors & Styles
local function push_theme()
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_WindowBg,             reaper.ImGui_ColorConvertDouble4ToU32(0.08, 0.08, 0.1, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_TitleBg,              reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.15, 0.25, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_TitleBgActive,        reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.2, 0.4, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBg,              reaper.ImGui_ColorConvertDouble4ToU32(0.15, 0.15, 0.18, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBgHovered,       reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.25, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBgActive,        reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.35, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_SliderGrab,           reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.35, 0.8, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_SliderGrabActive,     reaper.ImGui_ColorConvertDouble4ToU32(0.6, 0.45, 0.9, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,               reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.25, 0.45, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered,        reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.35, 0.6, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,         reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.45, 0.75, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text,                 reaper.ImGui_ColorConvertDouble4ToU32(0.92, 0.92, 0.95, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Header,               reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.18, 0.3, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_HeaderHovered,        reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.25, 0.45, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_HeaderActive,         reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.35, 0.6, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Border,               reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.3, 0.5))

    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_FrameRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_GrabRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_WindowRounding, 8.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ButtonRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, 8.0, 6.0)
end

-- Pop Theme Styles & Colors
local function pop_theme()
    reaper.ImGui_PopStyleColor(ctx, 16)
    reaper.ImGui_PopStyleVar(ctx, 5)
end

-- Render the main controls
local function render_ui()
    local num_takes = #gui_state.selected_takes
    
    if num_takes == 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.3, 0.3, 1.0))
        reaper.ImGui_Text(ctx, "No selected media items with active takes.")
        reaper.ImGui_PopStyleColor(ctx)
        return
    end

    -- Visual feedback on selection size
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.8, 1.0, 1.0))
    reaper.ImGui_Text(ctx, string.format("Selected active takes: %d", num_takes))
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Combo for selecting range
    local range_changed, new_range_idx = reaper.ImGui_Combo(ctx, "Slider Range", gui_state.range_idx, RANGE_LABELS)
    if range_changed then
        gui_state.range_idx = new_range_idx
    end

    local current_range = RANGE_OPTIONS[gui_state.range_idx + 1] or 1000

    -- Double-click / Drag slider for relative offset
    -- Range is centered around 0
    local slider_changed, new_slider_val = reaper.ImGui_SliderDouble(ctx, "Offset Adjust", gui_state.slider_value, -current_range, current_range, "%.1f ms")
    local is_slider_active = reaper.ImGui_IsItemActive(ctx)
    local is_slider_activated = reaper.ImGui_IsItemActivated(ctx)
    local is_slider_deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    if slider_changed then
        gui_state.slider_value = new_slider_val
        
        -- Apply real-time visual offset change (no undo block during drag)
        local offset_sec = new_slider_val / 1000.0
        for _, info in ipairs(gui_state.selected_takes) do
            if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                local target_offset = info.baseline_offset + offset_sec
                reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", target_offset)
                reaper.UpdateItemInProject(info.item)
            end
        end
        reaper.UpdateArrange()
    end

    if is_slider_deactivated then
        -- User finished editing, commit the changes
        if gui_state.slider_value ~= 0.0 then
            -- Restore baseline offsets temporarily
            for _, info in ipairs(gui_state.selected_takes) do
                if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                    reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", info.baseline_offset)
                end
            end
            
            -- Begin proper undo block
            reaper.Undo_BeginBlock2(0)
            
            -- Apply final offsets
            local final_offset_sec = gui_state.slider_value / 1000.0
            for _, info in ipairs(gui_state.selected_takes) do
                if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                    local target_offset = info.baseline_offset + final_offset_sec
                    reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", target_offset)
                    reaper.UpdateItemInProject(info.item)
                end
            end
            
            -- End undo block
            reaper.Undo_EndBlock2(0, string.format("Adjust media offset by %.1f ms", gui_state.slider_value), -1)
            reaper.UpdateArrange()
            
            -- Update baselines
            for _, info in ipairs(gui_state.selected_takes) do
                info.baseline_offset = info.baseline_offset + final_offset_sec
            end
        end
        gui_state.slider_value = 0.0
    end

    reaper.ImGui_Spacing(ctx)

    -- Fine-tuning buttons row
    local win_width = reaper.ImGui_GetWindowWidth(ctx)
    local button_width = math.floor((win_width - 40) / 7)
    if button_width < 45 then button_width = 45 end
    local button_height = 24

    if reaper.ImGui_Button(ctx, "-10ms", button_width, button_height) then
        adjust_offset_by_delta(-10.0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "-1ms", button_width, button_height) then
        adjust_offset_by_delta(-1.0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "-0.1ms", button_width, button_height) then
        adjust_offset_by_delta(-0.1)
    end
    reaper.ImGui_SameLine(ctx)
    
    -- Highlight Reset 0 button
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.25, 0.25, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(0.65, 0.3, 0.3, 1.0))
    if reaper.ImGui_Button(ctx, "Reset 0", button_width, button_height) then
        reset_offsets_to_zero()
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+0.1ms", button_width, button_height) then
        adjust_offset_by_delta(0.1)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+1ms", button_width, button_height) then
        adjust_offset_by_delta(1.0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+10ms", button_width, button_height) then
        adjust_offset_by_delta(10.0)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Custom input row
    local input_changed, new_custom_val = reaper.ImGui_InputDouble(ctx, "Custom Step (ms)", gui_state.custom_delta, 1.0, 10.0, "%.1f")
    if input_changed then
        gui_state.custom_delta = new_custom_val
    end
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Apply Custom", -1, 24) then
        adjust_offset_by_delta(gui_state.custom_delta)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Display selected takes details table
    reaper.ImGui_Text(ctx, "Selected Takes Details:")
    reaper.ImGui_Spacing(ctx)

    local table_flags = imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_Resizable | imgui.TableFlags_ScrollY
    local display_height = 120 -- Constrain table height with scrolling
    if reaper.ImGui_BeginTable(ctx, "OffsetsTable", 3, table_flags, 0, display_height) then
        reaper.ImGui_TableSetupColumn(ctx, "Take Name")
        reaper.ImGui_TableSetupColumn(ctx, "Original Start Offset")
        reaper.ImGui_TableSetupColumn(ctx, "Current Start Offset")
        reaper.ImGui_TableHeadersRow(ctx)

        for _, info in ipairs(gui_state.selected_takes) do
            if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                reaper.ImGui_TableNextRow(ctx)
                
                -- Col 1: Take Name
                reaper.ImGui_TableNextColumn(ctx)
                reaper.ImGui_Text(ctx, info.name)
                
                -- Col 2: Original Offset
                reaper.ImGui_TableNextColumn(ctx)
                reaper.ImGui_Text(ctx, string.format("%.1f ms (%.4fs)", info.baseline_offset * 1000.0, info.baseline_offset))
                
                -- Col 3: Current Offset
                reaper.ImGui_TableNextColumn(ctx)
                local cur_offset = reaper.GetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS")
                reaper.ImGui_Text(ctx, string.format("%.1f ms (%.4fs)", cur_offset * 1000.0, cur_offset))
            end
        end
        reaper.ImGui_EndTable(ctx)
    end
end

-- Key shortcuts
local function handle_keyboard_shortcuts()
    local is_ctrl_down = reaper.ImGui_IsKeyDown(ctx, imgui.Key_LeftCtrl) or reaper.ImGui_IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = reaper.ImGui_IsKeyDown(ctx, imgui.Key_LeftSuper) or reaper.ImGui_IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = reaper.ImGui_IsKeyDown(ctx, imgui.Key_LeftShift) or reaper.ImGui_IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)
        update_takes_list()
    end

    -- Redo (Ctrl+Y or Cmd+Shift+Z)
    if (is_ctrl_down and not is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
        update_takes_list()
    end

    -- Escape key handling
    if reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
    end
end

-- Main Loop
local function loop()
    if not script_running then
        return
    end

    -- Selection management
    update_takes_list()

    -- Set size constraints
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 480, 320, 800, 600)

    -- Set window style/colors
    push_theme()

    local window_flags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost
    local visible, open = reaper.ImGui_Begin(ctx, script_name, true, window_flags)
    
    if not open then
        script_running = false
    end

    -- Bring window to front if it loses focus to keep it topmost
    if visible and script_running then
        local is_window_focused = reaper.ImGui_IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
        if not is_window_focused then
            reaper.ImGui_SetWindowFocus(ctx)
        end
    end

    if visible and script_running then
        handle_keyboard_shortcuts()
        render_ui()
    end

    reaper.ImGui_End(ctx)
    pop_theme()

    if script_running then
        reaper.defer(loop)
    end
end

-- Init
reaper.defer(loop)
