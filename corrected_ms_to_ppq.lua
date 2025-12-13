-- Corrected version of the ms_to_ppq function that properly handles tempo changes
-- This function converts milliseconds to PPQ (pulses per quarter note) changes for a specific note position
function ms_to_ppq_corrected(ms, take, note_ppq_pos)
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
function get_ppq_delta_for_ms_at_position(ms, take, start_ppq_pos)
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