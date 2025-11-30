--[[
# ReaScript Name: Voicing Converter
# Author: Vladimir K (Based on concept) & Gemini (Implementation)
# Version: 1.2.4
# Description:
# Analyzes the voicing of a selected chord (Close/Wide) and allows you
# to convert it to various wide voicings (Drop 2, Drop 4) or back to close.
# Includes a "Restore" button to revert the last conversion.
#
# Changelog:
# v1.2.4: Fixed error on startup by using the correct API function 
#         (MIDI_EnumSelNotes) to check for selected notes, as provided.
# v1.2.3: Corrected a typo in an API function name.
# v1.2.2: Fixed bug where buttons remained active after deselecting notes.
# v1.2.1: Fixed bug where restoring would fail if notes were deselected.
# v1.2.0: Added a "Restore Original Voicing" button.
# v1.1.2: Fixed "position out of bounds" error in Drop 4 logic.
# v1.1.1: Fixed ImGui assertion error on startup.
# v1.1.0: Added "Drop 4" voicing option.
# v1.0.0: Initial release.
#
# Instructions:
# 1. Run this script. A window will appear and stay on top.
# 2. In the MIDI Editor, select the notes of a chord.
# 3. Click "Analyze Voicing".
# 4. Click a "Convert..." button.
# 5. If you dislike the result, click "Restore Original Voicing".
--]]

local reaper = reaper

-- ## COMPATIBILITY FIX: Use require() for broader ReaImGui support ##
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load the ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

-- ## SCRIPT CONFIGURATION AND STATE ##
local SCRIPT_NAME = "Voicing Converter"
local ctx = imgui.CreateContext(SCRIPT_NAME)
local status_message = "Select notes and click 'Analyze Voicing'."
local analyzed_voicing_type = nil -- "Close", "Wide", or nil
local analyzed_chord_name = ""
local analyzed_note_count = 0
local saved_original_notes = nil -- To store notes before conversion

---------------------------------------------------------------------
-- ## MUSIC THEORY LOGIC (Chord/Scale Detection) ##
---------------------------------------------------------------------
-- Add current script directory to package path for shared modules
local script_path = debug.getinfo(1, "S").source
if script_path:sub(1,1) == "@" then
    script_path = script_path:sub(2)
end
local script_dir = script_path:match("(.*[\\|/])") or "./"
package.path = script_dir .. "?.lua;" .. package.path
-- Load shared music theory module
local MusicTheory = require('shared.music_theory')

---------------------------------------------------------------------
-- ## HELPER FUNCTION to get selected notes ##
---------------------------------------------------------------------
function get_selected_notes()
    local editor = reaper.MIDIEditor_GetActive()
    if not editor then status_message = "Error: Open a MIDI editor."; return nil end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take then status_message = "Error: Could not get MIDI take."; return nil end
    local notes = {}
    for i = 0, reaper.MIDI_CountEvts(take) - 1 do
        local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if selected then
            table.insert(notes, {
                index = i, pitch = pitch, vel = vel, muted = muted,
                start_ppq = startppq, end_ppq = endppq, chan = chan
            })
        end
    end
    if #notes == 0 then status_message = "Error: No notes selected."; return nil end
    table.sort(notes, function(a, b) return a.pitch < b.pitch end)
    return take, notes
end

---------------------------------------------------------------------
-- ## VOICING LOGIC ##
---------------------------------------------------------------------

