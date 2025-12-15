-- @noindex
-- @description LegatoTool: Fill gaps between selected notes and add 10% legato

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Centralized require statements at the top of the file
local SCRIPT_INIT = require "script_init"
local LEGATO_OPERATIONS = require "legato_operations"
local MIDI_UTILS = require "midi_utils"

-- Initialize script with validation
local current_take, selected_notes = SCRIPT_INIT.quick_script_init(2)
if not current_take then
    return  -- Error already shown by init function
end

-- Apply legato with default extension using the shared function
LEGATO_OPERATIONS.apply_legato_with_extension(current_take, selected_notes, MIDI_UTILS.CONSTANTS.EXTENSION_PERCENTAGE_DEFAULT)

-- Finalize changes with consistent undo handling
LEGATO_OPERATIONS.finalize_changes(current_take, "Quick Legato (Fill gaps + extend)")