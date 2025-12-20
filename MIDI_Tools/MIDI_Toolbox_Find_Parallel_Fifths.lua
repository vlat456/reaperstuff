-- @noindex
-- @description Parallel Intervals Detector: Advanced tool for detecting parallel intervals with UI

local reaper = reaper

-- Set up module path consistently
SCRIPT_INIT.setup_module_path()

-- Centralized require statements at the top of the file
local SCRIPT_INIT = require "script_init"
local PARALLEL_DETECTOR = require "parallel_detector"
local CLEANUP_MANAGER = require "cleanup_manager"
local UNDO_MANAGER = require "undo_manager"
local MIDI_UTILS = require "midi_utils"
local LEGATO_COMMON = require "legato_common"

-- Check for reaimgui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load the ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

-- Script variables
local script_name = "Parallel Intervals Detector"
local ctx = imgui.CreateContext(script_name)
local script_running = true

-- Unified GUI State Management System
local gui_state = {
    -- MIDI context
    take = nil,
    selected_note_count = 0,
    total_note_count = 0,
    
    -- Detection results
    parallel_fifths_count = 0,
    parallel_octaves_count = 0,
    parallel_fourths_count = 0,
    total_errors_count = 0,
    
    -- Detection options
    detect_fifths = true,
    detect_octaves = false,
    detect_fourths = false,
    use_selected_notes = true,
    
    -- Cache management
    notes_cache = {},
    cached_detection_results = {},
    last_detection_take = nil,
    last_detection_options = {},
    
    -- State invalidation flags
    needs_note_count_update = false,
    needs_total_count_update = false,
    needs_detection_update = false,
    needs_cache_invalidation = false
}

-- UI Constants to replace magic numbers
local UI_CONSTANTS = {
    MIN_NOTES_FOR_DETECTION = 4,  -- Need at least 4 notes for meaningful parallel detection
    BUTTON_WIDTH = 120,
    TOLERANCE_MIN = 0.010,
    TOLERANCE_MAX = 0.200,
    TOLERANCE_DEFAULT = 0.040
}

-- Centralized state management functions
local function invalidate_all_caches()
    gui_state.needs_cache_invalidation = true
    gui_state.needs_note_count_update = true
    gui_state.needs_total_count_update = true
    gui_state.needs_detection_update = true
    gui_state.notes_cache = {}
    gui_state.cached_detection_results = {}
    gui_state.last_detection_take = nil
    gui_state.last_detection_options = {}
end

local function update_note_count()
    if gui_state.needs_note_count_update then
        local new_count = 0
        if gui_state.take then
            -- Use the centralized function from legato_common module
            new_count = LEGATO_COMMON.count_selected_notes()
        end
        
        if gui_state.selected_note_count ~= new_count then
            gui_state.selected_note_count = new_count
            gui_state.needs_cache_invalidation = true
        end
        gui_state.needs_note_count_update = false
    end
    return gui_state.selected_note_count
end

local function update_total_note_count()
    if gui_state.needs_total_count_update or gui_state.last_detection_take ~= gui_state.take then
        if gui_state.take then
            local retval, notecnt, _, _ = reaper.MIDI_CountEvts(gui_state.take)
            gui_state.total_note_count = retval and notecnt or 0
            gui_state.last_detection_take = gui_state.take
        else
            gui_state.total_note_count = 0
        end
        gui_state.needs_total_count_update = false
    end
    return gui_state.total_note_count
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
    -- Clear all caches using unified state management
    invalidate_all_caches()
    
    -- Reset all state variables
    gui_state.parallel_fifths_count = 0
    gui_state.parallel_octaves_count = 0
    gui_state.parallel_fourths_count = 0
    gui_state.total_errors_count = 0
    gui_state.selected_note_count = 0
    gui_state.total_note_count = 0
    gui_state.take = nil
    gui_state.detect_fifths = true
    gui_state.detect_octaves = false
    gui_state.detect_fourths = false
    gui_state.use_selected_notes = true
end

-- Register cleanup function with robust protection
CLEANUP_MANAGER.setup_atexit_handler("Parallel_Intervals_Detector", cleanup_resources)

