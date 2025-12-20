-- @noindex
-- @description Test specific parallel interval scenarios with different chord sizes

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

-- Helper function to run a test and report results
local function run_scenario(name, notes, expected_fifths, expected_octaves, expected_fourths)
    reaper.ShowConsoleMsg("\n=== " .. name .. " ===\n")
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    reaper.ShowConsoleMsg("Chords formed:\n")
    for i, chord in ipairs(chords) do
        reaper.ShowConsoleMsg("  Chord " .. i .. ": ")
        for j, note in ipairs(chord) do
            reaper.ShowConsoleMsg(note.pitch .. " ")
        end
        reaper.ShowConsoleMsg("\n")
    end
    
    -- Test each interval type
    local fifths = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    local octaves = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_octave)
    local fourths = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fourth)
    
    reaper.ShowConsoleMsg("Parallel fifths: " .. #fifths .. " (expected: " .. expected_fifths .. ")\n")
    reaper.ShowConsoleMsg("Parallel octaves: " .. #octaves .. " (expected: " .. expected_octaves .. ")\n")
    reaper.ShowConsoleMsg("Parallel fourths: " .. #fourths .. " (expected: " .. expected_fourths .. ")\n")
    
    -- Show details for detected parallels
    if #fifths > 0 then
        reaper.ShowConsoleMsg("Fifth details:\n")
        for _, error in ipairs(fifths) do
            reaper.ShowConsoleMsg(string.format("  Voices %d&%d: %d->%d and %d->%d\n",
                error.voice_A, error.voice_B,
                error.pitch_A_curr, error.pitch_A_next,
                error.pitch_B_curr, error.pitch_B_next))
        end
    end
    
    if #octaves > 0 then
        reaper.ShowConsoleMsg("Octave details:\n")
        for _, error in ipairs(octaves) do
            reaper.ShowConsoleMsg(string.format("  Voices %d&%d: %d->%d and %d->%d\n",
                error.voice_A, error.voice_B,
                error.pitch_A_curr, error.pitch_A_next,
                error.pitch_B_curr, error.pitch_B_next))
        end
    end
    
    if #fourths > 0 then
        reaper.ShowConsoleMsg("Fourth details:\n")
        for _, error in ipairs(fourths) do
            reaper.ShowConsoleMsg(string.format("  Voices %d&%d: %d->%d and %d->%d\n",
                error.voice_A, error.voice_B,
                error.pitch_A_curr, error.pitch_A_next,
                error.pitch_B_curr, error.pitch_B_next))
        end
    end
    
    -- Check results
    local success = (#fifths == expected_fifths and 
                    #octaves == expected_octaves and 
                    #fourths == expected_fourths)
    
    if success then
        reaper.ShowConsoleMsg("✓ Scenario PASSED\n")
    else
        reaper.ShowConsoleMsg("✗ Scenario FAILED\n")
    end
    
    return success
end

-- Scenario 1: Simple 2-note parallel fifths
local function scenario_2note_fifths()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G (fifth)
        create_note(62, 480), -- D
        create_note(69, 480)  -- A (fifth)
    }
    return run_scenario("2-note parallel fifths", notes, 1, 0, 0)
end

-- Scenario 2: 3-note chords with outer voice parallel fifths
local function scenario_3note_outer_fifths()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480)  -- A
    }
    return run_scenario("3-note outer voice fifths", notes, 1, 0, 0)
end

-- Scenario 3: 3-note chords with parallel octaves
local function scenario_3note_octaves()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(72, 0),   -- C (octave)
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(74, 480)  -- D (octave)
    }
    return run_scenario("3-note parallel octaves", notes, 0, 1, 0)
end

-- Scenario 4: 4-note chords with multiple parallel fifths
local function scenario_4note_multiple_fifths()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(72, 0),   -- C (octave)
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480), -- A
        create_note(74, 480)  -- D (octave)
    }
    return run_scenario("4-note multiple fifths", notes, 1, 1, 1)
end

-- Scenario 5: 4-note chords with parallel fourths
local function scenario_4note_fourths()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(65, 0),   -- F (fourth above C)
        create_note(69, 0),   -- A
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480), -- A (fourth above E)
        create_note(73, 480)  -- C#
    }
    return run_scenario("4-note parallel fourths", notes, 0, 0, 0)
end

