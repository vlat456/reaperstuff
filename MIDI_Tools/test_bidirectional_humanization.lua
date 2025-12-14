-- @noindex
-- Test script for bidirectional humanization functionality

-- Centralized require statement at the top of the file
local LEGATO_COMMON = require "legato_common"

-- Function to test bidirectional humanization
function test_bidirectional_humanization()
    -- Get current MIDI context
    local current_take = LEGATO_COMMON.get_active_take()
    
    if not current_take then
        reaper.MB("No active MIDI take found. Please open a MIDI editor and select some notes.", "Test Error", 0)
        return
    end
    
    -- Count selected notes
    local note_count = LEGATO_COMMON.count_selected_notes()
    
    if note_count < 2 then
        reaper.MB("Please select at least 2 notes for testing bidirectional humanization.", "Test Error", 0)
        return
    end
    
    -- Store original note positions for comparison
    local original_notes = LEGATO_COMMON.get_selected_notes()
    
    -- Apply bidirectional humanization with 50% strength
    LEGATO_COMMON.apply_humanization(50, false, false)  -- 50% strength, no boundary constraints, no undo
    
    -- Get the modified notes
    local modified_notes = LEGATO_COMMON.get_selected_notes()
    
    -- Analyze the changes
    local shortened_count = 0
    local lengthened_count = 0
    local unchanged_count = 0
    
    for i = 1, #original_notes do
        local original_end = original_notes[i].endppqpos
        local modified_end = modified_notes[i].endppqpos
        
        if modified_end < original_end then
            shortened_count = shortened_count + 1
        elseif modified_end > original_end then
            lengthened_count = lengthened_count + 1
        else
            unchanged_count = unchanged_count + 1
        end
    end
    
    -- Display results
    local message = string.format(
        "Bidirectional Humanization Test Results:\n\n" ..
        "Total notes processed: %d\n" ..
        "Notes shortened: %d\n" ..
        "Notes lengthened: %d\n" ..
        "Notes unchanged: %d\n\n" ..
        "If you see both shortened and lengthened notes, the bidirectional humanization is working correctly!",
        note_count, shortened_count, lengthened_count, unchanged_count
    )
    
    reaper.MB(message, "Bidirectional Humanization Test", 0)
    
    -- Check if legato is maintained
    local legato_maintained = true
    local sorted_modified = LEGATO_COMMON.get_cached_sorted_selected_notes()
    
    for i = 1, #sorted_modified - 1 do
        local current_note = sorted_modified[i]
        local next_note = sorted_modified[i + 1]
        
        -- Check if current note extends beyond next note start (same pitch)
        if current_note.pitch == next_note.pitch and current_note.endppqpos > next_note.startppqpos then
            legato_maintained = false
            break
        end
    end
    
    if not legato_maintained then
        reaper.MB("Warning: Legato may not be properly maintained for same-pitch notes.", "Legato Check", 0)
    end
end

-- Run the test
test_bidirectional_humanization()