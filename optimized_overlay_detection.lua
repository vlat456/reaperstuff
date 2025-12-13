-- Optimized overlay detection algorithm using event-based sweep line approach
-- Time complexity: O(n log n) instead of O(n²) or O(n³) in the original version

-- Optimized function to detect note overlays (selected notes with the same pitch that have overlapping time ranges)
function detect_overlays_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    -- Get selected notes only
    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Create events for sweep line algorithm
    -- Each note creates two events: start and end
    local events = {}
    
    for _, note in ipairs(selected_notes) do
        -- Start event: +1 at note start position
        table.insert(events, {pos = note.startppqpos, type = 'start', pitch = note.pitch, note_idx = note.index})
        -- End event: -1 at note end position
        table.insert(events, {pos = note.endppqpos, type = 'end', pitch = note.pitch, note_idx = note.index})
    end

    -- Sort events by position, with start events before end events at the same position
    table.sort(events, function(a, b)
        if a.pos == b.pos then
            -- Process start events before end events at the same position
            if a.type == 'start' and b.type == 'end' then
                return true
            elseif a.type == 'end' and b.type == 'start' then
                return false
            else
                return a.pitch < b.pitch
            end
        end
        return a.pos < b.pos
    end)

    -- Track active notes by pitch
    local active_notes_by_pitch = {}
    local overlay_indices = {}
    local overlay_set = {} -- Use a set to avoid duplicate indices

    for _, event in ipairs(events) do
        if event.type == 'start' then
            -- Check if there are already active notes with the same pitch
            if not active_notes_by_pitch[event.pitch] then
                active_notes_by_pitch[event.pitch] = {}
            end
            
            -- If there are already active notes of this pitch, there's an overlay
            for _, active_idx in ipairs(active_notes_by_pitch[event.pitch]) do
                -- Mark both notes as overlay
                overlay_set[active_idx] = true
                overlay_set[event.note_idx] = true
            end
            
            -- Add this note to active list
            table.insert(active_notes_by_pitch[event.pitch], event.note_idx)
        elseif event.type == 'end' then
            -- Remove this note from active list
            if active_notes_by_pitch[event.pitch] then
                local new_list = {}
                for _, idx in ipairs(active_notes_by_pitch[event.pitch]) do
                    if idx ~= event.note_idx then
                        table.insert(new_list, idx)
                    end
                end
                active_notes_by_pitch[event.pitch] = new_list
            end
        end
    end

    -- Convert set back to array for indices
    for idx, _ in pairs(overlay_set) do
        table.insert(overlay_indices, idx)
    end

    -- Only update selection if overlays were found
    if #overlay_indices > 0 then
        -- Get fresh selected notes to deselect
        local fresh_selected_notes = get_selected_notes()
        
        -- Deselect all selected notes first
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

-- Optimized version of heal_overlays function
function heal_overlays_optimized()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return 0 end

    -- Get selected notes only
    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Sort selected notes by start position (already mostly sorted, but ensure it)
    table.sort(selected_notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    -- Instead of O(n²) nested loop, use interval tree approach or just one pass with tracking
    -- This approach will fix overlapping notes of the same pitch in a single pass
    local resolved_count = 0
    local pitch_last_end_time = {} -- Track the last end time for each pitch

    for i, note in ipairs(selected_notes) do
        local last_end_for_pitch = pitch_last_end_time[note.pitch] or -1

        -- Check if this note overlaps with the previous note of the same pitch
        if last_end_for_pitch > note.startppqpos then
            -- There's an overlap - fix it by adjusting the previous note's end time
            local prev_note_idx = find_previous_note_of_pitch(selected_notes, i, note.pitch)
            if prev_note_idx then
                local new_end_pos = note.startppqpos

                if new_end_pos > selected_notes[prev_note_idx].startppqpos then
                    local result = reaper.MIDI_SetNote(
                        current_take,
                        selected_notes[prev_note_idx].index,
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
                        -- Update the last end time for this pitch
                        pitch_last_end_time[note.pitch] = new_end_pos
                    end
                end
            end
        else
            -- Update the last end time for this pitch to the current note's end
            pitch_last_end_time[note.pitch] = note.endppqpos
        end
    end

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()

    return resolved_count
end

-- Helper function to find the previous note of the same pitch
function find_previous_note_of_pitch(notes, current_index, pitch)
    for i = current_index - 1, 1, -1 do
        if notes[i].pitch == pitch then
            return i
        end
    end
    return nil
end

-- Optimized version of the detect_overlays_count function
function detect_overlays_count_optimized(current_take)
    if not current_take then return 0 end

    -- Get selected notes only
    local selected_notes = get_selected_notes()

    if #selected_notes < 2 then
        return 0  -- Need at least 2 notes to check for overlays
    end

    -- Use the same sweep line algorithm as detect_overlays_optimized
    local events = {}
    
    for _, note in ipairs(selected_notes) do
        table.insert(events, {pos = note.startppqpos, type = 'start', pitch = note.pitch, note_idx = note.index})
        table.insert(events, {pos = note.endppqpos, type = 'end', pitch = note.pitch, note_idx = note.index})
    end

    table.sort(events, function(a, b)
        if a.pos == b.pos then
            if a.type == 'start' and b.type == 'end' then
                return true
            elseif a.type == 'end' and b.type == 'start' then
                return false
            else
                return a.pitch < b.pitch
            end
        end
        return a.pos < b.pos
    end)

    local active_notes_by_pitch = {}
    local overlay_set = {} -- Use a set to avoid duplicate indices

    for _, event in ipairs(events) do
        if event.type == 'start' then
            if not active_notes_by_pitch[event.pitch] then
                active_notes_by_pitch[event.pitch] = {}
            end
            
            for _, active_idx in ipairs(active_notes_by_pitch[event.pitch]) do
                overlay_set[active_idx] = true
                overlay_set[event.note_idx] = true
            end
            
            table.insert(active_notes_by_pitch[event.pitch], event.note_idx)
        elseif event.type == 'end' then
            if active_notes_by_pitch[event.pitch] then
                local new_list = {}
                for _, idx in ipairs(active_notes_by_pitch[event.pitch]) do
                    if idx ~= event.note_idx then
                        table.insert(new_list, idx)
                    end
                end
                active_notes_by_pitch[event.pitch] = new_list
            end
        end
    end

    return #overlay_set
end