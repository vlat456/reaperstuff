-- @description Media Offset Tool
-- @author drvlat
-- @version 1.1.3
-- @about
--   An ImGui-based utility for adjusting media offsets in REAPER.
--   Supports three target modes selected via radio buttons:
--     1) Take Start Offset
--     2) Track Playback Offset
--     3) Move Item Position
--   If MIDI notes are selected, overrides normal modes to adjust note timing directly.
--   Works inside the MIDI Editor for the current MIDI item, or falls back to selected items/tracks in the Arrange view.
--   Features an absolute slider fixed at ±500ms, fine-tuning buttons, absolute offset reset, and clean status labels.
-- @provides
--   [main=main,midi_editor,midi_inlineeditor,midi_eventlisteditor] Media_Offset_Tool.lua

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
local script_name = "Media Offset Tool v1.1.3"
local ctx = reaper.ImGui_CreateContext(script_name)
local script_running = true

-- Fixed range ±500 ms
local FIXED_RANGE = 500.0

-- Target adjustment modes
local MODE_TAKE_OFFSET = 0    -- Mode A: Media Take Source Start Offset
local MODE_TRACK_OFFSET = 1   -- Mode B: Track Playback Offset
local MODE_ITEM_POSITION = 2  -- Mode C: Move Item Timeline Position
local MODE_MIDI_NOTES = 3     -- Override Mode: Shift Selected MIDI Notes

local gui_state -- Forward declaration for helper functions

-- Helper to check if notes are selected in the active MIDI editor take
local function has_selected_midi_notes()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if midi_editor then
        local take = reaper.MIDIEditor_GetTake(midi_editor)
        if take then
            local note_index = reaper.MIDI_EnumSelNotes(take, -1)
            if note_index ~= -1 then
                return true, take
            end
        end
    end
    return false, nil
end

-- Generate signature for selected MIDI notes to detect selection change
local function get_midi_notes_signature(take)
    local sig = {"midi_notes:" .. tostring(take)}
    local note_idx = -1
    local safety = 0
    while safety < 10000 do
        note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
        if note_idx == -1 then break end
        table.insert(sig, tostring(note_idx))
        safety = safety + 1
    end
    return table.concat(sig, ";")
end

-- Get the current effective adjustment mode (dynamic override if MIDI notes are selected)
local function get_effective_mode()
    local has_notes, take = has_selected_midi_notes()
    if has_notes then
        return MODE_MIDI_NOTES, take
    else
        return gui_state.adjust_mode, nil
    end
end

-- Unified GUI State
gui_state = {
    selected_targets = {},
    slider_value = 0.0,
    adjust_mode = MODE_TRACK_OFFSET, -- Default to Mode B (Track Playback Offset)
    last_selection_state = "",
}

-- Load persisted mode from project metadata
local _, saved_mode_str = reaper.GetProjExtState(0, "Walter_MediaOffsetTool", "selected_mode")
if saved_mode_str and saved_mode_str ~= "" then
    local saved_mode = tonumber(saved_mode_str)
    if saved_mode == MODE_TAKE_OFFSET or saved_mode == MODE_TRACK_OFFSET or saved_mode == MODE_ITEM_POSITION then
        gui_state.adjust_mode = saved_mode
    end
end

-- Check selection signature to detect change
local function get_selection_signature()
    local eff_mode, take = get_effective_mode()
    local sig = {}
    table.insert(sig, "mode:" .. tostring(eff_mode))
    
    if eff_mode == MODE_MIDI_NOTES then
        table.insert(sig, get_midi_notes_signature(take))
    elseif eff_mode == MODE_TRACK_OFFSET then
        -- Mode B (Track Playback Offset)
        local num_tracks = reaper.CountSelectedTracks(0)
        if num_tracks > 0 then
            if num_tracks > 1000 then num_tracks = 1000 end -- Safety limit
            for i = 0, num_tracks - 1 do
                local track = reaper.GetSelectedTrack(0, i)
                if track then
                    table.insert(sig, tostring(track))
                end
            end
        else
            -- Fallback to active MIDI editor track
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    local item = reaper.GetMediaItemTake_Item(take)
                    if item then
                        local track = reaper.GetMediaItem_Track(item)
                        if track then
                            table.insert(sig, "editor:" .. tostring(track))
                        end
                    end
                end
            end
        end
    else
        -- Mode A (Take Source Offset) & Mode C (Move Item Position)
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 0 then
            if num_items > 10000 then num_items = 10000 end -- Safety limit
            for i = 0, num_items - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                if item then
                    if gui_state.adjust_mode == MODE_TAKE_OFFSET then
                        local take = reaper.GetActiveTake(item)
                        if take then
                            table.insert(sig, tostring(take))
                        end
                    else
                        table.insert(sig, tostring(item))
                    end
                end
            end
        else
            -- Fallback to active MIDI editor take / item
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    if gui_state.adjust_mode == MODE_TAKE_OFFSET then
                        table.insert(sig, "editor:" .. tostring(take))
                    else
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            table.insert(sig, "editor:" .. tostring(item))
                        end
                    end
                end
            end
        end
    end
    
    return table.concat(sig, ";")