-- Function to perform parallel interval detection
local function detect_parallel_intervals()
    if not gui_state.take then return end
    
    -- Get notes based on selection preference
    local notes
    if gui_state.use_selected_notes then
        -- Use the centralized function from legato_common module
        notes = LEGATO_COMMON.get_selected_notes()
    else
        -- Get all notes
        notes = PARALLEL_DETECTOR.get_all_notes_from_take(gui_state.take)
    end
    
    if #notes < UI_CONSTANTS.MIN_NOTES_FOR_DETECTION then
        gui_state.parallel_fifths_count = 0
        gui_state.parallel_octaves_count = 0
        gui_state.parallel_fourths_count = 0
        gui_state.total_errors_count = 0
        return
    end
    
    -- Begin undo block for marker creation
    UNDO_MANAGER.begin_undo_block("Detect Parallel Intervals")
    
    -- Clear existing markers (optional - you might want to comment this out)
    -- local marker_count = reaper.CountProjectMarkers(0)
    -- for i = marker_count - 1, 0, -1 do
    --     local _, _, _, _, name = reaper.EnumProjectMarkers3(0, i)
    --     if name and (name:find("Parallel") or name:find("fifths") or name:find("octaves") or name:find("fourths")) then
    --         reaper.DeleteProjectMarkerByIndex(0, i, false)
    --     end
    -- end
    
    -- Detect intervals based on options
    gui_state.parallel_fifths_count = 0
    gui_state.parallel_octaves_count = 0
    gui_state.parallel_fourths_count = 0
    
    if gui_state.detect_fifths then
        local errors_found = PARALLEL_DETECTOR.detect_parallel_fifths(gui_state.take, notes, true)  -- Use selection mode
        gui_state.parallel_fifths_count = #errors_found
    end
    
    if gui_state.detect_octaves then
        local errors_found = PARALLEL_DETECTOR.detect_parallel_octaves(gui_state.take, notes, true)  -- Use selection mode
        gui_state.parallel_octaves_count = #errors_found
    end
    
    if gui_state.detect_fourths then
        local errors_found = PARALLEL_DETECTOR.detect_parallel_fourths(gui_state.take, notes, true)  -- Use selection mode
        gui_state.parallel_fourths_count = #errors_found
    end
    
    gui_state.total_errors_count = gui_state.parallel_fifths_count + gui_state.parallel_octaves_count + gui_state.parallel_fourths_count
    
    -- End undo block
    UNDO_MANAGER.end_undo_block("Detect Parallel Intervals")
    
    -- Update arrange view
    reaper.UpdateArrange()
end

-- Handle global keyboard shortcuts
function handle_keyboard_shortcuts()
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)
        invalidate_all_caches()
        update_note_count()
        update_total_note_count()
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and imgui.IsKeyDown(ctx, imgui.Key_LeftShift) and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
        invalidate_all_caches()
        update_note_count()
        update_total_note_count()
    end

    -- Escape key handling
    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
        invalidate_all_caches()
    end
end

-- Render UI controls for MIDI context
function render_ui_controls()
    -- Display note counts
    local notes_to_analyze = gui_state.use_selected_notes and gui_state.selected_note_count or gui_state.total_note_count
    imgui.Text(ctx, "Notes to analyze: " .. notes_to_analyze)
    
    if notes_to_analyze < UI_CONSTANTS.MIN_NOTES_FOR_DETECTION then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Select at least " .. UI_CONSTANTS.MIN_NOTES_FOR_DETECTION .. " notes for meaningful detection.")
        reaper.ImGui_PopStyleColor(ctx)
    end
    
    imgui.Separator(ctx)
    
    -- Render detection options
    render_detection_options()
    
    imgui.Separator(ctx)
    
    -- Render action buttons
    render_action_buttons()
    
    imgui.Separator(ctx)
    
    -- Render results section
    render_results_section()
end

-- Render detection options
function render_detection_options()
    imgui.Text(ctx, "Detection Options:")
    
    -- Interval type checkboxes
    local _, new_detect_fifths = imgui.Checkbox(ctx, "Detect Parallel Fifths", gui_state.detect_fifths)
    if new_detect_fifths ~= gui_state.detect_fifths then
        gui_state.detect_fifths = new_detect_fifths
        gui_state.needs_detection_update = true
    end
    
    local _, new_detect_octaves = imgui.Checkbox(ctx, "Detect Parallel Octaves", gui_state.detect_octaves)
    if new_detect_octaves ~= gui_state.detect_octaves then
        gui_state.detect_octaves = new_detect_octaves
        gui_state.needs_detection_update = true
    end
    
    local _, new_detect_fourths = imgui.Checkbox(ctx, "Detect Parallel Fourths", gui_state.detect_fourths)
    if new_detect_fourths ~= gui_state.detect_fourths then
        gui_state.detect_fourths = new_detect_fourths
        gui_state.needs_detection_update = true
    end
    
    imgui.Spacing(ctx)
    
    -- Note selection radio buttons
    imgui.Text(ctx, "Analyze:")
    local new_use_selected = imgui.RadioButton(ctx, "Selected notes only", gui_state.use_selected_notes)
    if new_use_selected ~= gui_state.use_selected_notes then
        gui_state.use_selected_notes = new_use_selected
        gui_state.needs_detection_update = true
    end
    
    imgui.SameLine(ctx)
    local new_use_all = imgui.RadioButton(ctx, "All notes", not gui_state.use_selected_notes)
    if new_use_all == gui_state.use_selected_notes then
        gui_state.use_selected_notes = not new_use_all
        gui_state.needs_detection_update = true
    end
