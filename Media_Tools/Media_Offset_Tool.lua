-- @description Media Offset Tool
-- @author drvlat
-- @version 1.14.1
-- @about
--   An ImGui-based utility for adjusting media offsets in REAPER.
--   Supports three target modes selected via radio buttons:
--     1) Take Start Offset
--     2) Track Playback Offset
--     3) Move Item Position
--   If MIDI notes are selected, overrides normal modes to adjust note timing directly.
--   Works inside the MIDI Editor for the current MIDI item, or falls back to selected items/tracks in the Arrange view.
--   Features an absolute slider fixed at ±500ms, fine-tuning buttons, absolute offset reset, and clean status labels.
--   Note offsets are robustly stored directly inside the MIDI stream as Text Events at the note start position.
-- @provides
--   [main=main,midi_editor,midi_inlineeditor,midi_eventlisteditor] Media_Offset_Tool.lua
--   [nomain] modules/config_manager.lua
--   [nomain] modules/preset_manager.lua
--   [nomain] modules/offset_engine.lua
--   [nomain] modules/theme_manager.lua
--   [nomain] modules/target_manager.lua
--   [nomain] modules/ui_renderer.lua
--   [nomain] modules/ui_modals.lua
--   [nomain] modules/ui_settings.lua
--   [nomain] modules/ui_trigger_editor.lua
--   [nomain] modules/ui_presets_dropdown.lua
--   [nomain] modules/ui_info_panel.lua
--   [nomain] modules/ui_shortcuts.lua

local reaper = reaper

-- Check for reaimgui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Toggle action state behavior (terminate on repeat run, set state checkmark)
if reaper.set_action_options then
  reaper.set_action_options(1)
end
local _, _, section_id, cmd_id = reaper.get_action_context()
if section_id and cmd_id and section_id ~= -1 and cmd_id ~= -1 then
  reaper.SetToggleCommandState(section_id, cmd_id, 1)
  reaper.RefreshToolbar2(section_id, cmd_id)
end

-- Load the ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')






-- Load modules
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
package.path = script_path .. "modules/?.lua;" .. package.path
local preset_manager = require("preset_manager")
local config_manager = require("config_manager")
local offset_engine = require("offset_engine")
local theme_manager = require("theme_manager")
local ui_renderer = require("ui_renderer")
local ui_settings = require("ui_settings")
local ui_modals = require("ui_modals")
local ui_trigger_editor = require("ui_trigger_editor")
local ui_presets_dropdown = require("ui_presets_dropdown")
local ui_info_panel = require("ui_info_panel")
local ui_shortcuts = require("ui_shortcuts")
local target_manager = require("target_manager")

-- Script variables
local script_name = "Media Offset Tool v1.14.1"
local ctx = reaper.ImGui_CreateContext(script_name)
local script_running = true
local gui_state -- Forward declaration for helper functions

-- Per-frame caching for has_selected_midi_notes()
local frame_counter = 0
local cached_frame = -1
local cached_has_notes = false
local cached_take = nil

-- Fixed range ±500 ms
local FIXED_RANGE = 500.0

-- Presets configuration variables and helpers
local current_preset_name = ""
local combo_preset_name = ""
local new_preset_lib_input = ""
local new_preset_instr_input = ""
local new_preset_art_input = ""
local rename_preset_lib_input = ""
local rename_preset_instr_input = ""
local rename_preset_art_input = ""
local open_new_preset_modal = false
local new_preset_show_in_grid = true
local rename_preset_show_in_grid = true

-- Helper to split a preset name into Library, Instrument, Articulation
local function split_preset_name(name)
    return preset_manager.split_preset_name(name)
end
-- Helper to build a preset name from parts (instrument optional)
local function join_preset_name(lib, instr, art)
    return preset_manager.join_preset_name(lib, instr, art)
end

local open_new_preset_focus = false
local open_rename_preset_modal = false
local open_rename_preset_focus = false
local open_delete_preset_modal = false
local show_info = false
local show_settings = false
local focus_main_next_frame = false

local presets
local preset_keys
local presets_show_in_grid
local presets_ks_pitch
local presets_note_vel_min
local presets_note_vel_max

-- Helper to split a string by separator
local function split_string(inputstr, sep)
    return preset_manager.split_string(inputstr, sep)
end

local function get_presets_file_path()
    return preset_manager.get_presets_file_path()
end

local presets_lib_order = {}
local presets_instr_order = {}
local presets_art_order = {}

local function load_presets()
    local p, pk, ps, pksp, pmin, pmax, lo, io, ao = preset_manager.load_presets()
    presets_lib_order = lo or {}
    presets_instr_order = io or {}
    presets_art_order = ao or {}
    return p, pk, ps, pksp, pmin, pmax
end

local function save_presets(presets_table, show_in_grid_table)
    preset_manager.save_presets(
        presets_table, 
        show_in_grid_table, 
        presets_ks_pitch, 
        presets_note_vel_min, 
        presets_note_vel_max,
        presets_lib_order,
        presets_instr_order,
        presets_art_order
    )
end

presets, preset_keys, presets_show_in_grid, presets_ks_pitch, presets_note_vel_min, presets_note_vel_max = load_presets()

-- ── Settings file (load/save) ────────────────────────────────────────────
local function get_settings_file_path()
    return config_manager.get_settings_file_path()
end

local DEFAULT_BG              = config_manager.DEFAULTS.theme_bg
local DEFAULT_ACCENT          = config_manager.DEFAULTS.theme_accent
local DEFAULT_TEXT            = config_manager.DEFAULTS.theme_text
local DEFAULT_DANGER          = config_manager.DEFAULTS.theme_danger
local DEFAULT_POSITIVE        = config_manager.DEFAULTS.theme_positive
local DEFAULT_SLIDER_GRAB     = config_manager.DEFAULTS.theme_slider_grab
local DEFAULT_APPLY_BTN       = config_manager.DEFAULTS.theme_apply_btn
local DEFAULT_FRAME_BG        = config_manager.DEFAULTS.theme_frame_bg
local DEFAULT_CHECK_MARK      = config_manager.DEFAULTS.theme_check_mark
local DEFAULT_INACTIVE_BTN    = config_manager.DEFAULTS.theme_inactive_btn
local DEFAULT_INACTIVE_BTN_TEXT = config_manager.DEFAULTS.theme_inactive_btn_text
local DEFAULT_ACTIVE_BTN      = config_manager.DEFAULTS.theme_active_btn

