-- @noindex
-- @description Note Mover: Tool to move or copy notes by musical intervals

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Centralized require statements at the top of the file
local SCRIPT_INIT = require "script_init"
local CLEANUP_MANAGER = require "cleanup_manager"
local UNDO_MANAGER = require "undo_manager"
local MIDI_UTILS = require "midi_utils"

-- Check for reaimgui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load the ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

-- Script variables
local script_name = "Note Mover"
local ctx = imgui.CreateContext(script_name)
local script_running = true

-- Musical intervals in semitones
local INTERVALS = {
    {name = "Unison", semitones = 0},
    {name = "2nd", semitones = 2},
    {name = "Minor 3rd", semitones = 3},
    {name = "Major 3rd", semitones = 4},
    {name = "4th", semitones = 5},
    {name = "Tritone", semitones = 6},
    {name = "5th", semitones = 7},
    {name = "Minor 6th", semitones = 8},
    {name = "Major 6th", semitones = 9},
    {name = "Minor 7th", semitones = 10},
    {name = "Major 7th", semitones = 11},
    {name = "Octave", semitones = 12}
}

-- Unified GUI State Management System
local gui_state = {
    -- MIDI context
    take = nil,
    selected_note_count = 0,
    
    -- Operation controls
    operation_mode = "move",  -- "move" or "copy"
    direction = "+",  -- "+" or "-"
    selected_interval = 0,  -- Index in INTERVALS table
    
    -- State invalidation flags
    needs_note_count_update = false
}

-- UI Constants to replace magic numbers
local UI_CONSTANTS = {
    BUTTON_WIDTH = 80,
    BUTTON_HEIGHT = 30,
    MIN_NOTES_FOR_OPERATION = 1
}

-- Centralized state management functions
local function invalidate_all_caches()
    gui_state.needs_note_count_update = true
end

local function update_note_count()
    if gui_state.needs_note_count_update then
        local current_take, _ = MIDI_UTILS.get_midi_context()
        if not current_take then
            gui_state.selected_note_count = 0
            gui_state.needs_note_count_update = false
            return gui_state.selected_note_count
        end
        
        local note_count = 0
        local note_index = -1
        local safety_counter = 0
        local max_notes = MIDI_UTILS.CONSTANTS.MAX_NOTES_LIMIT

        while safety_counter < max_notes do
            note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
            if note_index == -1 then
                break
            end
            note_count = note_count + 1
            safety_counter = safety_counter + 1
        end
        
        gui_state.selected_note_count = note_count
        gui_state.needs_note_count_update = false
    end
    return gui_state.selected_note_count
end

local function handle_take_change(new_take)
    if gui_state.take ~= new_take then
        gui_state.take = new_take
        invalidate_all_caches()
    end
end

local function handle_selection_change()
    invalidate_all_caches()
end

-- Robust cleanup function
local function cleanup_resources()
    -- Reset all state variables
    gui_state.operation_mode = "move"
    gui_state.direction = "+"
    gui_state.selected_interval = 0
    gui_state.selected_note_count = 0
    gui_state.take = nil
end

-- Register cleanup function with robust protection
CLEANUP_MANAGER.setup_atexit_handler("Note_Mover", cleanup_resources)