end

-- Helper to parse note offsets metadata from a take
local function get_take_note_offsets(take)
    if not take or not reaper.TakeIsMIDI(take) then return {} end
    local retval, val = reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:Walter_MIDI_Note_Offsets", "", false)
    local offsets = {}
    if retval and val ~= "" then
        for entry in val:gmatch("[^;]+") do
            local key, offset_str = entry:match("^([^:]+):([^:]+)$")
            if key and offset_str then
                offsets[key] = tonumber(offset_str) or 0.0
            end
        end
    end
    return offsets
end

-- Helper to save note offsets metadata to a take
local function save_take_note_offsets(take, offsets)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local entries = {}
    for key, val in pairs(offsets) do
        if math.abs(val) > 0.001 then
            table.insert(entries, key .. ":" .. tostring(val))
        end
    end
    local val_str = table.concat(entries, ";")
    reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:Walter_MIDI_Note_Offsets", val_str, true)
end

-- Helper to clean up note offsets metadata from a take
local function cleanup_take_note_offsets(take)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local _, _, _, notes_count = reaper.MIDI_CountEvts(take)
    local offsets = get_take_note_offsets(take)
    
    -- Build a quick lookup map of existing notes by pitch_chan:ppq
    local existing_notes = {}
    for idx = 0, notes_count - 1 do
        local retval, _, _, startppq, _, chan, pitch = reaper.MIDI_GetNote(take, idx)
        if retval then
            local lookup_key = string.format("%d_%d", pitch, chan)
            if not existing_notes[lookup_key] then
                existing_notes[lookup_key] = {}
            end
            table.insert(existing_notes[lookup_key], startppq)
        end
    end
    
    local cleaned_offsets = {}
    local changed = false
    
    for key, offset_ms in pairs(offsets) do
        local o_pitch, o_chan, o_orig_ppq = key:match("^(%d+)_(%d+)_(%d+)$")
        if o_pitch and o_chan and o_orig_ppq then
            o_pitch = tonumber(o_pitch)
            o_chan = tonumber(o_chan)
            o_orig_ppq = tonumber(o_orig_ppq)
            
            local orig_time = reaper.MIDI_GetProjTimeFromPPQPos(take, o_orig_ppq)
            local current_time_expected = orig_time + (offset_ms / 1000.0)
            local expected_current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, current_time_expected)
            
            local lookup_key = string.format("%d_%d", o_pitch, o_chan)
            local found = false
            local ppqs = existing_notes[lookup_key]
            if ppqs then
                for _, startppq in ipairs(ppqs) do
                    if math.abs(startppq - expected_current_ppq) < 5 then
                        found = true
                        break
                    end
                end
            end
            
            if found then
                cleaned_offsets[key] = offset_ms
            else
                changed = true
            end
        end
    end
    
    if changed then
        save_take_note_offsets(take, cleaned_offsets)
    end
end