local theme_bg              = {DEFAULT_BG[1],              DEFAULT_BG[2],              DEFAULT_BG[3]}
local theme_accent          = {DEFAULT_ACCENT[1],          DEFAULT_ACCENT[2],          DEFAULT_ACCENT[3]}
local theme_text            = {DEFAULT_TEXT[1],            DEFAULT_TEXT[2],            DEFAULT_TEXT[3]}
local theme_danger          = {DEFAULT_DANGER[1],          DEFAULT_DANGER[2],          DEFAULT_DANGER[3]}
local theme_positive        = {DEFAULT_POSITIVE[1],        DEFAULT_POSITIVE[2],        DEFAULT_POSITIVE[3]}
local theme_slider_grab     = {DEFAULT_SLIDER_GRAB[1],     DEFAULT_SLIDER_GRAB[2],     DEFAULT_SLIDER_GRAB[3]}
local theme_apply_btn       = {DEFAULT_APPLY_BTN[1],       DEFAULT_APPLY_BTN[2],       DEFAULT_APPLY_BTN[3]}
local theme_frame_bg        = {DEFAULT_FRAME_BG[1],        DEFAULT_FRAME_BG[2],        DEFAULT_FRAME_BG[3]}
local theme_check_mark      = {DEFAULT_CHECK_MARK[1],      DEFAULT_CHECK_MARK[2],      DEFAULT_CHECK_MARK[3]}
local theme_inactive_btn    = {DEFAULT_INACTIVE_BTN[1],    DEFAULT_INACTIVE_BTN[2],    DEFAULT_INACTIVE_BTN[3]}
local theme_inactive_btn_text = {DEFAULT_INACTIVE_BTN_TEXT[1], DEFAULT_INACTIVE_BTN_TEXT[2], DEFAULT_INACTIVE_BTN_TEXT[3]}
local theme_active_btn      = {DEFAULT_ACTIVE_BTN[1],      DEFAULT_ACTIVE_BTN[2],      DEFAULT_ACTIVE_BTN[3]}

local settings_write_keyswitches = false

local function load_settings()
    local themes, write_ks = config_manager.load_settings()
    theme_bg = themes.theme_bg
    theme_accent = themes.theme_accent
    theme_text = themes.theme_text
    theme_danger = themes.theme_danger
    theme_positive = themes.theme_positive
    theme_slider_grab = themes.theme_slider_grab
    theme_apply_btn = themes.theme_apply_btn
    theme_frame_bg = themes.theme_frame_bg
    theme_check_mark = themes.theme_check_mark
    theme_inactive_btn = themes.theme_inactive_btn
    theme_inactive_btn_text = themes.theme_inactive_btn_text
    theme_active_btn = themes.theme_active_btn
    settings_write_keyswitches = write_ks
end

local function save_settings()
    local themes = {
        theme_bg              = theme_bg,
        theme_accent          = theme_accent,
        theme_text            = theme_text,
        theme_danger          = theme_danger,
        theme_positive        = theme_positive,
        theme_slider_grab     = theme_slider_grab,
        theme_apply_btn       = theme_apply_btn,
        theme_frame_bg        = theme_frame_bg,
        theme_check_mark      = theme_check_mark,
        theme_inactive_btn    = theme_inactive_btn,
        theme_inactive_btn_text = theme_inactive_btn_text,
        theme_active_btn      = theme_active_btn
    }
    local write_ks = false
    if gui_state and gui_state.write_keyswitches ~= nil then
        write_ks = gui_state.write_keyswitches
    else
        write_ks = settings_write_keyswitches
    end
    config_manager.save_settings(themes, write_ks)
end

load_settings()

-- Helper: pack float {r,g,b} table to uint32 in 0xRRGGBBAA format (ColorEdit4 native format)
local function theme_pack(t)
    return theme_manager.theme_pack(t)
end
-- Helper: unpack uint32 to float {r,g,b} table
local function theme_unpack(u)
    return theme_manager.theme_unpack(u)
end

-- Working copies for the color pickers: stored as uint32 to avoid float→uint8→float
-- precision drift inside the picker loop (which causes HUE/saturation self-movement).
local settings_edit_bg_u32              = theme_pack(theme_bg)
local settings_edit_accent_u32          = theme_pack(theme_accent)
local settings_edit_text_u32            = theme_pack(theme_text)
local settings_edit_danger_u32          = theme_pack(theme_danger)
local settings_edit_positive_u32        = theme_pack(theme_positive)
local settings_edit_slider_grab_u32     = theme_pack(theme_slider_grab)
local settings_edit_apply_btn_u32       = theme_pack(theme_apply_btn)
local settings_edit_frame_bg_u32        = theme_pack(theme_frame_bg)
local settings_edit_check_mark_u32      = theme_pack(theme_check_mark)
local settings_edit_inactive_btn_u32    = theme_pack(theme_inactive_btn)
local settings_edit_inactive_btn_text_u32 = theme_pack(theme_inactive_btn_text)
local settings_edit_active_btn_u32      = theme_pack(theme_active_btn)

-- Target adjustment modes
local MODE_TAKE_OFFSET = 0    -- Mode A: Media Take Source Start Offset
local MODE_TRACK_OFFSET = 1   -- Mode B: Track Playback Offset
local MODE_ITEM_POSITION = 2  -- Mode C: Move Item Timeline Position
local MODE_MIDI_NOTES = 3     -- Override Mode: Shift Selected MIDI Notes

-- Helper to check if notes are selected in the active MIDI editor take
local function has_selected_midi_notes()
    if cached_frame == frame_counter then
        return cached_has_notes, cached_take
    end
    
    local midi_editor = reaper.MIDIEditor_GetActive()
    if midi_editor then
        local take = reaper.MIDIEditor_GetTake(midi_editor)
        if take then
            local note_index = reaper.MIDI_EnumSelNotes(take, -1)
            if note_index ~= -1 then
                cached_has_notes = true
                cached_take = take
                cached_frame = frame_counter
                return true, take
            end
        end
    end
    
    cached_has_notes = false
    cached_take = nil
    cached_frame = frame_counter
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
    write_keyswitches = settings_write_keyswitches, -- Default to loaded settings
    move_envelopes = (reaper.GetToggleCommandState(40070) == 1), -- Initialize from REAPER's global "move envelopes with items" option
}

