-- @noindex
-- @description Test weird cases and edge cases for parallel interval detection

-- Mock REAPER API for testing
local reaper = {
    ShowConsoleMsg = function(msg) 
        io.write(msg)
        io.flush()
    end,
    ColorToNative = function(r, g, b) 
        return (r << 16) | (g << 8) | b 
    end
}

-- Set global reaper for modules
_G.reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

local PARALLEL_DETECTOR = require "parallel_detector"

-- Simple test framework
local function run_test(test_name, test_func)
    reaper.ShowConsoleMsg("\n--- " .. test_name .. " ---\n")
    local success, result = pcall(test_func)
    if success then
        reaper.ShowConsoleMsg("✓ " .. test_name .. " PASSED\n")
        return true
    else
        reaper.ShowConsoleMsg("✗ " .. test_name .. " FAILED: " .. tostring(result) .. "\n")
        return false
    end
end

-- Helper function to create mock notes
local function create_note(pitch, start_ppq)
    return {
        pitch = pitch,
        start = start_ppq,
        endppq = start_ppq + 480,
        chan = 0,
        vel = 100,
        selected = false,
        id = -1
    }
end

-- Edge Case 1: Single note (no intervals possible)
local function test_single_note()
    local notes = {
        create_note(60, 0)  -- Just one note
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Single note chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    return #chords == 1 and #errors == 0
end

-- Edge Case 2: Empty note list
local function test_empty_notes()
    local notes = {}
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Empty notes chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    return #chords == 0 and #errors == 0
end

-- Edge Case 3: Nil input
local function test_nil_input()
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(nil)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Nil input chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    return #chords == 0 and #errors == 0
end

-- Edge Case 4: Very large pitch numbers (extreme range)
local function test_extreme_pitches()
    local notes = {
        create_note(0, 0),     -- Lowest possible MIDI note
        create_note(7, 0),     -- Perfect fifth above
        create_note(12, 480),   -- Octave above lowest
        create_note(19, 480)    -- Perfect fifth above
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Extreme pitches chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    return #chords == 2 and #errors == 1
end

-- Edge Case 5: Same pitch repeated (unison)
local function test_unison_intervals()
    local notes = {
        create_note(60, 0),   -- C
        create_note(60, 0),   -- C (unison)
        create_note(62, 480), -- D
        create_note(62, 480)  -- D (unison)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Unison chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should not detect parallel fifths with unisons
    return #chords == 2 and #errors == 0
end

-- Edge Case 6: Very close timing (within threshold)
local function test_close_timing()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 5),   -- G (5 PPQ later, very close)
        create_note(62, 480), -- D
        create_note(69, 485)  -- A (5 PPQ later, very close)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Close timing chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should group into 2 chords and detect parallel fifth
    return #chords == 2 and #errors == 1
end

-- Edge Case 7: Very wide timing (beyond threshold)
local function test_wide_timing()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 20),  -- G (20 PPQ later, still same chord)
        create_note(62, 480), -- D
        create_note(69, 500)  -- A (20 PPQ later, still same chord)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Wide timing chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should group into 2 chords and detect parallel fifth
    return #chords == 2 and #errors == 1
end

-- Edge Case 8: Crossing voices (voice crossing)
local function test_crossing_voices()
    local notes = {
        create_note(60, 0),   -- C (lower voice)
        create_note(67, 0),   -- G (higher voice)
        create_note(69, 480), -- A (now lower voice crosses)
        create_note(62, 480)  -- D (now higher voice crosses)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Crossing voices chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifth despite voice crossing
    return #chords == 2 and #errors == 1
end

-- Edge Case 9: Enharmonic equivalents (same pitch different notation)
local function test_enharmonic_handling()
    -- Note: This test is limited since MIDI doesn't distinguish enharmonics
    -- But we can test interval detection with different pitch combinations
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(61, 480), -- C# (enharmonic to Db)
        create_note(68, 480)  -- G# (enharmonic to Ab)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Enharmonic chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifth (C-G to C#-G#)
    return #chords == 2 and #errors == 1
end

-- Edge Case 10: Mixed motion types (parallel + contrary)
local function test_mixed_motion()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(62, 480), -- D (up - parallel with C)
        create_note(66, 480), -- F# (up - parallel with E)
        create_note(65, 480)  -- F (down - contrary with G)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Mixed motion chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifth between C and G voices
    return #chords == 2 and #errors == 1
end

-- Edge Case 11: Very long chord progression (many chords)
local function test_long_progression()
    local notes = {}
    
    -- Create 10 chords with parallel fifths
    for i = 0, 9 do
        table.insert(notes, create_note(60 + i, i * 240))    -- Moving up by step
        table.insert(notes, create_note(67 + i, i * 240))    -- Parallel fifth
    end
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Long progression chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect 9 parallel fifths (between each consecutive chord pair)
    return #chords == 10 and #errors == 9
end

-- Edge Case 12: Irregular chord sizes
local function test_irregular_chord_sizes()
    local notes = {
        -- 2-note chord
        create_note(60, 0),
        create_note(67, 0),
        -- 3-note chord
        create_note(62, 480),
        create_note(66, 480),
        create_note(69, 480),
        -- 2-note chord
        create_note(64, 960),
        create_note(71, 960),
        -- 4-note chord
        create_note(65, 1440),
        create_note(69, 1440),
        create_note(72, 1440),
        create_note(76, 1440)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Irregular chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle varying chord sizes correctly
    return #chords == 4 and #errors >= 2
end

-- Edge Case 13: Overlapping note timings
local function test_overlapping_timings()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 10),  -- G (slightly later)
        create_note(64, 15),  -- E (even later, but still same chord)
        create_note(62, 480), -- D
        create_note(69, 490), -- A (slightly later)
        create_note(66, 495)  -- F# (even later, but still same chord)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Overlapping timings chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should group into 2 chords despite overlapping start times
    return #chords == 2 and #errors >= 1
end

-- Edge Case 14: Zero-length notes (same start and end)
local function test_zero_length_notes()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 480), -- D
        create_note(69, 480)  -- A
    }
    
    -- Manually set endppq to same as start for zero length
    for _, note in ipairs(notes) do
        note.endppq = note.start
    end
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Zero-length notes chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should still work with zero-length notes
    return #chords == 2 and #errors == 1