-- Function to move notes by interval
local function move_notes_by_interval(interval_semitones, direction)
    local current_take, midi_editor = MIDI_UTILS.get_midi_context()
    
    if not current_take then return end
    
    local selected_notes = {}
    local note_index = -1
    local safety_counter = 0
    local max_notes = MIDI_UTILS.CONSTANTS.MAX_NOTES_LIMIT

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end

        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
        if retval then
            table.insert(selected_notes, {
                index = note_index,
                selected = selected,
                muted = muted,
                startppqpos = startppqpos,
                endppqpos = endppqpos,
                chan = chan,
                pitch = pitch,
                vel = vel
            })
        end
        safety_counter = safety_counter + 1
    end
    
    if #selected_notes == 0 then return end
    
    -- Calculate the pitch change
    local pitch_change = direction == "+" and interval_semitones or -interval_semitones
    
    -- Apply the pitch change to each note
    for _, note in ipairs(selected_notes) do
        local new_pitch = note.pitch + pitch_change
        
        -- Ensure the new pitch is within MIDI range (0-127)
        new_pitch = math.max(0, math.min(127, new_pitch))
        
        -- Update the note pitch
        reaper.MIDI_SetNote(
            current_take,
            note.index,
            nil,  -- selected (keep current)
            nil,  -- muted (keep current)
            nil,  -- startppqpos (keep current)
            nil,  -- endppqpos (keep current)
            nil,  -- chan (keep current)
            new_pitch,  -- new pitch
            nil,  -- vel (keep current)
            true   -- noSort (do sort after all changes)
        )
    end
    
    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()
    
    -- Register undo
    local item = reaper.GetMediaItemTake_Item(current_take)
    MIDI_UTILS.register_undo(item, "Move notes by interval", UNDO_MANAGER)
end

-- Function to copy notes by interval
local function copy_notes_by_interval(interval_semitones, direction)
    local current_take, midi_editor = MIDI_UTILS.get_midi_context()
    
    if not current_take then return end
    
    local selected_notes = {}
    local note_index = -1
    local safety_counter = 0
    local max_notes = MIDI_UTILS.CONSTANTS.MAX_NOTES_LIMIT

    while safety_counter < max_notes do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end

        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
        if retval then
            table.insert(selected_notes, {
                index = note_index,
                selected = selected,
                muted = muted,
                startppqpos = startppqpos,
                endppqpos = endppqpos,
                chan = chan,
                pitch = pitch,
                vel = vel
            })
        end
        safety_counter = safety_counter + 1
    end
    
    if #selected_notes == 0 then return end
    
    -- Calculate the pitch change
    local pitch_change = direction == "+" and interval_semitones or -interval_semitones
    
    -- Create new notes with the pitch change
    for _, note in ipairs(selected_notes) do
        local new_pitch = note.pitch + pitch_change
        
        -- Ensure the new pitch is within MIDI range (0-127)
        new_pitch = math.max(0, math.min(127, new_pitch))
        
        -- Insert new note
        reaper.MIDI_InsertNote(
            current_take,
            note.selected,  -- selected
            note.muted,  -- muted
            note.startppqpos,  -- startppqpos
            note.endppqpos,  -- endppqpos
            note.chan,  -- chan
            new_pitch,  -- pitch
            note.vel,  -- vel
            false  -- noSort (do sort after all changes)
        )
    end
    
    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()
    
    -- Register undo
    local item = reaper.GetMediaItemTake_Item(current_take)
    MIDI_UTILS.register_undo(item, "Copy notes by interval", UNDO_MANAGER)
end

-- Function to apply the selected operation
local function apply_operation()
    if gui_state.selected_note_count < UI_CONSTANTS.MIN_NOTES_FOR_OPERATION then
        return
    end
    
    local interval = INTERVALS[gui_state.selected_interval + 1]
    if not interval then return end
    
    if gui_state.operation_mode == "move" then
        move_notes_by_interval(interval.semitones, gui_state.direction)
    else
        copy_notes_by_interval(interval.semitones, gui_state.direction)
    end
end

-- Handle global keyboard shortcuts
function handle_keyboard_shortcuts()
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = imgui.IsKeyDown(ctx, imgui.Key_LeftShift) or imgui.IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)
        invalidate_all_caches()
        update_note_count()
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
        invalidate_all_caches()
        update_note_count()
    end

    -- Escape key handling
    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
        cleanup_resources()
    end
end

-- Render UI controls for MIDI context
function render_ui_controls()
    if gui_state.selected_note_count < UI_CONSTANTS.MIN_NOTES_FOR_OPERATION then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Select at least " .. UI_CONSTANTS.MIN_NOTES_FOR_OPERATION .. " note to apply operation.")
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, tostring(gui_state.selected_note_count) .. " selected notes")
    end

    imgui.Separator(ctx)

    -- Render operation mode radio buttons
    render_operation_mode_controls()
    
    imgui.Separator(ctx)
    
    -- Render direction radio buttons
    render_direction_controls()
    
    imgui.Separator(ctx)
    
    -- Render interval buttons
    render_interval_buttons()