-- Load persisted mode from project metadata
local _, saved_mode_str = reaper.GetProjExtState(0, "Walter_MediaOffsetTool", "selected_mode")
if saved_mode_str and saved_mode_str ~= "" then
    local saved_mode = tonumber(saved_mode_str)
    if saved_mode == MODE_TAKE_OFFSET or saved_mode == MODE_TRACK_OFFSET or saved_mode == MODE_ITEM_POSITION then
        gui_state.adjust_mode = saved_mode
    end
end


-- Helper to parse note offsets metadata from parent item (namespaced by take GUID)
local function get_take_note_offsets(take)
    return offset_engine.get_take_note_offsets(take)
end

-- Helper to save note offsets metadata to parent item (namespaced by take GUID)
local function save_take_note_offsets(take, offsets)
    return offset_engine.save_take_note_offsets(take, offsets)
end

-- Helper to parse note presets metadata from parent item (namespaced by take GUID)
local function get_take_note_presets(take)
    return offset_engine.get_take_note_presets(take)
end

-- Helper to save note presets metadata to parent item (namespaced by take GUID)
local function save_take_note_presets(take, note_presets)
    return offset_engine.save_take_note_presets(take, note_presets)
end

-- Helper to delete/write preset name as a MIDI Text Event
local function write_note_preset_text_event(take, startppq, preset_name)
    return offset_engine.write_note_preset_text_event(take, startppq, preset_name)
end

-- Helper to read preset name from MIDI Text Event
local function read_note_preset_text_event(take, startppq)
    return offset_engine.read_note_preset_text_event(take, startppq)
end

-- Helper to delete/write offset as a MIDI Text Event
local function write_note_offset_text_event(take, startppq, offset_ms)
    return offset_engine.write_note_offset_text_event(take, startppq, offset_ms)
end

-- Helper to read offset from MIDI Text Event
local function read_note_offset_text_event(take, startppq)
    return offset_engine.read_note_offset_text_event(take, startppq)
end

-- Helper to build a lookup cache of text events in a take
local function build_take_text_events_cache(take)
    return offset_engine.build_take_text_events_cache(take)
end

-- Helper to query text events near a specific PPQ position using the cache
local function find_text_events_near_ppq(cache, startppq)
    return offset_engine.find_text_events_near_ppq(cache, startppq)
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
                
                -- Write preset name to MIDI Text Event
                local current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.start_time + (info.offset_ms / 1000.0))
                write_note_preset_text_event(take, current_ppq, preset_name)
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

-- Helper to check if a pitch is used as a keyswitch in any preset
local function is_keyswitch_pitch(pitch)
    return target_manager.is_keyswitch_pitch(pitch, gui_state, presets_ks_pitch)
end

-- Helper to clean up note offsets and presets metadata from a take (both P_EXT and Text Events)
local function cleanup_take_note_offsets(take)
    target_manager.cleanup_take_note_offsets(take, gui_state, presets_ks_pitch)
end

-- Helper to auto-detect matching preset for a selected MIDI note
local function detect_preset_for_note(take, target_idx, target_vel, target_start_ppq, target_chan)
    return target_manager.detect_preset_for_note(
        take, target_idx, target_vel, target_start_ppq, target_chan, gui_state,
        presets_ks_pitch, presets, presets_note_vel_min, presets_note_vel_max
    )
end

-- Populate selection info
local function update_targets_list(force)
    local callbacks = {
        get_effective_mode = get_effective_mode,
        has_selected_midi_notes = has_selected_midi_notes,
        get_midi_notes_signature = get_midi_notes_signature,
        split_preset_name = split_preset_name
    }
    local modes = {
        MODE_MIDI_NOTES = MODE_MIDI_NOTES,
        MODE_TRACK_OFFSET = MODE_TRACK_OFFSET,
        MODE_TAKE_OFFSET = MODE_TAKE_OFFSET,
        MODE_ITEM_POSITION = MODE_ITEM_POSITION
    }
    local presets_state = {
        presets = presets,
        presets_ks_pitch = presets_ks_pitch,
        presets_note_vel_min = presets_note_vel_min,
        presets_note_vel_max = presets_note_vel_max,
        current_preset_name = current_preset_name,
        combo_preset_name = combo_preset_name
    }
    target_manager.update_targets_list(ctx, gui_state, presets_state, modes, force, callbacks)
    
    current_preset_name = presets_state.current_preset_name
    combo_preset_name = presets_state.combo_preset_name
end

