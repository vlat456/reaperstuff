-- @description Quick Legato - Apply legato effect with default settings
-- @author drvlat
-- @version 0.1.0
-- @provides [main=midi_editor,midi_inlineeditor,midi_eventlisteditor] .
-- @about
--   This is a quick legato script that applies legato to selected MIDI notes
--   without any UI. It extends MIDI notes to create legato effects with a
--   default legato amount of 50ms, no humanization, and no boundary constraints.

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
    reaper.MB("Please select at least 2 MIDI notes to apply legato.", "Not enough notes", 0)
    return
end

-- Apply legato with default settings:
-- - legato_amount: 50ms (reasonable default for quick legato)
-- - humanize_strength: 0 (no humanization)
-- - keep_within_boundaries: false (don't constrain to item boundaries)
local legato_amount = 50  -- Default 50ms legato
local humanize_strength = 0  -- No humanization
local keep_within_boundaries = false  -- No boundary constraints

-- Apply the legato effect using common function
LEGATO_COMMON.apply_legato(nil, legato_amount, humanize_strength, keep_within_boundaries)

reaper.Undo_OnStateChange_Item(0, "Quick Legato", reaper.GetMediaItemTake_Item(current_take))