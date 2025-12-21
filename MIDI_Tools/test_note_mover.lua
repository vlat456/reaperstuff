-- @noindex
-- @description Test script for NoteMover functionality

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Import required modules
local MIDI_UTILS = require "midi_utils"

-- Test function to verify NoteMover functionality
function test_note_mover()
    local current_take, midi_editor = MIDI_UTILS.get_midi_context()
    
    if not current_take then
        reaper.ShowMessageBox("Please open a MIDI editor with notes to test NoteMover functionality.", "Test NoteMover", 0)
        return false
    end
    
    -- Check if there are selected notes
    local note_count = 0
    local note_index = -1
    local safety_counter = 0
    local max_notes = MIDI_UTILS.CONSTANTS.MAX_NOTES_LIMIT

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end
        note_count = note_count + 1
        safety_counter = safety_counter + 1
    end
    
    if note_count == 0 then
        reaper.ShowMessageBox("Please select at least one note to test NoteMover functionality.", "Test NoteMover", 0)
        return false
    end
    
    -- Test passed
    reaper.ShowMessageBox("NoteMover test environment is ready!\n\n" ..
                         "Selected notes: " .. note_count .. "\n" ..
                         "You can now run the NoteMover script to test its functionality.", "Test NoteMover", 0)
    return true
end

-- Run the test
test_note_mover()