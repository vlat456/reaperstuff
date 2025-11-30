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
local take = nil
local last_clicked_cc_lane = -1
local lane_name = ""
local redundant_event_count = 0
local total_event_count = 0
local smooth_amount = 0 -- 0-100%
local last_smooth_amount = 0
local cc_list_cache = {}
local is_smoothing = false

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
            if val == last_event_value then
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
            if val == last_event_value then
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
    if smooth_amount == 0 then return end
    
    local c = smooth_amount / 100
    local changes = 0

    for i = 2, #cc_list_cache - 1 do
        local prev_val = cc_list_cache[i-1].val
        local curr_val = cc_list_cache[i].val
        local next_val = cc_list_cache[i+1].val

        local avg = (prev_val + curr_val + next_val) / 3
        local new_val = curr_val - c * (curr_val - avg)
        new_val = math.floor(math.max(0, math.min(127, new_val + 0.5)))
        
        local cc_event = cc_list_cache[i]
        reaper.MIDI_SetCC(take, cc_event.idx, true, false, nil, nil, nil, nil, new_val, false)
        changes = changes + 1
    end
    if changes > 0 then
      reaper.UpdateArrange()
    end
end

-- GUI
function loop()
    imgui.SetNextWindowSize(ctx, 300, 220, imgui.Cond_Once)
    local visible, open = imgui.Begin(ctx, script_name, true)
    if not visible then 
        imgui.End(ctx)
        return 
    end

    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then
        imgui.Text(ctx, "Please open a MIDI editor.")
    else
        -- Shared Info
        local current_lane = reaper.MIDIEditor_GetSetting_int(reaper.MIDIEditor_GetActive(), "last_clicked_cc_lane")
        if last_clicked_cc_lane ~= current_lane or lane_name == "" then
            calculate_redundant_ccs()
        end
        
        imgui.Text(ctx, lane_name or "Select a CC lane")
        if imgui.Button(ctx, "Update") then
            calculate_redundant_ccs()
        end
        imgui.Separator(ctx)

        -- Remove Redundant Section
        imgui.Text(ctx, "Remove Redundant CCs")
        imgui.Text(ctx, "Total Events: " .. total_event_count)
        imgui.Text(ctx, "Redundant Events: " .. redundant_event_count)
        if imgui.Button(ctx, "Remove") then
            remove_redundant_ccs()
        end

        imgui.Separator(ctx)

        -- Smooth Section
        imgui.Text(ctx, "Smooth Selected CCs")
        local _, new_smooth_amount = imgui.SliderInt(ctx, "Amount", smooth_amount, 0, 100, "%d%%")
        smooth_amount = new_smooth_amount

        -- Handle smoothing logic
        if smooth_amount ~= last_smooth_amount then
            if not is_smoothing then
                reaper.Undo_BeginBlock()
                cc_list_cache = build_cc_cache()
                is_smoothing = true
            end
            smooth_ccs()
        elseif is_smoothing then
            reaper.Undo_EndBlock("Smooth CC events", -1)
            is_smoothing = false
            cc_list_cache = {}
        end
        last_smooth_amount = smooth_amount
    end
    
    imgui.End(ctx)
    if open then
        reaper.defer(loop)
    end
end


-- Init
reaper.defer(loop)