end

-- Render operation mode controls
function render_operation_mode_controls()
    imgui.Text(ctx, "Operation Mode:")
    
    -- Move radio button
    local move_selected = gui_state.operation_mode == "move"
    if imgui.RadioButton(ctx, "Move", move_selected) then
        gui_state.operation_mode = "move"
    end
    imgui.SameLine(ctx)
    
    -- Copy radio button
    local copy_selected = gui_state.operation_mode == "copy"
    if imgui.RadioButton(ctx, "Copy", copy_selected) then
        gui_state.operation_mode = "copy"
    end
end

-- Render direction controls
function render_direction_controls()
    imgui.Text(ctx, "Direction:")
    
    -- Up (+) radio button
    local up_selected = gui_state.direction == "+"
    if imgui.RadioButton(ctx, "Up (+)", up_selected) then
        gui_state.direction = "+"
    end
    imgui.SameLine(ctx)
    
    -- Down (-) radio button
    local down_selected = gui_state.direction == "-"
    if imgui.RadioButton(ctx, "Down (-)", down_selected) then
        gui_state.direction = "-"
    end
end

-- Render interval buttons
function render_interval_buttons()
    imgui.Text(ctx, "Interval:")
    
    local buttons_per_row = 4
    local button_count = 0
    
    for i, interval in ipairs(INTERVALS) do
        local is_selected = (gui_state.selected_interval == i - 1)
        local direction_symbol = gui_state.direction == "+" and "+" or "-"
        local button_text = direction_symbol .. interval.name
        
        if is_selected then
            reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button, reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.6, 0.2, 1.0)) -- Green
            reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.7, 0.3, 1.0)) -- Lighter green
        end
        
        if imgui.Button(ctx, button_text, UI_CONSTANTS.BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT) then
            gui_state.selected_interval = i - 1
            -- Apply the operation when button is clicked
            apply_operation()
        end
        
        if is_selected then
            reaper.ImGui_PopStyleColor(ctx, 2)
        end
        
        button_count = button_count + 1
        if button_count % buttons_per_row ~= 0 and i < #INTERVALS then
            imgui.SameLine(ctx)
        end
    end
end

-- Main GUI loop
function loop()
    if not script_running then
        -- Use robust cleanup manager instead of manual cleanup
        CLEANUP_MANAGER.execute_cleanup("Note_Mover")
        return
    end

    -- Handle global keyboard shortcuts
    handle_keyboard_shortcuts()

    -- Handle escape key and window management
    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost
    local visible, open = imgui.Begin(ctx, script_name, true, flags)
    
    if not open then
        script_running = false
        -- Use robust cleanup manager when window is closed
        CLEANUP_MANAGER.execute_cleanup("Note_Mover")
    end

    -- Force window to stay on top by bringing it to front if it loses focus
    if visible and script_running then
        local is_window_focused = imgui.IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
        if not is_window_focused then
            -- Bring window to front to maintain topmost behavior
            imgui.SetWindowFocus(ctx)
        end
    end

    -- Clean up caches when the script is terminated to prevent memory leaks
    if not script_running then
        invalidate_all_caches()
    end

    if visible and script_running then
        local current_take, midi_editor = MIDI_UTILS.get_midi_context()

        if not midi_editor then
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Handle take changes using unified state management
            handle_take_change(current_take)

            if not current_take then
                imgui.Text(ctx, "Could not get MIDI take.")
            else
                -- Check if MIDI selection has changed
                local current_note_count = update_note_count()
                if gui_state.selected_note_count ~= current_note_count then
                    handle_selection_change()
                end

                -- Update note count using unified state management
                update_note_count()

                -- Render UI controls
                render_ui_controls()
            end -- end of current_take check
        end -- end of midi_editor check
    end -- end of visible check

    imgui.Spacing(ctx)
    imgui.End(ctx)

    if script_running then
        reaper.defer(loop)
    end
end

-- Init
reaper.defer(loop)