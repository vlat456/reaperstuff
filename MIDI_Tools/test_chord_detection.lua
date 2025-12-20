-- @noindex
-- @description Test chord detection for parallel intervals with different chord sizes

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
    else
        reaper.ShowConsoleMsg("✗ " .. test_name .. " FAILED: " .. tostring(result) .. "\n")
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

-- Test 1: 2-note chords
local function test_2note_chords()
    -- Create simple 2-note chords
    local notes = {
        create_note(60, 0),   -- C
        create_note(67, 0),   -- G (fifth)
        create_note(62, 480), -- D
        create_note(69, 480)  -- A (fifth)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    reaper.ShowConsoleMsg("Number of chords: " .. #chords .. "\n")
    for i, chord in ipairs(chords) do
        reaper.ShowConsoleMsg("Chord " .. i .. ": ")
        for j, note in ipairs(chord) do
            reaper.ShowConsoleMsg(note.pitch .. " ")
        end
        reaper.ShowConsoleMsg("\n")
    end
    
    -- Test parallel fifth detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    reaper.ShowConsoleMsg("Parallel fifths found: " .. #errors .. "\n")
    
    for _, error in ipairs(errors) do
        reaper.ShowConsoleMsg(string.format("Voices %d&%d: %d->%d and %d->%d\n",
            error.voice_A, error.voice_B,
            error.pitch_A_curr, error.pitch_A_next,
            error.pitch_B_curr, error.pitch_B_next))
    end
    
    assert(#chords == 2, "Should create 2 chords")
    assert(#chords[1] == 2, "First chord should have 2 notes")
    assert(#chords[2] == 2, "Second chord should have 2 notes")
    assert(#errors == 1, "Should detect 1 parallel fifth")
end

-- Test 2: 3-note chords
local function test_3note_chords()
    -- Create 3-note chords
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480)  -- A
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    reaper.ShowConsoleMsg("Number of chords: " .. #chords .. "\n")
    for i, chord in ipairs(chords) do
        reaper.ShowConsoleMsg("Chord " .. i .. ": ")
        for j, note in ipairs(chord) do
            reaper.ShowConsoleMsg(note.pitch .. " ")
        end
        reaper.ShowConsoleMsg("\n")
    end
    
    -- Test parallel fifth detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    reaper.ShowConsoleMsg("Parallel fifths found: " .. #errors .. "\n")
    
    for _, error in ipairs(errors) do
        reaper.ShowConsoleMsg(string.format("Voices %d&%d: %d->%d and %d->%d\n",
            error.voice_A, error.voice_B,
            error.pitch_A_curr, error.pitch_A_next,
            error.pitch_B_curr, error.pitch_B_next))
    end
    
    assert(#chords == 2, "Should create 2 chords")
    assert(#chords[1] == 3, "First chord should have 3 notes")
    assert(#chords[2] == 3, "Second chord should have 3 notes")
    assert(#errors >= 1, "Should detect at least 1 parallel fifth")
end

-- Test 3: 4-note chords
local function test_4note_chords()
    -- Create 4-note chords
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
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    reaper.ShowConsoleMsg("Number of chords: " .. #chords .. "\n")
    for i, chord in ipairs(chords) do
        reaper.ShowConsoleMsg("Chord " .. i .. ": ")
        for j, note in ipairs(chord) do
            reaper.ShowConsoleMsg(note.pitch .. " ")
        end
        reaper.ShowConsoleMsg("\n")
    end
    
    -- Test parallel fifth detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    reaper.ShowConsoleMsg("Parallel fifths found: " .. #errors .. "\n")
    
    for _, error in ipairs(errors) do
        reaper.ShowConsoleMsg(string.format("Voices %d&%d: %d->%d and %d->%d\n",
            error.voice_A, error.voice_B,
            error.pitch_A_curr, error.pitch_A_next,
            error.pitch_B_curr, error.pitch_B_next))
    end
    
    assert(#chords == 2, "Should create 2 chords")
    assert(#chords[1] == 4, "First chord should have 4 notes")
    assert(#chords[2] == 4, "Second chord should have 4 notes")
    assert(#errors >= 1, "Should detect at least 1 parallel fifth in 4-note texture")
end

-- Test 4: 5-note chords
local function test_5note_chords()
    -- Create 5-note chords
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
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    reaper.ShowConsoleMsg("Number of chords: " .. #chords .. "\n")
    for i, chord in ipairs(chords) do
        reaper.ShowConsoleMsg("Chord " .. i .. ": ")
        for j, note in ipairs(chord) do
            reaper.ShowConsoleMsg(note.pitch .. " ")
        end
        reaper.ShowConsoleMsg("\n")
    end
    
    -- Test parallel fifth detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    reaper.ShowConsoleMsg("Parallel fifths found: " .. #errors .. "\n")
    
    for _, error in ipairs(errors) do
        reaper.ShowConsoleMsg(string.format("Voices %d&%d: %d->%d and %d->%d\n",
            error.voice_A, error.voice_B,
            error.pitch_A_curr, error.pitch_A_next,
            error.pitch_B_curr, error.pitch_B_next))
    end
    
    assert(#chords == 2, "Should create 2 chords")
    assert(#chords[1] == 5, "First chord should have 5 notes")
    assert(#chords[2] == 5, "Second chord should have 5 notes")
    assert(#errors >= 2, "Should detect at least 2 parallel fifths in 5-note texture")
end

-- Test 5: Mixed interval types in 4-note chords
local function test_mixed_intervals()
    -- Create chords with different interval types
    local notes = {
        -- Chord 1: C-E-G-C' (has fifth and octave)
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
        create_note(72, 0),   -- C (octave)
        -- Chord 2: D-F#-A-D' (parallel fifth and octave)
        create_note(62, 480), -- D
        create_note(66, 480), -- F#
        create_note(69, 480), -- A
        create_note(74, 480)  -- D (octave)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    -- Test parallel fifths
    local fifths = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    reaper.ShowConsoleMsg("Parallel fifths found: " .. #fifths .. "\n")
    
    -- Test parallel octaves
    local octaves = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_octave)
    reaper.ShowConsoleMsg("Parallel octaves found: " .. #octaves .. "\n")
    
    -- Test parallel fourths
    local fourths = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fourth)
    reaper.ShowConsoleMsg("Parallel fourths found: " .. #fourths .. "\n")
    
    assert(#fifths >= 1, "Should detect at least 1 parallel fifth")
    assert(#octaves >= 1, "Should detect at least 1 parallel octave")
end

-- Test 6: Edge case - single chord (no parallel motion)
local function test_single_chord()
    -- Create only one chord
    local notes = {
        create_note(60, 0),   -- C
        create_note(64, 0),   -- E
        create_note(67, 0),   -- G
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    reaper.ShowConsoleMsg("Number of chords: " .. #chords .. "\n")
    
    -- Should not detect any parallel intervals with only one chord
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    reaper.ShowConsoleMsg("Parallel fifths found: " .. #errors .. "\n")
    
    assert(#chords == 1, "Should create 1 chord")
    assert(#errors == 0, "Should not detect parallel intervals with single chord")
end

-- Main test runner
local function main()
    reaper.ShowConsoleMsg("Starting Chord Detection Tests\n")
    reaper.ShowConsoleMsg("=============================\n")
    
    run_test("2-note chords", test_2note_chords)
    run_test("3-note chords", test_3note_chords)
    run_test("4-note chords", test_4note_chords)
    run_test("5-note chords", test_5note_chords)
    run_test("Mixed interval types", test_mixed_intervals)
    run_test("Single chord edge case", test_single_chord)
    
    reaper.ShowConsoleMsg("\nAll chord detection tests completed!\n")
end

-- Run the tests
main()