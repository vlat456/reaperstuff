--[[
# Description
A script to make selected notes legato in the MIDI editor.
This script adds the specified amount of time (in milliseconds) to the duration of each selected note.
For notes of the same pitch, overlap prevention ensures they never overlap regardless of the legato setting.

# Instructions
1. Open the MIDI editor in REAPER.
2. Select at least 2 notes that you want to make legato.
3. Run this script.
4. Use the GUI slider to adjust the legato amount (0-400ms).
   The legato amount represents additional time added to each note's original duration.

# Requirements
* REAPER v5.95+
* ReaImGui: v0.4+ (Available via ReaPack -> ReaTeam Extensions)
--]]

local reaper = reaper

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
local legato_amount = 0 -- Current legato amount in milliseconds (0-400ms)
local drag_start_legato_amount = 0 -- Legato amount at the start of dragging
local drag_start_note_states = {} -- Store the note states at drag start for delta calculations
local notes_cache_valid = false
local notes_cache = {}  -- Cache for selected notes

-- Function to get current MIDI context consistently
function get_midi_context()
    local midi_editor = reaper.MIDIEditor_GetActive()
    if not midi_editor then return nil, nil end

    local current_take = reaper.MIDIEditor_GetTake(midi_editor)
    if not current_take then return nil, nil end

    return current_take, midi_editor
end

-- Helper function to get the active MIDI take
function get_active_take()
    local current_take, midi_editor = get_midi_context()
    return current_take
end

-- Function to count selected notes in the current take
function count_selected_notes()
    local current_take, midi_editor = get_midi_context()

    if not current_take then
        return 0
    end

    local note_count = 0
    local note_index = -1

    while true do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end
        note_count = note_count + 1
    end

    return note_count
end

-- Function to build notes cache with original values preserved
function build_notes_cache()
    local current_take, midi_editor = get_midi_context()

    if not current_take then return {} end

    local notes = {}
    local note_index = -1

    while true do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end

        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
        if retval then
            table.insert(notes, {
                index = note_index,
                selected = selected,
                muted = muted,
                startppqpos = startppqpos,
                endppqpos = endppqpos,  -- Current end position
                original_endppqpos = endppqpos,  -- Baseline end position when cache was created
                chan = chan,
                pitch = pitch,
                vel = vel
            })
        end
    end

    -- Sort notes by start position
    table.sort(notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    return notes
end

-- Function to get selected notes with their properties
function get_selected_notes()
    local current_take, midi_editor = get_midi_context()

    if not current_take then
        return {}
    end

    local notes = {}
    local note_index = -1

    while true do
        note_index = reaper.MIDI_EnumSelNotes(current_take, note_index)
        if note_index == -1 then
            break
        end

        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(current_take, note_index)
        if retval then
            table.insert(notes, {
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
    end

    -- Sort notes by start position
    table.sort(notes, function(a, b)
        return a.startppqpos < b.startppqpos
    end)

    return notes
end

-- Function to restore notes to their original state
function restore_original_notes(cache)
    local current_take, midi_editor = get_midi_context()

    if not current_take or not cache then return end

    for _, note in ipairs(cache) do
        -- Restore to original end position
        reaper.MIDI_SetNote(
            current_take,
            note.index,
            nil,  -- selected
            nil,  -- muted
            nil,  -- startppqpos (keep current)
            note.original_endppqpos,  -- Restore original end position
            nil,  -- chan
            nil,  -- pitch
            nil,  -- vel
            true   -- take
        )
    end

    reaper.UpdateArrange()
end

-- Function to apply legato to selected notes using delta from baseline state
function apply_legato(cache)
    local current_take, midi_editor = get_midi_context()

    if not current_take then return end

    local selected_notes = cache or get_selected_notes()

    if #selected_notes < 2 then
        return  -- Need at least 2 notes for legato
    end

    -- Get project tempo to convert milliseconds to PPQ
    local proj = 0 -- Current project (0 means currently active project)
    local tempo = reaper.Master_GetTempo()

    -- Convert milliseconds to PPQ (pulses per quarter note)
    -- Standard MIDI timebase is 480 PPQ at 120 BPM
    -- 1 ms = (tempo/60) * (480/1000) PPQ
    local ms_to_ppq = function(ms)
        return (ms * tempo * 480) / (60 * 1000)
    end

    -- Calculate the delta from the drag start value
    local delta_ms = legato_amount - drag_start_legato_amount
    local delta_ppq = ms_to_ppq(delta_ms)

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

        -- Make sure the new end position is not before the start position
        if new_end_ppq > note.startppqpos then
            reaper.MIDI_SetNote(current_take, note.index, nil, nil, note.startppqpos, new_end_ppq, nil, nil, nil, true)
        end
    end

    reaper.UpdateArrange()
end


-- Main GUI loop
function loop()
    if not script_running then return end

    -- Handle global keyboard shortcuts
    local is_ctrl_down = imgui.IsKeyDown(ctx, imgui.Key_LeftCtrl) or imgui.IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = imgui.IsKeyDown(ctx, imgui.Key_LeftSuper) or imgui.IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = imgui.IsKeyDown(ctx, imgui.Key_LeftShift) or imgui.IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)
    end

    -- Redo (Ctrl+Y on Windows, Cmd+Shift+Z on macOS)
    if (is_ctrl_down and not is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and imgui.IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
    end

    if imgui.IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
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

    if visible and script_running then
        local current_take, midi_editor = get_midi_context()

        if not midi_editor then
            imgui.Text(ctx, "Please open a MIDI editor.")
        else
            -- Clear cache if take changes
            if take ~= current_take then
                if #notes_cache > 0 then
                    notes_cache = {}
                end
            end

            take = current_take

            if not current_take then
                imgui.Text(ctx, "Could not get MIDI take.")
            else
                -- Count selected notes (with caching to avoid repeated calculation)
                if current_take then
                    -- Recalculate if cache is invalid or MIDI context changed
                    local current_note_count = count_selected_notes()
                    if selected_note_count ~= current_note_count or take ~= current_take then
                        selected_note_count = current_note_count
                        take = current_take
                    end
                else
                    selected_note_count = 0
                end

                if selected_note_count < 2 then
                    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.2, 0.2, 1.0)) -- Red
                    imgui.Text(ctx, "Select at least 2 notes to apply legato.")
                    reaper.ImGui_PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(selected_note_count) .. " selected notes")
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
                    reaper.Undo_BeginBlock()
                    drag_start_legato_amount = legato_amount  -- Store the value at drag start
                    drag_start_note_states = build_notes_cache()  -- Store the note states at drag start
                    notes_cache = drag_start_note_states  -- Use the drag start states as the reference
                end

                if value_changed then
                    -- Update legato_amount first
                    legato_amount = new_legato_amount

                    if selected_note_count >= 2 then
                        if is_active and #notes_cache > 0 then
                            -- Currently dragging, apply delta from initial state
                            apply_legato(notes_cache)
                        else
                            -- Not dragging, apply to current state (no delta)
                            local temp_cache = build_notes_cache()
                            apply_legato(temp_cache)
                        end
                    end
                end

                -- Clear the cache when the slider is not active to prevent memory buildup
                -- But only when not actively dragging (to preserve the cache during dragging)
                if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #notes_cache > 0 then
                    notes_cache = {}
                end

                if imgui.IsItemDeactivatedAfterEdit(ctx) then
                    -- End the undo block that was started on activation
                    reaper.Undo_EndBlock("", -1)
                end
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