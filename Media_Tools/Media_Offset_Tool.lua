-- @description Media Offset Tool
-- @author drvlat
-- @version 1.2.2
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
local script_name = "Media Offset Tool v1.2.2"
local ctx = reaper.ImGui_CreateContext(script_name)
local script_running = true

-- Fixed range ±500 ms
local FIXED_RANGE = 500.0

-- Presets configuration variables and helpers
local current_preset_name = ""
local combo_preset_name = ""
local new_preset_lib_input = ""
local new_preset_art_input = ""
local rename_preset_lib_input = ""
local rename_preset_art_input = ""
local open_new_preset_modal = false
local new_preset_show_in_grid = true
local rename_preset_show_in_grid = true

-- Helper to split a preset name into Library and Articulation
local function split_preset_name(name)
    if not name or name == "" then
        return "", ""
    end
    local lib, art = name:match("^(.-)%s*-%s*(.-)$")
    if lib and art then
        return lib, art
    else
        return name, ""
    end
end
local open_new_preset_focus = false
local open_rename_preset_modal = false
local open_rename_preset_focus = false
local open_delete_preset_modal = false
local show_info = false

local function get_presets_file_path()
    local sep = package.config:sub(1,1)
    return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "Walter_MediaOffset_Presets.txt"
end

local function load_presets()
    local path = get_presets_file_path()
    local loaded_presets = {}
    local show_in_grid = {}
    local keys = {}
    local f = io.open(path, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("[\r\n]", "")
            local name, rest = line:match("^(.-)=([^=]+)$")
            if name and rest then
                local val_str, show_str = rest:match("^(.-)|(.-)$")
                local val = 0.0
                local show = true
                if val_str and show_str then
                    val = tonumber(val_str) or 0.0
                    show = (show_str == "1")
                else
                    val = tonumber(rest) or 0.0
                end
                loaded_presets[name] = val
                show_in_grid[name] = show
                table.insert(keys, name)
            end
        end
        f:close()
    end
    table.sort(keys)
    return loaded_presets, keys, show_in_grid
end

local function save_presets(presets_table, show_in_grid_table)
    local path = get_presets_file_path()
    local f = io.open(path, "w")
    if f then
        local sorted_keys = {}
        for k in pairs(presets_table) do
            table.insert(sorted_keys, k)
        end
        table.sort(sorted_keys)
        for _, k in ipairs(sorted_keys) do
            local show = true
            if show_in_grid_table and show_in_grid_table[k] ~= nil then
                show = show_in_grid_table[k]
            end
            f:write(string.format("%s=%s|%d\n", k, tostring(presets_table[k]), show and 1 or 0))
        end
        f:close()
    end
end

local presets, preset_keys, presets_show_in_grid = load_presets()

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
    is_dragging = false,
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

-- Helper to parse note offsets metadata from parent item (namespaced by take GUID)
local function get_take_note_offsets(take)
    if not take or not reaper.TakeIsMIDI(take) then return {} end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return {} end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return {} end
    
    local _, val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Offsets_" .. guid, "", false)
    local offsets = {}
    if val and val ~= "" then
        for entry in val:gmatch("[^;]+") do
            local key, offset_str = entry:match("^([^:]+):([^:]+)$")
            if key and offset_str then
                offsets[key] = tonumber(offset_str) or 0.0
            end
        end
    end
    return offsets
end

-- Helper to save note offsets metadata to parent item (namespaced by take GUID)
local function save_take_note_offsets(take, offsets)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return end
    
    local entries = {}
    for key, val in pairs(offsets) do
        if math.abs(val) > 0.001 then
            table.insert(entries, key .. ":" .. tostring(val))
        end
    end
    local val_str = table.concat(entries, ";")
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Offsets_" .. guid, val_str, true)
end

-- Helper to parse note presets metadata from parent item (namespaced by take GUID)
local function get_take_note_presets(take)
    if not take or not reaper.TakeIsMIDI(take) then return {} end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return {} end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return {} end
    
    local _, val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Presets_" .. guid, "", false)
    local presets_map = {}
    if val and val ~= "" then
        for entry in val:gmatch("[^;]+") do
            local key, preset_name = entry:match("^([^:]+):(.*)$")
            if key and preset_name then
                presets_map[key] = preset_name
            end
        end
    end
    return presets_map
end

-- Helper to save note presets metadata to parent item (namespaced by take GUID)
local function save_take_note_presets(take, note_presets)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return end
    
    local entries = {}
    for key, val in pairs(note_presets) do
        if val and val ~= "" then
            table.insert(entries, key .. ":" .. val)
        end
    end
    local val_str = table.concat(entries, ";")
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Presets_" .. guid, val_str, true)
end

-- Helper to save the preset name metadata to all selected targets
local function save_preset_name_to_targets(preset_name)
    local eff_mode = get_effective_mode()
    if #gui_state.selected_targets == 0 then return end
    
    if eff_mode == MODE_MIDI_NOTES then
        local first_target = gui_state.selected_targets[1]
        if first_target then
            local take = first_target.take
            local note_presets = get_take_note_presets(take)
            for _, info in ipairs(gui_state.selected_targets) do
                local key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                if preset_name and preset_name ~= "" then
                    note_presets[key] = preset_name
                    info.preset_name = preset_name
                else
                    note_presets[key] = nil
                    info.preset_name = ""
                end
            end
            save_take_note_presets(take, note_presets)
        end
    elseif eff_mode == MODE_TRACK_OFFSET then
        for _, info in ipairs(gui_state.selected_targets) do
            info.preset_name = preset_name or ""
            if reaper.ValidatePtr(info.track, "MediaTrack*") then
                reaper.GetSetMediaTrackInfo_String(info.track, "P_EXT:Walter_MediaOffsetTool_preset", preset_name or "", true)
            end
        end
    elseif eff_mode == MODE_TAKE_OFFSET then
        for _, info in ipairs(gui_state.selected_targets) do
            info.preset_name = preset_name or ""
            if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(info.take, "GUID", "", false)
                if take_guid and take_guid ~= "" then
                    local parent_item = reaper.GetMediaItemTake_Item(info.take)
                    if parent_item then
                        reaper.GetSetMediaItemInfo_String(parent_item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, preset_name or "", true)
                    end
                end
            end
        end
    elseif eff_mode == MODE_ITEM_POSITION then
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.item, "MediaItem*") then
                reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_preset", preset_name or "", true)
                info.preset_name = preset_name or ""
            end
        end
    end