-- Populate selection info
local function update_targets_list(force)
    -- Skip rebuilding selection while the user is actively interacting with the GUI,
    -- unless forced (e.g. on mode change).
    if not force and reaper.ImGui_IsAnyItemActive(ctx) then
        return
    end
    
    local current_sig = get_selection_signature()
    local selection_changed = current_sig ~= gui_state.last_selection_state
    
    if selection_changed then
        gui_state.last_selection_state = current_sig
        gui_state.selected_targets = {}
        
        local eff_mode, take = get_effective_mode()
        
        if eff_mode == MODE_MIDI_NOTES then
            -- Clean up stale offsets
            cleanup_take_note_offsets(take)
            
            -- Override: selected MIDI notes in active take
            local offsets = get_take_note_offsets(take)
            local note_idx = -1
            local safety = 0
            while safety < 10000 do
                note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                if note_idx == -1 then break end
                local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
                if retval then
                    -- Look up in offsets metadata
                    local found_offset = 0.0
                    local original_ppq = startppq
                    
                    for key, offset_ms in pairs(offsets) do
                        local o_pitch, o_chan, o_orig_ppq = key:match("^(%d+)_(%d+)_(%d+)$")
                        if o_pitch and o_chan and o_orig_ppq then
                            o_pitch = tonumber(o_pitch)
                            o_chan = tonumber(o_chan)
                            o_orig_ppq = tonumber(o_orig_ppq)
                            
                            if o_pitch == pitch and o_chan == chan then
                                local orig_time = reaper.MIDI_GetProjTimeFromPPQPos(take, o_orig_ppq)
                                local current_time_expected = orig_time + (offset_ms / 1000.0)
                                local expected_current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, current_time_expected)
                                
                                if math.abs(startppq - expected_current_ppq) < 5 then
                                    found_offset = offset_ms
                                    original_ppq = o_orig_ppq
                                    break
                                end
                            end
                        end
                    end
                    
                    -- Original unshifted positions
                    local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, original_ppq)
                    local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, original_ppq + (endppq - startppq))
                    
                    table.insert(gui_state.selected_targets, {
                        take = take,
                        note_index = note_idx,
                        original_ppq = original_ppq,
                        offset_ms = found_offset,
                        start_time = start_time,
                        end_time = end_time,
                        pitch = pitch,
                        chan = chan,
                        vel = vel,
                        muted = muted
                    })
                end
                safety = safety + 1
            end
            
            -- Initialize slider_value
            if #gui_state.selected_targets > 0 then
                local first_offset = gui_state.selected_targets[1].offset_ms
                local all_same = true
                for i = 2, #gui_state.selected_targets do
                    if math.abs(gui_state.selected_targets[i].offset_ms - first_offset) > 0.01 then
                        all_same = false
                        break
                    end
                end
                if all_same then
                    gui_state.slider_value = first_offset
                else
                    gui_state.slider_value = 0.0
                end
            else
                gui_state.slider_value = 0.0
            end
            
        elseif eff_mode == MODE_TRACK_OFFSET then
            -- Mode B: Track Playback Offset
            local num_tracks = reaper.CountSelectedTracks(0)
            if num_tracks > 0 then
                if num_tracks > 1000 then num_tracks = 1000 end
                for i = 0, num_tracks - 1 do
                    local track = reaper.GetSelectedTrack(0, i)
                    if track then
                        local _, name = reaper.GetTrackName(track)
                        name = name or "Unnamed Track"
                        local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                        table.insert(gui_state.selected_targets, {
                            track = track,
                            name = name,
                            baseline_offset = cur_offset
                        })
                    end
                end
            else
                -- Fallback to active MIDI editor track
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local track = reaper.GetMediaItem_Track(item)
                            if track then
                                local _, name = reaper.GetTrackName(track)
                                name = name or "Unnamed Track"
                                local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                                table.insert(gui_state.selected_targets, {
                                    track = track,
                                    name = name .. " (MIDI Editor)",
                                    baseline_offset = cur_offset
                                })
                            end
                        end
                    end
                end
            end
            
            if #gui_state.selected_targets > 0 then
                gui_state.slider_value = gui_state.selected_targets[1].baseline_offset * 1000.0
            else
                gui_state.slider_value = 0.0
            end
            
        elseif eff_mode == MODE_TAKE_OFFSET then
            -- Mode A: Media Take Source Start Offset
            local num_items = reaper.CountSelectedMediaItems(0)
            if num_items > 0 then
                if num_items > 10000 then num_items = 10000 end
                for i = 0, num_items - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if item then
                        local take = reaper.GetActiveTake(item)
                        if take then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name,
                                baseline_offset = cur_offset
                            })
                        end
                    end
                end
            else
                -- Fallback to active MIDI editor take
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name .. " (MIDI Editor)",
                                baseline_offset = cur_offset
                            })
                        end
                    end
                end
            end
            
            if #gui_state.selected_targets > 0 then
                gui_state.slider_value = gui_state.selected_targets[1].baseline_offset * 1000.0
            else
                gui_state.slider_value = 0.0
            end
            
        elseif eff_mode == MODE_ITEM_POSITION then
            -- Mode C: Move Item Timeline Position
            local num_items = reaper.CountSelectedMediaItems(0)
            if num_items > 0 then
                if num_items > 10000 then num_items = 10000 end
                for i = 0, num_items - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if item then
                        local take = reaper.GetActiveTake(item)
                        local name = take and reaper.GetTakeName(take) or "Empty Item"
                        local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        
                        -- Read saved offset from item metadata
                        local retval, saved_val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                        local saved_offset_sec = 0.0
                        if retval and saved_val ~= "" then
                            saved_offset_sec = (tonumber(saved_val) or 0.0) / 1000.0
                        end
                        
                        -- The original zero position is current position minus saved offset
                        local zero_pos = cur_pos - saved_offset_sec
                        
                        table.insert(gui_state.selected_targets, {
                            item = item,
                            name = name,
                            zero_position = zero_pos,
                            baseline_offset = cur_pos
                        })
                    end
                end
            else
                -- Fallback to active MIDI editor item
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            
                            -- Read saved offset from item metadata
                            local retval, saved_val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                            local saved_offset_sec = 0.0
                            if retval and saved_val ~= "" then
                                saved_offset_sec = (tonumber(saved_val) or 0.0) / 1000.0
                            end
                            
                            local zero_pos = cur_pos - saved_offset_sec
                            
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                name = name .. " (MIDI Editor)",
                                zero_position = zero_pos,
                                baseline_offset = cur_pos
                            })
                        end
                    end
                end
            end
            
            -- Initialize slider value with the saved offset of the first item
            if #gui_state.selected_targets > 0 then
                local first_item = gui_state.selected_targets[1].item
                local retval, saved_val = reaper.GetSetMediaItemInfo_String(first_item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                if retval and saved_val ~= "" then
                    gui_state.slider_value = tonumber(saved_val) or 0.0
                else
                    gui_state.slider_value = 0.0
                end
            else
                gui_state.slider_value = 0.0
            end
        end
    else
        -- Sync baselines and values if NOT dragging
        local is_slider_active = reaper.ImGui_IsAnyItemActive(ctx)
        if not is_slider_active and #gui_state.selected_targets > 0 then
            local eff_mode, take = get_effective_mode()
            if eff_mode == MODE_MIDI_NOTES then
                local offsets = get_take_note_offsets(take)
                local any_drifted = false
                local note_idx = -1
                
                for _, info in ipairs(gui_state.selected_targets) do
                    note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                    if note_idx == -1 then break end
                    local retval, selected, muted, startppq, endppq = reaper.MIDI_GetNote(info.take, note_idx)
                    if retval then
                        local orig_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, info.original_ppq)
                        local current_time_expected = orig_time + (info.offset_ms / 1000.0)
                        local expected_current_ppq = reaper.MIDI_GetPPQPosFromProjTime(info.take, current_time_expected)
                        
                        if math.abs(startppq - expected_current_ppq) >= 5 then
                            -- Note has drifted (manually moved). Clean up old metadata entry
                            local old_key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                            offsets[old_key] = nil
                            
                            -- Reset baseline to new position
                            info.original_ppq = startppq
                            info.offset_ms = 0.0
                            info.start_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, startppq)
                            info.end_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, endppq)
                            any_drifted = true
                        end
                    end
                end
                
                if any_drifted then
                    save_take_note_offsets(take, offsets)
                    
                    local first_offset = gui_state.selected_targets[1].offset_ms
                    local all_same = true
                    for i = 2, #gui_state.selected_targets do
                        if math.abs(gui_state.selected_targets[i].offset_ms - first_offset) > 0.01 then
                            all_same = false
                            break
                        end
                    end
                    if all_same then
                        gui_state.slider_value = first_offset
                    else
                        gui_state.slider_value = 0.0
                    end
                end
            elseif eff_mode == MODE_TRACK_OFFSET then
                local first_info = gui_state.selected_targets[1]
                if reaper.ValidatePtr(first_info.track, "MediaTrack*") then
                    local actual_offset = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
                    gui_state.slider_value = actual_offset * 1000.0
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.track, "MediaTrack*") then
                        info.baseline_offset = reaper.GetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET")
                    end
                end
            elseif eff_mode == MODE_TAKE_OFFSET then
                local first_info = gui_state.selected_targets[1]
                if reaper.ValidatePtr(first_info.take, "MediaItem_Take*") then
                    local actual_offset = reaper.GetMediaItemTakeInfo_Value(first_info.take, "D_STARTOFFS")
                    gui_state.slider_value = actual_offset * 1000.0
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                        info.baseline_offset = reaper.GetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS")
                    end
                end
            elseif eff_mode == MODE_ITEM_POSITION then
                local first_info = gui_state.selected_targets[1]
                if first_info and reaper.ValidatePtr(first_info.item, "MediaItem*") then
                    local cur_pos = reaper.GetMediaItemInfo_Value(first_info.item, "D_POSITION")
                    local retval, saved_val = reaper.GetSetMediaItemInfo_String(first_info.item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                    local saved_offset_ms = 0.0
                    if retval and saved_val ~= "" then
                        saved_offset_ms = tonumber(saved_val) or 0.0
                    end
                    gui_state.slider_value = saved_offset_ms
                    first_info.zero_position = cur_pos - (saved_offset_ms / 1000.0)
                end
                
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.item, "MediaItem*") then
                        local cur_pos = reaper.GetMediaItemInfo_Value(info.item, "D_POSITION")
                        info.baseline_offset = cur_pos
                        local retval, saved_val = reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                        local saved_offset_ms = 0.0
                        if retval and saved_val ~= "" then
                            saved_offset_ms = tonumber(saved_val) or 0.0
                        end
                        info.zero_position = cur_pos - (saved_offset_ms / 1000.0)
                    end
                end
            end
        end
    end