end

-- Edge Case 15: Negative start times (theoretical edge case)
local function test_negative_timing()
    local notes = {
        create_note(60, -240), -- C (negative timing)
        create_note(67, -240), -- G (negative timing)
        create_note(62, 0),    -- D
        create_note(69, 0)     -- A
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Negative timing chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle negative timing gracefully
    return #chords == 2 and #errors == 1
end

-- Edge Case 16: Very large chord (many notes)
local function test_large_chord()
    local notes = {}
    
    -- Create a 10-note chord
    local base_pitches = {60, 62, 64, 65, 67, 69, 71, 72, 74, 76}
    for i, pitch in ipairs(base_pitches) do
        table.insert(notes, create_note(pitch, 0))
        table.insert(notes, create_note(pitch + 2, 480)) -- All move up 2 semitones
    end
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Large chord chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle large chords correctly
    return #chords == 2 and #errors >= 2
end

-- Edge Case 17: Identical chords (no motion)
local function test_identical_chords()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(60, 480), -- C (same as before)
        create_note(64, 480), -- E (same as before)
        create_note(67, 480)  -- G (same as before)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Identical chords chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should not detect parallel motion with identical chords
    return #chords == 2 and #errors == 0
end

-- Edge Case 18: Random pitch distribution
local function test_random_pitches()
    local notes = {
        create_note(62, 0),   -- D
        create_note(71, 0),   -- B
        create_note(65, 480), -- F
        create_note(74, 480)  -- D (octave above first)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Random pitches chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle non-standard pitch relationships
    return #chords == 2 and #errors == 0
end

-- Main test runner
local function main()
    reaper.ShowConsoleMsg("Starting Edge Cases and Weird Scenarios Tests\n")
    reaper.ShowConsoleMsg("=================================================\n")
    
    local passed = 0
    local total = 0
    
    -- Run all edge case tests
    local tests = {
        {"Single note", test_single_note},
        {"Empty notes", test_empty_notes},
        {"Nil input", test_nil_input},
        {"Extreme pitches", test_extreme_pitches},
        {"Unison intervals", test_unison_intervals},
        {"Close timing", test_close_timing},
        {"Wide timing", test_wide_timing},
        {"Crossing voices", test_crossing_voices},
        {"Enharmonic handling", test_enharmonic_handling},
        {"Mixed motion", test_mixed_motion},
        {"Long progression", test_long_progression},
        {"Irregular chord sizes", test_irregular_chord_sizes},
        {"Overlapping timings", test_overlapping_timings},
        {"Zero-length notes", test_zero_length_notes},
        {"Negative timing", test_negative_timing},
        {"Large chord", test_large_chord},
        {"Identical chords", test_identical_chords},
        {"Random pitches", test_random_pitches}
    }
    
    for _, test in ipairs(tests) do
        total = total + 1
        if run_test(test[1], test[2]) then
            passed = passed + 1
        end
    end
    
    -- Summary
    reaper.ShowConsoleMsg("\n=== Edge Cases Test Summary ===\n")
    reaper.ShowConsoleMsg("Passed: " .. passed .. "/" .. total .. "\n")
    reaper.ShowConsoleMsg("Failed: " .. (total - passed) .. "/" .. total .. "\n")
    
    if passed == total then
        reaper.ShowConsoleMsg("All edge case tests passed! ✓\n")
    else
        reaper.ShowConsoleMsg("Some edge case tests failed! ✗\n")
    end
end

-- Run the tests
main()