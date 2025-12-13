-- @description Legato Tool - Creating legato effects and stuff 
-- @author drvlat
-- @version 0.1.2
-- @provides [main=midi_editor,midi_inlineeditor,midi_eventlisteditor] .
-- @about
--   This is a ReaScript for REAPER that provides tools for creating legato effects in MIDI.
--   It extends MIDI notes to create legato effects, detects and handles note overlays,
--   and fills gaps between notes.
--
--   The tool provides a user interface for adjusting settings and applying legato effects
--   to selected MIDI notes in the MIDI editor.

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
local script_name = "Legato Tool"
local ctx = imgui.CreateContext(script_name)
local script_running = true
local take = nil
local last_clicked_cc_lane = -1  -- This will be repurposed for general MIDI context
local selected_note_count = 0
local overlay_count = 0  -- For tracking overlay count
local legato_amount = 0 -- Current legato amount in milliseconds (0-400ms)
local drag_start_legato_amount = 0 -- Legato amount at the start of dragging
local drag_start_note_states = {} -- Store the note states at drag start for delta calculations
local keep_within_boundaries = false -- Flag to keep notes within media item boundaries
local humanize_strength = 0 -- Strength of humanization effect (0-100)
local notes_cache_valid = false
local notes_cache = {}  -- Cache for selected notes
local last_selected_note_indices = {} -- Store indices of selected notes to detect changes

-- Function to get current MIDI context consistently
function get_midi_context()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil, nil end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then return nil, nil end

    return current_take, midi_editor
end

-- Helper function to get the active MIDI take
function get_active_take()
    local current_take, midi_editor = get_midi_context()
    return current_take
end

-- Function to count selected notes in the current take
function count_selected_notes()
    local current_take, midi_editor = get_midi_context()

    if not current_take then
        return 0
    end

    local note_count = 0
    local note_index = -1
    local safety_counter = 0
    local max_notes = 10000  -- Safety limit to prevent infinite loops

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end
        note_count = note_count + 1
        safety_counter = safety_counter + 1
    end

    return note_count
end

-- Function to build notes cache with original values preserved
function build_notes_cache()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return {} end

    local notes = {}
    local note_index = -1
    local safety_counter = 0
    local max_notes = 10000  -- Safety limit to prevent infinite loops

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end

        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
        if not retval then
            -- Error retrieving note - skip this note
            reaper.MB("Error retrieving MIDI note at index " .. note_index, "Legato Tool Error", 0)
            break  -- Stop processing and return partial results
        end

        table.insert(notes, {
            index = note_index,
            selected = selected,
            muted = muted,
            startppqpos = startppqpos,
            endppqpos = endppqpos,  -- Current end position
            original_endppqpos = endppqpos,  -- Baseline end position when cache was created
            chan = chan,
            pitch = pitch,
            vel = vel
        })

        safety_counter = safety_counter + 1
    end

    -- Sort notes by start position
    table.sort(notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    return notes
end

-- Function to get selected notes with their properties
function get_selected_notes()
    local current_take, midi_editor = get_midi_context()

    if not current_take then
        return {}
    end

    local notes = {}
    local note_index = -1
    local safety_counter = 0
    local max_notes = 10000  -- Safety limit to prevent infinite loops

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end

        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
        if not retval then
            -- Error retrieving note - skip this note
            reaper.MB("Error retrieving MIDI note at index " .. note_index, "Legato Tool Error", 0)
            break  -- Stop processing and return partial results
        end

        table.insert(notes, {
            index = note_index,
            selected = selected,
            muted = muted,
            startppqpos = startppqpos,
            endppqpos = endppqpos,
            chan = chan,
            pitch = pitch,
            vel = vel
        })

        safety_counter = safety_counter + 1
    end

    -- Sort notes by start position
    table.sort(notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    return notes
end

-- Function to get media item boundaries in PPQ for the given take
function get_item_boundaries_in_ppq(take)
    if not take then return 0, math.huge end  -- Return a reasonable range if no take

    -- Get the media item that contains the take
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return 0, math.huge end

    -- Get item position and length in project time
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if item_pos == nil or item_pos == -1 or item_len == nil or item_len == -1 then
        -- Error getting item info
        reaper.MB("Error getting media item info", "Legato Tool Error", 0)
        return 0, math.huge
    end

    local item_end = item_pos + item_len

    -- Convert to PPQ relative to the take - check for valid conversion
    local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_pos)
    if start_ppq == nil or start_ppq == -1 then
        reaper.MB("Error converting start time to PPQ", "Legato Tool Error", 0)
        return 0, math.huge
    end

    local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_end)
    if end_ppq == nil or end_ppq == -1 then
        reaper.MB("Error converting end time to PPQ", "Legato Tool Error", 0)
        return 0, math.huge
    end

    return start_ppq, end_ppq
