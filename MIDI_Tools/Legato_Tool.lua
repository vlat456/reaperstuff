-- @description Legato Tool - Creating legato effects and stuff
-- @author drvlat
-- @version 0.2.0
-- @provides [main=midi_editor,midi_inlineeditor,midi_eventlisteditor] .
-- @about
--   This is a ReaScript for REAPER that provides tools for creating legato effects in MIDI.
--   It extends MIDI notes to create legato effects, detects and handles note overlays,
--   and fills gaps between notes.
--
--   The tool provides a user interface for adjusting settings and applying legato effects
--   to selected MIDI notes in the MIDI editor.
-- @changelog
--      0.2.0 - extracted common functionality to shared library, added quick scripts
--      0.1.6 - resolve all overlays (guaranteed) at once
--      0.1.5 - some minor optimization, proper undo handling
--      0.1.4 - non-deterministic humanization
--      0.1.3 - added Non-legato function and legato humanization.


local reaper = reaper

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

local LEGATO_COMMON = require "legato_common"

-- Create local aliases for common functions to maintain existing function calls
local get_midi_context = LEGATO_COMMON.get_midi_context
local get_active_take = LEGATO_COMMON.get_active_take
local count_selected_notes = LEGATO_COMMON.count_selected_notes
local get_selected_notes = LEGATO_COMMON.get_selected_notes
local get_selected_notes_optimized = LEGATO_COMMON.get_selected_notes_optimized
local get_item_boundaries_in_ppq = LEGATO_COMMON.get_item_boundaries_in_ppq
local get_current_selected_note_info = LEGATO_COMMON.get_current_selected_note_info
local midi_selection_changed = LEGATO_COMMON.midi_selection_changed
local restore_original_notes = LEGATO_COMMON.restore_original_notes
local detect_overlays = LEGATO_COMMON.detect_overlays
local table_contains = LEGATO_COMMON.table_contains
local get_cached_sorted_selected_notes = LEGATO_COMMON.get_cached_sorted_selected_notes
local invalidate_sorted_notes_cache = LEGATO_COMMON.invalidate_sorted_notes_cache
local invalidate_cached_sorted_notes = LEGATO_COMMON.invalidate_cached_sorted_notes
local ms_to_ppq_corrected = LEGATO_COMMON.ms_to_ppq_corrected
local get_ppq_delta_for_ms_at_position = LEGATO_COMMON.get_ppq_delta_for_ms_at_position
local heal_overlays = LEGATO_COMMON.heal_overlays
local heal_all_overlaps_guaranteed = LEGATO_COMMON.heal_all_overlaps_guaranteed
local detect_overlays_count = LEGATO_COMMON.detect_overlays_count
local select_all_notes = LEGATO_COMMON.select_all_notes
local non_legato = LEGATO_COMMON.non_legato
local fill_gaps = LEGATO_COMMON.fill_gaps
local build_notes_cache = LEGATO_COMMON.build_notes_cache
local common_apply_legato = LEGATO_COMMON.apply_legato  -- Renamed to avoid conflict with GUI-specific function

-- The humanization function will be handled inline during GUI interaction to ensure proper access to current global state

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
local take = nil
local last_clicked_cc_lane = -1  -- This will be repurposed for general MIDI context
local selected_note_count = 0
local overlay_count = 0  -- For tracking overlay count
local legato_amount = 0 -- Current legato amount in milliseconds (0-400ms)
local drag_start_legato_amount = 0 -- Legato amount at the start of dragging
local drag_start_note_states = {} -- Store the note states at drag start for delta calculations
local keep_within_boundaries = false -- Flag to keep notes within media item boundaries
local humanize_strength = 0 -- Strength of humanization effect (0-100)
local notes_cache_valid = false
local notes_cache = {}  -- Cache for selected notes

