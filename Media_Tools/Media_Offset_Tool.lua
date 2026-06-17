-- @description Media Offset Tool
-- @author drvlat
-- @version 1.0.6
-- @about
--   An ImGui-based utility for adjusting the track Media Playback Offset (positive and negative) of selected tracks.
--   Works inside the MIDI Editor for the current MIDI item's track, or falls back to selected tracks in the Arrange view.
--   Features an absolute slider fixed at ±500ms that always displays the current offset value, fine-tuning buttons, absolute offset reset, and two simple status labels.
-- @provides
--   [main=main,midi_editor,midi_inlineeditor,midi_eventlisteditor] Media_Offset_Tool.lua

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
local script_name = "Media Offset Tool v1.0.6"
local ctx = reaper.ImGui_CreateContext(script_name)
local script_running = true

-- Fixed range ±500 ms
local FIXED_RANGE = 500.0

-- Unified GUI State
local gui_state = {
    selected_tracks = {},
    slider_value = 0.0,
    last_selection_state = "",
}

-- Check selection signature to detect change
local function get_selection_signature()
    local sig = {}
    
    local num_tracks = reaper.CountSelectedTracks(0)
    if num_tracks > 0 then
        if num_tracks > 1000 then num_tracks = 1000 end -- Safety limit
        for i = 0, num_tracks - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            if track then
                table.insert(sig, tostring(track))
            end
        end
    else
        -- Fallback to active MIDI editor track only if no tracks are selected in Arrange
        local midi_editor = reaper.MIDIEditor_GetActive()
        if midi_editor then
            local take = reaper.MIDIEditor_GetTake(midi_editor)
            if take then
                local item = reaper.GetMediaItemTake_Item(take)
                if item then
                    local track = reaper.GetMediaItem_Track(item)
                    if track then
                        table.insert(sig, "editor:" .. tostring(track))
                    end
                end
            end
        end
    end
    
    return table.concat(sig, ";")
end

-- Populate selection info
local function update_tracks_list()
    local current_sig = get_selection_signature()
    local selection_changed = current_sig ~= gui_state.last_selection_state
    
    if selection_changed then
        gui_state.last_selection_state = current_sig
        gui_state.selected_tracks = {}
        
        local num_tracks = reaper.CountSelectedTracks(0)
        if num_tracks > 0 then
            -- Prioritize selected tracks in Arrange view
            if num_tracks > 1000 then num_tracks = 1000 end
            for i = 0, num_tracks - 1 do
                local track = reaper.GetSelectedTrack(0, i)
                if track then
                    local _, name = reaper.GetTrackName(track)
                    name = name or "Unnamed Track"
                    local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                    table.insert(gui_state.selected_tracks, {
                        track = track,
                        name = name,
                        baseline_offset = cur_offset
                    })
                end
            end
        else
            -- Fallback to active MIDI editor track
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    local item = reaper.GetMediaItemTake_Item(take)
                    if item then
                        local track = reaper.GetMediaItem_Track(item)
                        if track then
                            local _, name = reaper.GetTrackName(track)
                            name = name or "Unnamed Track"
                            local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                            table.insert(gui_state.selected_tracks, {
                                track = track,
                                name = name .. " (MIDI Editor)",
                                baseline_offset = cur_offset
                            })
                        end
                    end
                end
            end
        end

        -- Set slider value to first track's offset on selection change
        if #gui_state.selected_tracks > 0 then
            gui_state.slider_value = gui_state.selected_tracks[1].baseline_offset * 1000.0
        else
            gui_state.slider_value = 0.0
        end
    else
        -- Sync baseline offsets and slider value with REAPER if we are NOT dragging the slider
        local is_slider_active = reaper.ImGui_IsAnyItemActive(ctx)
        if not is_slider_active and #gui_state.selected_tracks > 0 then
            local first_info = gui_state.selected_tracks[1]
            if reaper.ValidatePtr(first_info.track, "MediaTrack*") then
                local actual_offset = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
                gui_state.slider_value = actual_offset * 1000.0
            end

            for _, info in ipairs(gui_state.selected_tracks) do
                if reaper.ValidatePtr(info.track, "MediaTrack*") then
                    info.baseline_offset = reaper.GetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET")
                end
            end
        end
    end
end