-- Scenario 6: 5-note chords with complex parallel motion
local function scenario_5note_complex()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(71, 0),   -- B
        create_note(72, 0),   -- C (octave)
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480), -- A
        create_note(73, 480), -- C#
        create_note(74, 480)  -- D (octave)
    }
    return run_scenario("5-note complex parallels", notes, 2, 1, 1)
end

-- Scenario 7: Contrary motion (no parallels)
local function scenario_contrary_motion()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(69, 480), -- A (up)
        create_note(65, 480)  -- F (down)
    }
    return run_scenario("Contrary motion", notes, 0, 0, 0)
end

-- Scenario 8: Static voice (should not be detected)
local function scenario_static_voice()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(62, 480), -- D (moves)
        create_note(67, 480)  -- G (static)
    }
    return run_scenario("Static voice", notes, 0, 0, 0)
end

-- Scenario 9: Mixed parallel intervals in 4-note texture
local function scenario_mixed_intervals()
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(72, 0),   -- C (octave)
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480), -- A
        create_note(74, 480)  -- D (octave)
    }
    return run_scenario("Mixed intervals", notes, 1, 1, 1)
end

-- Scenario 10: Three-chord progression with multiple parallels
local function scenario_three_chord_progression()
    local notes = {
        -- Chord 1: C major
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        
        -- Chord 2: G major (parallel fifth from C-E)
        create_note(67, 480), -- G
        create_note(71, 480), -- B
        create_note(74, 480), -- D
        
        -- Chord 3: D major (parallel fifth from G-B)
        create_note(62, 960), -- D
        create_note(66, 960), -- F#
        create_note(69, 960)  -- A
    }
    return run_scenario("Three-chord progression", notes, 2, 0, 0)
end

-- Scenario 11: Close harmony in 4-note texture
local function scenario_close_harmony()
    local notes = {
        create_note(60, 0),   -- C
        create_note(62, 0),   -- D
        create_note(64, 0),   -- E
        create_note(65, 0),   -- F
        create_note(62, 480), -- D
        create_note(64, 480), -- E
        create_note(66, 480), -- F#
        create_note(67, 480)  -- G
    }
    return run_scenario("Close harmony", notes, 0, 0, 1)
end

-- Scenario 12: Open harmony with parallel fifths
local function scenario_open_harmony()
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G
        create_note(72, 0),   -- C (octave)
        create_note(79, 0),   -- G (octave)
        create_note(62, 480), -- D
        create_note(69, 480), -- A
        create_note(74, 480), -- D (octave)
        create_note(81, 480)  -- A (octave)
    }
    return run_scenario("Open harmony", notes, 3, 2, 1)
end

-- Main test runner
local function main()
    reaper.ShowConsoleMsg("Starting Parallel Interval Scenario Tests\n")
    reaper.ShowConsoleMsg("=======================================\n")
    
    local passed = 0
    local total = 0
    
    -- Run all scenarios
    total = total + 1
    if scenario_2note_fifths() then passed = passed + 1 end
    
    total = total + 1
    if scenario_3note_outer_fifths() then passed = passed + 1 end
    
    total = total + 1
    if scenario_3note_octaves() then passed = passed + 1 end
    
    total = total + 1
    if scenario_4note_multiple_fifths() then passed = passed + 1 end
    
    total = total + 1
    if scenario_4note_fourths() then passed = passed + 1 end
    
    total = total + 1
    if scenario_5note_complex() then passed = passed + 1 end
    
    total = total + 1
    if scenario_contrary_motion() then passed = passed + 1 end
    
    total = total + 1
    if scenario_static_voice() then passed = passed + 1 end
    
    total = total + 1
    if scenario_mixed_intervals() then passed = passed + 1 end
    
    total = total + 1
    if scenario_three_chord_progression() then passed = passed + 1 end
    
    total = total + 1
    if scenario_close_harmony() then passed = passed + 1 end
    
    total = total + 1
    if scenario_open_harmony() then passed = passed + 1 end
    
    -- Summary
    reaper.ShowConsoleMsg("\n=== Test Summary ===\n")
    reaper.ShowConsoleMsg("Passed: " .. passed .. "/" .. total .. "\n")
    reaper.ShowConsoleMsg("Failed: " .. (total - passed) .. "/" .. total .. "\n")
    
    if passed == total then
        reaper.ShowConsoleMsg("All scenario tests passed! ✓\n")
    else
        reaper.ShowConsoleMsg("Some scenario tests failed! ✗\n")
    end
end

-- Run the tests
main()