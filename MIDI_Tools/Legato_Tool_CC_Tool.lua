-- @noindex

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Check for reaimgui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load the ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

-- Centralized require statements at the top of the file
local CLEANUP_MANAGER = require "cleanup_manager"
local UNDO_MANAGER = require "undo_manager"

-- Script variables
local script_name = "Combined CC Tool"
local ctx = imgui.CreateContext(script_name)
local script_running = true

-- Unified GUI State Management System
local gui_state = {
    -- MIDI context
    take = nil,
    last_clicked_cc_lane = -1,
    lane_name = "",
    
    -- CC statistics
    redundant_event_count = 0,
    total_event_count = 0,
    selected_in_lane_count = 0,
    
    -- CC controls
    smooth_amount = 0, -- 0-100%
    cc_redundancy_threshold = 0,
    
    -- Cache management
    cc_list_cache = {},
    selected_ccs_cache_valid = false,
    last_selected_ccs_signature = "", -- Track selection changes to detect when to invalidate cache
    
    -- Drag state
    drag_start_threshold = 0,
    threshold_drag_active = false
}

-- Centralized state management functions
local function invalidate_all_caches()
    gui_state.cc_list_cache = {}
    gui_state.selected_ccs_cache_valid = false
    gui_state.last_selected_ccs_signature = ""
end

-- Function to ensure gui_state.take is properly updated
local function update_gui_state_take()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if midi_editor then
        local current_take = reaper.MIDIEditor_GetTake(midi_editor)
        if current_take then
            gui_state.take = current_take
        end
    end
end

-- Robust cleanup function
local function cleanup_resources()
    -- Clear all caches using unified state management
    invalidate_all_caches()
    
    -- Reset all state variables
    gui_state.take = nil
    gui_state.last_clicked_cc_lane = -1
    gui_state.lane_name = ""
    gui_state.smooth_amount = 0
    gui_state.cc_redundancy_threshold = 0
    gui_state.redundant_event_count = 0
    gui_state.total_event_count = 0
    gui_state.selected_in_lane_count = 0
    gui_state.drag_start_threshold = 0
    gui_state.threshold_drag_active = false
end

-- Register cleanup function with robust protection
CLEANUP_MANAGER.setup_atexit_handler("Combined_CC_Tool", cleanup_resources)


-- Function to get current MIDI context consistently
function get_midi_context()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil, nil, nil end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then return nil, nil, nil end

    -- Update gui_state.take when we have a valid take
    gui_state.take = current_take

    local current_lane = reaper.MIDIEditor_GetSetting_int(midi_editor, "last_clicked_cc_lane")
    if current_lane < 0 or current_lane > 127 then return gui_state.take, midi_editor, current_lane end

    return gui_state.take, midi_editor, current_lane
end

-- Function to compute a signature of selected CCs in the current lane to detect selection changes
function compute_selected_ccs_signature()
    local current_take, midi_editor, lane = get_midi_context()

    if not gui_state.take or lane < 0 or lane > 127 then return "" end

    local signature_parts = {}
    local i = -1
    while true do
        i = reaper.MIDI_EnumSelCC(gui_state.take, i)
        if i == -1 then break end

        local _, _, _, ppqpos, _, _, cc, _ = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
        if cc == lane then
            table.insert(signature_parts, ppqpos) -- Use position to identify the selected CC
        end
    end

    -- Sort to ensure consistent order and create a string signature
    table.sort(signature_parts)
    return table.concat(signature_parts, ",")
end

-- Helper function to get the active MIDI take
function get_active_take()
    return gui_state.take
end

