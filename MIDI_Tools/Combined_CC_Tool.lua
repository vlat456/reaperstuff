-- @description Combined CC Tool - Removing redundant CCs and smoothing selected CCs
-- @author drvlat
-- @version 0.1.4
-- @provides [main=midi_editor,midi_inlineeditor,midi_eventlisteditor] .
-- @about
--   This is a ReaScript for REAPER that provides tools for cleaning up MIDI CC data.
--   It removes redundant control change events and smooths selected CCs in the MIDI editor.
--
--   The tool provides a user interface for adjusting settings and applying CC cleanup
--   operations to selected MIDI CCs in the MIDI editor.
-- @changelog 
--      0.1.4 - working undo

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
local script_name = "Combined CC Tool"
local ctx = imgui.CreateContext(script_name)
local script_running = true
local take = nil
local last_clicked_cc_lane = -1
local lane_name = ""
local redundant_event_count = 0
local total_event_count = 0
local smooth_amount = 0 -- 0-100%
local cc_redundancy_threshold = 0 -- New global variable for redundancy threshold
local cc_list_cache = {}
local selected_in_lane_count = 0
local selected_ccs_cache_valid = false
local last_selected_ccs_signature = "" -- Track selection changes to detect when to invalidate cache

-- Variables for threshold slider with undo/redo functionality
local drag_start_threshold = 0 -- Threshold value at the start of dragging
local threshold_drag_active = false -- Track if threshold slider is currently being dragged


-- Function to get current MIDI context consistently
function get_midi_context()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil, nil, nil end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then return nil, nil, nil end

    local current_lane = reaper.MIDIEditor_GetSetting_int(midi_editor, "last_clicked_cc_lane")
    if current_lane < 0 or current_lane > 127 then return current_take, midi_editor, current_lane end

    return current_take, midi_editor, current_lane
end

-- Function to compute a signature of selected CCs in the current lane to detect selection changes
function compute_selected_ccs_signature()
    local current_take, midi_editor, lane = get_midi_context()

    if not current_take or lane < 0 or lane > 127 then return "" end

    local signature_parts = {}
    local i = -1
    while true do
        i = reaper.MIDI_EnumSelCC(current_take, i)
        if i == -1 then break end

        local _, _, _, ppqpos, _, _, cc, _ = reaper.MIDI_GetCC(current_take, i, false, false, 0, 0, 0, 0, 0)
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
    local current_take, midi_editor, lane = get_midi_context()
    return current_take
end

-- Logic from "Remove redundant CCs"
function calculate_redundant_ccs()
    local current_take, midi_editor, lane = get_midi_context()

    if not midi_editor then
        lane_name = "Please open a MIDI editor."
        total_event_count = 0
        redundant_event_count = 0
        take = nil
        last_clicked_cc_lane = -1  -- Reset to indicate no valid lane
        selected_ccs_cache_valid = false  -- Invalidate cache when context is invalid
        return
    end

    if not current_take then
        lane_name = "Could not get MIDI take."
        total_event_count = 0
        redundant_event_count = 0
        take = nil
        last_clicked_cc_lane = -1  -- Reset to indicate no valid lane
        selected_ccs_cache_valid = false  -- Invalidate cache when context is invalid
        return
    end

    take = current_take

    if lane < 0 or lane > 127 then
        redundant_event_count = 0
        total_event_count = 0
        lane_name = "Select a CC lane"
        last_clicked_cc_lane = lane  -- Still update to the invalid lane number so the condition will be accurate
        selected_ccs_cache_valid = false  -- Invalidate cache when context is invalid
        return
    end

    last_clicked_cc_lane = lane
    local _, name = reaper.MIDIEditor_GetSetting_str(midi_editor, "last_clicked_cc_lane", "")
    lane_name = "CC" .. lane .. " " .. name

    local _, _, cc_count, _ = reaper.MIDI_CountEvts(take, 0, 0, 0)

    local last_event_value = nil  -- Use nil to indicate no previous event has been processed yet
    redundant_event_count = 0
    total_event_count = 0

    for i = 0, cc_count - 1 do
        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(take, i, false, false, 0, 0, 0, 0, 0)
        if cc == last_clicked_cc_lane then
            total_event_count = total_event_count + 1
            -- Only check for redundancy if this is not the first event in the lane
            if last_event_value ~= nil and math.abs(val - last_event_value) <= cc_redundancy_threshold then
                redundant_event_count = redundant_event_count + 1
            end
            -- For the first event, just set it as the reference; for subsequent events, always update the reference
            last_event_value = val
        end
    end