function analyze_voicing_logic()
    saved_original_notes = nil -- Reset restore state on new analysis
    local _, notes = get_selected_notes()
    if not notes or #notes < 3 then
        status_message = "Select at least 3 notes to analyze voicing."
        analyzed_voicing_type = nil
        analyzed_note_count = 0
        return
    end
    
    analyzed_note_count = #notes
    local pitches = {}
    for _, n in ipairs(notes) do table.insert(pitches, n.pitch) end
    local _, _, full_chord_name, _ = MusicTheory:GetChord(pitches)
    analyzed_chord_name = full_chord_name
    local min_pitch, max_pitch = notes[1].pitch, notes[#notes].pitch
    if (max_pitch - min_pitch) < 12 then
        analyzed_voicing_type = "Close"
    else
        analyzed_voicing_type = "Wide"
    end
    status_message = "Analyzed: " .. analyzed_chord_name .. " (" .. analyzed_voicing_type .. " Voicing)"
end

function convert_voicing_logic(target_type, drop_method)
    local take, notes = get_selected_notes()
    if not notes then return end
    
    saved_original_notes = notes -- Save original notes before conversion
    
    local original_pitches = {}
    for _, n in ipairs(notes) do table.insert(original_pitches, n.pitch) end

    local _, _, _, pitch_classes = MusicTheory:GetChord(original_pitches)
    if not pitch_classes then
        status_message = "Could not identify chord for conversion."
        saved_original_notes = nil -- Clear save state on failure
        return
    end

    local new_pitches
    local bass_note = notes[1]
    local undo_message = ""

    if target_type == "Close" then
        new_pitches = {}
        local unplaced_pcs = {}
        for _, pc in ipairs(pitch_classes) do unplaced_pcs[pc] = true end
        table.insert(new_pitches, bass_note.pitch)
        unplaced_pcs[bass_note.pitch % 12] = nil
        local current_pitch = bass_note.pitch
        while next(unplaced_pcs) do
            current_pitch = current_pitch + 1
            if unplaced_pcs[current_pitch % 12] then
                table.insert(new_pitches, current_pitch)
                unplaced_pcs[current_pitch % 12] = nil
            end
        end
        undo_message = "Convert Voicing to Close"

    elseif target_type == "Wide" then
        local close_pitches = {}
        local temp_unplaced_pcs = {}
        for _, pc in ipairs(pitch_classes) do temp_unplaced_pcs[pc] = true end
        table.insert(close_pitches, bass_note.pitch)
        temp_unplaced_pcs[bass_note.pitch % 12] = nil
        local p = bass_note.pitch
        while next(temp_unplaced_pcs) do
            p = p + 1
            if temp_unplaced_pcs[p % 12] then
                table.insert(close_pitches, p)
                temp_unplaced_pcs[p % 12] = nil
            end
        end
        table.sort(close_pitches)

        if drop_method == "Drop 2" then
            if #close_pitches >= 3 then
                local note_to_drop = table.remove(close_pitches, #close_pitches - 1)
                table.insert(close_pitches, note_to_drop - 12)
            end
            new_pitches = close_pitches
            undo_message = "Convert Voicing to Wide (Drop 2)"
        elseif drop_method == "Drop 4" then
            if #close_pitches >= 4 then
                local original_len = #close_pitches
                local idx2_to_remove = original_len - 1
                local idx4_to_remove = original_len - 3
                local note2 = table.remove(close_pitches, idx2_to_remove)
                local note4 = table.remove(close_pitches, idx4_to_remove)
                table.insert(close_pitches, note2 - 12)
                table.insert(close_pitches, note4 - 12)
            end
            new_pitches = close_pitches
            undo_message = "Convert Voicing to Wide (Drop 4)"
        end
    end

    if not new_pitches then return end
    table.sort(new_pitches)

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    reaper.MIDI_DisableSort(take)

    table.sort(notes, function(a, b) return a.index > b.index end)
    for _, n in ipairs(notes) do reaper.MIDI_DeleteNote(take, n.index) end

    local start_ppq = bass_note.start_ppq
    local end_ppq = bass_note.end_ppq
    for i, p in ipairs(new_pitches) do
        local vel = (notes[i] and notes[i].vel) or bass_note.vel
        reaper.MIDI_InsertNote(take, true, false, start_ppq, end_ppq, 0, p, vel, false)
    end

    reaper.MIDI_Sort(take)
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(undo_message, 0)

    analyze_voicing_logic()
    saved_original_notes = notes
    status_message = "Success! " .. undo_message .. "."
end

function restore_voicing_logic()
    if not saved_original_notes then
        status_message = "No original voicing saved to restore."
        return
    end

    local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
    if not take then 
        status_message = "Error: Could not get active MIDI take to restore notes."
        return 
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    reaper.MIDI_DisableSort(take)

    local _, current_notes = get_selected_notes()
    if current_notes then
        table.sort(current_notes, function(a, b) return a.index > b.index end)
        for _, n in ipairs(current_notes) do reaper.MIDI_DeleteNote(take, n.index) end
    end

    for _, n in ipairs(saved_original_notes) do
         reaper.MIDI_InsertNote(take, true, n.muted, n.start_ppq, n.end_ppq, n.chan, n.pitch, n.vel, false)
    end

    reaper.MIDI_Sort(take)
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Restore Original Voicing", 0)

    analyze_voicing_logic()
    status_message = "Original voicing restored."
end


---------------------------------------------------------------------
-- ## GUI INITIALIZATION AND MAIN LOOP ##
---------------------------------------------------------------------
function loop()
    local flags = imgui.WindowFlags_TopMost | imgui.WindowFlags_NoResize | imgui.WindowFlags_NoCollapse | imgui.WindowFlags_AlwaysAutoResize
    local is_visible, is_open = imgui.Begin(ctx, SCRIPT_NAME, true, flags)

    if is_visible then
        -- Check for active selection at the start of every frame
        local editor = reaper.MIDIEditor_GetActive()
        if editor then
            local take = reaper.MIDIEditor_GetTake(editor)
            -- FIX: Use MIDI_EnumSelNotes to check if any notes are selected.
            -- If it returns -1 for the first note, nothing is selected.
            if take and reaper.MIDI_EnumSelNotes(take, -1) == -1 then
                -- If no notes are selected, reset the script's state
                if analyzed_voicing_type or saved_original_notes then
                    status_message = "Select notes and click 'Analyze Voicing'."
                end
                analyzed_voicing_type = nil
                analyzed_note_count = 0
                saved_original_notes = nil
            end
        end

        imgui.Text(ctx, "1. Select chord notes in the MIDI editor.")
        if imgui.Button(ctx, "2. Analyze Voicing", -1, 30) then
            analyze_voicing_logic()
        end
        imgui.Separator(ctx)

        imgui.Text(ctx, "3. Convert voicing:")

        local disable_drop2 = (not analyzed_voicing_type or analyzed_voicing_type ~= "Close")
        if disable_drop2 then imgui.BeginDisabled(ctx) end
        if imgui.Button(ctx, "Convert to Wide (Drop 2)", -1, 24) then
            convert_voicing_logic("Wide", "Drop 2")
        end
        if disable_drop2 then imgui.EndDisabled(ctx) end

        local disable_drop4 = (not analyzed_voicing_type or analyzed_voicing_type ~= "Close" or analyzed_note_count < 4)
        if disable_drop4 then imgui.BeginDisabled(ctx) end
        if imgui.Button(ctx, "Convert to Wide (Drop 4)", -1, 24) then
            convert_voicing_logic("Wide", "Drop 4")
        end
        if disable_drop4 then imgui.EndDisabled(ctx) end

        local disable_to_close = (not analyzed_voicing_type or analyzed_voicing_type ~= "Wide")
        if disable_to_close then imgui.BeginDisabled(ctx) end
        if imgui.Button(ctx, "Convert to Close Voicing", -1, 24) then
            convert_voicing_logic("Close")
        end
        if disable_to_close then imgui.EndDisabled(ctx) end
        
        imgui.Separator(ctx)
        
        local disable_restore = (not saved_original_notes)
        if disable_restore then imgui.BeginDisabled(ctx) end
        if imgui.Button(ctx, "Restore Original Voicing", -1, 24) then
            restore_voicing_logic()
        end
        if disable_restore then imgui.EndDisabled(ctx) end

        imgui.Separator(ctx)
        imgui.Text(ctx, "Status:")
        imgui.TextWrapped(ctx, status_message)
        imgui.End(ctx)
    end

    if is_open then reaper.defer(loop) end
end

reaper.defer(loop)