end

-- Apply current slider/adjustment value to all selected targets
local function apply_offset_to_targets(value)
    local eff_mode = get_effective_mode()
    if eff_mode == MODE_MIDI_NOTES then
        local shift_sec = value / 1000.0
        local first_target = gui_state.selected_targets[1]
        if first_target then
            local take = first_target.take
            local note_idx = -1
            for _, info in ipairs(gui_state.selected_targets) do
                note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                if note_idx == -1 then break end
                local new_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.start_time + shift_sec)
                local new_end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.end_time + shift_sec)
                reaper.MIDI_SetNote(
                    take,
                    note_idx,
                    nil,  -- selected
                    nil,  -- muted
                    new_start_ppq,
                    new_end_ppq,
                    nil,  -- chan
                    nil,  -- pitch
                    nil,  -- vel
                    true  -- noSort
                )
            end
            reaper.MIDI_Sort(take)
            local item = reaper.GetMediaItemTake_Item(take)
            if item then
                reaper.UpdateItemInProject(item)
            end
        end
    elseif eff_mode == MODE_TRACK_OFFSET then
        local target_sec = value / 1000.0
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(info.track, "I_PLAY_OFFSET_FLAG", 0)
                reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", target_sec)
            end
        end
    elseif eff_mode == MODE_TAKE_OFFSET then
        local target_sec = value / 1000.0
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", target_sec)
                reaper.UpdateItemInProject(info.item)
            end
        end
    elseif eff_mode == MODE_ITEM_POSITION then
        local shift_sec = value / 1000.0
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.item, "MediaItem*") then
                reaper.SetMediaItemInfo_Value(info.item, "D_POSITION", info.zero_position + shift_sec)
                reaper.UpdateItemInProject(info.item)
            end
        end
    end
    reaper.UpdateArrange()
