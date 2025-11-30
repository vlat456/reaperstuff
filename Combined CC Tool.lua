--[[
# Description
A script to remove redundant CC events and smooth selected CC events in the MIDI editor.
This script combines the functionality of the EEL scripts "Remove redundant CCs" and "Smooth CCs".

# Instructions
1.  Open the MIDI editor in REAPER.
2.  Select a CC lane by clicking on it.
3.  Run this script.
4.  Use the GUI to remove redundant CCs or smooth the selected CCs.

# Requirements
*   REAPER v5.95+
*   ReaImGui: v0.4+ (Available via ReaPack -> ReaTeam Extensions)
--]]

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

-- Helper function to get the active MIDI take
function get_active_take()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil end
    return reaper.MIDIEditor_GetTake(midi_editor)
end

-- Logic from "Remove redundant CCs"
function calculate_redundant_ccs()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then
        lane_name = "Please open a MIDI editor."
        total_event_count = 0
        redundant_event_count = 0
        take = nil
        return
    end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then
        lane_name = "Could not get MIDI take."
        total_event_count = 0
        redundant_event_count = 0
        take = nil
        return
    end

    take = current_take
    
    local lane = reaper.MIDIEditor_GetSetting_int(midi_editor, "last_clicked_cc_lane")
    if lane < 0 or lane > 127 then
        redundant_event_count = 0
        total_event_count = 0
        lane_name = "Select a CC lane"
        return
    end

    last_clicked_cc_lane = lane
    local _, name = reaper.MIDIEditor_GetSetting_str(midi_editor, "last_clicked_cc_lane", "")
    lane_name = "CC" .. lane .. " " .. name

    local _, _, cc_count, _ = reaper.MIDI_CountEvts(take, 0, 0, 0)

    local last_event_value = -1
    redundant_event_count = 0
    total_event_count = 0

    for i = 0, cc_count - 1 do
        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(take, i, false, false, 0, 0, 0, 0, 0)
        if cc == last_clicked_cc_lane then
            total_event_count = total_event_count + 1
            if math.abs(val - last_event_value) <= cc_redundancy_threshold then -- MODIFIED
                redundant_event_count = redundant_event_count + 1
            end
            last_event_value = val
        end
    end
end

function remove_redundant_ccs()
    if not take or redundant_event_count == 0 then return end

    local lane = reaper.MIDIEditor_GetSetting_int(reaper.MIDIEditor_GetActive(), "last_clicked_cc_lane")
    if lane < 0 or lane > 127 then return end

    reaper.Undo_BeginBlock()

    local last_event_value = -1
    local changes = 0
    local i = 0
    while true do
        local _, _, cc_count, _ = reaper.MIDI_CountEvts(take, 0, 0, 0)
        if i >= cc_count then break end

        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(take, i, false, false, 0, 0, 0, 0, 0)

        if cc == lane then
            if math.abs(val - last_event_value) <= cc_redundancy_threshold then -- MODIFIED
                reaper.MIDI_DeleteCC(take, i)
                changes = changes + 1
                -- The index stays the same because the next event shifts down
                i = i - 1
            else
                last_event_value = val
            end
        end
        i = i + 1
    end
    reaper.Undo_EndBlock("Remove " .. changes .. " redundant CC events", -1)
    calculate_redundant_ccs() -- Recalculate after removal
    cc_redundancy_threshold = 0 -- Reset threshold to 0
end

function select_all_ccs_in_lane()
    if not take or last_clicked_cc_lane < 0 or last_clicked_cc_lane > 127 then return end

    reaper.Undo_BeginBlock()
    local changes = 0
    local _, _, cc_count, _ = reaper.MIDI_CountEvts(take, 0, 0, 0)
    for i = 0, cc_count - 1 do
        local _, selected, muted, ppqpos, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, i)
        if msg2 == last_clicked_cc_lane and not selected then
            reaper.MIDI_SetCC(take, i, true, muted, ppqpos, chanmsg, chan, msg2, msg3, false)
            changes = changes + 1
        end
    end
    reaper.Undo_EndBlock("Select all CCs in lane", -1)