end

function remove_redundant_ccs()
    local current_take, midi_editor, lane = get_midi_context()

    if not current_take then return end
    if lane < 0 or lane > 127 then return end

    -- First, collect all indices of redundant CCs to avoid index shifting issues during deletion
    -- The algorithm processes events in order and marks events as redundant based on similarity
    -- to the last NON-redundant event in the same lane
    local redundant_indices = {}
    local last_event_value = -1
    local _, _, cc_count, _ = reaper.MIDI_CountEvts(current_take, 0, 0, 0)

    for i = 0, cc_count - 1 do
        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(current_take, i, false, false, 0, 0, 0, 0, 0)
        if cc == lane then
            if math.abs(val - last_event_value) <= cc_redundancy_threshold then
                -- This CC is redundant (similar to the last non-redundant value)
                table.insert(redundant_indices, i)
            else
                -- This CC is not redundant, so update the reference value
                last_event_value = val
            end
        end
        -- CCs in other lanes are ignored for the redundancy calculation
    end

    -- If no redundant CCs found, return early without doing anything
    if #redundant_indices == 0 then return end

    -- Delete redundant CCs in reverse order to avoid index shifting issues
    local changes = 0
    for i = #redundant_indices, 1, -1 do
        reaper.MIDI_DeleteCC(current_take, redundant_indices[i])
        changes = changes + 1
    end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    -- Update the item and register the change in undo system
    reaper.UpdateItemInProject(item)
    reaper.Undo_OnStateChange_Item(0, "Remove " .. changes .. " redundant CC events", item)
    reaper.MIDI_Sort(current_take) -- Ensure MIDI events are properly sorted after modifications
    calculate_redundant_ccs() -- Recalculate after removal
    cc_redundancy_threshold = 0 -- Reset threshold to 0
    -- Invalidate all caches since CC events were removed
    selected_ccs_cache_valid = false
    -- Clear the smoothing cache as well since CC indices may have changed
    if #cc_list_cache > 0 then
        cc_list_cache = {}
    end
end

function select_all_ccs_in_lane()
    local current_take, midi_editor, lane = get_midi_context()

    if not current_take or lane < 0 or lane > 127 then return end

    local changes = 0
    local _, _, cc_count, _ = reaper.MIDI_CountEvts(current_take, 0, 0, 0)
    for i = 0, cc_count - 1 do
        local _, selected, muted, ppqpos, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(current_take, i)
        if msg2 == lane and not selected then
            reaper.MIDI_SetCC(current_take, i, true, muted, ppqpos, chanmsg, chan, msg2, msg3, false)
            changes = changes + 1
        end
    end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    -- Update the item and register the change in undo system
    reaper.UpdateItemInProject(item)
    reaper.Undo_OnStateChange_Item(0, "Select all CCs in lane", item)
    reaper.MIDI_Sort(current_take) -- Ensure MIDI events are properly sorted after modifications
    -- Invalidate all caches since selection changed
    selected_ccs_cache_valid = false
    -- Clear the smoothing cache as well since selected CCs have changed
    if #cc_list_cache > 0 then
        cc_list_cache = {}
    end
    -- Reset the selection signature to force recalculation of selected count in the next GUI update
    last_selected_ccs_signature = ""
    -- Update the MIDI arrangement to ensure changes are reflected immediately
    reaper.UpdateArrange()
    -- Immediately update the selected count for the GUI to show correct value
    local current_take, _, lane = get_midi_context()
    if current_take and lane >= 0 and lane <= 127 then
        selected_in_lane_count = 0
        local i = -1
        while true do
            i = reaper.MIDI_EnumSelCC(current_take, i)
            if i == -1 then break end
            local _, _, _, _, _, _, cc, _ = reaper.MIDI_GetCC(current_take, i, false, false, 0, 0, 0, 0, 0)
            if cc == lane then
                selected_in_lane_count = selected_in_lane_count + 1
            end
        end
        selected_ccs_cache_valid = true
    end
end


-- Logic from "Smooth CCs"
function build_cc_cache()
    local current_take, midi_editor, lane = get_midi_context()

    if not current_take then return {} end
    if lane < 0 or lane > 127 then return {} end

    local list = {}
    local i = -1
    while true do
        i = reaper.MIDI_EnumSelCC(current_take, i)
        if i == -1 then break end

        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(current_take, i, false, false, 0, 0, 0, 0, 0)
        if cc == lane then
            table.insert(list, {idx = i, val = val})
        end
    end
    return list