end

-- Helper to set absolute offset value (with undo registration)
local function adjust_offset_to_value(target_ms)
    if #gui_state.selected_targets == 0 then return end
    
    local eff_mode = get_effective_mode()
    local undo_msg = ""
    if eff_mode == MODE_MIDI_NOTES then
        undo_msg = string.format("Shift %d MIDI notes by %.1f ms", #gui_state.selected_targets, target_ms)
    elseif eff_mode == MODE_TRACK_OFFSET then
        undo_msg = string.format("Set track media playback offset to %.1f ms", target_ms)
    elseif eff_mode == MODE_TAKE_OFFSET then
        undo_msg = string.format("Set take source start offset to %.1f ms", target_ms)
    elseif eff_mode == MODE_ITEM_POSITION then
        undo_msg = string.format("Move items timeline position by %.1f ms", target_ms)
    end
    
    reaper.Undo_BeginBlock2(0)
    apply_offset_to_targets(target_ms)
    reaper.Undo_EndBlock2(0, undo_msg, -1)
    
    if eff_mode == MODE_TRACK_OFFSET then
        reaper.TrackList_AdjustWindows(false)
    end
    
    if eff_mode == MODE_MIDI_NOTES then
        local first_target = gui_state.selected_targets[1]
        if first_target then
            local take = first_target.take
            local offsets = get_take_note_offsets(take)
            for _, info in ipairs(gui_state.selected_targets) do
                local key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                offsets[key] = target_ms
                info.offset_ms = target_ms
            end
            save_take_note_offsets(take, offsets)
        end
        gui_state.slider_value = target_ms
    elseif eff_mode == MODE_TRACK_OFFSET or eff_mode == MODE_TAKE_OFFSET then
        for _, info in ipairs(gui_state.selected_targets) do
            info.baseline_offset = target_ms / 1000.0
        end
        gui_state.slider_value = target_ms
    elseif eff_mode == MODE_ITEM_POSITION then
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.item, "MediaItem*") then
                reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_offset", tostring(target_ms), true)
                info.baseline_offset = info.zero_position + (target_ms / 1000.0)
            end
        end
        gui_state.slider_value = target_ms
    end
