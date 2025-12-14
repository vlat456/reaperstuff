-- @noindex
-- @description LegatoTool: Heal overlapping notes quickly

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Now we can require the shared modules
local SCRIPT_INIT = require "script_init"
local LEGATO_COMMON = require "legato_common"

-- Initialize script with validation
local current_take, selected_notes = SCRIPT_INIT.quick_script_init(2)
if not current_take then
    return  -- Error already shown by init function
end

-- Heal ALL overlays using the guaranteed function (iterative healing)
LEGATO_COMMON.heal_all_overlaps_guaranteed()  -- registers undo internally

-- Quick script: no messages, silent operation