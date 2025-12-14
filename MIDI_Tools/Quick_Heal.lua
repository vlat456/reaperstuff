-- @noindex
-- @description LegatoTool: Heal overlapping notes quickly

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
    -- Not enough notes to heal, exit silently
    return
end

-- Heal ALL overlays using the guaranteed function (iterative healing)
LEGATO_COMMON.heal_all_overlaps_guaranteed()  -- registers undo internally

-- Quick script: no messages, silent operation