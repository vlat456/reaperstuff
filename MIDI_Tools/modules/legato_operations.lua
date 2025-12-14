-- @noindex
-- @description Common legato operations shared across scripts

local reaper = reaper

local M = {}

-- Function to get media item boundaries in PPQ for the given take
local function get_item_boundaries_in_ppq(take)
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

-- Corrected version of the ms_to_ppq function that properly handles tempo changes
-- This function converts milliseconds to PPQ (pulses per quarter note) changes for a specific note position
local function ms_to_ppq_corrected(ms, take, note_ppq_pos)
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

-- Function to apply overlap prevention constraints
function M.apply_overlap_constraints(note, selected_notes, new_end_ppq)
    -- Same pitch overlap prevention - check against all selected notes
    for _, potential_next_note in ipairs(selected_notes) do
        if note.pitch == potential_next_note.pitch and
           potential_next_note.startppqpos > note.startppqpos and
           potential_next_note.startppqpos < new_end_ppq then
            new_end_ppq = math.min(new_end_ppq, potential_next_note.startppqpos)
        end
    end
    
    return new_end_ppq
end

-- Function to apply item boundary constraints
function M.apply_boundary_constraints(note, new_end_ppq, current_take, keep_within_boundaries)
    if not keep_within_boundaries then
        return new_end_ppq
    end
    
    local item_start_ppq, item_end_ppq = get_item_boundaries_in_ppq(current_take)
    
    -- Constrain to item end boundary
    new_end_ppq = math.min(new_end_ppq, item_end_ppq)
    
    -- Constrain to item start boundary - note end should not be before item start
    -- But only if the note is within the item boundaries
    if note.startppqpos >= item_start_ppq and note.startppqpos < item_end_ppq then
        -- If note starts within the item, make sure end doesn't go before item start
        new_end_ppq = math.max(new_end_ppq, item_start_ppq)
    end
    
    return new_end_ppq
end

-- Function to safely set note end position
function M.safe_set_note_end(current_take, note_index, start_ppq, new_end_ppq)
    -- Make sure the new end position is not before the start position
    if new_end_ppq > start_ppq then
        local result = reaper.MIDI_SetNote(current_take, note_index, nil, nil, start_ppq, new_end_ppq, nil, nil, nil, true)
        if not result then
            reaper.MB("Error setting MIDI note at index " .. note_index, "Legato Tool Error", 0)
            return false
        end
        return true
    end
    return false
end

-- Function to apply legato with gap filling and extension
function M.apply_legato_with_extension(current_take, selected_notes, extension_percentage)
    extension_percentage = extension_percentage or 0.1  -- Default to 10%
    
    for i, note in ipairs(selected_notes) do
        -- Find the next note that starts after this note
        local next_note = nil
        for j = i + 1, #selected_notes do
            if selected_notes[j].startppqpos > note.startppqpos then
                next_note = selected_notes[j]
                break
            end
        end

        if next_note then
            -- Calculate new end position: extend to next note start (gap filling) + legato extension
            local new_end_ppq = next_note.startppqpos  -- Start by filling the gap

            -- Add legato extension: percentage of the next note's original length
            if next_note then
                -- Convert the next note's length from PPQ to milliseconds
                local start_time = reaper.MIDI_GetProjTimeFromPPQPos(current_take, next_note.startppqpos)
                local end_time = reaper.MIDI_GetProjTimeFromPPQPos(current_take, next_note.endppqpos)
                local next_note_length_ms = (end_time - start_time) * 1000  -- Convert seconds to milliseconds

                -- Calculate percentage of the next note's length
                local extension_ms = math.max(next_note_length_ms * extension_percentage, 1)  -- At least 1ms extension

                local extension_ppq = ms_to_ppq_corrected(extension_ms, current_take, note.startppqpos)
                new_end_ppq = new_end_ppq + extension_ppq
            end

            -- Apply overlap prevention
            new_end_ppq = M.apply_overlap_constraints(note, selected_notes, new_end_ppq)
            
            -- Apply boundary constraints (default to false for quick scripts)
            new_end_ppq = M.apply_boundary_constraints(note, new_end_ppq, current_take, false)

            -- Set the note end position
            M.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq)
        end
    end
end

-- Function to finalize changes (sort, update, register undo)
function M.finalize_changes(current_take, undo_message)
    local item = reaper.GetMediaItemTake_Item(current_take)
    
    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateItemInProject(item)
    reaper.Undo_OnStateChange_Item(0, undo_message, item)
    reaper.UpdateArrange()
    
    return item
end

return M