end

-- Helper to apply delta relative to current value
local function adjust_offset_by_delta(delta_ms)
    local target_ms = gui_state.slider_value + delta_ms
    adjust_offset_to_value(target_ms)
end

-- Helper to reset offsets to 0
local function reset_offsets_to_zero()
    adjust_offset_to_value(0.0)
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
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, 8.0, 6.0)
end

-- Pop Theme Styles & Colors
local function pop_theme()
    reaper.ImGui_PopStyleColor(ctx, 16)
    reaper.ImGui_PopStyleVar(ctx, 4)
end

-- Helper to get track and take from current context, independent of mode
local function get_current_context_track_and_take()
    local track, take
    
    -- 1. Check selected items in Arrange view
    local num_items = reaper.CountSelectedMediaItems(0)
    if num_items > 0 then
        local item = reaper.GetSelectedMediaItem(0, 0)
        if item then
            take = reaper.GetActiveTake(item)
            track = reaper.GetMediaItem_Track(item)
        end
    end
    
    -- 2. Fallback to active MIDI editor
    local midi_editor = reaper.MIDIEditor_GetActive()
    if midi_editor then
        local active_take = reaper.MIDIEditor_GetTake(midi_editor)
        if active_take then
            if not take then take = active_take end
            if not track then
                local item = reaper.GetMediaItemTake_Item(active_take)
                if item then
                    track = reaper.GetMediaItem_Track(item)
                end
            end
        end
    end
    
    -- 3. Fallback to first selected track if no track was found yet
    if not track then
        local num_tracks = reaper.CountSelectedTracks(0)
        if num_tracks > 0 then
            track = reaper.GetSelectedTrack(0, 0)
        end
    end
    
    return track, take
end

