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

-- Apply "Fill gaps" functionality + small extension for legato effect
-- This extends each note to the start of the next note, with a small extension
local item = reaper.GetMediaItemTake_Item(current_take)

-- Process each note to extend to the next note's start with gap-filling + legato extension
for i, note in ipairs(selected_notes) do
    -- Find the next note that starts after this note
    local next_note = nil

    for j = i + 1, #selected_notes do
        if selected_notes[j].startppqpos > note.startppqpos then
            next_note = selected_notes[j]
            break
        end
    end

    if next_note then
        -- Calculate new end position: extend to next note start (gap filling) + legato extension
        local new_end_ppq = next_note.startppqpos  -- Start by filling the gap

        -- Add legato extension: 10% of the next note's original length
        if next_note then
            -- Convert the next note's length from PPQ to milliseconds
            local start_time = reaper.MIDI_GetProjTimeFromPPQPos(current_take, next_note.startppqpos)
            local end_time = reaper.MIDI_GetProjTimeFromPPQPos(current_take, next_note.endppqpos)
            local next_note_length_ms = (end_time - start_time) * 1000  -- Convert seconds to milliseconds

            -- Calculate 10% of the next note's length
            local ten_percent_length_ms = math.max(next_note_length_ms * 0.1, 1)  -- At least 1ms extension

            local extension_ppq = LEGATO_COMMON.ms_to_ppq_corrected(ten_percent_length_ms, current_take, note.startppqpos)
            new_end_ppq = new_end_ppq + extension_ppq
        end

        -- Same pitch overlap prevention - check against original selected notes
        for _, potential_next_note in ipairs(selected_notes) do
            if note.pitch == potential_next_note.pitch and
               potential_next_note.startppqpos > note.startppqpos and
               potential_next_note.startppqpos < new_end_ppq then
                new_end_ppq = math.min(new_end_ppq, potential_next_note.startppqpos)
            end
        end

        -- Keep within item boundaries
        local keep_within_boundaries = false -- Default to false for quick script
        if keep_within_boundaries then
            local item_start_ppq, item_end_ppq = LEGATO_COMMON.get_item_boundaries_in_ppq(current_take)
            new_end_ppq = math.min(new_end_ppq, item_end_ppq)
        end

        -- Make sure the new end position is not before the start position
        if new_end_ppq > note.startppqpos then
            local result = reaper.MIDI_SetNote(current_take, note.index, nil, nil, note.startppqpos, new_end_ppq, nil, nil, nil, true)
            if not result then
                reaper.MB("Error setting MIDI note at index " .. note.index, "Legato Tool Error", 0)
                return  -- Stop processing this note
            end
        end
    end
end

-- Sort MIDI events to ensure correct ordering after changes
reaper.MIDI_Sort(current_take)
reaper.UpdateItemInProject(item)
reaper.Undo_OnStateChange_Item(0, "Quick Legato (Fill gaps + extend)", item)
reaper.UpdateArrange()