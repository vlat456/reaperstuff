-- @noindex
-- @description Standardized undo management for MIDI tools scripts

local reaper = reaper

local M = {}

-- Function to register undo with consistent pattern
function M.register_undo(item, undo_message, operation_type)
    operation_type = operation_type or "General operation"
    
    -- Get the media item associated with the take
    if not item then
        reaper.ShowConsoleMsg("Warning: No item available for undo registration: " .. undo_message)
        return false
    end
    
    -- Update the item and register the change in undo system
    reaper.UpdateItemInProject(item)
    reaper.Undo_OnStateChange_Item(0, undo_message, item)
    reaper.UpdateArrange()
    
    return true
end

-- Function to begin undo block for complex operations
function M.begin_undo_block(undo_message)
    undo_message = undo_message or "Complex operation"
    reaper.Undo_BeginBlock2(0)
    return true
end

-- Function to end undo block
function M.end_undo_block(undo_message)
    undo_message = undo_message or "Complex operation"
    reaper.Undo_EndBlock2(0, undo_message)
    return true
end

-- Function to handle undo with error protection
function M.safe_undo_operation(item, undo_message, operation_func, ...)
    local success, error_msg = pcall(operation_func, ...)
    if success then
        return M.register_undo(item, undo_message)
    else
        reaper.ShowConsoleMsg("Undo operation failed: " .. tostring(error_msg))
        return false
    end
end

return M