-- Helper to set absolute offset value (with undo registration)
local function adjust_offset_to_value(target_ms)
    if #gui_state.selected_tracks == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    local target_sec = target_ms / 1000.0
    for _, info in ipairs(gui_state.selected_tracks) do
        if reaper.ValidatePtr(info.track, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(info.track, "I_PLAY_OFFSET_FLAG", 0) -- Enable (uncheck bypass) & set to seconds
            reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", target_sec)
            info.baseline_offset = target_sec
        end
    end
    reaper.Undo_EndBlock2(0, string.format("Set track media playback offset to %.1f ms", target_ms), -1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
    
    gui_state.slider_value = target_ms
end

-- Helper to apply delta relative to current value
local function adjust_offset_by_delta(delta_ms)
    local target_ms = gui_state.slider_value + delta_ms
    adjust_offset_to_value(target_ms)
end

-- Helper to reset offsets to 0
local function reset_offsets_to_zero()
    adjust_offset_to_value(0.0)
end

-- Push Theme Custom Colors & Styles
local function push_theme()
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_WindowBg,             reaper.ImGui_ColorConvertDouble4ToU32(0.08, 0.08, 0.1, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_TitleBg,              reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.15, 0.25, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_TitleBgActive,        reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.2, 0.4, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBg,              reaper.ImGui_ColorConvertDouble4ToU32(0.15, 0.15, 0.18, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBgHovered,       reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.25, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_FrameBgActive,        reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.35, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_SliderGrab,           reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.35, 0.8, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_SliderGrabActive,     reaper.ImGui_ColorConvertDouble4ToU32(0.6, 0.45, 0.9, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button,               reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.25, 0.45, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered,        reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.35, 0.6, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonActive,         reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.45, 0.75, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text,                 reaper.ImGui_ColorConvertDouble4ToU32(0.92, 0.92, 0.95, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Header,               reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.18, 0.3, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_HeaderHovered,        reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.25, 0.45, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_HeaderActive,         reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.35, 0.6, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Border,               reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.3, 0.5))

    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_FrameRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_GrabRounding, 6.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_WindowRounding, 8.0)
    reaper.ImGui_PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, 8.0, 6.0)
end

-- Pop Theme Styles & Colors
local function pop_theme()
    reaper.ImGui_PopStyleColor(ctx, 16)
    reaper.ImGui_PopStyleVar(ctx, 4)
end

-- Render the main controls
local function render_ui()
    local num_tracks = #gui_state.selected_tracks
    
    if num_tracks == 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.3, 0.3, 1.0))
        reaper.ImGui_Text(ctx, "No selected tracks.")
        reaper.ImGui_PopStyleColor(ctx)
        return
    end

    -- Double-click / Drag slider for absolute offset (displaying current value)
    local slider_changed, new_slider_val = reaper.ImGui_SliderDouble(ctx, "Offset (ms)", gui_state.slider_value, -FIXED_RANGE, FIXED_RANGE, "%.1f ms")
    local is_slider_active = reaper.ImGui_IsItemActive(ctx)
    local is_slider_activated = reaper.ImGui_IsItemActivated(ctx)
    local is_slider_deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    if slider_changed then
        gui_state.slider_value = new_slider_val
        
        -- Apply real-time visual offset change (no undo block during drag)
        local offset_sec = new_slider_val / 1000.0
        for _, info in ipairs(gui_state.selected_tracks) do
            if reaper.ValidatePtr(info.track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(info.track, "I_PLAY_OFFSET_FLAG", 0) -- Enable offset
                reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", offset_sec)
            end
        end
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
    end

    if is_slider_deactivated then
        -- User finished editing, commit the changes to a single undo point
        -- Restore baseline offsets temporarily
        for _, info in ipairs(gui_state.selected_tracks) do
            if reaper.ValidatePtr(info.track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", info.baseline_offset)
            end
        end
        
        -- Begin proper undo block
        reaper.Undo_BeginBlock2(0)
        
        -- Apply final offsets
        local final_offset_sec = gui_state.slider_value / 1000.0
        for _, info in ipairs(gui_state.selected_tracks) do
            if reaper.ValidatePtr(info.track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(info.track, "I_PLAY_OFFSET_FLAG", 0) -- Enable offset
                reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", final_offset_sec)
            end
        end
        
        -- End undo block
        reaper.Undo_EndBlock2(0, string.format("Set track media playback offset to %.1f ms", gui_state.slider_value), -1)
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
        
        -- Update baselines
        for _, info in ipairs(gui_state.selected_tracks) do
            info.baseline_offset = final_offset_sec
        end
    end

    reaper.ImGui_Spacing(ctx)

    -- Fine-tuning buttons row
    local win_width = reaper.ImGui_GetWindowWidth(ctx)
    local button_width = math.floor((win_width - 40) / 7)
    if button_width < 45 then button_width = 45 end
    local button_height = 24

    if reaper.ImGui_Button(ctx, "-10ms", button_width, button_height) then
        adjust_offset_by_delta(-10.0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "-1ms", button_width, button_height) then
        adjust_offset_by_delta(-1.0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "-0.1ms", button_width, button_height) then
        adjust_offset_by_delta(-0.1)
    end
    reaper.ImGui_SameLine(ctx)
    
    -- Highlight Reset 0 button
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_Button, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.25, 0.25, 1.0))
    reaper.ImGui_PushStyleColor(ctx, imgui.Col_ButtonHovered, reaper.ImGui_ColorConvertDouble4ToU32(0.65, 0.3, 0.3, 1.0))
    if reaper.ImGui_Button(ctx, "Reset 0", button_width, button_height) then
        reset_offsets_to_zero()
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+0.1ms", button_width, button_height) then
        adjust_offset_by_delta(0.1)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+1ms", button_width, button_height) then
        adjust_offset_by_delta(1.0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+10ms", button_width, button_height) then
        adjust_offset_by_delta(10.0)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Display selected tracks details simply as labels
    local first_info = gui_state.selected_tracks[1]
    if first_info and reaper.ValidatePtr(first_info.track, "MediaTrack*") then
        local cur_offset_sec = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
        local track_display_name = first_info.name
        if num_tracks > 1 then
            track_display_name = string.format("%s (+ %d others)", first_info.name, num_tracks - 1)
        end
        reaper.ImGui_Text(ctx, "Track: " .. track_display_name)
        reaper.ImGui_Text(ctx, string.format("Current Playback Offset: %.1f ms", cur_offset_sec * 1000.0))
    end
end

-- Key shortcuts
local function handle_keyboard_shortcuts()
    local is_ctrl_down = reaper.ImGui_IsKeyDown(ctx, imgui.Key_LeftCtrl) or reaper.ImGui_IsKeyDown(ctx, imgui.Key_RightCtrl)
    local is_super_down = reaper.ImGui_IsKeyDown(ctx, imgui.Key_LeftSuper) or reaper.ImGui_IsKeyDown(ctx, imgui.Key_RightSuper)
    local is_shift_down = reaper.ImGui_IsKeyDown(ctx, imgui.Key_LeftShift) or reaper.ImGui_IsKeyDown(ctx, imgui.Key_RightShift)

    -- Undo (Ctrl+Z or Cmd+Z)
    if (is_ctrl_down or is_super_down) and not is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Z, false) then
        reaper.Undo_DoUndo2(0)
        update_tracks_list()
    end

    -- Redo (Ctrl+Y or Cmd+Shift+Z)
    if (is_ctrl_down and not is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
        update_tracks_list()
    end

    -- Escape key handling
    if reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Escape, false) then
        script_running = false
    end
end

-- Main Loop
local function loop()
    if not script_running then
        return
    end

    -- Selection management
    update_tracks_list()

    -- Set size constraints
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 400, 160, 600, 250)

    -- Set window style/colors
    push_theme()

    local window_flags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost
    local visible, open = reaper.ImGui_Begin(ctx, script_name, true, window_flags)
    
    if not open then
        script_running = false
    end

    -- Bring window to front if it loses focus to keep it topmost
    if visible and script_running then
        local is_window_focused = reaper.ImGui_IsWindowFocused(ctx, imgui.FocusedFlags_RootAndChildWindows)
        if not is_window_focused then
            reaper.ImGui_SetWindowFocus(ctx)
        end
    end

    if visible and script_running then
        handle_keyboard_shortcuts()
        render_ui()
    end

    reaper.ImGui_End(ctx)
    pop_theme()

    if script_running then
        reaper.defer(loop)
    end
end

-- Init
reaper.defer(loop)
