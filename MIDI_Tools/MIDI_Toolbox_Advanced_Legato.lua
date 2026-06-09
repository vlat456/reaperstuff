-- @noindex
-- @description Legato_Tool: Advanced legato editing tool with UI (Refactored)

local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Centralized require statements at the top of the file
local SCRIPT_INIT = require "script_init"
local LEGATO_COMMON = require "legato_common"
local CLEANUP_MANAGER = require "cleanup_manager"
local UNDO_MANAGER = require "undo_manager"
local LEGATO_OPERATIONS = require "legato_operations"
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
local script_name = "Legato Tool"
local ctx = imgui.CreateContext(script_name)
local script_running = true

-- Unified GUI State Management System
local gui_state = {
    -- MIDI context
    take = nil,
    selected_note_count = 0,
    overlay_count = 0,
    
    -- Legato controls
    legato_amount = 0,
    drag_start_legato_amount = 0,
    drag_start_note_states = {},
    
    -- Humanization controls
    humanize_strength = 0,
    
    -- Options
    keep_within_boundaries = false,
    
    -- Cache management
    notes_cache = {},
    cached_overlay_count = -1,
    last_overlay_calculation_take = nil,
    
    -- State invalidation flags
    needs_note_count_update = false,
    needs_overlay_count_update = false,
    needs_cache_invalidation = false
}

-- UI Constants to replace magic numbers
local UI_CONSTANTS = {
    LEGATO_MAX_MS = 400,
    HUMANIZE_MAX = 100,
    BUTTON_WIDTH = 50,
    MIN_NOTES_FOR_LEGATO = 2,
    MIN_NOTES_FOR_HUMANIZE = 1
}

-- Centralized state management functions
local function invalidate_all_caches()
    gui_state.needs_cache_invalidation = true
    gui_state.needs_note_count_update = true
    gui_state.needs_overlay_count_update = true
    gui_state.cached_overlay_count = -1
    gui_state.last_overlay_calculation_take = nil
    gui_state.notes_cache = {}
    gui_state.drag_start_note_states = {}
    
    -- Also invalidate the common cache
    LEGATO_COMMON.invalidate_cached_sorted_notes()
end

local function update_note_count()
    if gui_state.needs_note_count_update then
        local new_count = LEGATO_COMMON.count_selected_notes()
        if gui_state.selected_note_count ~= new_count then
            gui_state.selected_note_count = new_count
            gui_state.needs_cache_invalidation = true
        end
        gui_state.needs_note_count_update = false
    end
    return gui_state.selected_note_count
end

local function update_overlay_count()
    if gui_state.needs_overlay_count_update or gui_state.last_overlay_calculation_take ~= gui_state.take then
        if gui_state.take then
            gui_state.cached_overlay_count = LEGATO_COMMON.detect_overlays_count(gui_state.take)
            gui_state.last_overlay_calculation_take = gui_state.take
        else
            gui_state.cached_overlay_count = 0
        end
        gui_state.overlay_count = gui_state.cached_overlay_count
        gui_state.needs_overlay_count_update = false
    end
    return gui_state.overlay_count
end

local function handle_take_change(new_take)
    if gui_state.take ~= new_take then
        gui_state.take = new_take
        invalidate_all_caches()
    end
end

local function handle_selection_change()
    gui_state.legato_amount = 0
    gui_state.drag_start_legato_amount = 0
    invalidate_all_caches()
end

-- Robust cleanup function
local function cleanup_resources()
    -- Clear all caches using unified state management
    invalidate_all_caches()
    
    -- Reset all state variables
    gui_state.legato_amount = 0
    gui_state.humanize_strength = 0
    gui_state.keep_within_boundaries = false
    gui_state.selected_note_count = 0
    gui_state.overlay_count = 0
    gui_state.take = nil
end

-- Register cleanup function with robust protection
CLEANUP_MANAGER.setup_atexit_handler("Legato_Tool", cleanup_resources)