-- Render the main controls
local function render_ui()
    local num_targets = #gui_state.selected_targets
    
    if num_targets == 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.3, 0.3, 1.0))
        reaper.ImGui_Text(ctx, "No targets matching current selection mode.")
        reaper.ImGui_PopStyleColor(ctx)
        return
    end

    -- Target Mode Radio Buttons
    local has_notes, _ = has_selected_midi_notes()
    if has_notes then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.8, 0.5, 1.0))
        reaper.ImGui_Text(ctx, "Offsetting selected MIDI notes (modes disabled):")
        reaper.ImGui_PopStyleColor(ctx)
    else
        reaper.ImGui_Text(ctx, "Offset Mode:")
    end
    
    local mode_changed = false
    reaper.ImGui_BeginDisabled(ctx, has_notes)
    
    local rb_a = reaper.ImGui_RadioButton(ctx, "Take Start Offset", gui_state.adjust_mode == MODE_TAKE_OFFSET)
    if rb_a then
        gui_state.adjust_mode = MODE_TAKE_OFFSET
        mode_changed = true
    end
    
    reaper.ImGui_SameLine(ctx)
    local rb_b = reaper.ImGui_RadioButton(ctx, "Track Playback Offset", gui_state.adjust_mode == MODE_TRACK_OFFSET)
    if rb_b then
        gui_state.adjust_mode = MODE_TRACK_OFFSET
        mode_changed = true
    end
    
    reaper.ImGui_SameLine(ctx)
    local rb_c = reaper.ImGui_RadioButton(ctx, "Move Item Position", gui_state.adjust_mode == MODE_ITEM_POSITION)
    if rb_c then
        gui_state.adjust_mode = MODE_ITEM_POSITION
        mode_changed = true
    end
    
    reaper.ImGui_EndDisabled(ctx)
    
    if mode_changed then
        -- Persist the selected mode in project metadata
        reaper.SetProjExtState(0, "Walter_MediaOffsetTool", "selected_mode", tostring(gui_state.adjust_mode))
        
        gui_state.last_selection_state = ""
        update_targets_list(true)
        return
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Double-click / Drag slider for absolute offset (displaying current value)
    local slider_changed, new_slider_val = reaper.ImGui_SliderDouble(ctx, "Offset (ms)", gui_state.slider_value, -FIXED_RANGE, FIXED_RANGE, "%.1f ms")
    local is_slider_active = reaper.ImGui_IsItemActive(ctx)
    local is_slider_activated = reaper.ImGui_IsItemActivated(ctx)
    local is_slider_deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    if slider_changed then
        local eff_mode = get_effective_mode()
        gui_state.slider_value = new_slider_val
        apply_offset_to_targets(new_slider_val)
        if eff_mode == MODE_TRACK_OFFSET then
            reaper.TrackList_AdjustWindows(false)
        end
    end

    if is_slider_deactivated then
        local eff_mode, take = get_effective_mode()
        -- Restore baseline offsets temporarily
        if eff_mode == MODE_MIDI_NOTES then
            if take then
                local note_idx = -1
                for _, info in ipairs(gui_state.selected_targets) do
                    note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                    if note_idx == -1 then break end
                    local orig_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.start_time)
                    local orig_end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.end_time)
                    reaper.MIDI_SetNote(
                        take,
                        note_idx,
                        nil,
                        nil,
                        orig_start_ppq,
                        orig_end_ppq,
                        nil,
                        nil,
                        nil,
                        true
                    )
                end
                reaper.MIDI_Sort(take)
                local item = reaper.GetMediaItemTake_Item(take)
                if item then
                    reaper.UpdateItemInProject(item)
                end
            end
        elseif eff_mode == MODE_TRACK_OFFSET then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.track, "MediaTrack*") then
                    reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", info.baseline_offset)
                end
            end
        elseif eff_mode == MODE_TAKE_OFFSET then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                    reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", info.baseline_offset)
                    reaper.UpdateItemInProject(info.item)
                end
            end
        elseif eff_mode == MODE_ITEM_POSITION then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.item, "MediaItem*") then
                    reaper.SetMediaItemInfo_Value(info.item, "D_POSITION", info.baseline_offset)
                    reaper.UpdateItemInProject(info.item)
                end
            end
        end
        reaper.UpdateArrange()
        
        -- Commit final offsets in a single undo block
        local undo_msg = ""
        if eff_mode == MODE_MIDI_NOTES then
            undo_msg = string.format("Shift %d MIDI notes by %.1f ms", #gui_state.selected_targets, gui_state.slider_value)
        elseif eff_mode == MODE_TRACK_OFFSET then
            undo_msg = string.format("Set track media playback offset to %.1f ms", gui_state.slider_value)
        elseif eff_mode == MODE_TAKE_OFFSET then
            undo_msg = string.format("Set take source start offset to %.1f ms", gui_state.slider_value)
        elseif eff_mode == MODE_ITEM_POSITION then
            undo_msg = string.format("Move items timeline position by %.1f ms", gui_state.slider_value)
        end
        
        reaper.Undo_BeginBlock2(0)
        apply_offset_to_targets(gui_state.slider_value)
        reaper.Undo_EndBlock2(0, undo_msg, -1)
        
        if eff_mode == MODE_TRACK_OFFSET then
            reaper.TrackList_AdjustWindows(false)
        end
        
        -- Update baselines
        if eff_mode == MODE_MIDI_NOTES then
            local first_target = gui_state.selected_targets[1]
            if first_target then
                local take = first_target.take
                local offsets = get_take_note_offsets(take)
                for _, info in ipairs(gui_state.selected_targets) do
                    local key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                    offsets[key] = gui_state.slider_value
                    info.offset_ms = gui_state.slider_value
                end
                save_take_note_offsets(take, offsets)
            end
        elseif eff_mode == MODE_TRACK_OFFSET or eff_mode == MODE_TAKE_OFFSET then
            local final_val_sec = gui_state.slider_value / 1000.0
            for _, info in ipairs(gui_state.selected_targets) do
                info.baseline_offset = final_val_sec
            end
        elseif eff_mode == MODE_ITEM_POSITION then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.item, "MediaItem*") then
                    reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_offset", tostring(gui_state.slider_value), true)
                    info.baseline_offset = info.zero_position + (gui_state.slider_value / 1000.0)
                end
            end
        end
    end

    reaper.ImGui_Spacing(ctx)

    -- Fine-tuning buttons row
    local avail_w, _ = reaper.ImGui_GetContentRegionAvail(ctx)
    local button_width = math.floor((avail_w - 48) / 7)
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
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Display details section
    local track, take = get_current_context_track_and_take()
    local eff_mode = get_effective_mode()
    
    -- 1. Track Playback Offset (Always visible)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local cur_offset_sec = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
        local _, name = reaper.GetTrackName(track)
        name = name or "Unnamed Track"
        
        local label = "Track (" .. name .. ")"
        if eff_mode == MODE_TRACK_OFFSET and num_targets > 1 then
            label = string.format("Track (%s + %d others)", name, num_targets - 1)
        end
        reaper.ImGui_Text(ctx, label .. " Playback Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, string.format("%.1f ms (%.4fs)", cur_offset_sec * 1000.0, cur_offset_sec))
    else
        reaper.ImGui_Text(ctx, "Track Playback Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No track selected")
    end
    
    -- 2. Take Start Offset (Always visible)
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local cur_offset_sec = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local name = reaper.GetTakeName(take) or "Unnamed Take"
        
        local label = "Take (" .. name .. ")"
        if eff_mode == MODE_TAKE_OFFSET and num_targets > 1 then
            label = string.format("Take (%s + %d others)", name, num_targets - 1)
        end
        reaper.ImGui_Text(ctx, label .. " Start Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, string.format("%.1f ms (%.4fs)", cur_offset_sec * 1000.0, cur_offset_sec))
    else
        reaper.ImGui_Text(ctx, "Take Start Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No take selected")
    end

    -- 3. Item Position Offset (Always visible, stored in item extension metadata)
    local item
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        item = reaper.GetMediaItemTake_Item(take)
    else
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 0 then
            item = reaper.GetSelectedMediaItem(0, 0)
        end
    end
    
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        local retval, saved_val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
        local saved_ms = 0.0
        if retval and saved_val ~= "" then
            saved_ms = tonumber(saved_val) or 0.0
        end
        
        local display_name = "Unnamed Item"
        local active_take = reaper.GetActiveTake(item)
        if active_take then
            display_name = reaper.GetTakeName(active_take) or "Unnamed Take"
        end
        
        local label = "Item (" .. display_name .. ")"
        if eff_mode == MODE_ITEM_POSITION and num_targets > 1 then
            label = string.format("Item (%s + %d others)", display_name, num_targets - 1)
        end
        reaper.ImGui_Text(ctx, label .. " Position Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, string.format("%.1f ms", saved_ms))
    else
        reaper.ImGui_Text(ctx, "Item Position Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No item selected")
    end

    -- 4. MIDI Note Offset (Always visible)
    local has_notes, active_take = has_selected_midi_notes()
    if has_notes and active_take then
        local num_selected = #gui_state.selected_targets
        local display_str = "0.0 ms"
        if num_selected > 0 then
            local first_offset = gui_state.selected_targets[1].offset_ms or 0.0
            local all_same = true
            for i = 2, num_selected do
                local offset = gui_state.selected_targets[i].offset_ms or 0.0
                if math.abs(offset - first_offset) > 0.01 then
                    all_same = false
                    break
                end
            end
            if all_same then
                display_str = string.format("%.1f ms", first_offset)
            else
                display_str = "Multiple values"
            end
        end
        
        local label = string.format("MIDI Notes (%d selected)", num_selected)
        reaper.ImGui_Text(ctx, label .. " Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, display_str)
    else
        reaper.ImGui_Text(ctx, "MIDI Note Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No notes selected")
    end

    -- 5. Dynamic Mode Details (Move Item position)
    if eff_mode == MODE_ITEM_POSITION then
        local first_info = gui_state.selected_targets[1]
        if first_info and reaper.ValidatePtr(first_info.item, "MediaItem*") then
            local cur_pos_sec = reaper.GetMediaItemInfo_Value(first_info.item, "D_POSITION")
            local display_name = first_info.name
            if num_targets > 1 then
                display_name = string.format("%s (+ %d others)", first_info.name, num_targets - 1)
            end
            reaper.ImGui_Text(ctx, "Move Item (" .. display_name .. ") Pos:")
            reaper.ImGui_SameLine(ctx, 240)
            reaper.ImGui_Text(ctx, string.format("%.3f s", cur_pos_sec))
        end
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
        update_targets_list(true)
    end

    -- Redo (Ctrl+Y or Cmd+Shift+Z)
    if (is_ctrl_down and not is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
        update_targets_list(true)
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
    update_targets_list()

    -- Set size constraints
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 460, 200, 700, 300)

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
