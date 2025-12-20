-- @noindex
-- @description Parallel intervals detection module for MIDI analysis

local reaper = reaper

-- Import shared utilities
local MIDI_UTILS = require "midi_utils"

local M = {}

-- Constants for parallel detection
M.CONSTANTS = {
    TOLERANCE_MS = 0.040,  -- Time window (in seconds) for grouping notes into "chords" (40ms)
    DEFAULT_PPQ_THRESHOLD = 10,  -- PPQ threshold for note simultaneity
    MARKER_COLOR = reaper.ColorToNative(255, 0, 0)|0x1000000,  -- Red marker color
    PERFECT_FIFTH_INTERVAL = 7,  -- Mod 12 value for perfect fifth
    PERFECT_OCTAVE_INTERVAL = 0,  -- Mod 12 value for perfect octave
    PERFECT_FOURTH_INTERVAL = 5,  -- Mod 12 value for perfect fourth
}

-- Function to check if an interval is a perfect fifth (or 12th, etc.)
function M.is_perfect_fifth(note_a, note_b)
    local diff = math.abs(note_a - note_b)
    return (diff % 12) == M.CONSTANTS.PERFECT_FIFTH_INTERVAL
end

-- Function to check if an interval is a perfect octave (or double octave, etc.)
function M.is_perfect_octave(note_a, note_b)
    local diff = math.abs(note_a - note_b)
    return (diff % 12) == M.CONSTANTS.PERFECT_OCTAVE_INTERVAL
end

-- Function to check if an interval is a perfect fourth (or 11th, etc.)
function M.is_perfect_fourth(note_a, note_b)
    local diff = math.abs(note_a - note_b)
    return (diff % 12) == M.CONSTANTS.PERFECT_FOURTH_INTERVAL
end

-- Function to check if two notes move in parallel motion
function M.is_parallel_motion(note1_curr, note2_curr, note1_next, note2_next)
    -- Calculate deltas for both voices
    local delta1 = note1_next - note1_curr
    local delta2 = note2_next - note2_curr
    
    -- Check if both voices are moving (not static)
    if delta1 == 0 and delta2 == 0 then
        return false  -- Static motion is not parallel
    end
    
    -- Check if both voices move in the same direction
    local sign1 = 0
    if delta1 > 0 then sign1 = 1 elseif delta1 < 0 then sign1 = -1 end
    
    local sign2 = 0
    if delta2 > 0 then sign2 = 1 elseif delta2 < 0 then sign2 = -1 end
    
    return sign1 == sign2 and sign1 ~= 0  -- Same non-zero direction
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

-- Function to group notes into chords based on start time proximity
function M.group_notes_into_chords(notes, ppq_threshold)
    if not notes then
        return {}
    end
    
    ppq_threshold = ppq_threshold or M.CONSTANTS.DEFAULT_PPQ_THRESHOLD
    
    -- Sort notes by start time (with nil checks)
    table.sort(notes, function(a, b) 
        if not a or not a.start then return false end
        if not b or not b.start then return true end
        return a.start < b.start 
    end)
    
    local chords = {}
    local current_chord = {}
    local current_start_ppq = -1
    
    for i, note in ipairs(notes) do
        if #current_chord == 0 then
            table.insert(current_chord, note)
            current_start_ppq = note.start
        else
            -- Check time difference
            local ppq_diff = note.start - current_start_ppq
            if ppq_diff < ppq_threshold then
                -- Same chord
                table.insert(current_chord, note)
            else
                -- Save previous chord and start new one
                table.sort(current_chord, function(a, b) return a.pitch < b.pitch end)
                table.insert(chords, current_chord)
                
                current_chord = {note}
                current_start_ppq = note.start
            end
        end
    end
    
    -- Add the last chord
    if #current_chord > 0 then
        table.sort(current_chord, function(a, b) return a.pitch < b.pitch end)
        table.insert(chords, current_chord)
    end
    
    return chords
end

