-- @noindex
-- @description LegatoTool: Apply non-legato effect to selected notes (remove legato/overlaps)

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

local LEGATO_COMMON = require "legato_common"

-- Main script logic
local current_take, midi_editor = LEGATO_COMMON.get_midi_context()

if not current_take then
    reaper.MB("No active MIDI take found. Please open a MIDI editor with selected notes.", "Error", 0)
    return
end

local selected_notes = LEGATO_COMMON.get_selected_notes_optimized()
if #selected_notes < 2 then
    reaper.MB("Please select at least 2 MIDI notes to apply non-legato effect.", "Not enough notes", 0)
    return
end

-- Apply non-legato effect (de-legato) - ensures notes don't overlap with small gaps
LEGATO_COMMON.non_legato()  -- registers undo internally

-- Quick script: no additional messages, silent operation after validation