-- Logic from "Remove redundant CCs"
function calculate_redundant_ccs()
    local current_take, midi_editor, lane = get_midi_context()

    if not midi_editor then
        gui_state.lane_name = "Please open a MIDI editor."
        gui_state.total_event_count = 0
        gui_state.redundant_event_count = 0
        gui_state.take = nil
        gui_state.last_clicked_cc_lane = -1  -- Reset to indicate no valid lane
        gui_state.selected_ccs_cache_valid = false  -- Invalidate cache when context is invalid
        return
    end

    if not current_take then
        gui_state.lane_name = "Could not get MIDI take."
        gui_state.total_event_count = 0
        gui_state.redundant_event_count = 0
        gui_state.take = nil
        gui_state.last_clicked_cc_lane = -1  -- Reset to indicate no valid lane
        gui_state.selected_ccs_cache_valid = false  -- Invalidate cache when context is invalid
        return
    end

    -- gui_state.take is already updated in get_midi_context()

    if lane < 0 or lane > 127 then
        gui_state.redundant_event_count = 0
        gui_state.total_event_count = 0
        gui_state.lane_name = "Select a CC lane"
        gui_state.last_clicked_cc_lane = lane  -- Still update to the invalid lane number so the condition will be accurate
        gui_state.selected_ccs_cache_valid = false  -- Invalidate cache when context is invalid
        return
    end

    gui_state.last_clicked_cc_lane = lane
    local _, name = reaper.MIDIEditor_GetSetting_str(midi_editor, "last_clicked_cc_lane", "")
    gui_state.lane_name = "CC" .. lane .. " " .. name

    local _, _, cc_count, _ = reaper.MIDI_CountEvts(gui_state.take, 0, 0, 0)

    local last_event_value = nil  -- Use nil to indicate no previous event has been processed yet
    gui_state.redundant_event_count = 0
    gui_state.total_event_count = 0

    for i = 0, cc_count - 1 do
        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
        if cc == gui_state.last_clicked_cc_lane then
            gui_state.total_event_count = gui_state.total_event_count + 1
            -- Only check for redundancy if this is not the first event in the lane
            if last_event_value ~= nil and math.abs(val - last_event_value) <= gui_state.cc_redundancy_threshold then
                gui_state.redundant_event_count = gui_state.redundant_event_count + 1
            end
            -- For the first event, just set it as the reference; for subsequent events, always update the reference
            last_event_value = val
        end
    end
end

function remove_redundant_ccs()
    local current_take, midi_editor, lane = get_midi_context()

    if not gui_state.take then return end
    if lane < 0 or lane > 127 then return end

    -- First, collect all indices of redundant CCs to avoid index shifting issues during deletion
    -- The algorithm processes events in order and marks events as redundant based on similarity
    -- to the last NON-redundant event in the same lane
    local redundant_indices = {}
    local last_event_value = nil  -- Initialize as nil to handle first event properly
    local first_event_in_lane = true  -- Track if this is the first event in the lane
    local _, _, cc_count, _ = reaper.MIDI_CountEvts(gui_state.take, 0, 0, 0)

    for i = 0, cc_count - 1 do
        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
        if cc == lane then
            if not first_event_in_lane and math.abs(val - last_event_value) <= gui_state.cc_redundancy_threshold then
                -- This CC is redundant (similar to the last non-redundant value)
                table.insert(redundant_indices, i)
            else
                -- This CC is not redundant, so update the reference value
                last_event_value = val
                first_event_in_lane = false  -- We've seen the first event now
            end
            -- Mark that we've seen at least one event in this lane
            first_event_in_lane = false
        end
        -- CCs in other lanes are ignored for the redundancy calculation
    end

    -- If no redundant CCs found, return early without doing anything
    if #redundant_indices == 0 then return end

    -- Delete redundant CCs in reverse order to avoid index shifting issues
    local changes = 0
    for i = #redundant_indices, 1, -1 do
        reaper.MIDI_DeleteCC(gui_state.take, redundant_indices[i])
        changes = changes + 1
    end

    -- Use standardized undo management
    local item = reaper.GetMediaItemTake_Item(gui_state.take)
    UNDO_MANAGER.register_undo(item, "Remove " .. changes .. " redundant CC events", "CC removal operation")
    reaper.MIDI_Sort(gui_state.take) -- Ensure MIDI events are properly sorted after modifications
    calculate_redundant_ccs() -- Recalculate after removal
    gui_state.cc_redundancy_threshold = 0 -- Reset threshold to 0
    -- Invalidate all caches since CC events were removed
    gui_state.selected_ccs_cache_valid = false
    -- Clear the smoothing cache as well since CC indices may have changed
    if #gui_state.cc_list_cache > 0 then
        gui_state.cc_list_cache = {}
    end