-- Function to analyze chords for parallel intervals
function M.analyze_parallel_intervals(chords, interval_check_func, take)
    local errors_found = {}
    
    for i = 1, #chords - 1 do
        local chord_curr = chords[i]
        local chord_next = chords[i + 1]
        
        -- Use the minimum number of voices to avoid index errors
        local voices_count = math.min(#chord_curr, #chord_next)
        
        -- Check all pairs of voices
        for vA = 1, voices_count do
            for vB = vA + 1, voices_count do
                -- Get pitches (with nil checks)
                local note_A_curr = chord_curr[vA]
                local note_B_curr = chord_curr[vB]
                local note_A_next = chord_next[vA]
                local note_B_next = chord_next[vB]
                
                -- Skip if any note is nil
                if not note_A_curr or not note_B_curr or not note_A_next or not note_B_next then
                    -- continue to next voice pair
                else
                    local pitch_A_curr = note_A_curr.pitch
                    local pitch_B_curr = note_B_curr.pitch
                    local pitch_A_next = note_A_next.pitch
                    local pitch_B_next = note_B_next.pitch
                    
                    -- Skip if any pitch is nil
                    if pitch_A_curr and pitch_B_curr and pitch_A_next and pitch_B_next then
                        -- Calculate intervals
                        local int_curr = math.abs(pitch_B_curr - pitch_A_curr)
                        local int_next = math.abs(pitch_B_next - pitch_A_next)
                        
                        -- Check if both intervals match the target interval type
                        if interval_check_func(pitch_A_curr, pitch_B_curr) and 
                           interval_check_func(pitch_A_next, pitch_B_next) then
                            
                            -- Check for parallel motion
                            if M.is_parallel_motion(pitch_A_curr, pitch_B_curr, pitch_A_next, pitch_B_next) then
                                -- Parallel interval detected
                                local error_info = {
                                    chord_index = i,
                                    voice_A = vA,
                                    voice_B = vB,
                                    pitch_A_curr = pitch_A_curr,
                                    pitch_B_curr = pitch_B_curr,
                                    pitch_A_next = pitch_A_next,
                                    pitch_B_next = pitch_B_next,
                                    interval_curr = int_curr,
                                    interval_next = int_next,
                                    position_ppq = chord_curr[vA].start
                                }
                                
                                table.insert(errors_found, error_info)
                            end
                        end
                    end
                end
            end
        end
    end
    
    return errors_found
end

-- Function to select notes involved in parallel intervals
function M.select_notes_for_errors(errors_found, take, interval_type_name)
    if not take or #errors_found == 0 then
        return0
    end
    
    -- Collect all note indices involved in parallel intervals
    local note_indices_to_select = {}
    
    -- Get all notes from the take to find the actual indices
    local retval, notecnt, _, _ = reaper.MIDI_CountEvts(take)
    if not retval or notecnt == 0 then
        return0
    end
    
    -- Create a map of notes by pitch and position for easier lookup
    local note_map = {}
    for note_idx = 0, notecnt - 1 do
        local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
        if not muted then
            local key = pitch .. "_" .. startppq  -- Unique key for pitch+position
            note_map[key] = note_idx
        end
    end
    
    -- Find notes involved in parallel intervals
    for _, error_info in ipairs(errors_found) do
        -- Create keys for the four notes involved
        local key_A_curr = error_info.pitch_A_curr .. "_" .. error_info.position_ppq
        local key_B_curr = error_info.pitch_B_curr .. "_" .. error_info.position_ppq
        
        -- Add current chord notes
        if note_map[key_A_curr] and not M.table_contains(note_indices_to_select, note_map[key_A_curr]) then
            table.insert(note_indices_to_select, note_map[key_A_curr])
        end
        if note_map[key_B_curr] and not M.table_contains(note_indices_to_select, note_map[key_B_curr]) then
            table.insert(note_indices_to_select, note_map[key_B_curr])
        end
        
        -- For next chord notes, we need to estimate their position
        -- This is approximate since we don't have exact next chord position
        local next_chord_estimate = error_info.position_ppq + 240  -- Rough estimate (quarter note)
        local key_A_next = error_info.pitch_A_next .. "_" .. next_chord_estimate
        local key_B_next = error_info.pitch_B_next .. "_" .. next_chord_estimate
        
        -- Find notes with matching pitch in the next chord region
        for note_idx = 0, notecnt - 1 do
            local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
            if not muted and startppq > error_info.position_ppq and startppq <= next_chord_estimate + 120 then
                if pitch == error_info.pitch_A_next or pitch == error_info.pitch_B_next then
                    if not M.table_contains(note_indices_to_select, note_idx) then
                        table.insert(note_indices_to_select, note_idx)
                    end
                end
            end
        end
    end
    
    -- Deselect all notes first
    for note_idx = 0, notecnt - 1 do
        reaper.MIDI_SetNote(take, note_idx, false, nil, nil, nil, nil, nil, true)
    end
    
    -- Select the identified notes
    for _, note_idx in ipairs(note_indices_to_select) do
        reaper.MIDI_SetNote(take, note_idx, true, nil, nil, nil, nil, nil, true)
    end
    
    return #note_indices_to_select
end

-- Function to add markers for detected parallel intervals (kept for compatibility)
function M.add_markers_for_errors(errors_found, take, interval_type_name)
    if not take or #errors_found == 0 then
        return 0
    end
    
    local markers_added = 0
    
    for _, error_info in ipairs(errors_found) do
        -- Convert PPQ position to project time
        local time_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, error_info.position_ppq)
        
        -- Create marker description
        local description = string.format("Parallel %s! Voices %d&%d: %d->%d and %d->%d",
            interval_type_name,
            error_info.voice_A, error_info.voice_B,
            error_info.pitch_A_curr, error_info.pitch_A_next,
            error_info.pitch_B_curr, error_info.pitch_B_next)
        
        -- Add marker
        reaper.AddProjectMarker2(0, false, time_pos, 0, description, -1, M.CONSTANTS.MARKER_COLOR)
        markers_added = markers_added + 1
    end
    
    return markers_added
