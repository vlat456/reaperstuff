-- @description Quick Heal - Heal note overlays with default settings
-- @author drvlat
-- @version 0.1.0
-- @provides [main=midi_editor,midi_inlineeditor,midi_eventlisteditor] .
-- @about
--   This is a quick heal script that heals note overlays in selected MIDI notes
--   without any UI. It adjusts notes so that same-pitch notes don't overlap.

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
    reaper.MB("Please select at least 2 MIDI notes to heal overlays.", "Not enough notes", 0)
    return
end

-- Heal overlays using the common function
local resolved_count = LEGATO_COMMON.heal_overlays(true)  -- true to register undo

if resolved_count > 0 then
    reaper.MB("Healed " .. resolved_count .. " note overlay(s).", "Quick Heal Result", 0)
else
    -- Check if there were any overlays to begin with
    local overlay_count = LEGATO_COMMON.detect_overlays_count(current_take)
    if overlay_count == 0 then
        reaper.MB("No overlays found to heal.", "Quick Heal Result", 0)
    else
        reaper.MB("No overlays could be resolved.", "Quick Heal Result", 0)
    end
end

reaper.Undo_OnStateChange_Item(0, "Quick Heal Overlays", reaper.GetMediaItemTake_Item(current_take))