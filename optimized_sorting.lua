-- Optimized version with cached sorted notes to eliminate redundant sorting
-- Add global variables for caching
local sorted_notes_cache = {}
local sorted_notes_cache_valid = false
local last_cache_take = nil
local last_cache_note_count = 0

-- Function to get cached sorted selected notes
function get_cached_sorted_selected_notes()
    local current_take, midi_editor = get_midi_context()
    
    if not current_take then
        return {}
    end
    
    -- Check if we need to rebuild the cache
    if not sorted_notes_cache_valid or 
       last_cache_take ~= current_take or
       last_cache_note_count ~= count_selected_notes() then
        
        -- Build fresh sorted cache
        sorted_notes_cache = {}
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

            table.insert(sorted_notes_cache, {
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
        table.sort(sorted_notes_cache, function(a, b)
            return a.startppqpos < b.startppqpos
        end)

        -- Update cache metadata
        sorted_notes_cache_valid = true
        last_cache_take = current_take
        last_cache_note_count = #sorted_notes_cache
    end

    return sorted_notes_cache
end

-- Function to invalidate the cache when needed
function invalidate_sorted_notes_cache()
    sorted_notes_cache_valid = false
    sorted_notes_cache = {}
    last_cache_take = nil
    last_cache_note_count = 0
end

-- Optimized version of get_selected_notes (no longer needs sorting)
function get_selected_notes_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then
        return {}
    end

    -- Return the cached sorted version instead of re-sorting
    return get_cached_sorted_selected_notes()
end

-- Optimized version of build_notes_cache (no longer needs sorting)
function build_notes_cache_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return {} end

    local notes = {}
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

    -- Sort notes by start position only once (or use the global cache)
    table.sort(notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    return notes
end

-- Optimized version of detect_overlays (no longer needs sorting)
function detect_overlays_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    -- Get cached sorted selected notes
    local selected_notes = get_cached_sorted_selected_notes()

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
        -- Deselect all selected notes first (get fresh list to avoid using cached list)
        local fresh_selected_notes = get_selected_notes()
        for _, note in ipairs(fresh_selected_notes) do
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

-- Optimized version of heal_overlays (no longer needs sorting)
function heal_overlays_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    -- Get cached sorted selected notes
    local selected_notes = get_cached_sorted_selected_notes()

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
    reaper.UpdateArrange()

    return resolved_count
end

-- Optimized version of detect_overlays_count (no longer needs sorting)
function detect_overlays_count_optimized(current_take)
    if not current_take then return 0 end

    -- Get the current MIDI context to get selected notes
    local _, _ = get_midi_context()

    -- Get cached sorted selected notes
    local selected_notes = get_cached_sorted_selected_notes()

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

-- Optimized version of non_legato (no longer needs sorting)
function non_legato_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return end

    -- Get cached sorted selected notes
    local selected_notes = get_cached_sorted_selected_notes()

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
                if new_end_ppq > note.startppqpos then
                    local result = reaper.MIDI_SetNote(current_take, note.index, nil, nil, note.startppqpos, new_end_ppq, nil, nil, nil, true)
                    if not result then
                        reaper.MB("Error setting MIDI note at index " .. note.index, "Legato Tool Error", 0)
                        return  -- Stop processing this note
                    end
                end
            end
        end
    end

    reaper.UpdateArrange()
end

-- Optimized version of fill_gaps (no longer needs sorting)
function fill_gaps_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return end

    -- Get cached sorted selected notes
    local selected_notes = get_cached_sorted_selected_notes()

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

-- In the main loop function, add cache invalidation when selection changes
function loop()
    if not script_running then
        -- Clean up caches when the script is terminated to prevent memory leaks
        sorted_notes_cache = {}
        sorted_notes_cache_valid = false
        notes_cache = {}
        drag_start_note_states = {}
        -- Reset all state variables when script terminates
        legato_amount = 0
        humanize_strength = 0
        return
    end

    -- ... existing code ...

    if visible and script_running then
        local current_take, midi_editor = get_midi_context()

        if not midi_editor then
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Check for changes that would invalidate the sorted notes cache
            if take ~= current_take then
                -- Clear the sorted notes cache when take changes
                invalidate_sorted_notes_cache()
                
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
                -- Check if MIDI selection has changed (this will trigger cache invalidation)
                if midi_selection_changed() then
                    -- Reset to fresh state when selection changes (like just opened)
                    legato_amount = 0  -- Reset slider to 0
                    humanize_strength = 0  -- Reset humanize strength to default
                    drag_start_legato_amount = 0  -- Reset drag start to 0
                    drag_start_note_states = {}  -- Clear the drag start states
                    notes_cache = {}  -- Clear the drag cache
                    
                    -- Invalidate the sorted notes cache since selection changed
                    invalidate_sorted_notes_cache()
                end

                -- Count selected notes and overlays (with caching to avoid repeated calculation)
                if current_take then
                    -- Recalculate if cache is invalid or MIDI context changed
                    local current_note_count = count_selected_notes()
                    if selected_note_count ~= current_note_count or take ~= current_take then
                        selected_note_count = current_note_count
                        take = current_take
                        
                        -- Invalidate sorted notes cache when note count changes
                        if last_cache_note_count ~= current_note_count then
                            invalidate_sorted_notes_cache()
                        end
                    end

                    -- Update overlay count when needed (for display)
                    overlay_count = detect_overlays_count_optimized(current_take)  -- Update overlay count for selected notes
                else
                    selected_note_count = 0
                    overlay_count = 0  -- Reset overlay count when there's no take
                end

                -- ... rest of existing code ...