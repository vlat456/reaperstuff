-- @noindex

local reaper = reaper

local M = {} -- Module table

-- Centralized require statements at the top of the file
local UNDO_MANAGER = require "undo_manager"
local SCRIPT_INIT = require "script_init"
local LEGATO_OPERATIONS = require "legato_operations"

-- Function to get current MIDI context consistently
function M.get_midi_context()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil, nil end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then return nil, nil end

    return current_take, midi_editor
end

-- Helper function to get the active MIDI take
function M.get_active_take()
    local current_take, midi_editor = M.get_midi_context()
    return current_take
end

-- Function to count selected notes in the current take
function M.count_selected_notes()
    local current_take, midi_editor = M.get_midi_context()

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

-- Function to get selected notes with their properties
function M.get_selected_notes()
    local current_take, midi_editor = M.get_midi_context()

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

-- Optimized cached sorted notes system now uses unified cache manager

-- Unified cache management system (defined before use)
local cache_manager = {
    -- Cache state
    valid = false,
    data = {},
    last_take = nil,
    last_note_count = 0,
    
    -- Function to invalidate the cache when needed
    invalidate = function(self)
        self.valid = false
        self.data = {}
        self.last_take = nil
        self.last_note_count = 0
    end,
    
    -- Function to check if cache is valid for current context
    is_valid = function(self, current_take, current_note_count)
        return self.valid and
               self.last_take == current_take and
               self.last_note_count == current_note_count
    end,
    
    -- Function to mark cache as valid with current context
    mark_valid = function(self, current_take, current_note_count)
        self.valid = true
        self.last_take = current_take
        self.last_note_count = current_note_count
    end
}

-- Optimized version of get_selected_notes (no longer needs sorting, uses cached version)
function M.get_selected_notes_optimized()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then
        return {}
    end

    -- Return the cached sorted version instead of re-sorting
    return M.get_cached_sorted_selected_notes()
end

-- Function to get media item boundaries in PPQ for the given take
function M.get_item_boundaries_in_ppq(take)
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
function M.get_current_selected_note_info()
    local current_take, midi_editor = M.get_midi_context()
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
local last_selected_note_indices = {} -- Store indices of selected notes to detect changes
function M.midi_selection_changed()
    local current_selection = M.get_current_selected_note_info()
    local last_selection = last_selected_note_indices

    -- Compare lengths first
    if #current_selection ~= #last_selection then
        last_selected_note_indices = current_selection
        M.invalidate_sorted_notes_cache() -- Invalidate cache when selection changes
        return true
    end

    -- Compare individual indices
    for i = 1, #current_selection do
        if current_selection[i] ~= last_selection[i] then
            last_selected_note_indices = current_selection
            M.invalidate_sorted_notes_cache() -- Invalidate cache when selection changes
            return true
        end
    end

    -- No change detected
    return false
end

