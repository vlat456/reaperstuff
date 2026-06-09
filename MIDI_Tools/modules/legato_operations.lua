-- @noindex
-- @description Common legato operations shared across scripts

local reaper = reaper

-- Import shared utilities
local MIDI_UTILS = require "midi_utils"
local UNDO_MANAGER = require "undo_manager"

local M = {}

-- Function to apply overlap prevention constraints
function M.apply_overlap_constraints(note, selected_notes, new_end_ppq)
    -- Same pitch overlap prevention - check against all selected notes
    for _, potential_next_note in ipairs(selected_notes) do
        if note.pitch == potential_next_note.pitch and
           potential_next_note.startppqpos > note.startppqpos and
           potential_next_note.startppqpos < new_end_ppq then
            new_end_ppq = math.min(new_end_ppq, potential_next_note.startppqpos)
        end
    end
    
    return new_end_ppq
end

-- Function to apply item boundary constraints
function M.apply_boundary_constraints(note, new_end_ppq, current_take, keep_within_boundaries)
    if not keep_within_boundaries then
        return new_end_ppq
    end
    
    local item_start_ppq, item_end_ppq = MIDI_UTILS.get_item_boundaries_in_ppq(current_take)
    
    -- Constrain to item end boundary
    new_end_ppq = math.min(new_end_ppq, item_end_ppq)
    
    -- Constrain to item start boundary - note end should not be before item start
    -- But only if the note is within the item boundaries
    if note.startppqpos >= item_start_ppq and note.startppqpos < item_end_ppq then
        -- If note starts within the item, make sure end doesn't go before item start
        new_end_ppq = math.max(new_end_ppq, item_start_ppq)
    end
    
    return new_end_ppq
end

-- Function to safely set note end position
function M.safe_set_note_end(current_take, note_index, start_ppq, new_end_ppq)
    -- Make sure the new end position is not before the start position
    if new_end_ppq > start_ppq then
        local result = reaper.MIDI_SetNote(current_take, note_index, nil, nil, start_ppq, new_end_ppq, nil, nil, nil, true)
        if not result then
            MIDI_UTILS.handle_error("Error setting MIDI note at index " .. note_index, "Legato Operation")
            return false
        end
        return true
    end
    return false
end

-- Function to apply legato with gap filling and extension
function M.apply_legato_with_extension(current_take, selected_notes, extension_percentage, merge_same_pitches)
    extension_percentage = extension_percentage or MIDI_UTILS.CONSTANTS.EXTENSION_PERCENTAGE_DEFAULT
    merge_same_pitches = merge_same_pitches or false
    
    local notes_to_delete = {}
    
    for i, note in ipairs(selected_notes) do
        -- Skip notes already marked for deletion by an earlier merge
        local skip_note = false
        for _, idx in ipairs(notes_to_delete) do
            if idx == note.index then
                skip_note = true
                break
            end
        end
        if skip_note then goto continue_note end
        
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

            -- Add legato extension: percentage of the next note's original length
            if next_note then
                -- Convert the next note's length from PPQ to milliseconds
                local start_time = reaper.MIDI_GetProjTimeFromPPQPos(current_take, next_note.startppqpos)
                local end_time = reaper.MIDI_GetProjTimeFromPPQPos(current_take, next_note.endppqpos)
                local next_note_length_ms = (end_time - start_time) * 1000  -- Convert seconds to milliseconds

                -- Calculate percentage of the next note's length
                local extension_ms = math.max(next_note_length_ms * extension_percentage, 1)  -- At least 1ms extension

                local extension_ppq = MIDI_UTILS.ms_to_ppq_corrected(extension_ms, current_take, note.startppqpos)
                new_end_ppq = new_end_ppq + extension_ppq
            end

            -- Handle same pitch notes
            if merge_same_pitches then
                -- Merge same-pitch notes: extend past them and mark for deletion
                local merged = true
                while merged do
                    merged = false
                    for _, other_note in ipairs(selected_notes) do
                        if note.pitch == other_note.pitch and
                           other_note.startppqpos > note.startppqpos and
                           other_note.startppqpos <= new_end_ppq and
                           other_note.index ~= note.index then
                            local already_marked = false
                            for _, idx in ipairs(notes_to_delete) do
                                if idx == other_note.index then
                                    already_marked = true
                                    break
                                end
                            end
                            if not already_marked then
                                new_end_ppq = math.max(new_end_ppq, other_note.endppqpos)
                                table.insert(notes_to_delete, other_note.index)
                                merged = true
                            end
                        end
                    end
                end
            else
                -- Apply overlap prevention
                new_end_ppq = M.apply_overlap_constraints(note, selected_notes, new_end_ppq)
            end
            
            -- Apply boundary constraints (default to false for quick scripts)
            new_end_ppq = M.apply_boundary_constraints(note, new_end_ppq, current_take, false)

            -- Set the note end position
            M.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq)
        end
        
        ::continue_note::
    end
    
    -- Delete notes that were merged
    if merge_same_pitches and #notes_to_delete > 0 then
        table.sort(notes_to_delete)
        for i = #notes_to_delete, 1, -1 do
            reaper.MIDI_DeleteNote(current_take, notes_to_delete[i])
        end
    end
end

-- Function to finalize changes (sort, update, register undo)
function M.finalize_changes(current_take, undo_message)
    local item = reaper.GetMediaItemTake_Item(current_take)
    
    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateItemInProject(item)
    reaper.Undo_OnStateChange_Item(0, undo_message, item)
    reaper.UpdateArrange()
    
    return item
end

return M