end

function smooth_ccs()
    if not take or #cc_list_cache < 3 then return end

    local c = smooth_amount / 100

    for i = 2, #cc_list_cache - 1 do
        local prev_val = cc_list_cache[i-1].val
        local curr_val = cc_list_cache[i].val
        local next_val = cc_list_cache[i+1].val

        local avg = (prev_val + curr_val + next_val) / 3
        local new_val = curr_val - c * (curr_val - avg)
        new_val = math.floor(math.max(0, math.min(127, new_val + 0.5)))

        local cc_event = cc_list_cache[i]
        reaper.MIDI_SetCC(take, cc_event.idx, true, false, nil, nil, nil, nil, new_val, false)
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
        selected_ccs_cache_valid = false
        if #cc_list_cache > 0 then
            cc_list_cache = {}
        end
        last_selected_ccs_signature = ""  -- Reset selection signature after undo
        -- Recalculate redundant CCs to update display after undo
        calculate_redundant_ccs()
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)  -- Using project-specific function as it's more reliable
        -- Invalidate all caches since redo may change CCs or selection
        selected_ccs_cache_valid = false
        if #cc_list_cache > 0 then
            cc_list_cache = {}
        end
        last_selected_ccs_signature = ""  -- Reset selection signature after redo
        -- Recalculate redundant CCs to update display after redo
        calculate_redundant_ccs()
    end
    
    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
    end

    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse
    local visible, open = imgui.Begin(ctx, script_name, true, flags)
    
    if not open then
        script_running = false
    end
    
    if visible and script_running then
        local current_take, midi_editor, current_lane = get_midi_context()

        if not midi_editor then
            -- Clear cache when no MIDI editor is active
            if #cc_list_cache > 0 then
                cc_list_cache = {}
            end
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Clear cache if take or lane changes
            if take ~= current_take or last_clicked_cc_lane ~= current_lane then
                if #cc_list_cache > 0 then
                    cc_list_cache = {}
                end
                -- Also invalidate the selected CCs count cache
                selected_ccs_cache_valid = false
                last_selected_ccs_signature = "" -- Reset signature when context changes
            end

            if not current_take then
                -- Clear cache if no take is available
                if #cc_list_cache > 0 then
                    cc_list_cache = {}
                end
                -- Reset all statistics when no take is available
                selected_ccs_cache_valid = false
                redundant_event_count = 0
                total_event_count = 0
                selected_in_lane_count = 0
                last_selected_ccs_signature = ""
                take = nil
                last_clicked_cc_lane = -1
                lane_name = ""
                imgui.Text(ctx, "Could not get MIDI take.")
            else
                -- Shared Info
                if last_clicked_cc_lane ~= current_lane or lane_name == "" then
                    calculate_redundant_ccs()
                end

                if last_clicked_cc_lane < 0 or last_clicked_cc_lane > 127 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, "Please select a CC lane")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, lane_name)
                end
            end -- end of current_take check

            if current_take and current_lane >= 0 and current_lane <= 127 then
                if imgui.Button(ctx, "Update") then
                    calculate_redundant_ccs()
                    -- Invalidate caches to match the behavior of other UI actions
                    selected_ccs_cache_valid = false
                    if #cc_list_cache > 0 then
                        cc_list_cache = {}
                    end
                end
            end
            imgui.Separator(ctx)

            -- Count selected CCs for the current lane (with caching to avoid repeated calculation)
            if current_take and current_lane >= 0 and current_lane <= 127 then
                -- Check if selection has changed and invalidate cache if needed
                local current_selection_signature = compute_selected_ccs_signature()
                if current_selection_signature ~= last_selected_ccs_signature then
                    selected_ccs_cache_valid = false
                    last_selected_ccs_signature = current_selection_signature
                end

                -- Recalculate if cache is invalid or MIDI context changed
                if not selected_ccs_cache_valid or take ~= current_take or last_clicked_cc_lane ~= current_lane then
                    selected_in_lane_count = 0
                    local i = -1
                    while true do
                        i = reaper.MIDI_EnumSelCC(current_take, i)
                        if i == -1 then break end
                        local _, _, _, _, _, _, cc, _ = reaper.MIDI_GetCC(current_take, i, false, false, 0, 0, 0, 0, 0)
                        if cc == current_lane then
                            selected_in_lane_count = selected_in_lane_count + 1
                        end
                    end
                    selected_ccs_cache_valid = true
                end
            else
                -- Reset count if no valid context
                selected_in_lane_count = 0
                selected_ccs_cache_valid = false
                last_selected_ccs_signature = ""
            end

            -- Smooth Section
            imgui.Text(ctx, "Smooth Selected CCs")
            if selected_in_lane_count < 3 then
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                imgui.Text(ctx, "Select at least 3 CC events to use smoother.")
                reaper.ImGui_PopStyleColor(ctx)
                if imgui.Button(ctx, "Select all events in lane") then
                    select_all_ccs_in_lane()
                end
            end
            local _, new_smooth_amount = imgui.SliderInt(ctx, "Amount", smooth_amount, 0, 100, "%d%%")
            smooth_amount = new_smooth_amount

            -- Handle smoothing logic
            if imgui.IsItemActivated(ctx) then
                reaper.Undo_BeginBlock2(0)
                cc_list_cache = build_cc_cache()  -- Cache once
            end

            if imgui.IsItemDeactivatedAfterEdit(ctx) then
                smooth_ccs()  -- Apply once with final smooth_amount
                if take then
                    -- Get the media item associated with the take
                    local item = reaper.GetMediaItemTake_Item(take)
                    reaper.MIDI_Sort(take) -- Ensure MIDI events are properly sorted after modifications
                    -- Update the item and register the change in undo system
                    reaper.UpdateItemInProject(item)
                    reaper.Undo_OnStateChange_Item(0, "Smooth CC events", item)
                end
                cc_list_cache = {}
                -- Also invalidate selected CCs cache since values have changed
                selected_ccs_cache_valid = false
                calculate_redundant_ccs() -- Recalculate redundant count after smoothing ends
            end

            -- Clear the cache when the slider is not active to prevent memory buildup
            -- But only when not actively dragging (to preserve the cache during dragging)
            if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #cc_list_cache > 0 then
                cc_list_cache = {}
            end

            imgui.Separator(ctx)

            -- Remove Redundant Section
            imgui.Text(ctx, "Remove Redundant CCs")
            imgui.Text(ctx, "Total Events: " .. total_event_count)
            imgui.Text(ctx, "Redundant Events: " .. redundant_event_count)
            local _, new_threshold = imgui.SliderInt(ctx, "Threshold", cc_redundancy_threshold, 0, 10)

            -- Handle threshold slider interaction for real-time feedback
            local threshold_value_changed = new_threshold ~= cc_redundancy_threshold
            local is_threshold_activated = imgui.IsItemActivated(ctx)  -- When user starts dragging
            local is_threshold_active = imgui.IsItemActive(ctx)        -- While user is dragging
            local is_threshold_deactivated = imgui.IsItemDeactivatedAfterEdit(ctx)  -- When user releases

            if is_threshold_activated then
                -- Store the original threshold value when starting to drag
                drag_start_threshold = cc_redundancy_threshold
                threshold_drag_active = true
            end

            if threshold_value_changed then
                cc_redundancy_threshold = new_threshold
                calculate_redundant_ccs() -- Recalculate counts when threshold changes
            end

            -- Apply threshold changes in real-time while dragging for visual feedback
            if is_threshold_active and threshold_drag_active and threshold_value_changed then
                -- Update the display counts in real-time without actually applying deletions during dragging
                calculate_redundant_ccs() -- Update the display counts based on current threshold
            end

            -- Handle when slider is released after dragging
            if is_threshold_deactivated then
                -- Just update internal state, don't apply changes automatically
                if threshold_drag_active then
                    threshold_drag_active = false
                end
            end

            if imgui.Button(ctx, "Remove") then
                remove_redundant_ccs()
            end
        end
    end
    
    imgui.Spacing(ctx)
    imgui.End(ctx)

    -- Clean up caches when the script is terminated to prevent memory leaks
    if not script_running then
        -- Clear all caches to ensure clean state on next run
        if #cc_list_cache > 0 then
            cc_list_cache = {}
        end
        selected_ccs_cache_valid = false
        redundant_event_count = 0
        total_event_count = 0
        selected_in_lane_count = 0
        last_selected_ccs_signature = ""
        take = nil
        last_clicked_cc_lane = -1
        lane_name = ""
    end

    if script_running then
        reaper.defer(loop)
    end
end
-- Init
reaper.defer(loop)