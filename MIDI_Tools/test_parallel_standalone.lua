-- @noindex
-- @description Standalone test for parallel interval detection (mocks REAPER API)

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

-- Load the parallel detector module
local PARALLEL_DETECTOR = require "parallel_detector"

-- Simple test framework
local TestFramework = {}
TestFramework.tests = {}
TestFramework.passed = 0
TestFramework.failed = 0

function TestFramework.assert(condition, message)
    if condition then
        TestFramework.passed = TestFramework.passed + 1
        reaper.ShowConsoleMsg("✓ PASS: " .. message .. "\n")
    else
        TestFramework.failed = TestFramework.failed + 1
        reaper.ShowConsoleMsg("✗ FAIL: " .. message .. "\n")
    end
end

function TestFramework.assert_equal(actual, expected, message)
    if actual == expected then
        TestFramework.assert(true, message .. " (got " .. tostring(actual) .. ")")
    else
        TestFramework.assert(false, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    end
end

function TestFramework.run_test(test_name, test_func)
    reaper.ShowConsoleMsg("\n=== Running test: " .. test_name .. " ===\n")
    local success, error_msg = pcall(test_func)
    if not success then
        TestFramework.failed = TestFramework.failed + 1
        reaper.ShowConsoleMsg("✗ FAIL: Test crashed with error: " .. tostring(error_msg) .. "\n")
    end
end

function TestFramework.summary()
    reaper.ShowConsoleMsg("\n=== Test Summary ===\n")
    reaper.ShowConsoleMsg("Passed: " .. TestFramework.passed .. "\n")
    reaper.ShowConsoleMsg("Failed: " .. TestFramework.failed .. "\n")
    reaper.ShowConsoleMsg("Total: " .. (TestFramework.passed + TestFramework.failed) .. "\n")
    if TestFramework.failed == 0 then
        reaper.ShowConsoleMsg("All tests passed! ✓\n")
    else
        reaper.ShowConsoleMsg("Some tests failed! ✗\n")
    end
end

-- Helper function to create mock notes
local function create_mock_note(pitch, start_ppq, vel, chan)
    return {
        pitch = pitch,
        start = start_ppq,
        endppq = start_ppq + 480,  -- Default length
        chan = chan or 0,
        vel = vel or 100,
        selected = false,
        id = -1
    }
end

-- Test 1: 2-note chords with parallel fifths
local function test_2note_parallel_fifths()
    reaper.ShowConsoleMsg("Testing 2-note chords with parallel fifths\n")
    
    -- Create test data: C-G moving to D-A (parallel fifths)
    local notes = {
        create_mock_note(60, 0),   -- C
        create_mock_note(67, 0),   -- G (perfect fifth above C)
        create_mock_note(62, 480), -- D
        create_mock_note(69, 480)  -- A (perfect fifth above D)
    }
    
    -- Group into chords
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    TestFramework.assert_equal(#chords, 2, "Should create 2 chords")
    TestFramework.assert_equal(#chords[1], 2, "First chord should have 2 notes")
    TestFramework.assert_equal(#chords[2], 2, "Second chord should have 2 notes")
    
    -- Test interval detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    TestFramework.assert_equal(#errors, 1, "Should detect 1 parallel fifth")
    if #errors > 0 then
        local error = errors[1]
        TestFramework.assert_equal(error.pitch_A_curr, 60, "First voice should start on C")
        TestFramework.assert_equal(error.pitch_B_curr, 67, "Second voice should start on G")
        TestFramework.assert_equal(error.pitch_A_next, 62, "First voice should move to D")
        TestFramework.assert_equal(error.pitch_B_next, 69, "Second voice should move to A")
    end
end

-- Test 2: 3-note chords with parallel fifths
local function test_3note_parallel_fifths()
    reaper.ShowConsoleMsg("Testing 3-note chords with parallel fifths\n")
    
    -- Create test data: C-E-G moving to D-F#-A (parallel fifths between outer voices)
    local notes = {
        create_mock_note(60, 0),   -- C
        create_mock_note(64, 0),   -- E
        create_mock_note(67, 0),   -- G
        create_mock_note(62, 480), -- D
        create_mock_note(66, 480), -- F#
        create_mock_note(69, 480)  -- A
    }
    
    -- Group into chords
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    TestFramework.assert_equal(#chords, 2, "Should create 2 chords")
    TestFramework.assert_equal(#chords[1], 3, "First chord should have 3 notes")
    TestFramework.assert_equal(#chords[2], 3, "Second chord should have 3 notes")
    
    -- Test interval detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    TestFramework.assert_equal(#errors, 1, "Should detect 1 parallel fifth (outer voices)")
    if #errors > 0 then
        local error = errors[1]
        TestFramework.assert_equal(error.pitch_A_curr, 60, "First voice should start on C")
        TestFramework.assert_equal(error.pitch_B_curr, 67, "Second voice should start on G")
        TestFramework.assert_equal(error.pitch_A_next, 62, "First voice should move to D")
        TestFramework.assert_equal(error.pitch_B_next, 69, "Second voice should move to A")
    end
end

-- Test 3: 4-note chords with parallel fifths
local function test_4note_parallel_fifths()
    reaper.ShowConsoleMsg("Testing 4-note chords with parallel fifths\n")
    
    -- Create test data: C-E-G-C' moving to D-F#-A-D' (multiple parallel fifths)
    local notes = {
        create_mock_note(60, 0),   -- C
        create_mock_note(64, 0),   -- E
        create_mock_note(67, 0),   -- G
        create_mock_note(72, 0),   -- C (octave)
        create_mock_note(62, 480), -- D
        create_mock_note(66, 480), -- F#
        create_mock_note(69, 480), -- A
        create_mock_note(74, 480)  -- D (octave)
    }
    
    -- Group into chords
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    TestFramework.assert_equal(#chords, 2, "Should create 2 chords")
    TestFramework.assert_equal(#chords[1], 4, "First chord should have 4 notes")
    TestFramework.assert_equal(#chords[2], 4, "Second chord should have 4 notes")
    
    -- Test interval detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    -- Should detect one parallel fifth in 4-note texture
    TestFramework.assert_equal(#errors, 1, "Should detect exactly 1 parallel fifth")
    
    -- Check for specific parallel fifths
    local found_c_g = false
    
    for _, error in ipairs(errors) do
        if error.pitch_A_curr == 60 and error.pitch_B_curr == 67 then
            found_c_g = true
            break
        end
    end
    
    TestFramework.assert(found_c_g, "Should detect C-G parallel fifth")
end

-- Test 4: 5-note chords with parallel fifths
local function test_5note_parallel_fifths()
    reaper.ShowConsoleMsg("Testing 5-note chords with parallel fifths\n")
    
    -- Create test data: C-E-G-B-C' moving to D-F#-A-C#-D' (complex texture)
    local notes = {
        create_mock_note(60, 0),   -- C
        create_mock_note(64, 0),   -- E
        create_mock_note(67, 0),   -- G
        create_mock_note(71, 0),   -- B
        create_mock_note(72, 0),   -- C (octave)
        create_mock_note(62, 480), -- D
        create_mock_note(66, 480), -- F#
        create_mock_note(69, 480), -- A
        create_mock_note(73, 480), -- C#
        create_mock_note(74, 480)  -- D (octave)
    }
    
    -- Group into chords
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    TestFramework.assert_equal(#chords, 2, "Should create 2 chords")
    TestFramework.assert_equal(#chords[1], 5, "First chord should have 5 notes")
    TestFramework.assert_equal(#chords[2], 5, "Second chord should have 5 notes")
    
    -- Test interval detection
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    -- Should detect multiple parallel fifths in 5-note texture
    TestFramework.assert(#errors >= 2, "Should detect at least 2 parallel fifths")
end

-- Test 5: Parallel octaves with different chord sizes
local function test_parallel_octaves()
    reaper.ShowConsoleMsg("Testing parallel octaves with different chord sizes\n")
    
    -- Test with 3-note chords
    local notes_3note = {
        create_mock_note(60, 0),   -- C
        create_mock_note(64, 0),   -- E
        create_mock_note(72, 0),   -- C (octave)
        create_mock_note(62, 480), -- D
        create_mock_note(66, 480), -- F#
        create_mock_note(74, 480)  -- D (octave)
    }
    
    local chords_3note = PARALLEL_DETECTOR.group_notes_into_chords(notes_3note)
    local errors_octaves = PARALLEL_DETECTOR.analyze_parallel_intervals(chords_3note, PARALLEL_DETECTOR.is_perfect_octave)
    
    TestFramework.assert_equal(#errors_octaves, 1, "Should detect 1 parallel octave in 3-note chords")
    
    -- Test with 4-note chords
    local notes_4note = {
        create_mock_note(60, 0),   -- C
        create_mock_note(64, 0),   -- E
        create_mock_note(67, 0),   -- G
        create_mock_note(72, 0),   -- C (octave)
        create_mock_note(62, 480), -- D
        create_mock_note(66, 480), -- F#
        create_mock_note(69, 480), -- A
        create_mock_note(74, 480)  -- D (octave)
    }
    
    local chords_4note = PARALLEL_DETECTOR.group_notes_into_chords(notes_4note)
    local errors_octaves_4note = PARALLEL_DETECTOR.analyze_parallel_intervals(chords_4note, PARALLEL_DETECTOR.is_perfect_octave)
    
    TestFramework.assert(#errors_octaves_4note >= 1, "Should detect at least 1 parallel octave in 4-note chords")
end

-- Test 6: Edge cases - no parallel intervals
local function test_no_parallel_intervals()
    reaper.ShowConsoleMsg("Testing edge cases with no parallel intervals\n")
    
    -- Contrary motion: C-G moving to A-F (no parallel intervals)
    local notes = {
        create_mock_note(60, 0),   -- C
        create_mock_note(67, 0),   -- G
        create_mock_note(69, 480), -- A (up)
        create_mock_note(65, 480)  -- F (down)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    
    -- Test for parallel fifths
    local errors_fifths = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    TestFramework.assert_equal(#errors_fifths, 0, "Should not detect parallel fifths in contrary motion")
    
    -- Test for parallel octaves
    local errors_octaves = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_octave)
    TestFramework.assert_equal(#errors_octaves, 0, "Should not detect parallel octaves in contrary motion")
end

-- Test 7: Static voices (should not be detected as parallel)
local function test_static_voices()
    reaper.ShowConsoleMsg("Testing static voices (should not be detected as parallel)\n")
    
    -- Static voice: C-G with G staying same, C moving to D
    local notes = {
        create_mock_note(60, 0),   -- C
        create_mock_note(67, 0),   -- G
        create_mock_note(62, 480), -- D (moves up)
        create_mock_note(67, 480)  -- G (stays same)
    }
    
    local chords = PARALLEL_DETECTOR.group_notes_into_chords(notes)
    local errors = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
    
    TestFramework.assert_equal(#errors, 0, "Should not detect parallel intervals with static voice")
end

-- Test 8: Interval detection accuracy
local function test_interval_detection_accuracy()
    reaper.ShowConsoleMsg("Testing interval detection accuracy\n")
    
    -- Test various interval types
    TestFramework.assert(PARALLEL_DETECTOR.is_perfect_fifth(60, 67), "Should detect C-G as perfect fifth")
    TestFramework.assert(PARALLEL_DETECTOR.is_perfect_fifth(67, 60), "Should detect G-C as perfect fifth")
    TestFramework.assert(not PARALLEL_DETECTOR.is_perfect_fifth(60, 64), "Should not detect C-E as perfect fifth")
    
    TestFramework.assert(PARALLEL_DETECTOR.is_perfect_octave(60, 72), "Should detect C-C as perfect octave")
    TestFramework.assert(PARALLEL_DETECTOR.is_perfect_octave(72, 60), "Should detect C-C as perfect octave")
    TestFramework.assert(not PARALLEL_DETECTOR.is_perfect_octave(60, 71), "Should not detect C-B as perfect octave")
    
    TestFramework.assert(PARALLEL_DETECTOR.is_perfect_fourth(60, 65), "Should detect C-F as perfect fourth")
    TestFramework.assert(PARALLEL_DETECTOR.is_perfect_fourth(65, 60), "Should detect F-C as perfect fourth")
    TestFramework.assert(not PARALLEL_DETECTOR.is_perfect_fourth(60, 64), "Should not detect C-E as perfect fourth")
end

-- Main test runner
local function run_all_tests()
    reaper.ShowConsoleMsg("Starting Standalone Parallel Interval Detection Tests\n")
    reaper.ShowConsoleMsg("====================================================\n")
    
    -- Run all tests
    TestFramework.run_test("2-note chords with parallel fifths", test_2note_parallel_fifths)
    TestFramework.run_test("3-note chords with parallel fifths", test_3note_parallel_fifths)
    TestFramework.run_test("4-note chords with parallel fifths", test_4note_parallel_fifths)
    TestFramework.run_test("5-note chords with parallel fifths", test_5note_parallel_fifths)
    TestFramework.run_test("Parallel octaves with different chord sizes", test_parallel_octaves)
    TestFramework.run_test("Edge cases - no parallel intervals", test_no_parallel_intervals)
    TestFramework.run_test("Static voices (should not be detected as parallel)", test_static_voices)
    TestFramework.run_test("Interval detection accuracy", test_interval_detection_accuracy)
    
    -- Show summary
    TestFramework.summary()
end

-- Run the tests
run_all_tests()

reaper.ShowConsoleMsg("\nTest completed. Check the output above for results.\n")