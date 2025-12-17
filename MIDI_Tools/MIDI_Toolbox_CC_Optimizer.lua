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
local MIDI_UTILS = require "midi_utils"

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
    
    -- Noise filtering controls
    noise_filter_threshold = 5, -- 0-20, threshold for detecting noise spikes
    noise_filter_enabled = false,
    
    -- Cache management
    cc_list_cache = {},
    selected_ccs_cache_valid = false,
    last_selected_ccs_signature = "", -- Track selection changes to detect when to invalidate cache
    
    -- Drag state
    drag_start_threshold = 0,
    threshold_drag_active = false,
    
    -- Performance optimization state
    smooth_preview_values = {},  -- Store preview values during drag
    smooth_timer = 0,            -- Timer for throttling operations
    smooth_update_interval = 50,  -- Update every 50ms during drag
    smooth_drag_active = false,   -- Track if smoothing drag is active
    large_dataset_mode = false,   -- Enable optimizations for large datasets
    last_smooth_amount = 0,      -- Track last processed smooth amount
    last_cache_clear = 0,        -- Track last cache clear time for periodic clearing
    last_cc_count = 0            -- Track last CC count to detect changes in events
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
    gui_state.noise_filter_threshold = 5
    gui_state.noise_filter_enabled = false
    gui_state.redundant_event_count = 0
    gui_state.total_event_count = 0
    gui_state.selected_in_lane_count = 0
    gui_state.drag_start_threshold = 0
    gui_state.threshold_drag_active = false
    
    -- Reset performance optimization state
    gui_state.smooth_preview_values = {}
    gui_state.smooth_timer = 0
    gui_state.smooth_drag_active = false
    gui_state.large_dataset_mode = false
    gui_state.last_smooth_amount = 0
    gui_state.last_cache_clear = 0
    gui_state.last_cc_count = 0
end

-- Register cleanup function with robust protection
CLEANUP_MANAGER.setup_atexit_handler("Combined_CC_Tool", cleanup_resources)


-- Function to get current MIDI context consistently (wrapper for shared utility)
function get_midi_context()
    local current_take, midi_editor = MIDI_UTILS.get_midi_context()
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

-- Helper function to get the active MIDI take (wrapper for shared utility)
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
    MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Remove " .. changes .. " redundant CC events", UNDO_MANAGER)
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
    MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Select all CCs in lane", UNDO_MANAGER)
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


-- Logic from "Smooth CCs" - Optimized version
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
            table.insert(list, {idx = i, val = val, original_val = val})
        end
    end
    
    -- Enable large dataset mode for performance optimization
    gui_state.large_dataset_mode = #list > 500
    
    return list
end

-- Optimized smoothing calculation without MIDI modification
function calculate_smooth_values(smooth_amount)
    if #gui_state.cc_list_cache < 3 then return {} end

    local c = smooth_amount / 100
    local smoothed_values = {}
    
    -- Pre-calculate for better performance
    for i = 1, #gui_state.cc_list_cache do
        smoothed_values[i] = gui_state.cc_list_cache[i].val
    end
    
    -- Apply smoothing algorithm
    for i = 2, #gui_state.cc_list_cache - 1 do
        local prev_val = smoothed_values[i-1]
        local curr_val = smoothed_values[i]
        local next_val = smoothed_values[i+1]

        local avg = (prev_val + curr_val + next_val) / 3
        local new_val = curr_val - c * (curr_val - avg)
        smoothed_values[i] = math.floor(math.max(0, math.min(127, new_val + 0.5)))
    end
    
    return smoothed_values
end