-- Function to get cached sorted selected notes
function M.get_cached_sorted_selected_notes()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then
        return {}
    end

    local current_note_count = M.count_selected_notes()
    
    -- Check if we need to rebuild the cache using the unified cache manager
    if not cache_manager:is_valid(current_take, current_note_count) then

        -- Build fresh sorted cache
        cache_manager.data = {}
        local note_index = -1
        local safety_counter = 0
        local max_notes = 10000

        while safety_counter < max_notes do
            note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
            if note_index == -1 then
                break
            end

            local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
            if not retval then
                reaper.MB("Error retrieving MIDI note at index " .. note_index, "Legato Tool Error", 0)
                break
            end

            table.insert(cache_manager.data, {
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

        -- Sort notes by start position only once
        table.sort(cache_manager.data, function(a, b)
            return a.startppqpos < b.startppqpos
        end)

        -- Mark cache as valid with current context
        cache_manager:mark_valid(current_take, #cache_manager.data)
    end

    return cache_manager.data
end

-- Primary cache invalidation function - now uses the unified cache manager
function M.invalidate_sorted_notes_cache()
    cache_manager:invalidate()
end

-- Backward compatibility wrapper - now uses the same unified cache manager
function M.invalidate_cached_sorted_notes()
    cache_manager:invalidate()
end

-- Corrected version of the ms_to_ppq function that properly handles tempo changes
-- This function converts milliseconds to PPQ (pulses per quarter note) changes for a specific note position
function M.ms_to_ppq_corrected(ms, take, note_ppq_pos)
    if not ms or ms < 0 then
        return 0
    end

    if not take or not note_ppq_pos then
        -- Fallback to original estimation if no take/position provided
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Convert the note's PPQ position to project time
    local note_time = reaper.MIDI_GetProjTimeFromPPQPos(take, note_ppq_pos)
    if not note_time or note_time < 0 then
        -- Fallback if conversion fails
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Calculate the target time after adding the milliseconds (convert ms to seconds)
    local target_time = note_time + (ms / 1000.0)

    -- Convert both times to PPQ and calculate the difference
    local target_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, target_time)
    local current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, note_time)

    if not target_ppq or not current_ppq then
        -- Fallback if conversion fails
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Return the difference in PPQ, which represents the distance for the specified milliseconds
    return target_ppq - current_ppq
end

-- Alternative function to get PPQ difference for legato extension at a specific position
function M.get_ppq_delta_for_ms_at_position(ms, take, start_ppq_pos)
    if not ms or ms <= 0 then
        return 0
    end

    if not take or not start_ppq_pos then
        -- Use default parameters if inputs are invalid
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Get the time for the starting PPQ position
    local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, start_ppq_pos)
    if not start_time then
        -- Fallback to estimated conversion
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Calculate the end time by adding the milliseconds (converted to seconds)
    local end_time = start_time + (ms / 1000.0)

    -- Get the PPQ position for the end time
    local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, end_time)
    if not end_ppq then
        -- Fallback to estimated conversion
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Return the PPQ difference
    return end_ppq - start_ppq_pos
end

-- Helper function to check if a table contains a value
function M.table_contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- Function to heal note overlays by adjusting note positions so that first note ends before second note starts
function M.heal_overlays(register_undo)
    -- Default to true if register_undo is nil
    if register_undo == nil then
        register_undo = true
    end

    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return 0 end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    -- Get cached sorted selected notes
    local selected_notes = M.get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Find overlapping notes of the same pitch and resolve the overlays (no need to sort again)
    local resolved_count = 0
    for i, note1 in ipairs(selected_notes) do
        for j = i + 1, #selected_notes do
            local note2 = selected_notes[j]

            -- Stop checking if note2 starts after note1 ends (notes are already sorted by start time)
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

    if register_undo then
        SCRIPT_INIT.register_undo(item, "Heal note overlays")
    end
    reaper.UpdateArrange()

    return resolved_count
end

-- Function to guarantee all overlaps are eliminated using iterative healing
function M.heal_all_overlaps_guaranteed()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return 0 end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    local iterations = 0
    local max_iterations = 100  -- Safety limit
    local total_resolved = 0

    repeat
        M.invalidate_cached_sorted_notes()  -- Important: invalidate cache after modifications

        local initial_overlay_count = M.detect_overlays_count(current_take)

        if initial_overlay_count == 0 then
            break  -- No overlaps remain
        end

        local resolved_count = M.heal_overlays(false)  -- Apply healing pass without undo registration
        total_resolved = total_resolved + resolved_count

        iterations = iterations + 1

        if iterations >= max_iterations then
            reaper.MB("Maximum iterations reached in guaranteed overlap healing (" .. iterations .. "). " ..
                     M.detect_overlays_count(current_take) .. " overlaps may remain.", "Warning", 0)
            break
        end

    until M.detect_overlays_count(current_take) == 0

    -- Final sort and update to ensure everything is properly ordered
    reaper.MIDI_Sort(current_take)
    SCRIPT_INIT.register_undo(item, "Heal all note overlays (guaranteed)")

    return total_resolved
end