-- GUI-specific function for applying legato with delta calculations during dragging
-- This is different from the common apply_legato function and needs to stay here
function apply_legato(cache, handle_undo)
    local current_take, midi_editor = get_midi_context()

    if not current_take then return end

    local selected_notes = cache or get_cached_sorted_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes for legato
    end

    -- Calculate the delta from the drag start value
    local delta_ms = legato_amount - drag_start_legato_amount
    local delta_ppq = ms_to_ppq_corrected(delta_ms, current_take, selected_notes[1] and selected_notes[1].startppqpos or 0)

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
            local _, _, _, _, current_end, _, _, _ = reaper.MIDI_GetNote(current_take, note.index)
            baseline_end_pos = current_end
        end

        -- Apply the delta to the baseline state
        local new_end_ppq = baseline_end_pos + delta_ppq

        -- Apply constraints:
        -- 1. Same pitch notes must not overlap - search all notes for potential overlap
        -- Check all selected notes for same pitch that start after this note ends
        for _, potential_next_note in ipairs(selected_notes) do
            if note.pitch == potential_next_note.pitch and
               potential_next_note.startppqpos > note.startppqpos and  -- Only look at notes that start after current note start
               potential_next_note.startppqpos < new_end_ppq then      -- And that start before the current note would end (with legato)
                new_end_ppq = math.min(new_end_ppq, potential_next_note.startppqpos)
            end
        end


        -- 2. Keep within item boundaries if checkbox is enabled
        if keep_within_boundaries then
            local item_start_ppq, item_end_ppq = get_item_boundaries_in_ppq(current_take)
            -- Constrain to item end boundary
            new_end_ppq = math.min(new_end_ppq, item_end_ppq)
            -- Constrain to item start boundary - note end should not be before item start
            -- But only if the note is within the item boundaries
            if note.startppqpos >= item_start_ppq and note.startppqpos < item_end_ppq then
                -- If note starts within the item, make sure end doesn't go before item start
                new_end_ppq = math.max(new_end_ppq, item_start_ppq)
            end
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

    -- Sort MIDI events to ensure correct ordering after changes
    reaper.MIDI_Sort(current_take)
    reaper.UpdateArrange()

    -- Only handle undo if explicitly requested (for standalone calls, not during dragging)
    if handle_undo then
        local item = reaper.GetMediaItemTake_Item(current_take)
        -- Update the item and register the change in undo system
        reaper.UpdateItemInProject(item)
        reaper.Undo_OnStateChange_Item(0, "Apply legato changes", item)
    end
end