end

function select_all_ccs_in_lane()
    local current_take, midi_editor, lane = get_midi_context()

    if not gui_state.take or lane < 0 or lane > 127 then return end

    local changes = 0
    local _, _, cc_count, _ = reaper.MIDI_CountEvts(gui_state.take, 0, 0, 0)
    for i = 0, cc_count - 1 do
        local _, selected, muted, ppqpos, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(gui_state.take, i)
        if msg2 == lane and not selected then
            reaper.MIDI_SetCC(gui_state.take, i, true, muted, ppqpos, chanmsg, chan, msg2, msg3, 0)
            changes = changes + 1
        end
    end

    -- Use standardized undo management
    local item = reaper.GetMediaItemTake_Item(gui_state.take)
    UNDO_MANAGER.register_undo(item, "Select all CCs in lane", "CC selection operation")
    reaper.MIDI_Sort(gui_state.take) -- Ensure MIDI events are properly sorted after modifications
    -- Invalidate all caches since selection changed
    gui_state.selected_ccs_cache_valid = false
    -- Clear the smoothing cache as well since selected CCs have changed
    if #gui_state.cc_list_cache > 0 then
        gui_state.cc_list_cache = {}
    end
    -- Reset the selection signature to force recalculation of selected count in the next GUI update
    gui_state.last_selected_ccs_signature = ""
    -- Update the MIDI arrangement to ensure changes are reflected immediately
    reaper.UpdateArrange()
    -- Immediately update the selected count for the GUI to show correct value
    if gui_state.take and lane >= 0 and lane <= 127 then
        gui_state.selected_in_lane_count = 0
        local i = -1
        while true do
            i = reaper.MIDI_EnumSelCC(gui_state.take, i)
            if i == -1 then break end
            local _, _, _, _, _, _, cc, _ = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
            if cc == lane then
                gui_state.selected_in_lane_count = gui_state.selected_in_lane_count + 1
            end
        end
        gui_state.selected_ccs_cache_valid = true
    end
end


-- Logic from "Smooth CCs"
function build_cc_cache()
    local current_take, midi_editor, lane = get_midi_context()

    if not gui_state.take then return {} end
    if lane < 0 or lane > 127 then return {} end

    local list = {}
    local i = -1
    while true do
        i = reaper.MIDI_EnumSelCC(gui_state.take, i)
        if i == -1 then break end

        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
        if cc == lane then
            table.insert(list, {idx = i, val = val})
        end
    end
    return list
end

function smooth_ccs()
    if not gui_state.take or #gui_state.cc_list_cache < 3 then return end

    local c = gui_state.smooth_amount / 100

    for i = 2, #gui_state.cc_list_cache - 1 do
        local prev_val = gui_state.cc_list_cache[i-1].val
        local curr_val = gui_state.cc_list_cache[i].val
        local next_val = gui_state.cc_list_cache[i+1].val

        local avg = (prev_val + curr_val + next_val) / 3
        local new_val = curr_val - c * (curr_val - avg)
        new_val = math.floor(math.max(0, math.min(127, new_val + 0.5)))

        local cc_event = gui_state.cc_list_cache[i]
        reaper.MIDI_SetCC(gui_state.take, cc_event.idx, true, false, nil, nil, nil, nil, new_val, false)
    end
    reaper.UpdateArrange()
end