-- Function to count note overlays (selected notes with the same pitch that have overlapping time ranges) without changing selection
function M.detect_overlays_count(current_take)
    if not current_take then return 0 end

    -- Get the current MIDI context to get selected notes
    local _, _ = M.get_midi_context()

    -- Get cached sorted selected notes
    local selected_notes = M.get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Find overlapping notes of the same pitch (no need to sort again)
    local overlay_indices = {}
    for i, note1 in ipairs(selected_notes) do
        for j = i + 1, #selected_notes do
            local note2 = selected_notes[j]

            -- Stop checking if note2 starts after note1 ends (notes are already sorted by start time)
            if note2.startppqpos >= note1.endppqpos then
                break
            end

            -- Check if notes have the same pitch and actually overlap in time
            if note1.pitch == note2.pitch and note1.endppqpos > note2.startppqpos then
                -- This is an overlay - mark both notes for counting
                if not M.table_contains(overlay_indices, note1.index) then
                    table.insert(overlay_indices, note1.index)
                end
                if not M.table_contains(overlay_indices, note2.index) then
                    table.insert(overlay_indices, note2.index)
                end
            end
        end
    end

    return #overlay_indices
end

-- Function to select all notes in the current take
function M.select_all_notes()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return 0 end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    local note_count = reaper.MIDI_CountEvts(current_take, nil, nil, nil)
    local changes = 0

    -- Deselect all currently selected notes first
    for i = 0, note_count - 1 do
        local _, selected, _, _, _, _, _, _ = reaper.MIDI_GetNote(current_take, i)
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

    -- Update the item and register the change in undo system
    SCRIPT_INIT.register_undo(item, "Select all notes in take")

    return changes
end

-- Function to apply non-legato (de-legato) effect - ensures notes don't overlap
function M.non_legato()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    -- Get cached sorted selected notes
    local selected_notes = M.get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes for non-legato
    end

    -- Process each note to ensure no overlaps (no need to sort again)
    for i, note in ipairs(selected_notes) do
        -- Find the next note that starts after this note
        if i < #selected_notes then
            local next_note = selected_notes[i + 1]

            -- Check if this note extends beyond or to the start of the next note
            if note.endppqpos >= next_note.startppqpos then
                -- Calculate new end position: couple of ten PPQ before next note starts
                local gap_ppq = 10  -- 10 PPQ gap to avoid mess
                local new_end_ppq = next_note.startppqpos - gap_ppq

                -- Make sure the new end position is not before the start position
                if not LEGATO_OPERATIONS.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq) then
                    return  -- Stop processing this note if error occurs
                end
            end
        end
    end

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    -- Update the item and register the change in undo system
    SCRIPT_INIT.register_undo(item, "Apply non-legato (de-legato) to notes")
end

-- Function to fill gaps between selected notes
function M.fill_gaps()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    -- Get cached sorted selected notes
    local selected_notes = M.get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes to fill gaps
    end

    -- Process each note to extend to the next note's start (no need to sort again)
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
            new_end_ppq = LEGATO_OPERATIONS.apply_overlap_constraints(note, selected_notes, new_end_ppq)

            -- Keep within item boundaries if checkbox is enabled
            local keep_within_boundaries = false -- Default to false for this function
            new_end_ppq = LEGATO_OPERATIONS.apply_boundary_constraints(note, new_end_ppq, current_take, keep_within_boundaries)

            -- Make sure the new end position is not before the start position
            if not LEGATO_OPERATIONS.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq) then
                return  -- Stop processing this note if error occurs
            end
        end
    end

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    -- Update the item and register the change in undo system
    SCRIPT_INIT.register_undo(item, "Fill gaps between notes")
end