-- Main GUI loop
function loop()
    if not script_running then

        -- Clean up caches when the script is terminated to prevent memory leaks
        notes_cache = {}
        drag_start_note_states = {}
        invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache
        -- Reset all state variables when script terminates
        legato_amount = 0
        humanize_strength = 0
        return
    end

    -- Handle global keyboard shortcuts
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = imgui.IsKeyDown(ctx, imgui.Key_LeftShift) or imgui.IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)  -- Actually, using project-specific as standard Undo_DoUndo() doesn't exist
        -- Invalidate all caches since undo may change CCs or selection
        notes_cache = {}
        drag_start_note_states = {}
        invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache
        last_selected_note_indices = {}  -- Reset selection signature to force recalculation
        -- Recalculate statistics to update display after undo
        selected_note_count = count_selected_notes()
        if take then
            overlay_count = detect_overlays_count(take)  -- Update overlay count after undo
        end
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)  -- Using project-specific function as it's more reliable
        -- Invalidate all caches since redo may change CCs or selection
        notes_cache = {}
        drag_start_note_states = {}
        invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache
        last_selected_note_indices = {}  -- Reset selection signature to force recalculation
        -- Recalculate statistics to update display after redo
        selected_note_count = count_selected_notes()
        if take then
            overlay_count = detect_overlays_count(take)  -- Update overlay count after redo
        end
    end

    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false

        -- Clean up caches when the script is terminated to prevent memory leaks
        notes_cache = {}
        drag_start_note_states = {}
        invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache
        -- Reset all state variables when script terminates via Escape key
        legato_amount = 0
        humanize_strength = 50
    end

    local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse
    local visible, open = imgui.Begin(ctx, script_name, true, flags)

    if not open then script_running = false end

    -- Check for clicks outside the window to close it
    local is_window_hovered = imgui.IsWindowHovered(ctx, imgui.HoveredFlags_RootAndChildWindows)
    local is_window_focused = imgui.IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
    local is_mouse_down = imgui.IsMouseDown(ctx, imgui.MouseButton_Left)

    -- Check if mouse was just released (meaning a click happened outside)
    local is_mouse_clicked = imgui.IsMouseClicked(ctx, imgui.MouseButton_Left)

    -- Close when clicking outside the window area
    if visible and is_window_hovered == false and is_mouse_clicked then
        script_running = false
    end

    -- Clean up caches when the script is terminated to prevent memory leaks
    if not script_running then

        notes_cache = {}
        drag_start_note_states = {}
        invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache
    end

    if visible and script_running then
        local current_take, midi_editor = get_midi_context()

        if not midi_editor then
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Clear cache if take changes to prevent memory leaks
            if take ~= current_take then
                if #notes_cache > 0 then
                    notes_cache = {}
                end
                if #drag_start_note_states > 0 then
                    drag_start_note_states = {}
                end
                invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache
            end

            take = current_take

            if not current_take then
                imgui.Text(ctx, "Could not get MIDI take.")
            else
                -- Check if MIDI selection has changed
                if midi_selection_changed() then  -- This also handles cache invalidation
                    -- Reset to fresh state when selection changes (like just opened)
                    legato_amount = 0  -- Reset slider to 0
                    drag_start_legato_amount = 0  -- Reset drag start to 0
                    drag_start_note_states = {}  -- Clear the drag start states
                    notes_cache = {}  -- Clear the drag cache
                end

                -- Count selected notes and overlays (with caching to avoid repeated calculation)
                if current_take then
                    -- Recalculate if cache is invalid or MIDI context changed
                    local current_note_count = count_selected_notes()
                    if selected_note_count ~= current_note_count or take ~= current_take then
                        selected_note_count = current_note_count
                        take = current_take

                        -- Invalidate sorted notes cache when note count changes
                        if last_cache_note_count ~= current_note_count then
                            invalidate_sorted_notes_cache()
                        end
                    end

                    -- Update overlay count when needed (for display)
                    overlay_count = detect_overlays_count(current_take)  -- Update overlay count for selected notes
                else
                    selected_note_count = 0
                    overlay_count = 0  -- Reset overlay count when there's no take
                end

                if selected_note_count < 2 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, "Select at least 2 notes to apply legato.")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(selected_note_count) .. " selected notes")
                end

                -- Select all notes button (full row)
                if imgui.Button(ctx, "Select all notes", -1, 0) then
                    select_all_notes()  -- Call the new select all function
                    invalidate_cached_sorted_notes() -- Invalidate cache after selection changes
                end

                imgui.Separator(ctx)

                -- Group of action buttons: Fill gaps, Detect Overlays, Heal Overlays
                if selected_note_count >= 2 then
                    if imgui.Button(ctx, "Fill gaps") then
                        fill_gaps()  -- Call the new fill gaps function
                        legato_amount = 0  -- Reset legato slider to 0
                        invalidate_cached_sorted_notes() -- Invalidate cache after changes
                    end
                    imgui.SameLine(ctx)  -- Put the Non-legato button next to Fill gaps
                    if imgui.Button(ctx, "Non-legato") then
                        non_legato()  -- Call the new non-legato function
                        legato_amount = 0  -- Reset legato slider to 0
                        invalidate_cached_sorted_notes() -- Invalidate cache after changes
                    end
                    imgui.SameLine(ctx)  -- Put the Detect overlays button next to Non-legato
                    if imgui.Button(ctx, "Detect overlays") then
                        overlay_count = detect_overlays()  -- Call the new detect overlays function and store count
                        invalidate_cached_sorted_notes() -- Invalidate cache after changes
                    end

                    imgui.SameLine(ctx)  -- Put the heal overlays button next to Detect overlays
                    if imgui.Button(ctx, "Heal overlays") then
                        local resolved_count = heal_all_overlaps_guaranteed()  -- Call the guaranteed heal function
                        overlay_count = detect_overlays_count(current_take)  -- Update overlay count after healing
                        invalidate_cached_sorted_notes() -- Invalidate cache after changes
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
                    imgui.EndDisabled(ctx)
                end

                -- Display overlay count text (red if overlays detected)
                if overlay_count > 0 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, tostring(overlay_count) .. " overlays detected")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(overlay_count) .. " overlays detected")
                end

                imgui.Separator(ctx)

                -- Legato Section
                imgui.Text(ctx, "Make Notes Legato")
                local _, new_legato_amount = imgui.SliderInt(ctx, "Legato Amount (ms)", legato_amount, 0, 400, "%d ms")

                -- Handle legato slider interaction for real-time feedback
                local value_changed = new_legato_amount ~= legato_amount
                local is_activated = imgui.IsItemActivated(ctx)
                local is_active = imgui.IsItemActive(ctx)

                -- Build cache when slider interaction starts (when starting to drag)
                if is_activated then
                    drag_start_legato_amount = legato_amount  -- Store the value at drag start
                    drag_start_note_states = build_notes_cache()  -- Store the note states at drag start
                    notes_cache = drag_start_note_states  -- Use the drag start states as the reference
                end

                if value_changed then
                    -- Update legato_amount first
                    legato_amount = new_legato_amount

                    if selected_note_count >= 2 then
                        if is_active and #notes_cache > 0 then
                            -- Currently dragging, apply delta from initial state (no undo handling during drag for visual feedback)
                            apply_legato(notes_cache, false)
                        else
                            -- Not dragging, apply to current state (like Apply button would)
                            local temp_cache = build_notes_cache()
                            apply_legato(temp_cache, false)
                        end
                    end
                end

                -- Clear the cache when the slider is not active to prevent memory buildup
                -- But only when not actively dragging (to preserve the cache during dragging)
                if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #notes_cache > 0 then
                    notes_cache = {}
                end

                if imgui.IsItemDeactivatedAfterEdit(ctx) then
                    -- Register undo when slider is released, and reset slider and states to 0 (like Apply button would)
                    if take then
                        reaper.MIDI_Sort(take)
                        local item = reaper.GetMediaItemTake_Item(take)
                        -- Update the item and register the change in undo system
                        reaper.UpdateItemInProject(item)
                        reaper.Undo_OnStateChange_Item(0, "Apply legato changes", item)
                    end

                    -- Update the drag start reference to current state for future delta calculations
                    drag_start_legato_amount = legato_amount  -- Set baseline to current value
                    drag_start_note_states = build_notes_cache()  -- Capture current visual state after changes
                    legato_amount = 0  -- Reset slider to 0

                    -- Also reset any other drag-related states to maintain consistency
                    -- If we're currently dragging, make sure to clear the cache
                    if #notes_cache > 0 then
                        notes_cache = {}
                    end
                    invalidate_cached_sorted_notes() -- Also invalidate sorted notes cache after applying changes
                end


                -- Humanize strength slider with real-time interaction
                local _, new_humanize_strength = imgui.SliderInt(ctx, "Humanize Strength", humanize_strength, 0, 100, "%d")

                -- Handle humanize slider interaction for real-time feedback
                local humanize_value_changed = new_humanize_strength ~= humanize_strength
                local is_humanize_activated = imgui.IsItemActivated(ctx)  -- When user starts dragging
                local is_humanize_active = imgui.IsItemActive(ctx)        -- While user is dragging
                local is_humanize_deactivated = imgui.IsItemDeactivatedAfterEdit(ctx)  -- When user releases

                -- Store original state when humanization starts for proper undo behavior
                if is_humanize_activated then
                    drag_start_note_states = build_notes_cache()  -- Store original note states when dragging starts
                end

                if humanize_value_changed then
                    -- Update humanize_strength first
                    humanize_strength = new_humanize_strength

                    -- Apply humanization for real-time feedback while dragging
                    -- First restore original state, then apply using current strength to avoid accumulation
                    if selected_note_count >= 1 and is_humanize_active then
                        if take and #drag_start_note_states > 0 then
                            -- Restore to original state
                            restore_original_notes(drag_start_note_states)
                            -- Apply humanization with current strength (no undo during dragging)
                            LEGATO_COMMON.apply_humanization(humanize_strength, keep_within_boundaries, false)
                        end
                    end
                end

                -- When slider is released, register undo for the current visual state (changes were already applied during drag)
                if is_humanize_deactivated and selected_note_count >= 1 then
                    if take then
                        reaper.MIDI_Sort(take)
                        local item = reaper.GetMediaItemTake_Item(take)
                        -- Update the item and register the change in undo system
                        reaper.UpdateItemInProject(item)
                        reaper.Undo_OnStateChange_Item(0, "Apply humanization", item)
                    end

                    -- Reset the humanize slider to 0 after applying
                    humanize_strength = 0
                    -- Reset the drag start state for future operations
                    drag_start_note_states = {}
                    reaper.UpdateArrange() -- Update display after reset
                end

                imgui.Separator(ctx)

                -- Keep within item boundaries checkbox
                local _, new_keep_within_boundaries = imgui.Checkbox(ctx, "Keep within item boundaries", keep_within_boundaries)
                keep_within_boundaries = new_keep_within_boundaries  -- Update the variable




            end
        end
    end

    imgui.Spacing(ctx)
    imgui.End(ctx)

    if script_running then
        reaper.defer(loop)
    end
end

-- Init
reaper.defer(loop)