-- GUI-specific function for applying legato with delta calculations during dragging
-- This is different from the common apply_legato function and needs to stay here
function apply_legato(cache, handle_undo)
    local current_take, midi_editor = MIDI_UTILS.get_midi_context()
    
    if not current_take then return end
    
    local selected_notes = cache or LEGATO_COMMON.get_cached_sorted_selected_notes()
    
    if #selected_notes < UI_CONSTANTS.MIN_NOTES_FOR_LEGATO then
        return  -- Need at least 2 notes for legato
    end
    
    -- Calculate the delta from the drag start value
    local delta_ms = gui_state.legato_amount - gui_state.drag_start_legato_amount
    local delta_ppq = MIDI_UTILS.ms_to_ppq_corrected(delta_ms, current_take, selected_notes[1] and selected_notes[1].startppqpos or 0)
    
    -- Apply the delta to the baseline state from when dragging started
    for i, note in ipairs(selected_notes) do
        local next_note = nil
        if i < #selected_notes then
            next_note = selected_notes[i + 1]
        end
        
        -- Get the baseline end position from the cache (state when dragging started)
        local baseline_end_pos
        if cache and note.original_endppqpos then
            baseline_end_pos = note.original_endppqpos  -- This is the baseline when cache was made
        else
            -- Fallback to current state if no cache
            local current_notes = LEGATO_COMMON.get_cached_sorted_selected_notes()
            for _, current_note in ipairs(current_notes) do
                if current_note.index == note.index then
                    baseline_end_pos = current_note.endppqpos
                    break
                end
            end
            -- If still not found, use direct access as last resort
            if not baseline_end_pos then
                local _, _, _, current_end, _, _, _ = reaper.MIDI_GetNote(current_take, note.index)
                baseline_end_pos = current_end
            end
        end
        
        -- Apply the delta to the baseline state
        local new_end_ppq = baseline_end_pos + delta_ppq
        
        -- Apply same pitch overlap prevention
        new_end_ppq = LEGATO_OPERATIONS.apply_overlap_constraints(note, selected_notes, new_end_ppq)
        
        -- Keep within item boundaries if checkbox is enabled
        new_end_ppq = LEGATO_OPERATIONS.apply_boundary_constraints(note, new_end_ppq, current_take, gui_state.keep_within_boundaries)
        
        -- Set the note end position safely
        if not LEGATO_OPERATIONS.safe_set_note_end(current_take, note.index, note.startppqpos, new_end_ppq) then
            return
        end
    end
    
    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()
    
    -- Only handle undo if explicitly requested (for standalone calls, not during dragging)
    if handle_undo then
        MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Apply legato changes", UNDO_MANAGER)
    end
end

-- Handle global keyboard shortcuts
function handle_keyboard_shortcuts()
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = imgui.IsKeyDown(ctx, imgui.Key_LeftShift) or imgui.IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)  -- Actually, using project-specific as standard Undo_DoUndo() doesn't exist
        -- Invalidate all caches since undo may change CCs or selection
        invalidate_all_caches()
        -- Recalculate statistics to update display after undo
        update_note_count()
        update_overlay_count()
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)  -- Using project-specific function as it's more reliable
        -- Invalidate all caches since redo may change CCs or selection
        invalidate_all_caches()
        -- Recalculate statistics to update display after redo
        update_note_count()
        update_overlay_count()
    end

    -- Escape key handling
    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
        -- Clean up caches when the script is terminated to prevent memory leaks
        invalidate_all_caches()
        -- Reset all state variables when script terminates via Escape key
        gui_state.legato_amount = 0
        gui_state.humanize_strength = 0
    end
end

-- Render UI controls for MIDI context
function render_ui_controls()
    if gui_state.selected_note_count < UI_CONSTANTS.MIN_NOTES_FOR_LEGATO then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, "Select at least " .. UI_CONSTANTS.MIN_NOTES_FOR_LEGATO .. " notes to apply legato.")
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, tostring(gui_state.selected_note_count) .. " selected notes")
    end

    -- Select all notes button (full row)
    if imgui.Button(ctx, "Select all notes", -1, 0) then
        LEGATO_COMMON.select_all_notes()  -- Call the new select all function
        invalidate_all_caches()
    end

    imgui.Separator(ctx)

    -- Group of action buttons: Fill gaps, Detect Overlays, Heal Overlays
    render_action_buttons()
    
    imgui.Separator(ctx)
    
    -- Render legato controls
    render_legato_controls()
    
    imgui.Separator(ctx)
    
    -- Render humanization controls
    render_humanization_controls()
    
    -- Render options section
    render_options_section()
end