-- Apply current slider/adjustment value to all selected targets
local function apply_offset_to_targets(value, preset_name)
    local eff_mode = get_effective_mode()
    if eff_mode == MODE_MIDI_NOTES then
        local shift_sec = value / 1000.0
        local first_target = gui_state.selected_targets[1]
        if first_target then
            local take = first_target.take
            local note_idx = -1
            
            local write_vel = nil
            local ks_pitch = -1
            local ks_vel = 100
            
            if gui_state.write_keyswitches and preset_name and preset_name ~= "" then
                local note_vel_min = presets_note_vel_min[preset_name] or -1
                local note_vel_max = presets_note_vel_max[preset_name] or -1
                if note_vel_min >= 0 and note_vel_max >= 0 then
                    write_vel = math.floor((note_vel_min + note_vel_max) / 2)
                end
                
                ks_pitch = presets_ks_pitch[preset_name] or -1
            end

            -- 1. Gather all selected notes and their properties from the take before making any modifications
            local selected_notes = {}
            local note_idx = -1
            while true do
                note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                if note_idx == -1 then break end
                local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
                if retval then
                    -- Ignore keyswitches from target notes collection
                    if not is_keyswitch_pitch(pitch) then
                        table.insert(selected_notes, {
                            idx = note_idx,
                            selected = selected,
                            muted = muted,
                            startppq = startppq,
                            endppq = endppq,
                            chan = chan,
                            pitch = pitch,
                            vel = vel
                        })
                    end
                end
            end

            -- 2. Collect indices of old keyswitches to delete, safely referencing the original take structure
            local deletions_map = {}
            if gui_state.write_keyswitches and preset_name ~= nil then
                local num_notes = reaper.MIDI_CountEvts(take)
                
                -- Build a map of target note indices to protect them from deletion
                local target_indices = {}
                for _, note_info in ipairs(selected_notes) do
                    target_indices[note_info.idx] = true
                end
                
                -- Build a list of candidate keyswitch notes in this take
                local ks_candidates = {}
                for idx = 0, num_notes - 1 do
                    local r, sel, mut, sppq, eppq, ch, pi, ve = reaper.MIDI_GetNote(take, idx)
                    if r and not target_indices[idx] and is_keyswitch_pitch(pi) then
                        table.insert(ks_candidates, {
                            idx = idx,
                            sppq = sppq,
                            chan = ch
                        })
                    end
                end
                
                for i, note_info in ipairs(selected_notes) do
                    local startppq = note_info.startppq
                    local chan = note_info.chan
                    
                    local target_info = gui_state.selected_targets[i]
                    local orig_ppq = target_info and target_info.original_ppq or startppq
                    local prev_ppq = target_info and reaper.MIDI_GetPPQPosFromProjTime(take, target_info.start_time + (target_info.offset_ms / 1000.0)) or orig_ppq
                    local new_ppq = target_info and reaper.MIDI_GetPPQPosFromProjTime(take, target_info.start_time + shift_sec) or startppq
                    
                    for _, cand in ipairs(ks_candidates) do
                        if cand.chan == chan then
                            local match = false
                            if math.abs(cand.sppq - math.max(0, orig_ppq - 30)) <= 10 then
                                match = true
                            elseif math.abs(cand.sppq - math.max(0, prev_ppq - 30)) <= 10 then
                                match = true
                            elseif math.abs(cand.sppq - math.max(0, new_ppq - 30)) <= 10 then
                                match = true
                            end
                            if match then
                                deletions_map[cand.idx] = true
                            end
                        end
                    end
                end
            end

            -- 3. Delete old keyswitches in descending index order first (while the take is still sorted)
            local deletions_list = {}
            for idx in pairs(deletions_map) do
                table.insert(deletions_list, idx)
            end
            table.sort(deletions_list, function(a, b) return a > b end)
            for _, idx in ipairs(deletions_list) do
                reaper.MIDI_DeleteNote(take, idx)
            end

            -- 4. Re-sort the take and re-gather selected notes so we have correct, stable indices for shifting
            reaper.MIDI_Sort(take)
            
            selected_notes = {}
            note_idx = -1
            while true do
                note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                if note_idx == -1 then break end
                local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
                if retval then
                    -- Ignore keyswitches from target notes collection
                    if not is_keyswitch_pitch(pitch) then
                        table.insert(selected_notes, {
                            idx = note_idx,
                            selected = selected,
                            muted = muted,
                            startppq = startppq,
                            endppq = endppq,
                            chan = chan,
                            pitch = pitch,
                            vel = vel
                        })
                    end
                end
            end

            -- 5. Modify the target notes' positions, queue new keyswitch insertions
            local insertions = {}
            for i, info in ipairs(gui_state.selected_targets) do
                local note_info = selected_notes[i]
                if not note_info then break end
                
                local new_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.start_time + shift_sec)
                local new_end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.end_time + shift_sec)
                
                reaper.MIDI_SetNote(
                    take,
                    note_info.idx,
                    nil,  -- selected
                    nil,  -- muted
                    new_start_ppq,
                    new_end_ppq,
                    nil,  -- chan
                    nil,  -- pitch
                    write_vel,  -- vel
                    true  -- noSort
                )
                
                if gui_state.write_keyswitches and preset_name and preset_name ~= "" and ks_pitch >= 0 then
                    -- Queue insertion of the new keyswitch at the new position (clamped to >= 0)
                    local target_ks_start = math.max(0, new_start_ppq - 30)
                    local target_ks_end = math.max(target_ks_start + 1, new_start_ppq - 10)
                    
                    -- Avoid duplicate insertions for the same channel, pitch, and position
                    local duplicate = false
                    for _, ins in ipairs(insertions) do
                        if ins.chan == note_info.chan and ins.pitch == ks_pitch and math.abs(ins.startppq - target_ks_start) < 2 then
                            duplicate = true
                            break
                        end
                    end
                    if not duplicate then
                        table.insert(insertions, {
                            chan = note_info.chan,
                            pitch = ks_pitch,
                            vel = ks_vel,
                            startppq = target_ks_start,
                            endppq = target_ks_end
                        })
                    end
                end
            end

            -- 6. Write MIDI Text Events
            if preset_name then
                for i, info in ipairs(gui_state.selected_targets) do
                    local note_info = selected_notes[i]
                    if not note_info then break end
                    local old_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.start_time + (info.offset_ms / 1000.0))
                    local new_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, info.start_time + shift_sec)
                    
                    -- Preset text event
                    write_note_preset_text_event(take, old_start_ppq, "")
                    if preset_name ~= "" then
                        write_note_preset_text_event(take, new_start_ppq, preset_name)
                    end
                    
                    -- Offset text event
                    write_note_offset_text_event(take, old_start_ppq, 0.0)
                    if math.abs(value) > 0.001 then
                        write_note_offset_text_event(take, new_start_ppq, value)
                    end
                end
            end
            
            -- 7. Insert new keyswitches
            for _, ins in ipairs(insertions) do
                reaper.MIDI_InsertNote(
                    take,
                    false, -- selected
                    false, -- muted
                    ins.startppq,
                    ins.endppq,
                    ins.chan,
                    ins.pitch,
                    ins.vel,
                    true -- noSort
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
                local old_pos = reaper.GetMediaItemInfo_Value(info.item, "D_POSITION")
                local length = reaper.GetMediaItemInfo_Value(info.item, "D_LENGTH")
                local new_pos = info.zero_position + shift_sec
                local delta = new_pos - old_pos
                
                if math.abs(delta) > 0.0001 then
                    if gui_state.move_envelopes then
                        -- 1. Track Envelopes (Points & Automation Items)
                        local track = reaper.GetMediaItem_Track(info.item)
                        if track then
                            local env_count = reaper.CountTrackEnvelopes(track)
                            for e = 0, env_count - 1 do
                                local env = reaper.GetTrackEnvelope(track, e)
                                if env then
                                    -- A. Move standard envelope points
                                    local pt_count = reaper.CountEnvelopePoints(env)
                                    for p = 0, pt_count - 1 do
                                        local retval, time, val, shape, tension, sel = reaper.GetEnvelopePoint(env, p)
                                        if retval and time >= old_pos and time <= (old_pos + length) then
                                            reaper.SetEnvelopePoint(env, p, time + delta, val, shape, tension, sel, true)
                                        end
                                    end
                                    
                                    -- B. Move Automation Items
                                    if reaper.CountAutomationItems then
                                        local ai_count = reaper.CountAutomationItems(env)
                                        for ai = 0, ai_count - 1 do
                                            local ai_pos = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
                                            if ai_pos >= old_pos and ai_pos <= (old_pos + length) then
                                                reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", ai_pos + delta, true)
                                            end
                                        end
                                    end
                                    
                                    reaper.Envelope_SortPoints(env)
                                end
                            end
                        end

                        -- 2. Take Envelopes (attached directly to takes within this item)
                        local take_count = reaper.CountTakes(info.item)
                        for t = 0, take_count - 1 do
                            local take = reaper.GetTake(info.item, t)
                            if take then
                                local take_env_count = reaper.CountTakeEnvelopes(take)
                                for e = 0, take_env_count - 1 do
                                    local env = reaper.GetTakeEnvelope(take, e)
                                    if env then
                                        local pt_count = reaper.CountEnvelopePoints(env)
                                        for p = 0, pt_count - 1 do
                                            local retval, time, val, shape, tension, sel = reaper.GetEnvelopePoint(env, p)
                                            if retval then
                                                -- Take envelope point times are relative to take source time, but let's shift them
                                                reaper.SetEnvelopePoint(env, p, time + delta, val, shape, tension, sel, true)
                                            end
                                        end
                                        reaper.Envelope_SortPoints(env)
                                    end
                                end
                            end
                        end
                    end

                    -- 3. Shift the Media Item itself
                    reaper.SetMediaItemInfo_Value(info.item, "D_POSITION", new_pos)
                    reaper.UpdateItemInProject(info.item)
                end
            end
        end
    end
    reaper.UpdateArrange()
end

-- Helper to set absolute offset value (with undo registration)
local function adjust_offset_to_value(target_ms, preset_name)
    if #gui_state.selected_targets == 0 then return end
    
    -- Determine active preset first so we can apply the correct keyswitches/triggers
    local active_preset = ""
    if preset_name and preset_name ~= "" then
        active_preset = preset_name
    elseif combo_preset_name ~= "" and presets[combo_preset_name] ~= nil then
        if math.abs(presets[combo_preset_name] - target_ms) < 0.01 then
            active_preset = combo_preset_name
        end
    end
    
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
    apply_offset_to_targets(target_ms, active_preset)
    
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
    save_preset_name_to_targets(active_preset)
    reaper.Undo_EndBlock2(0, undo_msg, -1)
    
    current_preset_name = active_preset
    combo_preset_name = active_preset
    if active_preset ~= "" then
        local lib, instr, art = split_preset_name(active_preset)
        if lib ~= "" then
            gui_state.selected_library = lib
        end
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
    local themes = {
        theme_bg          = theme_bg,
        theme_accent      = theme_accent,
        theme_text        = theme_text,
        theme_frame_bg    = theme_frame_bg,
        theme_slider_grab = theme_slider_grab,
        theme_check_mark  = theme_check_mark
    }
    theme_manager.push_theme(ctx, themes)
end

-- Pop Theme Styles & Colors
local function pop_theme()
    theme_manager.pop_theme(ctx)
end

-- Push/pop helpers for semantically-colored buttons (override the theme defaults)
local function push_danger_style()
    local themes = { theme_danger = theme_danger }
    theme_manager.push_danger_style(ctx, themes)
end
local function pop_danger_style()
    theme_manager.pop_danger_style(ctx)
end

local function push_positive_style()
    local themes = { theme_positive = theme_positive }
    theme_manager.push_positive_style(ctx, themes)
end
local function pop_positive_style()
    theme_manager.pop_positive_style(ctx)
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
    local mode_changed = ui_renderer.draw_mode_selector(ctx, gui_state, has_notes)
    
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
    local presets_state_dropdown = {
        presets = presets,
        preset_keys = preset_keys,
        presets_show_in_grid = presets_show_in_grid,
        presets_ks_pitch = presets_ks_pitch,
        presets_note_vel_min = presets_note_vel_min,
        presets_note_vel_max = presets_note_vel_max,
        current_preset_name = current_preset_name,
        combo_preset_name = combo_preset_name
    }
    local modal_state_dropdown = {
        new_preset_lib_input = new_preset_lib_input,
        new_preset_instr_input = new_preset_instr_input,
        new_preset_art_input = new_preset_art_input,
        new_preset_show_in_grid = new_preset_show_in_grid,
        open_new_preset_modal = open_new_preset_modal,
        open_new_preset_focus = open_new_preset_focus,
        open_rename_preset_modal = open_rename_preset_modal,
        open_rename_preset_focus = open_rename_preset_focus,
        open_delete_preset_modal = open_delete_preset_modal
    }
    ui_presets_dropdown.draw_presets_dropdown(
        ctx,
        gui_state,
        presets_state_dropdown,
        modal_state_dropdown,
        {
            save_presets = save_presets,
            load_presets = load_presets,
            adjust_offset_to_value = adjust_offset_to_value,
            split_preset_name = split_preset_name
        }
    )
    new_preset_lib_input = modal_state_dropdown.new_preset_lib_input
    new_preset_instr_input = modal_state_dropdown.new_preset_instr_input
    new_preset_art_input = modal_state_dropdown.new_preset_art_input
    new_preset_show_in_grid = modal_state_dropdown.new_preset_show_in_grid
    open_new_preset_modal = modal_state_dropdown.open_new_preset_modal
    open_new_preset_focus = modal_state_dropdown.open_new_preset_focus
    open_rename_preset_modal = modal_state_dropdown.open_rename_preset_modal
    open_rename_preset_focus = modal_state_dropdown.open_rename_preset_focus
    open_delete_preset_modal = modal_state_dropdown.open_delete_preset_modal

    presets = presets_state_dropdown.presets
    preset_keys = presets_state_dropdown.preset_keys
    presets_show_in_grid = presets_state_dropdown.presets_show_in_grid
    presets_ks_pitch = presets_state_dropdown.presets_ks_pitch
    presets_note_vel_min = presets_state_dropdown.presets_note_vel_min
    presets_note_vel_max = presets_state_dropdown.presets_note_vel_max
    current_preset_name = presets_state_dropdown.current_preset_name
    combo_preset_name = presets_state_dropdown.combo_preset_name

    -- Modals rendering
    local modal_state = {
        open_new = open_new_preset_modal,
        focus_new = open_new_preset_focus,
        new_lib = new_preset_lib_input,
        new_instr = new_preset_instr_input,
        new_art = new_preset_art_input,
        new_show_grid = new_preset_show_in_grid,

        open_rename = open_rename_preset_modal,
        focus_rename = open_rename_preset_focus,
        rename_lib = rename_preset_lib_input,
        rename_instr = rename_preset_instr_input,
        rename_art = rename_preset_art_input,
        rename_show_grid = rename_preset_show_in_grid,

        open_delete = open_delete_preset_modal,
    }
    local presets_state = {
        presets = presets,
        preset_keys = preset_keys,
        presets_show_in_grid = presets_show_in_grid,
        presets_ks_pitch = presets_ks_pitch,
        presets_note_vel_min = presets_note_vel_min,
        presets_note_vel_max = presets_note_vel_max,
        current_preset_name = current_preset_name,
        combo_preset_name = combo_preset_name
    }
    ui_modals.draw_modals(
        ctx,
        modal_state,
        gui_state,
        presets_state,
        {
            save_presets = save_presets,
            load_presets = load_presets,
            save_preset_name_to_targets = save_preset_name_to_targets,
            split_preset_name = split_preset_name,
            join_preset_name = join_preset_name
        }
    )
    open_new_preset_modal = modal_state.open_new
    open_new_preset_focus = modal_state.focus_new
    new_preset_lib_input = modal_state.new_lib
    new_preset_instr_input = modal_state.new_instr
    new_preset_art_input = modal_state.new_art
    new_preset_show_in_grid = modal_state.new_show_grid

    open_rename_preset_modal = modal_state.open_rename
    open_rename_preset_focus = modal_state.focus_rename
    rename_preset_lib_input = modal_state.rename_lib
    rename_preset_instr_input = modal_state.rename_instr
    rename_preset_art_input = modal_state.rename_art
    rename_preset_show_in_grid = modal_state.rename_show_grid

    open_delete_preset_modal = modal_state.open_delete

    presets = presets_state.presets
    preset_keys = presets_state.preset_keys
    presets_show_in_grid = presets_state.presets_show_in_grid
    presets_ks_pitch = presets_state.presets_ks_pitch
    presets_note_vel_min = presets_state.presets_note_vel_min
    presets_note_vel_max = presets_state.presets_note_vel_max
    current_preset_name = presets_state.current_preset_name
    combo_preset_name = presets_state.combo_preset_name

    -- Trigger Editor Panel (hidden from UI)
    --[[
    local presets_state_te = {
        presets = presets,
        presets_show_in_grid = presets_show_in_grid,
        presets_ks_pitch = presets_ks_pitch,
        presets_note_vel_min = presets_note_vel_min,
        presets_note_vel_max = presets_note_vel_max
    }
    ui_trigger_editor.draw_trigger_editor(
        ctx,
        combo_preset_name,
        presets_state_te,
        {
            save_presets = save_presets
        }
    )
    presets_ks_pitch = presets_state_te.presets_ks_pitch
    presets_note_vel_min = presets_state_te.presets_note_vel_min
    presets_note_vel_max = presets_state_te.presets_note_vel_max
    ]]

    -- Write Keyswitches has been moved to Settings

    -- Double-click / Drag slider for absolute offset (displaying current value) and manual input box side by side
    local is_slider_deactivated
    show_info, show_settings, is_slider_deactivated = ui_renderer.draw_offset_slider(
        ctx,
        gui_state,
        FIXED_RANGE,
        {
            apply_offset_to_targets = function(val)
                apply_offset_to_targets(val)
                current_preset_name = "" -- clear committed association, but keep combo selection for Save
            end,
            get_effective_mode = get_effective_mode,
            adjust_offset_to_value = function(val)
                adjust_offset_to_value(val)
            end,
            on_input_changed = function(val)
                current_preset_name = "" -- clear committed association, but keep combo selection for Save
            end
        },
        theme_apply_btn,
        show_info,
        show_settings
    )
    if show_settings then
        -- Snapshot current theme as uint32 (one-time float→u32, no further round-trip)
        settings_edit_bg_u32          = theme_pack(theme_bg)
        settings_edit_accent_u32      = theme_pack(theme_accent)
        settings_edit_text_u32        = theme_pack(theme_text)
        settings_edit_danger_u32      = theme_pack(theme_danger)
        settings_edit_positive_u32    = theme_pack(theme_positive)
        settings_edit_slider_grab_u32 = theme_pack(theme_slider_grab)
        settings_edit_apply_btn_u32   = theme_pack(theme_apply_btn)
        settings_edit_frame_bg_u32    = theme_pack(theme_frame_bg)
        settings_edit_check_mark_u32  = theme_pack(theme_check_mark)
        settings_edit_inactive_btn_u32 = theme_pack(theme_inactive_btn)
        settings_edit_inactive_btn_text_u32 = theme_pack(theme_inactive_btn_text)
        settings_edit_active_btn_u32  = theme_pack(theme_active_btn)
    end

    if is_slider_deactivated then
        if #gui_state.selected_targets > 0 then
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
                        local old_pos = reaper.GetMediaItemInfo_Value(info.item, "D_POSITION")
                        local length = reaper.GetMediaItemInfo_Value(info.item, "D_LENGTH")
                        local new_pos = info.baseline_offset
                        local delta = new_pos - old_pos
                        
                        if math.abs(delta) > 0.0001 then
                            if gui_state.move_envelopes then
                                -- Restore Track Envelopes
                                local track = reaper.GetMediaItem_Track(info.item)
                                if track then
                                    local env_count = reaper.CountTrackEnvelopes(track)
                                    for e = 0, env_count - 1 do
                                        local env = reaper.GetTrackEnvelope(track, e)
                                        if env then
                                            local pt_count = reaper.CountEnvelopePoints(env)
                                            for p = 0, pt_count - 1 do
                                                local retval, time, val, shape, tension, sel = reaper.GetEnvelopePoint(env, p)
                                                if retval and time >= old_pos and time <= (old_pos + length) then
                                                    reaper.SetEnvelopePoint(env, p, time + delta, val, shape, tension, sel, true)
                                                end
                                            end
                                            if reaper.CountAutomationItems then
                                                local ai_count = reaper.CountAutomationItems(env)
                                                for ai = 0, ai_count - 1 do
                                                    local ai_pos = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
                                                    if ai_pos >= old_pos and ai_pos <= (old_pos + length) then
                                                        reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", ai_pos + delta, true)
                                                    end
                                                end
                                            end
                                            reaper.Envelope_SortPoints(env)
                                        end
                                    end
                                end

                                -- Restore Take Envelopes
                                local take_count = reaper.CountTakes(info.item)
                                for t = 0, take_count - 1 do
                                    local take = reaper.GetTake(info.item, t)
                                    if take then
                                        local take_env_count = reaper.CountTakeEnvelopes(take)
                                        for e = 0, take_env_count - 1 do
                                            local env = reaper.GetTakeEnvelope(take, e)
                                            if env then
                                                local pt_count = reaper.CountEnvelopePoints(env)
                                                for p = 0, pt_count - 1 do
                                                    local retval, time, val, shape, tension, sel = reaper.GetEnvelopePoint(env, p)
                                                    if retval then
                                                        reaper.SetEnvelopePoint(env, p, time + delta, val, shape, tension, sel, true)
                                                    end
                                                end
                                                reaper.Envelope_SortPoints(env)
                                            end
                                        end
                                    end
                                end
                            end

                            -- Restore Media Item Position
                            reaper.SetMediaItemInfo_Value(info.item, "D_POSITION", new_pos)
                            reaper.UpdateItemInProject(info.item)
                        end
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
            
            local active_preset = ""
            if current_preset_name ~= "" and presets[current_preset_name] ~= nil then
                if math.abs(presets[current_preset_name] - gui_state.slider_value) < 0.01 then
                    active_preset = current_preset_name
                end
            end
            -- If user has a preset selected in the dropdown (but dragged to a new value),
            -- still associate it so "Save" afterwards can overwrite the preset value.
            if active_preset == "" and combo_preset_name ~= "" and presets[combo_preset_name] ~= nil then
                active_preset = combo_preset_name
            end

            reaper.Undo_BeginBlock2(0)
            apply_offset_to_targets(gui_state.slider_value, active_preset)
            
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
            
            save_preset_name_to_targets(active_preset)
            reaper.Undo_EndBlock2(0, undo_msg, -1)
        end
        
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
    push_danger_style()
    if reaper.ImGui_Button(ctx, "Reset 0", button_width, button_height) then
        reset_offsets_to_zero()
    end
    pop_danger_style()
    
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
        local track, take = get_current_context_track_and_take()
        local eff_mode = get_effective_mode()
        local has_notes, active_take = has_selected_midi_notes()
        local modes_struct = {
            MODE_TRACK_OFFSET = MODE_TRACK_OFFSET,
            MODE_TAKE_OFFSET = MODE_TAKE_OFFSET,
            MODE_ITEM_POSITION = MODE_ITEM_POSITION,
            MODE_MIDI_NOTES = MODE_MIDI_NOTES
        }
        ui_info_panel.draw_info_panel(
            ctx,
            gui_state,
            num_targets,
            eff_mode,
            track,
            take,
            has_notes,
            active_take,
            modes_struct
        )
    end

    -- Preset Board (2-Row wrapped buttons)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Right-aligned checkbox "Move envelopes with item" when MODE_ITEM_POSITION is active,
    -- placed vertically between the Preset Board and the Offset controls/slider, below the separator.
    if gui_state.adjust_mode == MODE_ITEM_POSITION then
        local has_notes, _ = has_selected_midi_notes()
        local label = "Move envelopes with item"
        local checkbox_w = 20 -- Typical checkbox square size
        local pad_x, _ = reaper.ImGui_GetStyleVar(ctx, imgui.StyleVar_FramePadding)
        local item_spacing_x, _ = reaper.ImGui_GetStyleVar(ctx, imgui.StyleVar_ItemSpacing)
        local text_w, _ = reaper.ImGui_CalcTextSize(ctx, label)
        local total_w = checkbox_w + item_spacing_x + text_w + pad_x * 2
        
        local avail_w, _ = reaper.ImGui_GetContentRegionAvail(ctx)
        if avail_w > total_w then
            reaper.ImGui_SameLine(ctx, avail_w - total_w + pad_x * 2)
        end
        
        reaper.ImGui_BeginDisabled(ctx, has_notes)
        local changed_env, new_env = reaper.ImGui_Checkbox(ctx, label, gui_state.move_envelopes == true)
        if changed_env then
            gui_state.move_envelopes = new_env
            -- Synchronize with REAPER's global setting
            local reaper_state = (reaper.GetToggleCommandState(40070) == 1)
            if reaper_state ~= new_env then
                reaper.Main_OnCommand(40070, 0) -- Toggle "Options: Move envelopes with items"
            end
        end
        reaper.ImGui_EndDisabled(ctx)
        reaper.ImGui_Spacing(ctx)
    end
    
    current_preset_name = ui_renderer.draw_preset_board(
        ctx,
        gui_state,
        preset_keys,
        presets_show_in_grid,
        presets,
        theme_accent,
        theme_bg,
        theme_inactive_btn,
        theme_inactive_btn_text,
        theme_active_btn,
        current_preset_name,
        function(offset, name)
            adjust_offset_to_value(offset, name)
        end,
        presets_lib_order,
        presets_instr_order,
        presets_art_order,
        function()
            save_presets(presets, presets_show_in_grid)
        end
    )
end

-- Key shortcuts
local function handle_keyboard_shortcuts()
    ui_shortcuts.handle_shortcuts(ctx, {
        undo = function()
            reaper.Undo_DoUndo2(0)
            update_targets_list(true)
        end,
        redo = function()
            reaper.Undo_DoRedo2(0)
            update_targets_list(true)
        end,
        exit = function()
            script_running = false
        end
    })
end

-- Main Loop
local function loop()
    if not script_running then
        return
    end

    frame_counter = frame_counter + 1

    -- Selection management
    update_targets_list()

    -- Synchronize move_envelopes state from REAPER's native option if not dragging/editing
    if not gui_state.is_dragging then
        gui_state.move_envelopes = (reaper.GetToggleCommandState(40070) == 1)
    end

    -- Set size constraints
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 460, 150, 800, 800)

    -- Set window style/colors
    push_theme()

    local window_flags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost | (imgui.WindowFlags_AlwaysAutoResize or 0)
    local visible, open = reaper.ImGui_Begin(ctx, script_name, true, window_flags)
    
    if not open then
        script_running = false
    end

    local is_main_focused = false
    if visible and script_running then
        is_main_focused = reaper.ImGui_IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
        if focus_main_next_frame then
            reaper.ImGui_SetWindowFocus(ctx)
            is_main_focused = true
            focus_main_next_frame = false
        end
        handle_keyboard_shortcuts()
        render_ui()
    end

    reaper.ImGui_End(ctx)

    local is_settings_focused = false
    if show_settings and script_running then
        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 350, 200, 600, 800)
        local settings_visible, settings_open = reaper.ImGui_Begin(
            ctx,
            "Settings##MediaOffsetTool",
            true,
            imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost | imgui.WindowFlags_NoDocking | (imgui.WindowFlags_AlwaysAutoResize or 0)
        )
        local panel_open = true
        if settings_visible then
            is_settings_focused = reaper.ImGui_IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
            
            local defaults = {
                bg = DEFAULT_BG,
                accent = DEFAULT_ACCENT,
                text = DEFAULT_TEXT,
                danger = DEFAULT_DANGER,
                positive = DEFAULT_POSITIVE,
                slider_grab = DEFAULT_SLIDER_GRAB,
                apply_btn = DEFAULT_APPLY_BTN,
                frame_bg = DEFAULT_FRAME_BG,
                check_mark = DEFAULT_CHECK_MARK,
                inactive_btn = DEFAULT_INACTIVE_BTN,
                inactive_btn_text = DEFAULT_INACTIVE_BTN_TEXT,
                active_btn = DEFAULT_ACTIVE_BTN
            }
            local theme_state = {
                bg_u32 = settings_edit_bg_u32,
                accent_u32 = settings_edit_accent_u32,
                text_u32 = settings_edit_text_u32,
                danger_u32 = settings_edit_danger_u32,
                positive_u32 = settings_edit_positive_u32,
                slider_grab_u32 = settings_edit_slider_grab_u32,
                apply_btn_u32 = settings_edit_apply_btn_u32,
                frame_bg_u32 = settings_edit_frame_bg_u32,
                check_mark_u32 = settings_edit_check_mark_u32,
                inactive_btn_u32 = settings_edit_inactive_btn_u32,
                inactive_btn_text_u32 = settings_edit_inactive_btn_text_u32,
                active_btn_u32 = settings_edit_active_btn_u32,

                theme_bg = theme_bg,
                theme_accent = theme_accent,
                theme_text = theme_text,
                theme_danger = theme_danger,
                theme_positive = theme_positive,
                theme_slider_grab = theme_slider_grab,
                theme_apply_btn = theme_apply_btn,
                theme_frame_bg = theme_frame_bg,
                theme_check_mark = theme_check_mark,
                theme_inactive_btn = theme_inactive_btn,
                theme_inactive_btn_text = theme_inactive_btn_text,
                theme_active_btn = theme_active_btn
            }
            
            panel_open = ui_settings.draw_settings_panel(
                ctx,
                gui_state,
                theme_state,
                defaults,
                {
                    save_settings = save_settings,
                    update_targets_list = update_targets_list
                }
            )
            
            settings_edit_bg_u32 = theme_state.bg_u32
            settings_edit_accent_u32 = theme_state.accent_u32
            settings_edit_text_u32 = theme_state.text_u32
            settings_edit_danger_u32 = theme_state.danger_u32
            settings_edit_positive_u32 = theme_state.positive_u32
            settings_edit_slider_grab_u32 = theme_state.slider_grab_u32
            settings_edit_apply_btn_u32 = theme_state.apply_btn_u32
            settings_edit_frame_bg_u32 = theme_state.frame_bg_u32
            settings_edit_check_mark_u32 = theme_state.check_mark_u32
            settings_edit_inactive_btn_u32 = theme_state.inactive_btn_u32
            settings_edit_inactive_btn_text_u32 = theme_state.inactive_btn_text_u32
            settings_edit_active_btn_u32 = theme_state.active_btn_u32

            theme_bg = theme_state.theme_bg
            theme_accent = theme_state.theme_accent
            theme_text = theme_state.theme_text
            theme_danger = theme_state.theme_danger
            theme_positive = theme_state.theme_positive
            theme_slider_grab = theme_state.theme_slider_grab
            theme_apply_btn = theme_state.theme_apply_btn
            theme_frame_bg = theme_state.theme_frame_bg
            theme_check_mark = theme_state.theme_check_mark
            theme_inactive_btn = theme_state.theme_inactive_btn
            theme_inactive_btn_text = theme_state.theme_inactive_btn_text
            theme_active_btn = theme_state.theme_active_btn
            
        end
        reaper.ImGui_End(ctx)
        if not settings_open or not panel_open then
            show_settings = false
        end
    end

    -- Bring window to front if it loses focus to keep it topmost
    if visible and script_running then
        local any_focused = is_main_focused or (show_settings and is_settings_focused)
        if not any_focused then
            focus_main_next_frame = true
        end
    end

    pop_theme()

    if script_running then
        reaper.defer(loop)
    else
        -- Clean up toggle state on exit
        if section_id and cmd_id and section_id ~= -1 and cmd_id ~= -1 then
            reaper.SetToggleCommandState(section_id, cmd_id, 0)
            reaper.RefreshToolbar2(section_id, cmd_id)
        end
    end
end

-- Init
reaper.defer(loop)