end

-- Function to get current selected note indices
function get_current_selected_note_info()
    local current_take, midi_editor = get_midi_context()
    if not current_take then return {} end

    local selected_indices = {}
    local note_index = -1
    local safety_counter = 0
    local max_notes = 10000  -- Safety limit to prevent infinite loops

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end
        table.insert(selected_indices, note_index)
        safety_counter = safety_counter + 1
    end

    return selected_indices
end

-- Function to check if MIDI selection has changed
function midi_selection_changed()
    local current_selection = get_current_selected_note_info()
    local last_selection = last_selected_note_indices

    -- Compare lengths first
    if #current_selection ~= #last_selection then
        last_selected_note_indices = current_selection
        return true
    end

    -- Compare individual indices
    for i = 1, #current_selection do
        if current_selection[i] ~= last_selection[i] then
            last_selected_note_indices = current_selection
            return true
        end
    end

    -- No change detected
    return false
end

-- Function to restore notes to their original state
function restore_original_notes(cache)
    local current_take, midi_editor = get_midi_context()

    if not current_take or not cache then return end

    for _, note in ipairs(cache) do
        -- Restore to original end position
        local result = reaper.MIDI_SetNote(
            current_take,
            note.index,
            nil,  -- selected
            nil,  -- muted
            nil,  -- startppqpos (keep current)
            note.original_endppqpos,  -- Restore original end position
            nil,  -- chan
            nil,  -- pitch
            nil,  -- vel
            true   -- take
        )

        if not result then
            reaper.MB("Error restoring MIDI note at index " .. note.index, "Legato Tool Error", 0)
            -- Continue with other notes even if one fails
        end
    end

    reaper.UpdateArrange()
end