-- Function to apply only humanization to selected notes (without legato changes)
function M.apply_humanization(humanize_strength, keep_within_boundaries, register_undo)
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    local selected_notes = M.get_cached_sorted_selected_notes()

    if #selected_notes < 1 then
        return  -- Need at least 1 note for humanization
    end

    -- Seed the random number generator once for non-deterministic humanization
    local time_val = reaper.time_precise and reaper.time_precise() or os and os.time() or 0
    math.randomseed(math.floor(time_val * 1000000))

    -- Apply humanization to all selected notes
    for i, note in ipairs(selected_notes) do
        -- Get the current end position of the note
        local _, _, _, _, current_end, _, _, _ = reaper.MIDI_GetNote(current_take, note.index)
        local new_end_ppq = current_end

        -- Apply humanization if enabled (humanize_strength > 0)
        if humanize_strength and humanize_strength > 0 then  -- Apply to all notes, regardless if they have a next note
            -- Calculate humanization range based on humanize_strength (0-100 scale)
            local humanize_range_ms = (humanize_strength / 100.0) * 300  -- Max 300ms variation at full strength (3x stronger)

            if humanize_range_ms > 0 then
                -- Generate bidirectional random humanization value in milliseconds
                -- Random value between -range/2 and +range/2 for more natural variation
                local humanize_ms = (math.random() - 0.5) * humanize_range_ms
                local humanize_ppq = M.ms_to_ppq_corrected(humanize_ms, current_take, note.startppqpos)

                -- Calculate preliminary new end position
                local preliminary_end_ppq = new_end_ppq + humanize_ppq
                
                -- Ensure legato is maintained: the note should not end before the next note starts
                -- Find the next note that starts after this note
                local next_note_start = nil
                for j = i + 1, #selected_notes do
                    if selected_notes[j].startppqpos > note.startppqpos then
                        next_note_start = selected_notes[j].startppqpos
                        break
                    end
                end
                
                -- If there's a next note, ensure we don't shorten this note too much
                if next_note_start then
                    -- Ensure the note extends at least to the start of the next note
                    -- We allow a small gap (e.g., 5 PPQ) to avoid exact overlaps
                    local min_end_ppq = next_note_start - 5
                    preliminary_end_ppq = math.max(preliminary_end_ppq, min_end_ppq)
                end
                
                -- Ensure the note doesn't end before it starts
                preliminary_end_ppq = math.max(preliminary_end_ppq, note.startppqpos + 1)
                
                new_end_ppq = preliminary_end_ppq
            end
        end

        -- Apply constraints using shared functions
        if new_end_ppq > note.startppqpos then
            -- 1. Apply same-pitch overlap prevention
            new_end_ppq = LEGATO_OPERATIONS.apply_overlap_constraints(note, selected_notes, new_end_ppq)
            
            -- 2. Keep within item boundaries if checkbox is enabled
            keep_within_boundaries = keep_within_boundaries or false -- Default to false if not provided
            new_end_ppq = LEGATO_OPERATIONS.apply_boundary_constraints(note, new_end_ppq, current_take, keep_within_boundaries)
            
            -- 3. Set the note end position safely
            if not LEGATO_OPERATIONS.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq) then
                return  -- Stop processing this note if error occurs
            end
        end
    end

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    -- Update the item and register the change in undo system if requested
    register_undo = register_undo ~= false -- Default to true if not specified
    if register_undo then
        SCRIPT_INIT.register_undo(item, "Apply humanization")
    end
    reaper.UpdateArrange()
end

-- Function to build notes cache with original values preserved
function M.build_notes_cache()
    local current_take, midi_editor = M.get_midi_context()

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

-- Function to restore notes to their original state
function M.restore_original_notes(cache)
    local current_take, midi_editor = M.get_midi_context()

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

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    if current_take then
        local item = reaper.GetMediaItemTake_Item(current_take)
        SCRIPT_INIT.register_undo(item, "Restore original notes")
    end
    reaper.UpdateArrange()
end