end

-- Helper to clean up note offsets and presets metadata from a take
local function cleanup_take_note_offsets(take)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local _, notes_count = reaper.MIDI_CountEvts(take)
    local offsets = get_take_note_offsets(take)
    local note_presets = get_take_note_presets(take)
    
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
    local cleaned_presets = {}
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
                if note_presets[key] then
                    cleaned_presets[key] = note_presets[key]
                end
            else
                changed = true
            end
        end
    end
    
    if changed then
        save_take_note_offsets(take, cleaned_offsets)
        save_take_note_presets(take, cleaned_presets)
    end
end

-- Populate selection info
local function update_targets_list(force)
    -- Skip rebuilding selection while the user is actively interacting with the GUI,
    -- unless forced (e.g. on mode change).
    if not force and (reaper.ImGui_IsAnyItemActive(ctx) or gui_state.is_dragging) then
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
            local note_presets = get_take_note_presets(take)
            local note_idx = -1
            local safety = 0
            while safety < 10000 do
                note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                if note_idx == -1 then break end
                local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
                if retval then
                    -- Look up in offsets metadata
                    local found_offset = 0.0
                    local found_preset = ""
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
                                    found_preset = note_presets[key] or ""
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
                        preset_name = found_preset,
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
                        local _, track_preset = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        table.insert(gui_state.selected_targets, {
                            track = track,
                            name = name,
                            baseline_offset = cur_offset,
                            preset_name = track_preset or ""
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
                                local _, track_preset = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                                table.insert(gui_state.selected_targets, {
                                    track = track,
                                    name = name .. " (MIDI Editor)",
                                    baseline_offset = cur_offset,
                                    preset_name = track_preset or ""
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
                            local take_preset = ""
                            local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                            if take_guid and take_guid ~= "" then
                                _, take_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, "", false)
                            end
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name,
                                baseline_offset = cur_offset,
                                preset_name = take_preset or ""
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
                            local take_preset = ""
                            local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                            if take_guid and take_guid ~= "" then
                                _, take_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, "", false)
                            end
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name .. " (MIDI Editor)",
                                baseline_offset = cur_offset,
                                preset_name = take_preset or ""
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
                        local _, item_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        
                        table.insert(gui_state.selected_targets, {
                            item = item,
                            name = name,
                            zero_position = zero_pos,
                            baseline_offset = cur_pos,
                            preset_name = item_preset or ""
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
                            local _, item_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                            
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                name = name .. " (MIDI Editor)",
                                zero_position = zero_pos,
                                baseline_offset = cur_pos,
                                preset_name = item_preset or ""
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
        
        -- Determine common preset name on selection change
        if #gui_state.selected_targets > 0 then
            local first_preset = gui_state.selected_targets[1].preset_name or ""
            local all_same = true
            for i = 2, #gui_state.selected_targets do
                if (gui_state.selected_targets[i].preset_name or "") ~= first_preset then
                    all_same = false
                    break
                end
            end
            if all_same then
                current_preset_name = first_preset
                combo_preset_name = first_preset
            else
                current_preset_name = ""
                combo_preset_name = ""
            end
        else
            current_preset_name = ""
            combo_preset_name = ""
        end
    else
        -- Sync baselines and values if NOT dragging
        local is_slider_active = reaper.ImGui_IsAnyItemActive(ctx) or gui_state.is_dragging
        local is_previewing = (combo_preset_name ~= "" and combo_preset_name ~= current_preset_name)
        if not is_slider_active and #gui_state.selected_targets > 0 then
            local eff_mode, take = get_effective_mode()
            if eff_mode == MODE_MIDI_NOTES then
                local offsets = get_take_note_offsets(take)
                local note_presets = get_take_note_presets(take)
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
                            note_presets[old_key] = nil
                            
                            -- Reset baseline to new position
                            info.original_ppq = startppq
                            info.offset_ms = 0.0
                            info.preset_name = ""
                            info.start_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, startppq)
                            info.end_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, endppq)
                            any_drifted = true
                        else
                            local old_key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                            info.preset_name = note_presets[old_key] or ""
                        end
                    end
                end
                
                if any_drifted then
                    save_take_note_offsets(take, offsets)
                    save_take_note_presets(take, note_presets)
                    
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
                    
                    current_preset_name = all_same_preset and first_preset or ""
                    combo_preset_name = current_preset_name
                end
            elseif eff_mode == MODE_TRACK_OFFSET then
                if not is_previewing then
                    local first_info = gui_state.selected_targets[1]
                    if reaper.ValidatePtr(first_info.track, "MediaTrack*") then
                        local actual_offset = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
                        gui_state.slider_value = actual_offset * 1000.0
                    end
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.track, "MediaTrack*") then
                        info.baseline_offset = reaper.GetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET")
                        local _, track_preset = reaper.GetSetMediaTrackInfo_String(info.track, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        info.preset_name = track_preset or ""
                    end
                end
            elseif eff_mode == MODE_TAKE_OFFSET then
                if not is_previewing then
                    local first_info = gui_state.selected_targets[1]
                    if reaper.ValidatePtr(first_info.take, "MediaItem_Take*") then
                        local actual_offset = reaper.GetMediaItemTakeInfo_Value(first_info.take, "D_STARTOFFS")
                        gui_state.slider_value = actual_offset * 1000.0
                    end
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                        info.baseline_offset = reaper.GetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS")
                        local take_preset = ""
                        local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(info.take, "GUID", "", false)
                        if take_guid and take_guid ~= "" then
                            local parent_item = reaper.GetMediaItemTake_Item(info.take)
                            if parent_item then
                                _, take_preset = reaper.GetSetMediaItemInfo_String(parent_item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, "", false)
                            end
                        end
                        info.preset_name = take_preset or ""
                    end
                end
            elseif eff_mode == MODE_ITEM_POSITION then
                if not is_previewing then
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
                        local _, item_preset = reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        info.preset_name = item_preset or ""
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
local function adjust_offset_to_value(target_ms, preset_name)
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
    
    -- Persist/Clear preset association
    local active_preset = ""
    if preset_name and preset_name ~= "" then
        active_preset = preset_name
    elseif combo_preset_name ~= "" and presets[combo_preset_name] ~= nil then
        if math.abs(presets[combo_preset_name] - target_ms) < 0.01 then
            active_preset = combo_preset_name
        end
    end
    save_preset_name_to_targets(active_preset)
    
    current_preset_name = active_preset
    combo_preset_name = active_preset
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

    -- Articulation presets dropdown and controls row
    reaper.ImGui_Text(ctx, "Preset:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 220)
    
    local combo_preview = combo_preset_name
    if combo_preview == "" then
        combo_preview = "-- Select Preset --"
    end
    
    if reaper.ImGui_BeginCombo(ctx, "##presets_combo", combo_preview) then
        for _, name in ipairs(preset_keys) do
            local is_selected = (name == combo_preset_name)
            if reaper.ImGui_Selectable(ctx, name, is_selected) then
                combo_preset_name = name
                gui_state.slider_value = presets[name]
            end
            if is_selected then
                reaper.ImGui_SetItemDefaultFocus(ctx)
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Save Button
    local has_selected_preset = (combo_preset_name ~= "" and presets[combo_preset_name] ~= nil)
    if not has_selected_preset then
        reaper.ImGui_BeginDisabled(ctx)
    end
    if reaper.ImGui_Button(ctx, "Save") then
        presets[combo_preset_name] = gui_state.slider_value
        save_presets(presets, presets_show_in_grid)
        presets, preset_keys, presets_show_in_grid = load_presets()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Overwrite the selected preset with the current offset.")
    end
    if not has_selected_preset then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Save As Button
    if reaper.ImGui_Button(ctx, "Save As") then
        local lib, art = split_preset_name(combo_preset_name)
        new_preset_lib_input = lib
        new_preset_art_input = ""
        new_preset_show_in_grid = true
        open_new_preset_modal = true
        open_new_preset_focus = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Save the current offset as a new preset.")
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Rename Button (Rn)
    if not has_selected_preset then
        reaper.ImGui_BeginDisabled(ctx)
    end
    if reaper.ImGui_Button(ctx, "Rn") then
        open_rename_preset_modal = true
        open_rename_preset_focus = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Rename selected preset.")
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Delete Button (Dl)
    if reaper.ImGui_Button(ctx, "Dl") then
        open_delete_preset_modal = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Delete selected preset.")
    end
    
    if not has_selected_preset then
        reaper.ImGui_EndDisabled(ctx)
    end

    -- Modals rendering
    if open_new_preset_modal then
        reaper.ImGui_OpenPopup(ctx, "New Preset")
        open_new_preset_modal = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "New Preset", nil, imgui.WindowFlags_AlwaysAutoResize) then
        reaper.ImGui_Text(ctx, "Library Name:")
        if open_new_preset_focus then
            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            open_new_preset_focus = false
        end
        local changed_lib, new_lib = reaper.ImGui_InputText(ctx, "##new_lib", new_preset_lib_input)
        if changed_lib then
            new_preset_lib_input = new_lib
        end
        
        reaper.ImGui_Text(ctx, "Articulation Name:")
        local changed_art, new_art = reaper.ImGui_InputText(ctx, "##new_art", new_preset_art_input)
        if changed_art then
            new_preset_art_input = new_art
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local cb_changed, new_cb_val = reaper.ImGui_Checkbox(ctx, "Show in Preset Grid", new_preset_show_in_grid)
        if cb_changed then
            new_preset_show_in_grid = new_cb_val
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local lib_trimmed = new_preset_lib_input:gsub("^%s*(.-)%s*$", "%1")
        local art_trimmed = new_preset_art_input:gsub("^%s*(.-)%s*$", "%1")
        local can_save = (lib_trimmed ~= "" and art_trimmed ~= "")
        
        if not can_save then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_Button(ctx, "OK", 80) then
            local combined_name = lib_trimmed .. " - " .. art_trimmed
            presets[combined_name] = gui_state.slider_value
            presets_show_in_grid[combined_name] = new_preset_show_in_grid
            save_presets(presets, presets_show_in_grid)
            presets, preset_keys, presets_show_in_grid = load_presets()
            save_preset_name_to_targets(combined_name)
            current_preset_name = combined_name
            combo_preset_name = combined_name
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if not can_save then
            reaper.ImGui_EndDisabled(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    if open_rename_preset_modal then
        local lib, art = split_preset_name(combo_preset_name)
        rename_preset_lib_input = lib
        rename_preset_art_input = art
        rename_preset_show_in_grid = (presets_show_in_grid[combo_preset_name] ~= false)
        reaper.ImGui_OpenPopup(ctx, "Rename Preset")
        open_rename_preset_modal = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "Rename Preset", nil, imgui.WindowFlags_AlwaysAutoResize) then
        reaper.ImGui_Text(ctx, "Library Name:")
        if open_rename_preset_focus then
            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            open_rename_preset_focus = false
        end
        local changed_lib, new_lib = reaper.ImGui_InputText(ctx, "##rename_lib", rename_preset_lib_input)
        if changed_lib then
            rename_preset_lib_input = new_lib
        end
        
        reaper.ImGui_Text(ctx, "Articulation Name:")
        local changed_art, new_art = reaper.ImGui_InputText(ctx, "##rename_art", rename_preset_art_input)
        if changed_art then
            rename_preset_art_input = new_art
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local cb_changed, new_cb_val = reaper.ImGui_Checkbox(ctx, "Show in Preset Grid", rename_preset_show_in_grid)
        if cb_changed then
            rename_preset_show_in_grid = new_cb_val
        end
        
        reaper.ImGui_Spacing(ctx)
        
        local lib_trimmed = rename_preset_lib_input:gsub("^%s*(.-)%s*$", "%1")
        local art_trimmed = rename_preset_art_input:gsub("^%s*(.-)%s*$", "%1")
        local combined_name = lib_trimmed .. " - " .. art_trimmed
        local can_save = (lib_trimmed ~= "" and art_trimmed ~= "" and (combined_name ~= combo_preset_name or rename_preset_show_in_grid ~= (presets_show_in_grid[combo_preset_name] ~= false)))
        
        if not can_save then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_Button(ctx, "OK", 80) then
            local val = presets[combo_preset_name]
            presets[combo_preset_name] = nil
            presets_show_in_grid[combo_preset_name] = nil
            
            presets[combined_name] = val
            presets_show_in_grid[combined_name] = rename_preset_show_in_grid
            save_presets(presets, presets_show_in_grid)
            presets, preset_keys, presets_show_in_grid = load_presets()
            if current_preset_name == combo_preset_name then
                current_preset_name = combined_name
                save_preset_name_to_targets(combined_name)
            end
            combo_preset_name = combined_name
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if not can_save then
            reaper.ImGui_EndDisabled(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    if open_delete_preset_modal then
        reaper.ImGui_OpenPopup(ctx, "Delete Preset?")
        open_delete_preset_modal = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "Delete Preset?", nil, imgui.WindowFlags_AlwaysAutoResize) then
        reaper.ImGui_Text(ctx, string.format("Are you sure you want to delete '%s'?", combo_preset_name))
        
        reaper.ImGui_Spacing(ctx)
        
        if reaper.ImGui_Button(ctx, "Yes", 80) then
            presets[combo_preset_name] = nil
            presets_show_in_grid[combo_preset_name] = nil
            save_presets(presets, presets_show_in_grid)
            presets, preset_keys, presets_show_in_grid = load_presets()
            if current_preset_name == combo_preset_name then
                current_preset_name = ""
                save_preset_name_to_targets("")
            end
            combo_preset_name = ""
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "No", 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Double-click / Drag slider for absolute offset (displaying current value) and manual input box side by side
    reaper.ImGui_Text(ctx, "Offset:")
    reaper.ImGui_SameLine(ctx, 90)
    
    reaper.ImGui_SetNextItemWidth(ctx, 220)
    local slider_changed, new_slider_val = reaper.ImGui_SliderDouble(ctx, "##slider", gui_state.slider_value, -FIXED_RANGE, FIXED_RANGE, "%.1f ms")
    local is_slider_active = reaper.ImGui_IsItemActive(ctx)
    local is_slider_activated = reaper.ImGui_IsItemActivated(ctx)
    local is_slider_deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    if is_slider_activated or is_slider_active then
        gui_state.is_dragging = true
    end

    if slider_changed then
        local eff_mode = get_effective_mode()
        gui_state.slider_value = new_slider_val
        apply_offset_to_targets(new_slider_val)
        current_preset_name = ""
        combo_preset_name = ""
        if eff_mode == MODE_TRACK_OFFSET then
            reaper.TrackList_AdjustWindows(false)
        end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 80)
    local input_changed, new_input_val = reaper.ImGui_InputDouble(ctx, "ms", gui_state.slider_value, 0.0, 0.0, "%.1f")
    if input_changed then
        gui_state.slider_value = new_input_val
        current_preset_name = ""
        combo_preset_name = ""
    end
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        adjust_offset_to_value(gui_state.slider_value)
    end

    -- Explicit Apply Button
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button, reaper.ImGui_ColorConvertDouble4ToU32(0.35, 0.2, 0.55, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(0.45, 0.3, 0.7, 1.0))
    if reaper.ImGui_Button(ctx, "Apply") then
        adjust_offset_to_value(gui_state.slider_value)
    end
    reaper.ImGui_PopStyleColor(ctx, 2)

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
        
        -- Persist/Clear preset association on slider commit
        local active_preset = ""
        if current_preset_name ~= "" and presets[current_preset_name] ~= nil then
            if math.abs(presets[current_preset_name] - gui_state.slider_value) < 0.01 then
                active_preset = current_preset_name
            end
        end
        save_preset_name_to_targets(active_preset)
        
        gui_state.is_dragging = false
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

    if show_info then
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

    -- Preset Board (10x10 Grid)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_Text(ctx, "Preset Board (10x10):")
    
    -- Prepare grouped data
    local libs = {}
    local lib_names = {}
    for _, name in ipairs(preset_keys) do
        if presets_show_in_grid[name] ~= false then
            local lib, art = name:match("^(.-)%s*-%s*(.-)$")
            if not lib then
                lib = "Other"
                art = name
            end
            if not libs[lib] then
                libs[lib] = {}
                table.insert(lib_names, lib)
            end
            if #libs[lib] < 10 then
                table.insert(libs[lib], { name = name, art = art, offset = presets[name] })
            end
        end
    end
    
    table.sort(lib_names)
    for lib in pairs(libs) do
        table.sort(libs[lib], function(a, b) return a.art < b.art end)
    end
    
    -- Limit to first 10 libraries
    local num_cols = math.min(#lib_names, 10)
    
    -- Set style for the table buttons
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_FramePadding, 2.0, 2.0)
    
    local table_flags = (imgui.TableFlags_Borders or 0) | (imgui.TableFlags_RowBg or 0) | (imgui.TableFlags_SizingStretchSame or 0)
    if reaper.ImGui_BeginTable(ctx, "preset_grid_table", 10, table_flags, 700.0) then
        -- Table Headers (Library Names)
        local col_flags = imgui.TableColumnFlags_WidthStretch or 8
        for col = 1, 10 do
            local lib_name = ""
            if col <= num_cols then
                lib_name = lib_names[col]
            end
            reaper.ImGui_TableSetupColumn(ctx, lib_name ~= "" and lib_name or " ", col_flags, 1.0)
        end
        reaper.ImGui_TableHeadersRow(ctx)
        
        -- Table Rows (Articulations)
        for row = 1, 10 do
            reaper.ImGui_TableNextRow(ctx)
            for col = 1, 10 do
                reaper.ImGui_TableSetColumnIndex(ctx, col - 1)
                
                local cell_data = nil
                if col <= num_cols then
                    local lib_name = lib_names[col]
                    cell_data = libs[lib_name][row]
                end
                
                local cell_w, _ = reaper.ImGui_GetContentRegionAvail(ctx)
                if cell_data then
                    -- Draw button with articulation name
                    local button_label = cell_data.art
                    if button_label == "" then button_label = "Preset" end
                    
                    -- Color button if it's the currently selected preset
                    local is_current = (current_preset_name == cell_data.name)
                    if is_current then
                        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.35, 0.8, 1.0))
                    end
                    
                    -- Unique ID for ImGui button
                    local button_id = string.format("%s##btn_%d_%d", button_label, col, row)
                    if reaper.ImGui_Button(ctx, button_id, cell_w, 20) then
                        current_preset_name = cell_data.name
                        adjust_offset_to_value(cell_data.offset, cell_data.name)
                    end
                    
                    if is_current then
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                    
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, string.format("%s\nOffset: %.1f ms", cell_data.name, cell_data.offset))
                    end
                else
                    -- Render a disabled placeholder button to maintain the grid look
                    reaper.ImGui_BeginDisabled(ctx)
                    reaper.ImGui_Button(ctx, string.format("-##empty_%d_%d", col, row), cell_w, 20)
                    reaper.ImGui_EndDisabled(ctx)
                end
            end
        end
        reaper.ImGui_EndTable(ctx)
    end
    
    reaper.ImGui_PopStyleVar(ctx)
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
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 720, 200, 1200, 800)

    -- Set window style/colors
    push_theme()

    local window_flags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost | (imgui.WindowFlags_AlwaysAutoResize or 0)
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
