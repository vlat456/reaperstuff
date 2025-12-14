-- @noindex
-- @description Common script initialization functions for MIDI tools

local reaper = reaper

local M = {}

-- Function to set up module path consistently
function M.setup_module_path()
    local info = debug.getinfo(2, 'S')  -- Use level 2 to get caller's info
    local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
    package.path = package.path .. ';' .. script_path .. 'modules/?.lua'
    return script_path
end

-- Function to validate MIDI context and show error if needed
function M.validate_midi_context(show_errors)
    show_errors = show_errors ~= false  -- Default to true
    
    local LEGATO_COMMON = require "legato_common"
    local current_take, midi_editor = LEGATO_COMMON.get_midi_context()
    
    if not current_take then
        if show_errors then
            reaper.MB("No active MIDI take found. Please open a MIDI editor with selected notes.", "Error", 0)
        end
        return nil, nil
    end
    
    return current_take, midi_editor
end

-- Function to validate minimum selected notes
function M.validate_min_selected_notes(min_notes, show_errors)
    min_notes = min_notes or 2
    show_errors = show_errors ~= false  -- Default to true
    
    local LEGATO_COMMON = require "legato_common"
    local selected_notes = LEGATO_COMMON.get_selected_notes_optimized()
    
    if #selected_notes < min_notes then
        if show_errors then
            reaper.MB("Please select at least " .. min_notes .. " notes.", "Error", 0)
        end
        return nil
    end
    
    return selected_notes
end

-- Complete initialization function for quick scripts
function M.quick_script_init(min_notes)
    M.setup_module_path()
    
    local current_take, midi_editor = M.validate_midi_context()
    if not current_take then
        return nil, nil
    end
    
    local selected_notes = M.validate_min_selected_notes(min_notes)
    if not selected_notes then
        return nil, nil
    end
    
    return current_take, selected_notes
end

-- Function to register undo consistently
function M.register_undo(item, undo_message)
    if item then
        reaper.UpdateItemInProject(item)
        reaper.Undo_OnStateChange_Item(0, undo_message, item)
        reaper.UpdateArrange()
    end
end

return M