-- Render action buttons group
function render_action_buttons()
    if gui_state.selected_note_count >= UI_CONSTANTS.MIN_NOTES_FOR_LEGATO then
        if imgui.Button(ctx, "Fill gaps") then
            LEGATO_COMMON.fill_gaps()
            gui_state.legato_amount = 0  -- Reset legato slider to 0
            invalidate_all_caches()
        end
        imgui.SameLine(ctx)  -- Put the Non-legato button next to Fill gaps
        if imgui.Button(ctx, "Non-legato") then
            LEGATO_COMMON.non_legato()  -- Call the new non-legato function
            gui_state.legato_amount = 0  -- Reset legato slider to 0
            invalidate_all_caches()
        end
        imgui.SameLine(ctx)  -- Put the Detect overlays button next to Non-legato
        if imgui.Button(ctx, "Detect overlays") then
            gui_state.overlay_count = LEGATO_COMMON.detect_overlays()  -- Call the new detect overlays function and store count
            invalidate_all_caches()
        end
        imgui.SameLine(ctx)  -- Put the heal overlays button next to Detect overlays
        if imgui.Button(ctx, "Heal overlays") then
            local resolved_count = LEGATO_COMMON.heal_all_overlaps_guaranteed()  -- Call the guaranteed heal function
            gui_state.overlay_count = LEGATO_COMMON.detect_overlays_count(gui_state.take)  -- Update overlay count after healing
            invalidate_all_caches()
        end
        imgui.SameLine(ctx)
        if imgui.Button(ctx, "Merge same pitches") then
            LEGATO_COMMON.merge_same_pitches()
            invalidate_all_caches()
        end
    else
        imgui.BeginDisabled(ctx)
        imgui.Button(ctx, "Fill gaps")
        imgui.SameLine(ctx)  -- Put the disabled Non-legato button next to Fill gaps
        imgui.Button(ctx, "Non-legato")
        imgui.SameLine(ctx)  -- Put the disabled Detect overlays button next to Non-legato
        imgui.Button(ctx, "Detect overlays")
        imgui.SameLine(ctx)  -- Put the disabled heal overlays button next to Detect overlays
        imgui.Button(ctx, "Heal overlays")
        imgui.SameLine(ctx)
        imgui.Button(ctx, "Merge same pitches")
        imgui.EndDisabled(ctx)
    end

    -- Display overlay count text (red if overlays detected)
    display_overlay_count()
end

-- Display overlay count text
function display_overlay_count()
    if gui_state.overlay_count > 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
        imgui.Text(ctx, tostring(gui_state.overlay_count) .. " overlays detected")
        reaper.ImGui_PopStyleColor(ctx)
    else
        imgui.Text(ctx, tostring(gui_state.overlay_count) .. " overlays detected")
    end
end

-- Render legato controls
function render_legato_controls()
    imgui.Text(ctx, "Make Notes Legato")
    local _, new_legato_amount = imgui.SliderInt(ctx, "Legato Amount (ms)", gui_state.legato_amount, 0, UI_CONSTANTS.LEGATO_MAX_MS, "%d ms")

    -- Handle legato slider interaction for real-time feedback
    handle_legato_slider_interaction(new_legato_amount)
end

-- Handle legato slider interaction
function handle_legato_slider_interaction(new_legato_amount)
    local value_changed = new_legato_amount ~= gui_state.legato_amount
    local is_activated = imgui.IsItemActivated(ctx)
    local is_active = imgui.IsItemActive(ctx)

    -- Build cache when slider interaction starts (when starting to drag)
    if is_activated then
        gui_state.drag_start_legato_amount = gui_state.legato_amount  -- Store the value at drag start
        gui_state.drag_start_note_states = LEGATO_COMMON.build_notes_cache()  -- Store the note states at drag start
        gui_state.notes_cache = gui_state.drag_start_note_states  -- Use the drag start states as the reference
    end

    if value_changed then
        -- Update legato_amount first
        gui_state.legato_amount = new_legato_amount

        if gui_state.selected_note_count >= UI_CONSTANTS.MIN_NOTES_FOR_LEGATO then
            if is_active and #gui_state.notes_cache > 0 then
                -- Currently dragging, apply delta from initial state (no undo handling during drag for visual feedback)
                apply_legato(gui_state.notes_cache, false)
            else
                -- Not dragging, apply to current state (like Apply button would)
                local temp_cache = LEGATO_COMMON.build_notes_cache()
                apply_legato(temp_cache, false)
            end
        end
    end

    -- Clear the cache when the slider is not active to prevent memory buildup
    -- But only when not actively dragging (to preserve the cache during dragging)
    if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #gui_state.notes_cache > 0 then
        gui_state.notes_cache = {}
    end

    if imgui.IsItemDeactivatedAfterEdit(ctx) then
        -- Register undo when slider is released, and reset slider and states to 0 (like Apply button would)
        if gui_state.take then
            reaper.MIDI_Sort(gui_state.take)
            MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Apply legato changes", UNDO_MANAGER)
        end

        -- Update the drag start reference to current state for future delta calculations
        gui_state.drag_start_legato_amount = gui_state.legato_amount  -- Set baseline to current value
        gui_state.drag_start_note_states = LEGATO_COMMON.build_notes_cache()  -- Capture current visual state after changes
        gui_state.legato_amount = 0  -- Reset slider to 0

        -- Also reset any other drag-related states to maintain consistency
        -- If we're currently dragging, make sure to clear the cache
        if #gui_state.notes_cache > 0 then
            gui_state.notes_cache = {}
        end
        LEGATO_COMMON.invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache after applying changes
        gui_state.cached_overlay_count = -1  -- Invalidate overlay cache after applying changes
        gui_state.last_overlay_calculation_take = nil
    end