-- GUI
function loop()
    if not script_running then return end

    -- Handle global keyboard shortcuts
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = imgui.IsKeyDown(ctx, imgui.Key_LeftShift) or imgui.IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)  -- Actually, using project-specific as standard Undo_DoUndo() doesn't exist
        -- Invalidate all caches since undo may change CCs or selection
        invalidate_all_caches()
        -- Recalculate redundant CCs to update display after undo
        calculate_redundant_ccs()
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)  -- Using project-specific function as it's more reliable
        -- Invalidate all caches since redo may change CCs or selection
        invalidate_all_caches()
        -- Recalculate redundant CCs to update display after redo
        calculate_redundant_ccs()
    end
    
    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
        -- Use robust cleanup manager instead of manual cleanup
        CLEANUP_MANAGER.execute_cleanup("Combined_CC_Tool")
    end

    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse
    local visible, open = imgui.Begin(ctx, script_name, true, flags)
    
    if not open then
        script_running = false
        -- Use robust cleanup manager when window is closed
        CLEANUP_MANAGER.execute_cleanup("Combined_CC_Tool")
    end
    
    if visible and script_running then
        local current_take, midi_editor, current_lane = get_midi_context()

        if not midi_editor then
            -- Clear cache when no MIDI editor is active
            invalidate_all_caches()
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Clear cache if take or lane changes
            if gui_state.take ~= current_take or gui_state.last_clicked_cc_lane ~= current_lane then
                invalidate_all_caches()
            end

            if not current_take then
                -- Clear cache if no take is available
                invalidate_all_caches()
                -- Reset all statistics when no take is available
                gui_state.redundant_event_count = 0
                gui_state.total_event_count = 0
                gui_state.selected_in_lane_count = 0
                gui_state.take = nil
                gui_state.last_clicked_cc_lane = -1
                gui_state.lane_name = ""
                imgui.Text(ctx, "Could not get MIDI take.")
            else
                -- gui_state.take is already updated in get_midi_context()
                
                -- Shared Info
                if gui_state.last_clicked_cc_lane ~= current_lane or gui_state.lane_name == "" then
                    calculate_redundant_ccs()
                end

                if gui_state.last_clicked_cc_lane < 0 or gui_state.last_clicked_cc_lane > 127 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, "Please select a CC lane")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, gui_state.lane_name)
                end
            end -- end of current_take check

            if gui_state.take and current_lane >= 0 and current_lane <= 127 then
                if imgui.Button(ctx, "Update") then
                    calculate_redundant_ccs()
                    -- Invalidate caches to match the behavior of other UI actions
                    invalidate_all_caches()
                end
            end
            imgui.Separator(ctx)

            -- Count selected CCs for the current lane (with caching to avoid repeated calculation)
            if gui_state.take and current_lane >= 0 and current_lane <= 127 then
                -- Check if selection has changed and invalidate cache if needed
                local current_selection_signature = compute_selected_ccs_signature()
                if current_selection_signature ~= gui_state.last_selected_ccs_signature then
                    gui_state.selected_ccs_cache_valid = false
                    gui_state.last_selected_ccs_signature = current_selection_signature
                end

                -- Recalculate if cache is invalid or MIDI context changed
                if not gui_state.selected_ccs_cache_valid or gui_state.take ~= current_take or gui_state.last_clicked_cc_lane ~= current_lane then
                    gui_state.selected_in_lane_count = 0
                    local i = -1
                    while true do
                        i = reaper.MIDI_EnumSelCC(gui_state.take, i)
                        if i == -1 then break end
                        local _, _, _, _, _, _, cc, _ = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
                        if cc == current_lane then
                            gui_state.selected_in_lane_count = gui_state.selected_in_lane_count + 1
                        end
                    end
                    gui_state.selected_ccs_cache_valid = true
                end
            else
                -- Reset count if no valid context
                gui_state.selected_in_lane_count = 0
                gui_state.selected_ccs_cache_valid = false
                gui_state.last_selected_ccs_signature = ""
            end

            -- Smooth Section
            imgui.Text(ctx, "Smooth Selected CCs")
            if gui_state.selected_in_lane_count < 3 then
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                imgui.Text(ctx, "Select at least 3 CC events to use smoother.")
                reaper.ImGui_PopStyleColor(ctx)
                if imgui.Button(ctx, "Select all events in lane") then
                    select_all_ccs_in_lane()
                end
            end
            local _, new_smooth_amount = imgui.SliderInt(ctx, "Amount", gui_state.smooth_amount, 0, 100, "%d%%")
            gui_state.smooth_amount = new_smooth_amount

            -- Handle smoothing logic
            if imgui.IsItemActivated(ctx) then
                UNDO_MANAGER.begin_undo_block("CC smoothing operation")
                gui_state.cc_list_cache = build_cc_cache()  -- Cache once
            end

            -- Real-time smoothing while dragging the slider
            if imgui.IsItemActive(ctx) and #gui_state.cc_list_cache > 0 then
                smooth_ccs()  -- Apply smoothing in real-time while dragging
                reaper.UpdateArrange() -- Update the view to show real-time changes
            end

            if imgui.IsItemDeactivatedAfterEdit(ctx) then
                smooth_ccs()  -- Apply once with final smooth_amount
                if gui_state.take then
                    -- Use standardized undo management
                    local item = reaper.GetMediaItemTake_Item(gui_state.take)
                    reaper.MIDI_Sort(gui_state.take) -- Ensure MIDI events are properly sorted after modifications
                    UNDO_MANAGER.register_undo(item, "Smooth CC events", "CC smoothing operation")
                end
                invalidate_all_caches()
                calculate_redundant_ccs() -- Recalculate redundant count after smoothing ends
            end

            -- Clear the cache when the slider is not active to prevent memory buildup
            -- But only when not actively dragging (to preserve the cache during dragging)
            if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #gui_state.cc_list_cache > 0 then
                invalidate_all_caches()
            end

            imgui.Separator(ctx)

            -- Remove Redundant Section
            imgui.Text(ctx, "Remove Redundant CCs")
            imgui.Text(ctx, "Total Events: " .. gui_state.total_event_count)
            imgui.Text(ctx, "Redundant Events: " .. gui_state.redundant_event_count)
            local _, new_threshold = imgui.SliderInt(ctx, "Threshold", gui_state.cc_redundancy_threshold, 0, 10)

            -- Handle threshold slider interaction for real-time feedback
            local threshold_value_changed = new_threshold ~= gui_state.cc_redundancy_threshold
            local is_threshold_activated = imgui.IsItemActivated(ctx)  -- When user starts dragging
            local is_threshold_active = imgui.IsItemActive(ctx)        -- While user is dragging
            local is_threshold_deactivated = imgui.IsItemDeactivatedAfterEdit(ctx)  -- When user releases

            if is_threshold_activated then
                -- Store the original threshold value when starting to drag
                gui_state.drag_start_threshold = gui_state.cc_redundancy_threshold
                gui_state.threshold_drag_active = true
            end

            if threshold_value_changed then
                gui_state.cc_redundancy_threshold = new_threshold
                calculate_redundant_ccs() -- Recalculate counts when threshold changes
            end

            -- Apply threshold changes in real-time while dragging for visual feedback
            if is_threshold_active and gui_state.threshold_drag_active and threshold_value_changed then
                -- Update the display counts in real-time without actually applying deletions during dragging
                calculate_redundant_ccs() -- Update the display counts based on current threshold
            end

            -- Handle when slider is released after dragging
            if is_threshold_deactivated then
                -- Just update internal state, don't apply changes automatically
                if gui_state.threshold_drag_active then
                    gui_state.threshold_drag_active = false
                end
            end

            if imgui.Button(ctx, "Remove") then
                remove_redundant_ccs()
            end

            -- Threshold percentage buttons
            imgui.Spacing(ctx)
            imgui.Text(ctx, "Quick Thresholds:")

            -- Create a row of buttons for quick threshold selection
            local button_width = 50
            if imgui.Button(ctx, "10%", button_width, 0) then
                gui_state.cc_redundancy_threshold = 1  -- 10% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "20%", button_width, 0) then
                gui_state.cc_redundancy_threshold = 2  -- 20% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "50%", button_width, 0) then
                gui_state.cc_redundancy_threshold = 5  -- 50% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "70%", button_width, 0) then
                gui_state.cc_redundancy_threshold = 7  -- 70% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "90%", button_width, 0) then
                gui_state.cc_redundancy_threshold = 9  -- 90% of max value 10
                remove_redundant_ccs()
            end
        end
    end
    
    imgui.Spacing(ctx)
    imgui.End(ctx)

    -- Clean up caches when the script is terminated to prevent memory leaks
    if not script_running then
        -- Use robust cleanup manager instead of manual cleanup
        CLEANUP_MANAGER.execute_cleanup("Combined_CC_Tool")
    end

    if script_running then
        reaper.defer(loop)
    end
end
-- Init
reaper.defer(loop)