-- Batch apply smoothed values to MIDI
function apply_smoothed_values(smoothed_values)
    if not gui_state.take or #smoothed_values == 0 then return end

    -- Begin undo block for batch operation
    UNDO_MANAGER.begin_undo_block("CC smoothing operation")
    
    -- Apply all changes in batch
    for i = 2, #gui_state.cc_list_cache - 1 do
        local cc_event = gui_state.cc_list_cache[i]
        if smoothed_values[i] then
            reaper.MIDI_SetCC(gui_state.take, cc_event.idx, true, false, nil, nil, nil, nil, smoothed_values[i], false)
        end
    end
    
    -- Sort once at the end
    reaper.MIDI_Sort(gui_state.take)
    
    -- End undo block
    UNDO_MANAGER.end_undo_block("CC smoothing operation")
    
    -- Register undo
    MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Smooth CC events", UNDO_MANAGER)
    
    -- Update arrange once at the end
    reaper.UpdateArrange()
end

-- Throttled smoothing function for real-time preview
function smooth_ccs_throttled()
    if not gui_state.take or #gui_state.cc_list_cache < 3 then return end
    
    local current_time = reaper.time_precise()
    
    -- Throttle updates based on dataset size
    local throttle_interval = gui_state.large_dataset_mode and 100 or 50
    
    if current_time - gui_state.smooth_timer < throttle_interval then
        return  -- Skip this update to maintain performance
    end
    
    gui_state.smooth_timer = current_time
    
    -- Calculate smoothed values without applying them
    gui_state.smooth_preview_values = calculate_smooth_values(gui_state.smooth_amount)
    
    -- For large datasets, only update arrange periodically
    if not gui_state.large_dataset_mode or math.floor(current_time * 10) % 5 == 0 then
        reaper.UpdateArrange()
    end
end

-- Legacy function for backward compatibility
function smooth_ccs()
    if not gui_state.take or #gui_state.cc_list_cache < 3 then return end

    local smoothed_values = calculate_smooth_values(gui_state.smooth_amount)
    apply_smoothed_values(smoothed_values)
end

-- Noise filtering functions
-- Calculate noise filtered values using high-pass filter approach
function calculate_noise_filtered_values(filter_threshold)
    if #gui_state.cc_list_cache < 3 then return {} end

    local filtered_values = {}
    local threshold = filter_threshold
    
    -- Copy original values
    for i = 1, #gui_state.cc_list_cache do
        filtered_values[i] = gui_state.cc_list_cache[i].val
    end
    
    -- Apply noise detection and filtering
    -- We'll use a combination of slope detection and local averaging to identify noise
    for i = 2, #gui_state.cc_list_cache - 1 do
        local prev_val = gui_state.cc_list_cache[i-1].val
        local curr_val = gui_state.cc_list_cache[i].val
        local next_val = gui_state.cc_list_cache[i+1].val
        
        -- Calculate the expected value based on linear interpolation between neighbors
        local expected_val = (prev_val + next_val) / 2
        local deviation = math.abs(curr_val - expected_val)
        
        -- If deviation exceeds threshold, consider it noise and replace with interpolated value
        if deviation > threshold then
            -- Use weighted average of neighbors for smoother result
            filtered_values[i] = math.floor((prev_val * 0.3 + expected_val * 0.4 + next_val * 0.3) + 0.5)
            -- Ensure value stays within valid CC range
            filtered_values[i] = math.max(0, math.min(127, filtered_values[i]))
        end
    end
    
    return filtered_values
end

-- Apply noise filtered values to MIDI
function apply_noise_filtered_values(filtered_values)
    if not gui_state.take or #filtered_values == 0 then return end

    -- Begin undo block for batch operation
    UNDO_MANAGER.begin_undo_block("CC noise filtering operation")
    
    -- Apply all changes in batch
    local changes = 0
    for i = 1, #gui_state.cc_list_cache do
        local cc_event = gui_state.cc_list_cache[i]
        if filtered_values[i] and filtered_values[i] ~= cc_event.original_val then
            reaper.MIDI_SetCC(gui_state.take, cc_event.idx, true, false, nil, nil, nil, nil, filtered_values[i], false)
            changes = changes + 1
        end
    end
    
    -- Sort once at the end
    reaper.MIDI_Sort(gui_state.take)
    
    -- End undo block
    UNDO_MANAGER.end_undo_block("CC noise filtering operation")
    
    -- Register undo
    MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Filter noise from " .. changes .. " CC events", UNDO_MANAGER)
    
    -- Update arrange once at the end
    reaper.UpdateArrange()
