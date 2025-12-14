-- @noindex
-- @description LegatoTool: Apply non-legato effect to selected notes (remove legato/overlaps)

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Centralized require statements at the top of the file
local SCRIPT_INIT = require "script_init"
local LEGATO_COMMON = require "legato_common"

-- Initialize script with validation
local current_take, selected_notes = SCRIPT_INIT.quick_script_init(2)
if not current_take then
    return  -- Error already shown by init function
end

-- Apply non-legato effect (de-legato) - ensures notes don't overlap with small gaps
LEGATO_COMMON.non_legato()  -- registers undo internally

-- Quick script: no additional messages, silent operation after validation