end

-- Render humanization controls
function render_humanization_controls()
    -- Humanize strength slider with real-time interaction
    local _, new_humanize_strength = imgui.SliderInt(ctx, "Humanize Strength", gui_state.humanize_strength, 0, UI_CONSTANTS.HUMANIZE_MAX, "%d")

    -- Handle humanize slider interaction for real-time feedback
    handle_humanization_slider_interaction(new_humanize_strength)
end

-- Handle humanization slider interaction
function handle_humanization_slider_interaction(new_humanize_strength)
    local humanize_value_changed = new_humanize_strength ~= gui_state.humanize_strength
    local is_humanize_activated = imgui.IsItemActivated(ctx)  -- When user starts dragging
    local is_humanize_active = imgui.IsItemActive(ctx)        -- While user is dragging
    local is_humanize_deactivated = imgui.IsItemDeactivatedAfterEdit(ctx)  -- When user releases

    -- Store original state when humanization starts for proper undo behavior
    if is_humanize_activated then
        gui_state.drag_start_note_states = LEGATO_COMMON.build_notes_cache()  -- Store original note states when dragging starts
    end

    if humanize_value_changed then
        -- Update humanize_strength first
        gui_state.humanize_strength = new_humanize_strength

        -- Apply humanization for real-time feedback while dragging
        -- First restore original state, then apply using current strength to avoid accumulation
        if gui_state.selected_note_count >= UI_CONSTANTS.MIN_NOTES_FOR_HUMANIZE and is_humanize_active then
            if gui_state.take and #gui_state.drag_start_note_states > 0 then
                -- Restore to original state
                LEGATO_COMMON.restore_original_notes(gui_state.drag_start_note_states)
                -- Apply humanization with current strength (no undo during dragging)
                LEGATO_COMMON.apply_humanization(gui_state.humanize_strength, gui_state.keep_within_boundaries, false)
            end
        end
    end

    -- When slider is released, register undo for the current visual state (changes were already applied during drag)
    if is_humanize_deactivated and gui_state.selected_note_count >= UI_CONSTANTS.MIN_NOTES_FOR_HUMANIZE then
        if gui_state.take then
            reaper.MIDI_Sort(gui_state.take)
            MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Apply humanization", UNDO_MANAGER)
        end

        -- Reset the humanize slider to 0 after applying
        gui_state.humanize_strength = 0
        -- Reset the drag start state for future operations
        gui_state.drag_start_note_states = {}
        reaper.UpdateArrange() -- Update display after reset
    end
end

-- Render options section
function render_options_section()
    imgui.Separator(ctx)

    -- Keep within item boundaries checkbox
    local _, new_keep_within_boundaries = imgui.Checkbox(ctx, "Keep within item boundaries", gui_state.keep_within_boundaries)
    gui_state.keep_within_boundaries = new_keep_within_boundaries  -- Update the variable
end

-- Main GUI loop
function loop()
    if not script_running then
        -- Use robust cleanup manager instead of manual cleanup
        CLEANUP_MANAGER.execute_cleanup("Legato_Tool")
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
        CLEANUP_MANAGER.execute_cleanup("Legato_Tool")
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
                if LEGATO_COMMON.midi_selection_changed() then  -- This also handles cache invalidation
                    handle_selection_change()
                end

                -- Update note count and overlay count using unified state management
                update_note_count()
                update_overlay_count()

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