-- Function to apply legato to selected notes using delta from baseline state
function M.apply_legato(cache, legato_amount, humanize_strength, keep_within_boundaries)
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return end

    local selected_notes = cache or M.get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes for legato
    end

    -- Calculate the delta from the legato amount
    local delta_ppq = M.ms_to_ppq_corrected(legato_amount, current_take, selected_notes[1] and selected_notes[1].startppqpos or 0)

    -- Apply the legato amount to the note positions
    for i, note in ipairs(selected_notes) do
        local next_note = nil
        if i < #selected_notes then
            next_note = selected_notes[i + 1]
        end

        -- Get the current end position of the note
        local _, _, _, _, current_end, _, _, _ = reaper.MIDI_GetNote(current_take, note.index)
        local new_end_ppq = current_end + delta_ppq

        -- Apply humanization if enabled
        if humanize_strength and humanize_strength > 0 then
            -- Calculate humanization range based on humanize_strength (0-100 scale)
            local humanize_range_ms = (humanize_strength / 100.0) * 300  -- Max 300ms variation at full strength (3x stronger)

            if humanize_range_ms > 0 then
                -- Generate random humanization value in milliseconds
                local humanize_ms = (math.random() - 0.5) * humanize_range_ms  -- Random value between -range/2 and +range/2
                local humanize_ppq = M.ms_to_ppq_corrected(humanize_ms, current_take, note.startppqpos)

                -- Add humanization to current position
                new_end_ppq = new_end_ppq + humanize_ppq
            end
        end
-- Apply constraints using shared functions
        
        -- 1. Same pitch notes must not overlap
        new_end_ppq = LEGATO_OPERATIONS.apply_overlap_constraints(note, selected_notes, new_end_ppq)
        
        -- 2. Keep within item boundaries if checkbox is enabled
        new_end_ppq = LEGATO_OPERATIONS.apply_boundary_constraints(note, new_end_ppq, current_take, keep_within_boundaries)
        
        -- 3. Set the note end position safely
        if not LEGATO_OPERATIONS.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq) then
            return  -- Stop processing this note if error occurs
        end
    end

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()

    -- Handle undo
    if current_take then
        local item = reaper.GetMediaItemTake_Item(current_take)
        SCRIPT_INIT.register_undo(item, "Apply legato changes")
    end
end

-- Function to detect note overlays (selected notes with the same pitch that have overlapping time ranges)
-- This function changes selection (for UI functionality)
function M.detect_overlays()
    local current_take, midi_editor = M.get_midi_context()

    if not current_take then return 0 end

    -- Get the media item associated with the take
    local item = reaper.GetMediaItemTake_Item(current_take)

    -- Get cached sorted selected notes
    local selected_notes = M.get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Find overlapping notes of the same pitch (no need to sort again)
    local overlay_indices = {}
    for i, note1 in ipairs(selected_notes) do
        for j = i + 1, #selected_notes do
            local note2 = selected_notes[j]

            -- Stop checking if note2 starts after note1 ends (notes are already sorted by start time)
            if note2.startppqpos >= note1.endppqpos then
                break
            end

            -- Check if notes have the same pitch and actually overlap in time
            if note1.pitch == note2.pitch and note1.endppqpos > note2.startppqpos then
                -- This is an overlay - mark both notes for selection
                if not M.table_contains(overlay_indices, note1.index) then
                    table.insert(overlay_indices, note1.index)
                end
                if not M.table_contains(overlay_indices, note2.index) then
                    table.insert(overlay_indices, note2.index)
                end
            end
        end
    end

    -- Only update selection if overlays were found
    if #overlay_indices > 0 then
        -- Deselect all selected notes first (get fresh list to avoid using cached list)
        local fresh_selected_notes = M.get_selected_notes()
        for _, note in ipairs(fresh_selected_notes) do
            reaper.MIDI_SetNote(current_take, note.index, false, nil, nil, nil, nil, nil, nil, true)  -- deselect only
        end

        -- Select only the overlay notes
        for _, overlay_index in ipairs(overlay_indices) do
            reaper.MIDI_SetNote(current_take, overlay_index, true, nil, nil, nil, nil, nil, nil, true)  -- select only
        end
    end  -- If no overlays found, keep original selection unchanged

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    -- Update the item and register the change in undo system
    reaper.UpdateItemInProject(item)
    reaper.Undo_OnStateChange_Item(0, "Detect and select overlays", item)
    reaper.UpdateArrange()
    return #overlay_indices
end

return M