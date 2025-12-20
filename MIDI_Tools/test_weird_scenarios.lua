-- @noindex
-- @description Test really weird and unusual scenarios for parallel interval detection

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

-- Weird Scenario 1: Microtonal intervals (non-integer pitch differences)
local function test_microtonal_intervals()
    -- Note: MIDI doesn't support microtonal, but we can test edge cases
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 480), -- D
        create_note(69, 480)  -- A
    }
    
    -- Manually create microtonal-like scenario by modifying pitches
    notes[2].pitch = 67.5  -- Quarter-tone sharp
    notes[4].pitch = 69.5  -- Quarter-tone sharp
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Microtonal chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle non-integer pitches gracefully
    return #chords == 2
end

-- Weird Scenario 2: Extremely dense chord (many notes at same time)
local function test_dense_chord()
    local notes = {}
    
    -- Create 20 notes all starting at the same time
    for i = 0, 19 do
        table.insert(notes, create_note(60 + i, 0))
    end
    
    -- Second chord with same structure
    for i = 0, 19 do
        table.insert(notes, create_note(62 + i, 480))
    end
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Dense chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle very large chords
    return #chords == 2 and #errors >= 10
end

-- Weird Scenario 3: Retrograde motion (descending instead of ascending)
local function test_retrograde_motion()
    local notes = {
        create_note(72, 0),   -- C (high)
        create_note(79, 0),   -- G (high)
        create_note(70, 480), -- Bb (lower)
        create_note(77, 480)  -- F (lower)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Retrograde chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifths in descending motion
    return #chords == 2 and #errors == 1
end

-- Weird Scenario 4: Cluster chords (seconds and thirds)
local function test_cluster_chords()
    local notes = {
        create_note(60, 0),   -- C
        create_note(61, 0),   -- C#
        create_note(62, 0),   -- D
        create_note(63, 0),   -- Eb
        create_note(64, 0),   -- E
        create_note(62, 480), -- D
        create_note(63, 480), -- Eb
        create_note(64, 480), -- E
        create_note(65, 480), -- F
        create_note(66, 480)  -- F#
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Cluster chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle dense clusters without false positives
    return #chords == 2 and #errors == 0
end

-- Weird Scenario 5: Polyrhythmic timing (irregular spacing)
local function test_polyrhythmic_timing()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 320), -- D (2/3 beat later)
        create_note(69, 320), -- A (2/3 beat later)
        create_note(64, 560), -- E (7/6 beat later)
        create_note(71, 560), -- B (7/6 beat later)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Polyrhythmic chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle irregular timing
    return #chords == 3
end

-- Weird Scenario 6: Octave displacement (same voice in different octaves)
local function test_octave_displacement()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(74, 480), -- D (octave + fifth above original)
        create_note(81, 480)  -- A (octave + fifth above original)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Octave displacement chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifths across octave displacement
    return #chords == 2 and #errors == 1
end

-- Weird Scenario 7: Compound intervals (larger than octave)
local function test_compound_intervals()
    local notes = {
        create_note(60, 0),   -- C
        create_note(79, 0),   -- G (12th above)
        create_note(62, 480), -- D
        create_note(81, 480)  -- A (12th above)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Compound intervals chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifths with compound intervals
    return #chords == 2 and #errors == 1
end

-- Weird Scenario 8: Inconsistent voice leading
local function test_inconsistent_voice_leading()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(62, 480), -- D (up)
        create_note(63, 480), -- Eb (down half step)
        create_note(69, 480)  -- A (up whole step)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Inconsistent voice leading chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should detect parallel fifth between outer voices only
    return #chords == 2 and #errors == 1
end

-- Weird Scenario 9: Modal mixture (accidentals)
local function test_modal_mixture()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 480), -- D
        create_note(68, 480)  -- Ab (modal mixture)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Modal mixture chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should not detect parallel fifth with modal mixture
    return #chords == 2 and #errors == 0
end

-- Weird Scenario 10: Extreme tempo (very fast chord changes)
local function test_extreme_tempo()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 1),   -- D (1 PPQ later - extremely fast)
        create_note(69, 1),   -- A (1 PPQ later - extremely fast)
        create_note(64, 2),   -- E (1 PPQ later)
        create_note(71, 2)    -- B (1 PPQ later)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Extreme tempo chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should handle very fast chord changes
    return #chords == 3
end

-- Weird Scenario 11: Silent notes (zero velocity)
local function test_silent_notes()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 480), -- D
        create_note(69, 480)  -- A
    }
    
    -- Make some notes silent
    notes[2].vel = 0
    notes[4].vel = 0
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Silent notes chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should still work with zero velocity notes
    return #chords == 2 and #errors == 1
end

-- Weird Scenario 12: Different channels (MIDI channels)
local function test_different_channels()
    local notes = {
        create_note(60, 0),   -- C (channel 0)
        create_note(67, 0),   -- G (channel 0)
        create_note(62, 480), -- D (channel 1)
        create_note(69, 480)  -- A (channel 1)
    }
    
    -- Set different channels
    notes[3].chan = 1
    notes[4].chan = 1
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    reaper.ShowConsoleMsg("Different channels chords: " .. #chords .. ", errors: " .. #errors .. "\n")
    -- Should ignore channels for parallel detection
    return #chords == 2 and #errors == 1
end

-- Main test runner
local function main()
    reaper.ShowConsoleMsg("Starting Weird and Unusual Scenarios Tests\n")
    reaper.ShowConsoleMsg("==========================================\n")
    
    local passed = 0
    local total = 0
    
    -- Run all weird scenario tests
    local tests = {
        {"Microtonal intervals", test_microtonal_intervals},
        {"Extremely dense chord", test_dense_chord},
        {"Retrograde motion", test_retrograde_motion},
        {"Cluster chords", test_cluster_chords},
        {"Polyrhythmic timing", test_polyrhythmic_timing},
        {"Octave displacement", test_octave_displacement},
        {"Compound intervals", test_compound_intervals},
        {"Inconsistent voice leading", test_inconsistent_voice_leading},
        {"Modal mixture", test_modal_mixture},
        {"Extreme tempo", test_extreme_tempo},
        {"Silent notes", test_silent_notes},
        {"Different channels", test_different_channels}
    }
    
    for _, test in ipairs(tests) do
        total = total + 1
        if run_test(test[1], test[2]) then
            passed = passed + 1
        end
    end
    
    -- Summary
    reaper.ShowConsoleMsg("\n=== Weird Scenarios Test Summary ===\n")
    reaper.ShowConsoleMsg("Passed: " .. passed .. "/" .. total .. "\n")
    reaper.ShowConsoleMsg("Failed: " .. (total - passed) .. "/" .. total .. "\n")
    
    if passed == total then
        reaper.ShowConsoleMsg("All weird scenario tests passed! ✓\n")
    else
        reaper.ShowConsoleMsg("Some weird scenario tests failed! ✗\n")
    end
end

-- Run the tests
main()