-- Function to detect note overlays (selected notes with the same pitch that have overlapping time ranges)
function detect_overlays()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    -- Get selected notes only
    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Sort selected notes by start position
    table.sort(selected_notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    -- Find overlapping notes of the same pitch
    local overlay_indices = {}
    for i, note1 in ipairs(selected_notes) do
        for j = i + 1, #selected_notes do
            local note2 = selected_notes[j]

            -- Stop checking if note2 starts after note1 ends (notes are sorted by start time)
            if note2.startppqpos >= note1.endppqpos then
                break
            end

            -- Check if notes have the same pitch and actually overlap in time
            if note1.pitch == note2.pitch and note1.endppqpos > note2.startppqpos then
                -- This is an overlay - mark both notes for selection
                if not table_contains(overlay_indices, note1.index) then
                    table.insert(overlay_indices, note1.index)
                end
                if not table_contains(overlay_indices, note2.index) then
                    table.insert(overlay_indices, note2.index)
                end
            end
        end
    end

    -- Only update selection if overlays were found
    if #overlay_indices > 0 then
        -- Deselect all selected notes first
        for _, note in ipairs(selected_notes) do
            reaper.MIDI_SetNote(current_take, note.index, false, nil, nil, nil, nil, nil, nil, true)  -- deselect only
        end

        -- Select only the overlay notes
        for _, overlay_index in ipairs(overlay_indices) do
            reaper.MIDI_SetNote(current_take, overlay_index, true, nil, nil, nil, nil, nil, nil, true)  -- select only
        end
    end  -- If no overlays found, keep original selection unchanged

    reaper.UpdateArrange()
    return #overlay_indices
end

-- Helper function to check if a table contains a value
function table_contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- Function to heal note overlays by adjusting note positions so that first note ends before second note starts
function heal_overlays()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    -- Get selected notes only
    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Sort selected notes by start position
    table.sort(selected_notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    -- Find overlapping notes of the same pitch and resolve the overlays
    local resolved_count = 0
    for i, note1 in ipairs(selected_notes) do
        for j = i + 1, #selected_notes do
            local note2 = selected_notes[j]

            -- Stop checking if note2 starts after note1 ends (notes are sorted by start time)
            if note2.startppqpos >= note1.endppqpos then
                break
            end

            -- Check if notes have the same pitch and actually overlap in time
            if note1.pitch == note2.pitch and note1.endppqpos > note2.startppqpos then
                -- This is an overlay - adjust the first note to end just before the second note starts
                -- Ensure note doesn't end before it starts
                local new_end_pos = note2.startppqpos

                if new_end_pos > note1.startppqpos then
                    -- Apply the adjustment to the first note
                    local result = reaper.MIDI_SetNote(
                        current_take,
                        note1.index,
                        nil,  -- selected (keep current)
                        nil,  -- muted (keep current)
                        nil,  -- startppqpos (keep current)
                        new_end_pos,  -- new end position
                        nil,  -- chan (keep current)
                        nil,  -- pitch (keep current)
                        nil,  -- vel (keep current)
                        true   -- noSort (do sort after all changes)
                    )

                    if result then
                        resolved_count = resolved_count + 1
                    end
                end
            end
        end
    end

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()

    return resolved_count
end

-- Function to count note overlays (selected notes with the same pitch that have overlapping time ranges) without changing selection
function detect_overlays_count(current_take)
    if not current_take then return 0 end

    -- Get the current MIDI context to get selected notes
    local _, _ = get_midi_context()

    -- Get selected notes only
    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Sort selected notes by start position
    table.sort(selected_notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    -- Find overlapping notes of the same pitch
    local overlay_indices = {}
    for i, note1 in ipairs(selected_notes) do
        for j = i + 1, #selected_notes do
            local note2 = selected_notes[j]

            -- Stop checking if note2 starts after note1 ends (notes are sorted by start time)
            if note2.startppqpos >= note1.endppqpos then
                break
            end

            -- Check if notes have the same pitch and actually overlap in time
            if note1.pitch == note2.pitch and note1.endppqpos > note2.startppqpos then
                -- This is an overlay - mark both notes for counting
                if not table_contains(overlay_indices, note1.index) then
                    table.insert(overlay_indices, note1.index)
                end
                if not table_contains(overlay_indices, note2.index) then
                    table.insert(overlay_indices, note2.index)
                end
            end
        end
    end

    return #overlay_indices
end

-- Function to select all notes in the current take
function select_all_notes()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    reaper.Undo_BeginBlock()

    local note_count = reaper.MIDI_CountEvts(current_take, nil, nil, nil)
    local changes = 0

    -- Deselect all currently selected notes first
    for i = 0, note_count - 1 do
        local _, selected = reaper.MIDI_GetNote(current_take, i)
        if selected then
            reaper.MIDI_SetNote(current_take, i, false, nil, nil, nil, nil, nil, nil, true)
        end
    end

    -- Select all notes
    for i = 0, note_count - 1 do
        reaper.MIDI_SetNote(current_take, i, true, nil, nil, nil, nil, nil, nil, true)
        changes = changes + 1
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Select all notes in take", -1)

    return changes
end

-- Function to fill gaps between selected notes
function fill_gaps()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return end

    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes to fill gaps
    end

    -- Sort notes by start position (in case they're not already sorted)
    table.sort(selected_notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    -- Process each note to extend to the next note's start
    for i, note in ipairs(selected_notes) do
        -- Find the next note that starts after this note
        local next_note_start = nil
        for j = i + 1, #selected_notes do
            if selected_notes[j].startppqpos > note.startppqpos then
                next_note_start = selected_notes[j].startppqpos
                break
            end
        end

        if next_note_start and next_note_start > note.endppqpos then
            -- Check for same pitch overlap prevention
            local new_end_ppq = next_note_start

            -- Same pitch overlap prevention
            for _, potential_next_note in ipairs(selected_notes) do
                if note.pitch == potential_next_note.pitch and
                   potential_next_note.startppqpos > note.startppqpos and
                   potential_next_note.startppqpos < new_end_ppq then
                    new_end_ppq = math.min(new_end_ppq, potential_next_note.startppqpos)
                end
            end

            -- Keep within item boundaries if checkbox is enabled
            if keep_within_boundaries then
                local item_start_ppq, item_end_ppq = get_item_boundaries_in_ppq(current_take)
                new_end_ppq = math.min(new_end_ppq, item_end_ppq)
            end

            -- Make sure the new end position is not before the start position
            if new_end_ppq > note.startppqpos then
                local result = reaper.MIDI_SetNote(current_take, note.index, nil, nil, note.startppqpos, new_end_ppq, nil, nil, nil, true)
                if not result then
                    reaper.MB("Error setting MIDI note at index " .. note.index, "Legato Tool Error", 0)
                    return  -- Stop processing this note
                end
            end
        end
    end

    reaper.UpdateArrange()
end


-- Function to apply legato to selected notes using delta from baseline state
function apply_legato(cache)
    local current_take, midi_editor = get_midi_context()

    if not current_take then return end

    local selected_notes = cache or get_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes for legato
    end

    -- Get project tempo at the MIDI item's location to convert milliseconds to PPQ
    -- Use time-based tempo function to handle projects with tempo changes
    local tempo = reaper.Master_GetTempo()  -- Default to master tempo

    local item = reaper.GetMediaItemTake_Item(current_take)
    if item then
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if item_pos and item_pos ~= -1 then
            local item_tempo = reaper.TimeMap2_GetDividedBpmAtTime(0, item_pos) -- Use current project (0) and item position
            if item_tempo and item_tempo > 0 then
                tempo = item_tempo
            end
        end
    end

    -- Validate tempo value
    if not tempo or tempo <= 0 then
        tempo = 120.0  -- Default to 120 BPM if all methods fail
    end

    -- Convert milliseconds to PPQ (pulses per quarter note)
    -- Standard MIDI timebase is 480 PPQ at 120 BPM
    -- 1 ms = (tempo/60) * (480/1000) PPQ
    local ms_to_ppq = function(ms)
        if not ms or ms < 0 then
            return 0
        end
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Calculate the delta from the drag start value
    local delta_ms = legato_amount - drag_start_legato_amount
    local delta_ppq = ms_to_ppq(delta_ms)

    -- Apply the delta to the baseline state from when dragging started
    for i, note in ipairs(selected_notes) do
        local next_note = nil
        if i < #selected_notes then
            next_note = selected_notes[i + 1]
        end

        -- Get the baseline end position from the cache (state when dragging started)
        local baseline_end_pos
        if cache and note.original_endppqpos then
            baseline_end_pos = note.original_endppqpos  -- This is the baseline when cache was made
        else
            -- Fallback to current state if no cache
            local _, _, _, _, current_end, _, _, _ = reaper.MIDI_GetNote(current_take, note.index)
            baseline_end_pos = current_end
        end

        -- Apply the delta to the baseline state
        local new_end_ppq = baseline_end_pos + delta_ppq

        -- Apply humanization if enabled (humanize_strength > 0)
        if humanize_strength > 0 and i < #selected_notes then  -- Only for notes that have a next note
            -- Calculate humanization range based on humanize_strength (0-100 scale)
            local humanize_range_ms = (humanize_strength / 100.0) * 100  -- Max 100ms variation at full strength

            if humanize_range_ms > 0 then
                -- Seed the random number generator for humanization
                local time_val = reaper.time_precise and reaper.time_precise() or os and os.time() or 0
                local seed_val = math.floor(time_val * 1000000) + #selected_notes + i  -- Use note index for variation
                math.randomseed(seed_val)

                -- Generate random humanization value in milliseconds
                local humanize_ms = math.random() * humanize_range_ms
                local humanize_ppq = (humanize_ms * tempo * 480) / (60 * 1000)

                -- Add humanization to current position
                new_end_ppq = new_end_ppq + humanize_ppq
            end
        end

        -- Apply constraints:
        -- 1. Same pitch notes must not overlap - search all notes for potential overlap
        -- Check all selected notes for same pitch that start after this note ends
        for _, potential_next_note in ipairs(selected_notes) do
            if note.pitch == potential_next_note.pitch and
               potential_next_note.startppqpos > note.startppqpos and  -- Only look at notes that start after current note start
               potential_next_note.startppqpos < new_end_ppq then      -- And that start before the current note would end (with legato)
                new_end_ppq = math.min(new_end_ppq, potential_next_note.startppqpos)
            end
        end

        -- Apply humanization range constraints (only if humanization is active and next note exists)
        if humanize_strength > 0 and i < #selected_notes then
            -- Ensure the note doesn't end before the next note starts (with reasonable overlap)
            local min_overlap_ppq = (2 * tempo * 480) / (60 * 1000) -- Minimum 2ms overlap
            local min_end_position = next_note.startppqpos + min_overlap_ppq
            new_end_ppq = math.max(new_end_ppq, min_end_position)

            -- Ensure the note doesn't extend beyond the next note's end
            new_end_ppq = math.min(new_end_ppq, next_note.endppqpos)
        end


        -- 2. Keep within item boundaries if checkbox is enabled
        if keep_within_boundaries then
            local item_start_ppq, item_end_ppq = get_item_boundaries_in_ppq(current_take)
            -- Constrain to item end boundary
            new_end_ppq = math.min(new_end_ppq, item_end_ppq)
            -- Constrain to item start boundary - note end should not be before item start
            -- But only if the note is within the item boundaries
            if note.startppqpos >= item_start_ppq and note.startppqpos < item_end_ppq then
                -- If note starts within the item, make sure end doesn't go before item start
                new_end_ppq = math.max(new_end_ppq, item_start_ppq)
            end
        end

        -- Make sure the new end position is not before the start position
        if new_end_ppq > note.startppqpos then
            local result = reaper.MIDI_SetNote(current_take, note.index, nil, nil, note.startppqpos, new_end_ppq, nil, nil, nil, true)
            if not result then
                reaper.MB("Error setting MIDI note at index " .. note.index, "Legato Tool Error", 0)
                return  -- Stop processing this note
            end
        end
    end

    reaper.UpdateArrange()
end


-- Main GUI loop
function loop()
    if not script_running then
        -- Clean up caches when the script is terminated to prevent memory leaks
        notes_cache = {}
        drag_start_note_states = {}
        -- Reset all state variables when script terminates
        legato_amount = 0
        humanize_strength = 0
        return
    end

    -- Handle global keyboard shortcuts
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = imgui.IsKeyDown(ctx, imgui.Key_LeftShift) or imgui.IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)
        -- Invalidate the selected CCs count cache since undo may change CCs or selection
        -- NOTE: For this tool, we should clear caches that may be invalidated
        notes_cache = {}
        drag_start_note_states = {}
        -- Reset all state variables when undo occurs
        legato_amount = 0
        humanize_strength = 0
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if ((is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false))) then
        reaper.Undo_DoRedo2(0)
        -- Invalidate caches when redo occurs
        notes_cache = {}
        drag_start_note_states = {}
        -- Reset all state variables when redo occurs
        legato_amount = 0
        humanize_strength = 0
    end

    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
        -- Clean up caches when the script is terminated to prevent memory leaks
        notes_cache = {}
        drag_start_note_states = {}
        -- Reset all state variables when script terminates via Escape key
        legato_amount = 0
        humanize_strength = 0
    end

    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse
    local visible, open = imgui.Begin(ctx, script_name, true, flags)

    if not open then script_running = false end

    -- Check for clicks outside the window to close it
    local is_window_hovered = imgui.IsWindowHovered(ctx, imgui.HoveredFlags_RootAndChildWindows)
    local is_window_focused = imgui.IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
    local is_mouse_down = imgui.IsMouseDown(ctx, imgui.MouseButton_Left)

    -- Check if mouse was just released (meaning a click happened outside)
    local is_mouse_clicked = imgui.IsMouseClicked(ctx, imgui.MouseButton_Left)

    -- Close when clicking outside the window area
    if visible and is_window_hovered == false and is_mouse_clicked then
        script_running = false
    end

    -- Clean up caches when the script is terminated to prevent memory leaks
    if not script_running then
        notes_cache = {}
        drag_start_note_states = {}
    end

    if visible and script_running then
        local current_take, midi_editor = get_midi_context()

        if not midi_editor then
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Clear cache if take changes to prevent memory leaks
            if take ~= current_take then
                if #notes_cache > 0 then
                    notes_cache = {}
                end
                if #drag_start_note_states > 0 then
                    drag_start_note_states = {}
                end
            end

            take = current_take

            if not current_take then
                imgui.Text(ctx, "Could not get MIDI take.")
            else
                -- Check if MIDI selection has changed
                if midi_selection_changed() then
                    -- Reset to fresh state when selection changes (like just opened)
                    legato_amount = 0  -- Reset slider to 0
                    humanize_strength = 0  -- Reset humanize strength to default
                    drag_start_legato_amount = 0  -- Reset drag start to 0
                    drag_start_note_states = {}  -- Clear the drag start states
                    notes_cache = {}  -- Clear the drag cache
                end

                -- Count selected notes and overlays (with caching to avoid repeated calculation)
                if current_take then
                    -- Recalculate if cache is invalid or MIDI context changed
                    local current_note_count = count_selected_notes()
                    if selected_note_count ~= current_note_count or take ~= current_take then
                        selected_note_count = current_note_count
                        take = current_take
                    end

                    -- Update overlay count when needed (for display)
                    overlay_count = detect_overlays_count(current_take)  -- Update overlay count for selected notes
                else
                    selected_note_count = 0
                    overlay_count = 0  -- Reset overlay count when there's no take
                end

                if selected_note_count < 2 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, "Select at least 2 notes to apply legato.")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(selected_note_count) .. " selected notes")
                end

                -- Select all notes button (full row)
                if imgui.Button(ctx, "Select all notes", -1, 0) then
                    -- Create an undo point for the current state
                    reaper.Undo_BeginBlock()
                    select_all_notes()  -- Call the new select all function
                    reaper.Undo_EndBlock("Select all notes in take", -1)
                end

                imgui.Separator(ctx)

                -- Group of action buttons: Fill gaps, Detect Overlays, Heal Overlays
                if selected_note_count >= 2 then
                    if imgui.Button(ctx, "Fill gaps") then
                        -- Create an undo point for the current state
                        reaper.Undo_BeginBlock()
                        fill_gaps()  -- Call the new fill gaps function
                        legato_amount = 0  -- Reset legato slider to 0
                        reaper.Undo_EndBlock("Fill gaps between notes", -1)
                    end
                    imgui.SameLine(ctx)  -- Put the Detect overlays button next to Fill gaps
                    if imgui.Button(ctx, "Detect overlays") then
                        -- Create an undo point for the current state
                        reaper.Undo_BeginBlock()
                        overlay_count = detect_overlays()  -- Call the new detect overlays function and store count
                        reaper.Undo_EndBlock("Detect and select overlays", -1)
                    end
                    imgui.SameLine(ctx)  -- Put the Heal overlays button next to Detect overlays
                    if imgui.Button(ctx, "Heal overlays") then
                        -- Create an undo point for the current state
                        reaper.Undo_BeginBlock()
                        local resolved_count = heal_overlays()  -- Call the heal overlays function
                        overlay_count = detect_overlays_count(current_take)  -- Update overlay count after healing
                        reaper.Undo_EndBlock("Heal note overlays", -1)
                    end
                else
                    imgui.BeginDisabled(ctx)
                    imgui.Button(ctx, "Fill gaps")
                    imgui.SameLine(ctx)  -- Put the disabled Detect overlays button next to Fill gaps
                    imgui.Button(ctx, "Detect overlays")
                    imgui.SameLine(ctx)  -- Put the disabled Heal overlays button next to Detect overlays
                    imgui.Button(ctx, "Heal overlays")
                    imgui.EndDisabled(ctx)
                end

                -- Display overlay count text (red if overlays detected)
                if overlay_count > 0 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, tostring(overlay_count) .. " overlays detected")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(overlay_count) .. " overlays detected")
                end

                imgui.Separator(ctx)

                -- Legato Section
                imgui.Text(ctx, "Make Notes Legato")
                local _, new_legato_amount = imgui.SliderInt(ctx, "Legato Amount (ms)", legato_amount, 0, 400, "%d ms")

                -- Handle legato slider interaction for real-time feedback
                local value_changed = new_legato_amount ~= legato_amount
                local is_activated = imgui.IsItemActivated(ctx)
                local is_active = imgui.IsItemActive(ctx)

                -- Build cache when slider interaction starts (when starting to drag)
                if is_activated then
                    reaper.Undo_BeginBlock()
                    drag_start_legato_amount = legato_amount  -- Store the value at drag start
                    drag_start_note_states = build_notes_cache()  -- Store the note states at drag start
                    notes_cache = drag_start_note_states  -- Use the drag start states as the reference
                end

                if value_changed then
                    -- Update legato_amount first
                    legato_amount = new_legato_amount

                    if selected_note_count >= 2 then
                        if is_active and #notes_cache > 0 then
                            -- Currently dragging, apply delta from initial state
                            apply_legato(notes_cache)
                        else
                            -- Not dragging, apply to current state (no delta)
                            local temp_cache = build_notes_cache()
                            apply_legato(temp_cache)
                        end
                    end
                end

                -- Clear the cache when the slider is not active to prevent memory buildup
                -- But only when not actively dragging (to preserve the cache during dragging)
                if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #notes_cache > 0 then
                    notes_cache = {}
                end

                if imgui.IsItemDeactivatedAfterEdit(ctx) then
                    -- End the undo block that was started on activation
                    reaper.Undo_EndBlock("", -1)
                end

                -- Apply button after legato slider
                if selected_note_count >= 2 then
                    if imgui.Button(ctx, "Apply") then
                        -- Create an undo point for the current state
                        reaper.Undo_BeginBlock()
                        reaper.Undo_EndBlock("Apply legato changes", -1)
                        -- Update the drag start reference to current state for future delta calculations
                        drag_start_legato_amount = legato_amount  -- Set baseline to current value
                        drag_start_note_states = build_notes_cache()  -- Capture current visual state
                        legato_amount = 0  -- Reset slider to 0
                        humanize_strength = 0  -- Reset humanize strength to default

                        -- Also reset any other drag-related states to maintain consistency
                        -- If we're currently dragging, make sure to clear the cache
                        if #notes_cache > 0 then
                            notes_cache = {}
                        end
                    end
                else
                    imgui.BeginDisabled(ctx)
                    imgui.Button(ctx, "Apply")
                    imgui.EndDisabled(ctx)
                end

                -- Humanize strength slider
                local _, new_humanize_strength = imgui.SliderInt(ctx, "Humanize Strength", humanize_strength, 0, 100, "%d")
                humanize_strength = new_humanize_strength

                imgui.Separator(ctx)

                -- Keep within item boundaries checkbox
                local _, new_keep_within_boundaries = imgui.Checkbox(ctx, "Keep within item boundaries", keep_within_boundaries)
                keep_within_boundaries = new_keep_within_boundaries  -- Update the variable




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