end

-- Render action buttons
function render_action_buttons()
    -- Detect button
    local can_detect = (gui_state.detect_fifths or gui_state.detect_octaves or gui_state.detect_fourths) and 
                     (gui_state.use_selected_notes and gui_state.selected_note_count >= UI_CONSTANTS.MIN_NOTES_FOR_DETECTION or 
                      not gui_state.use_selected_notes and gui_state.total_note_count >= UI_CONSTANTS.MIN_NOTES_FOR_DETECTION)
    
    if not can_detect then
        imgui.BeginDisabled(ctx)
    end
    
    if imgui.Button(ctx, "Detect Parallel Intervals", UI_CONSTANTS.BUTTON_WIDTH, 0) then
        detect_parallel_intervals()
    end
    
    if not can_detect then
        imgui.EndDisabled(ctx)
    end
    
    imgui.SameLine(ctx)
    
    -- Clear selection button
    if imgui.Button(ctx, "Clear Selection", UI_CONSTANTS.BUTTON_WIDTH, 0) then
        -- UNDO_MANAGER.begin_undo_block("Clear Note Selection")
        
        -- Deselect all notes in the take
        if gui_state.take then
            local retval, notecnt, _, _ = reaper.MIDI_CountEvts(gui_state.take)
            if retval then
                for note_idx = 0, notecnt - 1 do
                    reaper.MIDI_SetNote(gui_state.take, note_idx, false, nil, nil, nil, nil, nil, nil, true)
                end
            end
        end
        
        -- UNDO_MANAGER.end_undo_block("Clear Note Selection")
        
        -- Register undo
        local item = reaper.GetMediaItemTake_Item(gui_state.take)
        SCRIPT_INIT.register_undo(item, "Clear Note Selection")
        
        -- Reset counts
        gui_state.parallel_fifths_count = 0
        gui_state.parallel_octaves_count = 0
        gui_state.parallel_fourths_count = 0
        gui_state.total_errors_count = 0
        reaper.UpdateArrange()
    end
end

-- Render results section
function render_results_section()
    imgui.Text(ctx, "Detection Results:")
    
    -- Display results with color coding
    if gui_state.parallel_fifths_count > 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Parallel Fifths: " .. gui_state.parallel_fifths_count)
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, "Parallel Fifths: " .. gui_state.parallel_fifths_count)
    end
    
    if gui_state.parallel_octaves_count > 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Parallel Octaves: " .. gui_state.parallel_octaves_count)
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, "Parallel Octaves: " .. gui_state.parallel_octaves_count)
    end
    
    if gui_state.parallel_fourths_count > 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Parallel Fourths: " .. gui_state.parallel_fourths_count)
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, "Parallel Fourths: " .. gui_state.parallel_fourths_count)
    end
    
    imgui.Spacing(ctx)
    
    if gui_state.total_errors_count > 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Total Issues Found: " .. gui_state.total_errors_count)
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, "Total Issues Found: " .. gui_state.total_errors_count)
    end
end

-- Main GUI loop
function loop()
    if not script_running then
        -- Use robust cleanup manager instead of manual cleanup
        CLEANUP_MANAGER.execute_cleanup("Parallel_Intervals_Detector")
        return
    end

    -- Handle global keyboard shortcuts
    handle_keyboard_shortcuts()

    -- Handle escape key and window management
    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse
    local visible, open = imgui.Begin(ctx, script_name, true, flags)
    
    if not open then
        script_running = false
        -- Use robust cleanup manager when window is closed
        CLEANUP_MANAGER.execute_cleanup("Parallel_Intervals_Detector")
    end

    -- Check for clicks outside of window to close it
    local is_window_hovered = imgui.IsWindowHovered(ctx, imgui.HoveredFlags_RootAndChildWindows)
    local is_window_focused = imgui.IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
    local is_mouse_clicked = imgui.IsMouseClicked(ctx, imgui.MouseButton_Left)

    -- Close when clicking outside the window area
    if visible and is_window_hovered == false and is_mouse_clicked then
        script_running = false
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
                -- Check if MIDI selection has changed using centralized function
                if LEGATO_COMMON.midi_selection_changed() then
                    handle_selection_change()
                end

                -- Update note counts using unified state management
                update_note_count()
                update_total_note_count()

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