end

-- Main function to detect parallel fifths
function M.detect_parallel_fifths(take, notes)
    if not take or not notes or #notes == 0 then
        return {}
    end
    
    -- Group notes into chords
    local chords = M.group_notes_into_chords(notes)
    
    -- Analyze for parallel fifths
    local errors_found = M.analyze_parallel_intervals(chords, M.is_perfect_fifth, take)
    
    -- Add markers
    M.add_markers_for_errors(errors_found, take, "fifths")
    
    return errors_found
end

-- Main function to detect parallel octaves
function M.detect_parallel_octaves(take, notes)
    if not take or not notes or #notes == 0 then
        return {}
    end
    
    -- Group notes into chords
    local chords = M.group_notes_into_chords(notes)
    
    -- Analyze for parallel octaves
    local errors_found = M.analyze_parallel_intervals(chords, M.is_perfect_octave, take)
    
    -- Add markers
    M.add_markers_for_errors(errors_found, take, "octaves")
    
    return errors_found
end

-- Main function to detect parallel fourths
function M.detect_parallel_fourths(take, notes)
    if not take or not notes or #notes == 0 then
        return {}
    end
    
    -- Group notes into chords
    local chords = M.group_notes_into_chords(notes)
    
    -- Analyze for parallel fourths
    local errors_found = M.analyze_parallel_intervals(chords, M.is_perfect_fourth, take)
    
    -- Add markers
    M.add_markers_for_errors(errors_found, take, "fourths")
    
    return errors_found
end

-- Generic function to detect any parallel intervals
function M.detect_parallel_intervals(take, notes, interval_types)
    if not take or not notes or #notes == 0 then
        return {}
    end
    
    interval_types = interval_types or {"fifths"}  -- Default to fifths
    
    local all_errors = {}
    
    -- Group notes into chords once
    local chords = M.group_notes_into_chords(notes)
    
    -- Check each requested interval type
    for _, interval_type in ipairs(interval_types) do
        local check_func
        local type_name
        
        if interval_type == "fifths" then
            check_func = M.is_perfect_fifth
            type_name = "fifths"
        elseif interval_type == "octaves" then
            check_func = M.is_perfect_octave
            type_name = "octaves"
        elseif interval_type == "fourths" then
            check_func = M.is_perfect_fourth
            type_name = "fourths"
        else
            -- Skip unknown interval types
            goto continue
        end
        
        -- Analyze for this interval type
        local errors_found = M.analyze_parallel_intervals(chords, check_func, take)
        
        -- Add markers for this interval type
        M.add_markers_for_errors(errors_found, take, type_name)
        
        -- Add to total errors
        for _, error_info in ipairs(errors_found) do
            error_info.interval_type = type_name
            table.insert(all_errors, error_info)
        end
        
        ::continue::
    end
    
    return all_errors
end

-- Function to get all notes from a take (not just selected)
function M.get_all_notes_from_take(take)
    if not take then
        return {}
    end
    
    local retval, notecnt, _, _ = reaper.MIDI_CountEvts(take)
    if not retval or notecnt == 0 then
        return {}
    end
    
    local notes = {}
    
    for i = 0, notecnt - 1 do
        local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if not muted then  -- Skip muted notes
            table.insert(notes, {
                pitch = pitch,
                start = startppq,
                endppq = endppq,
                chan = chan,
                vel = vel,
                selected = selected,
                id = i
            })
        end
    end
    
    return notes
end

-- Function to log detection results to console
function M.log_detection_results(errors_found, interval_type)
    interval_type = interval_type or "intervals"
    
    if #errors_found == 0 then
        reaper.ShowConsoleMsg("No parallel " .. interval_type .. " found.\n")
        return
    end
    
    reaper.ShowConsoleMsg("Found " .. #errors_found .. " cases of parallel " .. interval_type .. ":\n")
    
    for _, error_info in ipairs(errors_found) do
        local msg = string.format("  Chord %d -> %d. Voices %d and %d. Notes: %d->%d and %d->%d\n",
            error_info.chord_index, error_info.chord_index + 1,
            error_info.voice_A, error_info.voice_B,
            error_info.pitch_A_curr, error_info.pitch_A_next,
            error_info.pitch_B_curr, error_info.pitch_B_next)
        reaper.ShowConsoleMsg(msg)
    end
end

return M