end


-- Logic from "Smooth CCs"
function build_cc_cache()
    if not take then return {} end
    local lane = reaper.MIDIEditor_GetSetting_int(reaper.MIDIEditor_GetActive(), "last_clicked_cc_lane")
    if lane < 0 or lane > 127 then return {} end

    local list = {}
    local i = -1
    while true do
        i = reaper.MIDI_EnumSelCC(take, i)
        if i == -1 then break end
        
        local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(take, i, false, false, 0, 0, 0, 0, 0)
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
        reaper.Undo_DoUndo2(0)
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
    end
    
    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
    end

    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse
    local visible, open = imgui.Begin(ctx, script_name, true, flags)
    
    if not open then script_running = false end
    
    if visible and script_running then
        local midi_editor = reaper.MIDIEditor_GetActive()
        if not midi_editor then
            -- Clear cache when no MIDI editor is active
            if #cc_list_cache > 0 then
                cc_list_cache = {}
            end
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            local current_take = reaper.MIDIEditor_GetTake(midi_editor)
            local current_lane = reaper.MIDIEditor_GetSetting_int(midi_editor, "last_clicked_cc_lane")

            -- Clear cache if take or lane changes
            if take ~= current_take or last_clicked_cc_lane ~= current_lane then
                if #cc_list_cache > 0 then
                    cc_list_cache = {}
                end
            end

            if not current_take then
                -- Clear cache if no take is available
                if #cc_list_cache > 0 then
                    cc_list_cache = {}
                end
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

            if current_take and last_clicked_cc_lane >= 0 and last_clicked_cc_lane <= 127 then
                if imgui.Button(ctx, "Update") then
                    calculate_redundant_ccs()
                end
            end
            imgui.Separator(ctx)

            -- Count selected CCs for the current lane
            local selected_in_lane_count = 0
            if take and last_clicked_cc_lane >= 0 and last_clicked_cc_lane <= 127 then
                local i = -1
                while true do
                    i = reaper.MIDI_EnumSelCC(take, i)
                    if i == -1 then break end
                    local _, _, _, _, _, _, cc, _ = reaper.MIDI_GetCC(take, i, false, false, 0, 0, 0, 0, 0)
                    if cc == last_clicked_cc_lane then
                        selected_in_lane_count = selected_in_lane_count + 1
                    end
                end
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
                reaper.Undo_BeginBlock()
                cc_list_cache = build_cc_cache()
            end

            if imgui.IsItemActive(ctx) and #cc_list_cache > 0 then
                smooth_ccs()
                calculate_redundant_ccs() -- Recalculate redundant count after smoothing
            end

            -- Clear the cache when the slider is not active to prevent memory buildup
            -- But only when not actively dragging (to preserve the cache during dragging)
            if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #cc_list_cache > 0 then
                cc_list_cache = {}
            end

            if imgui.IsItemDeactivatedAfterEdit(ctx) then
                if #cc_list_cache > 0 then
                    reaper.Undo_EndBlock("Smooth CC events", -1)
                else
                    reaper.Undo_EndBlock("", -1)
                end
                -- Cache is already cleared by the condition above, so no need to clear again
                calculate_redundant_ccs() -- Recalculate redundant count after smoothing ends
            end

            imgui.Separator(ctx)

            -- Remove Redundant Section
            imgui.Text(ctx, "Remove Redundant CCs")
            imgui.Text(ctx, "Total Events: " .. total_event_count)
            imgui.Text(ctx, "Redundant Events: " .. redundant_event_count)
            local _, new_threshold = imgui.SliderInt(ctx, "Threshold", cc_redundancy_threshold, 0, 10)
            if new_threshold ~= cc_redundancy_threshold then
                cc_redundancy_threshold = new_threshold
                calculate_redundant_ccs() -- Recalculate counts when threshold changes
            end
            if imgui.Button(ctx, "Remove") then
                remove_redundant_ccs()
            end
        end
    end
    
    imgui.Spacing(ctx)
    imgui.End(ctx)
    
    if script_running then
        reaper.defer(loop)
    end
end
-- Init
reaper.defer(loop)