end

-- Main noise filtering function
function filter_cc_noise()
    if not gui_state.take or #gui_state.cc_list_cache < 3 then return end

    local filtered_values = calculate_noise_filtered_values(gui_state.noise_filter_threshold)
    apply_noise_filtered_values(filtered_values)
end

-- Function to convert selected CC points to Bezier curves
function convert_to_bezier()
    local current_take, midi_editor, lane = get_midi_context()
    
    if not gui_state.take or lane < 0 or lane > 127 then return end
    
    -- Begin undo block for batch operation
    UNDO_MANAGER.begin_undo_block("Convert CC events to Bezier")
    
    local changes = 0
    local i = -1
    
    -- Iterate through all selected CC events
    while true do
        i = reaper.MIDI_EnumSelCC(gui_state.take, i)
        if i == -1 then break end
        
        local _, _, _, _, _, _, cc, _ = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
        if cc == lane then
            -- Check current shape before converting
            local _, current_shape, _ = reaper.MIDI_GetCCShape(gui_state.take, i, 0, 0)
            
            -- Only convert if not already a Bezier curve (shape 5)
            if current_shape ~= 5 then
                -- Set the shape to Bezier (shape flag 5 for Bezier)
                -- Using a default bezier tension of 0.1 for smoother curves
                reaper.MIDI_SetCCShape(gui_state.take, i, 5, 0.1, true)
                changes = changes + 1
            end
        end
    end
    
    -- Sort once at the end
    reaper.MIDI_Sort(gui_state.take)
    
    -- End undo block
    UNDO_MANAGER.end_undo_block("Convert CC events to Bezier")
    
    -- Register undo
    MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Convert " .. changes .. " CC events to Bezier", UNDO_MANAGER)
    
    -- Update arrange once at the end
    reaper.UpdateArrange()
    
    -- Invalidate caches since CC shapes were modified
    invalidate_all_caches()
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
            -- Clear cache if take, lane, or CC events change
            local _, _, current_cc_count, _ = reaper.MIDI_CountEvts(current_take, 0, 0, 0)
            if gui_state.take ~= current_take or
               gui_state.last_clicked_cc_lane ~= current_lane or
               gui_state.last_cc_count ~= current_cc_count then
                invalidate_all_caches()
                gui_state.last_cc_count = current_cc_count
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
            else
                -- Show performance mode indicator for large datasets
                if gui_state.large_dataset_mode then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.8, 0.2, 1.0)) -- Green
                    imgui.Text(ctx, "Performance mode active (" .. gui_state.selected_in_lane_count .. " points)")
                    reaper.ImGui_PopStyleColor(ctx)
                end
            end
            local _, new_smooth_amount = imgui.SliderInt(ctx, "Amount", gui_state.smooth_amount, 0, 100, "%d%%")
            gui_state.smooth_amount = new_smooth_amount

            -- Handle smoothing logic with performance optimizations
            if imgui.IsItemActivated(ctx) then
                -- Build cache once when slider is activated
                gui_state.cc_list_cache = build_cc_cache()
                gui_state.smooth_drag_active = true
                gui_state.smooth_timer = reaper.time_precise()
                gui_state.last_smooth_amount = gui_state.smooth_amount
            end

            -- Optimized real-time smoothing while dragging the slider
            if imgui.IsItemActive(ctx) and #gui_state.cc_list_cache > 0 then
                -- Only process if smooth amount actually changed
                if gui_state.smooth_amount ~= gui_state.last_smooth_amount then
                    smooth_ccs_throttled()  -- Use throttled version for performance
                    gui_state.last_smooth_amount = gui_state.smooth_amount
                end
            end

            if imgui.IsItemDeactivatedAfterEdit(ctx) then
                -- Apply final smoothing with batch operation
                if #gui_state.cc_list_cache > 0 and gui_state.smooth_amount > 0 then
                    local smoothed_values = calculate_smooth_values(gui_state.smooth_amount)
                    apply_smoothed_values(smoothed_values)
                end
                
                -- Reset performance state
                gui_state.smooth_drag_active = false
                gui_state.smooth_preview_values = {}
                
                -- Update caches and statistics
                invalidate_all_caches()
                calculate_redundant_ccs() -- Recalculate redundant count after smoothing ends
            end

            -- Clear the cache when the slider is not active to prevent memory buildup
            if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #gui_state.cc_list_cache > 0 then
                if not gui_state.large_dataset_mode then
                    invalidate_all_caches()
                else
                    -- For large datasets, clear cache periodically (e.g., every 30 seconds)
                    local current_time = reaper.time_precise()
                    if not gui_state.last_cache_clear or current_time - gui_state.last_cache_clear > 30 then
                        invalidate_all_caches()
                        gui_state.last_cache_clear = current_time
                    end
                end
            end
            
            -- Add Convert to Bezier button under the slider
            imgui.Spacing(ctx)
            if imgui.Button(ctx, "Convert to Bezier") then
                convert_to_bezier()
            end

            imgui.Separator(ctx)

            -- Noise Filter Section
            imgui.Text(ctx, "Filter Noise from Selected CCs")
            if gui_state.selected_in_lane_count < 3 then
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                imgui.Text(ctx, "Select at least 3 CC events to use noise filter.")
                reaper.ImGui_PopStyleColor(ctx)
            else
                imgui.Text(ctx, "Threshold: Detects and removes sudden spikes")
                local _, new_noise_threshold = imgui.SliderInt(ctx, "Sensitivity", gui_state.noise_filter_threshold, 1, 20, "%d")
                
                if new_noise_threshold ~= gui_state.noise_filter_threshold then
                    gui_state.noise_filter_threshold = new_noise_threshold
                end
                
                imgui.Spacing(ctx)
                
                -- Add Filter Noise button
                if imgui.Button(ctx, "Filter Noise") then
                    -- Build cache before filtering
                    gui_state.cc_list_cache = build_cc_cache()
                    filter_cc_noise()
                    -- Update caches and statistics after filtering
                    invalidate_all_caches()
                    calculate_redundant_ccs()
                end
                
                imgui.Spacing(ctx)
                imgui.Text(ctx, "Quick Presets:")
                
                -- Create a row of preset buttons for noise filtering
                local preset_width = 80
                if imgui.Button(ctx, "Gentle", preset_width, 0) then
                    gui_state.noise_filter_threshold = 3
                    gui_state.cc_list_cache = build_cc_cache()
                    filter_cc_noise()
                    invalidate_all_caches()
                    calculate_redundant_ccs()
                end
                imgui.SameLine(ctx)
                if imgui.Button(ctx, "Normal", preset_width, 0) then
                    gui_state.noise_filter_threshold = 5
                    gui_state.cc_list_cache = build_cc_cache()
                    filter_cc_noise()
                    invalidate_all_caches()
                    calculate_redundant_ccs()
                end
                imgui.SameLine(ctx)
                if imgui.Button(ctx, "Aggressive", preset_width, 0) then
                    gui_state.noise_filter_threshold = 8
                    gui_state.cc_list_cache = build_cc_cache()
                    filter_cc_noise()
                    invalidate_all_caches()
                    calculate_redundant_ccs()
                end
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
                gui_state.cc_redundancy_threshold = math.floor(10 * 0.1)  -- 10% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "20%", button_width, 0) then
                gui_state.cc_redundancy_threshold = math.floor(10 * 0.2)  -- 20% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "50%", button_width, 0) then
                gui_state.cc_redundancy_threshold = math.floor(10 * 0.5)  -- 50% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "70%", button_width, 0) then
                gui_state.cc_redundancy_threshold = math.floor(10 * 0.7)  -- 70% of max value 10
                remove_redundant_ccs()
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "90%", button_width, 0) then
                gui_state.cc_redundancy_threshold = math.floor(10 * 0.9)  -- 90% of max value 10
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