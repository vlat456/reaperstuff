-- @noindex
-- Debug script for user's specific scenario: C3-G3 to C#3-G#3

-- Mock REAPER functions for standalone testing
reaper = {
    ShowConsoleMsg = function(msg) print(msg) end,
    MB = function(msg, title, type) print(title .. ": " .. msg) end,
    ColorToNative = function(r, g, b) return r | (g << 8) | (b << 16) end,
    AddProjectMarker2 = function() end,
    MIDI_GetProjTimeFromPPQPos = function() return 0 end,
    MIDI_GetPPQPosFromProjTime = function() return 0 end,
    Master_GetTempo = function() return 120 end
}

-- Add modules path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])') or ""
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Import the parallel detector
local PARALLEL_DETECTOR = require "parallel_detector"

print("Testing user scenario: C3-G3 to C#3-G#3")
print("==========================================")

-- Create the user's scenario: C3-G3 followed by C#3-G#3
local user_notes = {
    -- First chord: C3-G3
    {pitch = 48, start = 0, endppq = 480, chan = 0, vel = 64, selected = true, id = 0},
    {pitch = 55, start = 0, endppq = 480, chan = 0, vel = 64, selected = true, id = 1},
    
    -- Second chord: C#3-G#3 (slightly later to form separate chord)
    {pitch = 49, start = 240, endppq = 720, chan = 0, vel = 64, selected = true, id = 2},
    {pitch = 56, start = 240, endppq = 720, chan = 0, vel = 64, selected = true, id = 3}
}

print("Notes created:")
for i, note in ipairs(user_notes) do
    local note_name = string.format("Note %d: pitch=%d (MIDI), start=%d", i, note.pitch, note.start)
    -- Convert MIDI to note name for clarity
    local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    local octave = math.floor(note.pitch / 12) - 1
    local note_name_str = note_names[(note.pitch % 12) + 1] .. octave
    print(string.format("  %s (%s)", note_name, note_name_str))
end

-- Test chord grouping
print("\nTesting chord grouping:")
local chords = PARALLEL_DETECTOR.group_notes_into_chords(user_notes)
print("Number of chords formed: " .. #chords)

for i, chord in ipairs(chords) do
    local chord_notes = {}
    for j, note in ipairs(chord) do
        local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
        local octave = math.floor(note.pitch / 12) - 1
        local note_name_str = note_names[(note.pitch % 12) + 1] .. octave
        table.insert(chord_notes, note_name_str)
    end
    print(string.format("  Chord %d: %s", i, table.concat(chord_notes, " ")))
end

-- Test interval detection
print("\nTesting interval detection:")
for i = 1, #chords - 1 do
    local chord_curr = chords[i]
    local chord_next = chords[i + 1]
    
    print(string.format("\nAnalyzing chord transition %d -> %d:", i, i + 1))
    
    for vA = 1, math.min(#chord_curr, #chord_next) do
        for vB = vA + 1, math.min(#chord_curr, #chord_next) do
            local note_A_curr = chord_curr[vA]
            local note_B_curr = chord_curr[vB]
            local note_A_next = chord_next[vA]
            local note_B_next = chord_next[vB]
            
            if note_A_curr and note_B_curr and note_A_next and note_B_next then
                local pitch_A_curr = note_A_curr.pitch
                local pitch_B_curr = note_B_curr.pitch
                local pitch_A_next = note_A_next.pitch
                local pitch_B_next = note_B_next.pitch
                
                local int_curr = math.abs(pitch_B_curr - pitch_A_curr)
                local int_next = math.abs(pitch_B_next - pitch_A_next)
                
                local is_fifth_curr = PARALLEL_DETECTOR.is_perfect_fifth(pitch_A_curr, pitch_B_curr)
                local is_fifth_next = PARALLEL_DETECTOR.is_perfect_fifth(pitch_A_next, pitch_B_next)
                local is_parallel = PARALLEL_DETECTOR.is_parallel_motion(pitch_A_curr, pitch_B_curr, pitch_A_next, pitch_B_next)
                
                print(string.format("  Voices %d&%d: %d->%d and %d->%d (intervals: %d->%d, fifths: %s->%s, parallel: %s)", 
                    vA, vB, pitch_A_curr, pitch_A_next, pitch_B_curr, pitch_B_next,
                    int_curr, int_next, tostring(is_fifth_curr), tostring(is_fifth_next), tostring(is_parallel)))
            end
        end
    end
end

-- Test full detection
print("\nTesting full parallel detection:")
local errors_found = PARALLEL_DETECTOR.analyze_parallel_intervals(chords, PARALLEL_DETECTOR.is_perfect_fifth)
print("Parallel fifths detected: " .. #errors_found)

if #errors_found > 0 then
    for _, error_info in ipairs(errors_found) do
        print(string.format("  Voices %d&%d: %d->%d and %d->%d", 
            error_info.voice_A, error_info.voice_B,
            error_info.pitch_A_curr, error_info.pitch_A_next,
            error_info.pitch_B_curr, error_info.pitch_B_next))
    end
else
    print("  No parallel fifths detected - this is the problem!")
end

print("\nDebug completed.")