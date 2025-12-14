-- @noindex
-- @description Shared MIDI utility functions to eliminate code duplication

local reaper = reaper

local M = {}

-- Constants to replace magic numbers
M.CONSTANTS = {
    MAX_NOTES_LIMIT = 10000,
    DEFAULT_PPQ_RESOLUTION = 480,
    HUMANIZATION_MAX_RANGE_MS = 300,
    DEFAULT_PPQ_GAP = 10,
    MIN_GAP_PPQ = 5,
    EXTENSION_PERCENTAGE_DEFAULT = 0.1
}

-- Function to get current MIDI context consistently
function M.get_midi_context()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil, nil end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then return nil, nil end

    return current_take, midi_editor
end

-- Function to get media item boundaries in PPQ for the given take
function M.get_item_boundaries_in_ppq(take)
    if not take then return 0, math.huge end  -- Return a reasonable range if no take

    -- Get the media item that contains the take
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return 0, math.huge end

    -- Get item position and length in project time
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if item_pos == nil or item_pos == -1 or item_len == nil or item_len == -1 then
        -- Error getting item info
        reaper.MB("Error getting media item info", "MIDI Utils Error", 0)
        return 0, math.huge
    end

    local item_end = item_pos + item_len

    -- Convert to PPQ relative to the take - check for valid conversion
    local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_pos)
    if start_ppq == nil or start_ppq == -1 then
        reaper.MB("Error converting start time to PPQ", "MIDI Utils Error", 0)
        return 0, math.huge
    end

    local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_end)
    if end_ppq == nil or end_ppq == -1 then
        reaper.MB("Error converting end time to PPQ", "MIDI Utils Error", 0)
        return 0, math.huge
    end

    return start_ppq, end_ppq
end

-- Corrected version of the ms_to_ppq function that properly handles tempo changes
-- This function converts milliseconds to PPQ (pulses per quarter note) changes for a specific note position
function M.ms_to_ppq_corrected(ms, take, note_ppq_pos)
    if not ms or ms < 0 then
        return 0
    end

    if not take or not note_ppq_pos then
        -- Fallback to original estimation if no take/position provided
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * M.CONSTANTS.DEFAULT_PPQ_RESOLUTION) / (60 * 1000)
    end

    -- Convert the note's PPQ position to project time
    local note_time = reaper.MIDI_GetProjTimeFromPPQPos(take, note_ppq_pos)
    if not note_time or note_time < 0 then
        -- Fallback if conversion fails
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * M.CONSTANTS.DEFAULT_PPQ_RESOLUTION) / (60 * 1000)
    end

    -- Calculate the target time after adding the milliseconds (convert ms to seconds)
    local target_time = note_time + (ms / 1000.0)

    -- Convert both times to PPQ and calculate the difference
    local target_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, target_time)
    local current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, note_time)

    if not target_ppq or not current_ppq then
        -- Fallback if conversion fails
        local tempo = reaper.Master_GetTempo()
        return (ms * tempo * M.CONSTANTS.DEFAULT_PPQ_RESOLUTION) / (60 * 1000)
    end

    -- Return the difference in PPQ, which represents the distance for the specified milliseconds
    return target_ppq - current_ppq
end

-- Helper function to get the active MIDI take
function M.get_active_take()
    local current_take, midi_editor = M.get_midi_context()
    return current_take
end

-- Standardized undo registration function
function M.register_undo(item, undo_message, undo_manager)
    undo_manager = undo_manager or require "undo_manager"
    
    if item then
        return undo_manager.register_undo(item, undo_message, "MIDI operation")
    else
        reaper.ShowConsoleMsg("Warning: No item available for undo registration: " .. undo_message)
        return false
    end
end

-- Standardized error handling with consistent messaging
function M.handle_error(error_message, context, show_message_box)
    context = context or "MIDI Operation"
    show_message_box = show_message_box ~= false  -- Default to true
    
    local full_message = context .. ": " .. error_message
    
    if show_message_box then
        reaper.MB(full_message, "Error", 0)
    else
        reaper.ShowConsoleMsg(full_message .. "\n")
    end
end

-- Safe function execution with error handling
function M.safe_execute(func, error_context, show_message_box)
    local success, result = pcall(func)
    if not success then
        M.handle_error(tostring(result), error_context, show_message_box)
        return nil
    end
    return result
end

return M