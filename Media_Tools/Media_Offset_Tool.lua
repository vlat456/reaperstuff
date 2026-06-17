-- @description Media Offset Tool
-- @author drvlat
-- @version 1.0.9
-- @about
--   An ImGui-based utility for adjusting media offsets in REAPER.
--   Supports three target modes selected via radio buttons:
--     1) Take Start Offset
--     2) Track Playback Offset
--     3) Move Item Position
--   Works inside the MIDI Editor for the current MIDI item, or falls back to selected items/tracks in the Arrange view.
--   Features an absolute slider fixed at ±500ms, fine-tuning buttons, absolute offset reset, and clean status labels.
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
local script_name = "Media Offset Tool v1.0.9"
local ctx = reaper.ImGui_CreateContext(script_name)
local script_running = true

-- Fixed range ±500 ms
local FIXED_RANGE = 500.0

-- Target adjustment modes
local MODE_TAKE_OFFSET = 0    -- Mode A: Media Take Source Start Offset
local MODE_TRACK_OFFSET = 1   -- Mode B: Track Playback Offset
local MODE_ITEM_POSITION = 2  -- Mode C: Move Item Timeline Position

-- Unified GUI State
local gui_state = {
    selected_targets = {},
    slider_value = 0.0,
    adjust_mode = MODE_TRACK_OFFSET, -- Default to Mode B (Track Playback Offset)
    last_selection_state = "",
}

-- Check selection signature to detect change
local function get_selection_signature()
    local sig = {}
    table.insert(sig, "mode:" .. tostring(gui_state.adjust_mode))
    
    if gui_state.adjust_mode == MODE_TRACK_OFFSET then
        -- Mode B (Track Playback Offset)
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
            -- Fallback to active MIDI editor track
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
    else
        -- Mode A (Take Source Offset) & Mode C (Move Item Position)
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 0 then
            if num_items > 10000 then num_items = 10000 end -- Safety limit
            for i = 0, num_items - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                if item then
                    if gui_state.adjust_mode == MODE_TAKE_OFFSET then
                        local take = reaper.GetActiveTake(item)
                        if take then
                            table.insert(sig, tostring(take))
                        end
                    else
                        table.insert(sig, tostring(item))
                    end
                end
            end
        else
            -- Fallback to active MIDI editor take / item
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    if gui_state.adjust_mode == MODE_TAKE_OFFSET then
                        table.insert(sig, "editor:" .. tostring(take))
                    else
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            table.insert(sig, "editor:" .. tostring(item))
                        end
                    end
                end
            end
        end
    end
    
    return table.concat(sig, ";")
end

-- Populate selection info
local function update_targets_list()
    local current_sig = get_selection_signature()
    local selection_changed = current_sig ~= gui_state.last_selection_state
    
    if selection_changed then
        gui_state.last_selection_state = current_sig
        gui_state.selected_targets = {}
        
        if gui_state.adjust_mode == MODE_TRACK_OFFSET then
            -- Mode B: Track Playback Offset
            local num_tracks = reaper.CountSelectedTracks(0)
            if num_tracks > 0 then
                if num_tracks > 1000 then num_tracks = 1000 end
                for i = 0, num_tracks - 1 do
                    local track = reaper.GetSelectedTrack(0, i)
                    if track then
                        local _, name = reaper.GetTrackName(track)
                        name = name or "Unnamed Track"
                        local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                        table.insert(gui_state.selected_targets, {
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
                                table.insert(gui_state.selected_targets, {
                                    track = track,
                                    name = name .. " (MIDI Editor)",
                                    baseline_offset = cur_offset
                                })
                            end
                        end
                    end
                end
            end
            
            if #gui_state.selected_targets > 0 then
                gui_state.slider_value = gui_state.selected_targets[1].baseline_offset * 1000.0
            else
                gui_state.slider_value = 0.0
            end
            
        elseif gui_state.adjust_mode == MODE_TAKE_OFFSET then
            -- Mode A: Media Take Source Start Offset
            local num_items = reaper.CountSelectedMediaItems(0)
            if num_items > 0 then
                if num_items > 10000 then num_items = 10000 end
                for i = 0, num_items - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if item then
                        local take = reaper.GetActiveTake(item)
                        if take then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name,
                                baseline_offset = cur_offset
                            })
                        end
                    end
                end
            else
                -- Fallback to active MIDI editor take
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name .. " (MIDI Editor)",
                                baseline_offset = cur_offset
                            })
                        end
                    end
                end
            end
            
            if #gui_state.selected_targets > 0 then
                gui_state.slider_value = gui_state.selected_targets[1].baseline_offset * 1000.0
            else
                gui_state.slider_value = 0.0
            end
            
        elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
            -- Mode C: Move Item Timeline Position (Relative offset shift starting at 0)
            local num_items = reaper.CountSelectedMediaItems(0)
            if num_items > 0 then
                if num_items > 10000 then num_items = 10000 end
                for i = 0, num_items - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if item then
                        local take = reaper.GetActiveTake(item)
                        local name = take and reaper.GetTakeName(take) or "Empty Item"
                        local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        table.insert(gui_state.selected_targets, {
                            item = item,
                            name = name,
                            baseline_offset = cur_pos
                        })
                    end
                end
            else
                -- Fallback to active MIDI editor item
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                name = name .. " (MIDI Editor)",
                                baseline_offset = cur_pos
                            })
                        end
                    end
                end
            end
            
            gui_state.slider_value = 0.0
        end
    else
        -- Sync baselines and values if NOT dragging
        local is_slider_active = reaper.ImGui_IsAnyItemActive(ctx)
        if not is_slider_active and #gui_state.selected_targets > 0 then
            if gui_state.adjust_mode == MODE_TRACK_OFFSET then
                local first_info = gui_state.selected_targets[1]
                if reaper.ValidatePtr(first_info.track, "MediaTrack*") then
                    local actual_offset = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
                    gui_state.slider_value = actual_offset * 1000.0
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.track, "MediaTrack*") then
                        info.baseline_offset = reaper.GetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET")
                    end
                end
            elseif gui_state.adjust_mode == MODE_TAKE_OFFSET then
                local first_info = gui_state.selected_targets[1]
                if reaper.ValidatePtr(first_info.take, "MediaItem_Take*") then
                    local actual_offset = reaper.GetMediaItemTakeInfo_Value(first_info.take, "D_STARTOFFS")
                    gui_state.slider_value = actual_offset * 1000.0
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                        info.baseline_offset = reaper.GetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS")
                    end
                end
            elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.item, "MediaItem*") then
                        info.baseline_offset = reaper.GetMediaItemInfo_Value(info.item, "D_POSITION")
                    end
                end
                gui_state.slider_value = 0.0
            end
        end
    end
end

-- Apply current slider/adjustment value to all selected targets
local function apply_offset_to_targets(value)
    if gui_state.adjust_mode == MODE_TRACK_OFFSET then
        local target_sec = value / 1000.0
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.track, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(info.track, "I_PLAY_OFFSET_FLAG", 0)
                reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", target_sec)
            end
        end
    elseif gui_state.adjust_mode == MODE_TAKE_OFFSET then
        local target_sec = value / 1000.0
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", target_sec)
                reaper.UpdateItemInProject(info.item)
            end
        end
    elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
        local shift_sec = value / 1000.0
        for _, info in ipairs(gui_state.selected_targets) do
            if reaper.ValidatePtr(info.item, "MediaItem*") then
                reaper.SetMediaItemInfo_Value(info.item, "D_POSITION", info.baseline_offset + shift_sec)
                reaper.UpdateItemInProject(info.item)
            end
        end
    end
    reaper.UpdateArrange()
end

-- Helper to set absolute offset value (with undo registration)
local function adjust_offset_to_value(target_ms)
    if #gui_state.selected_targets == 0 then return end
    
    local undo_msg = ""
    if gui_state.adjust_mode == MODE_TRACK_OFFSET then
        undo_msg = string.format("Set track media playback offset to %.1f ms", target_ms)
    elseif gui_state.adjust_mode == MODE_TAKE_OFFSET then
        undo_msg = string.format("Set take source start offset to %.1f ms", target_ms)
    elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
        undo_msg = string.format("Move items timeline position by %.1f ms", target_ms)
    end
    
    reaper.Undo_BeginBlock2(0)
    apply_offset_to_targets(target_ms)
    reaper.Undo_EndBlock2(0, undo_msg, -1)
    
    if gui_state.adjust_mode == MODE_TRACK_OFFSET then
        reaper.TrackList_AdjustWindows(false)
    end
    
    if gui_state.adjust_mode == MODE_TRACK_OFFSET or gui_state.adjust_mode == MODE_TAKE_OFFSET then
        for _, info in ipairs(gui_state.selected_targets) do
            info.baseline_offset = target_ms / 1000.0
        end
        gui_state.slider_value = target_ms
    elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
        for _, info in ipairs(gui_state.selected_targets) do
            info.baseline_offset = info.baseline_offset + target_ms / 1000.0
        end
        gui_state.slider_value = 0.0
    end
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
    local num_targets = #gui_state.selected_targets
    
    if num_targets == 0 then
        reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.3, 0.3, 1.0))
        reaper.ImGui_Text(ctx, "No targets matching current selection mode.")
        reaper.ImGui_PopStyleColor(ctx)
        return
    end

    -- Target Mode Radio Buttons
    reaper.ImGui_Text(ctx, "Offset Mode:")
    local mode_changed = false
    
    local rb_a = reaper.ImGui_RadioButton(ctx, "Take Start Offset", gui_state.adjust_mode == MODE_TAKE_OFFSET)
    if rb_a then
        gui_state.adjust_mode = MODE_TAKE_OFFSET
        mode_changed = true
    end
    
    reaper.ImGui_SameLine(ctx)
    local rb_b = reaper.ImGui_RadioButton(ctx, "Track Playback Offset", gui_state.adjust_mode == MODE_TRACK_OFFSET)
    if rb_b then
        gui_state.adjust_mode = MODE_TRACK_OFFSET
        mode_changed = true
    end
    
    reaper.ImGui_SameLine(ctx)
    local rb_c = reaper.ImGui_RadioButton(ctx, "Move Item Position", gui_state.adjust_mode == MODE_ITEM_POSITION)
    if rb_c then
        gui_state.adjust_mode = MODE_ITEM_POSITION
        mode_changed = true
    end
    
    if mode_changed then
        gui_state.last_selection_state = ""
        update_targets_list()
        return
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Double-click / Drag slider for absolute offset (displaying current value)
    local slider_changed, new_slider_val = reaper.ImGui_SliderDouble(ctx, "Offset (ms)", gui_state.slider_value, -FIXED_RANGE, FIXED_RANGE, "%.1f ms")
    local is_slider_active = reaper.ImGui_IsItemActive(ctx)
    local is_slider_activated = reaper.ImGui_IsItemActivated(ctx)
    local is_slider_deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    if slider_changed then
        gui_state.slider_value = new_slider_val
        apply_offset_to_targets(new_slider_val)
        if gui_state.adjust_mode == MODE_TRACK_OFFSET then
            reaper.TrackList_AdjustWindows(false)
        end
    end

    if is_slider_deactivated then
        -- Restore baseline offsets temporarily
        if gui_state.adjust_mode == MODE_TRACK_OFFSET then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.track, "MediaTrack*") then
                    reaper.SetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET", info.baseline_offset)
                end
            end
        elseif gui_state.adjust_mode == MODE_TAKE_OFFSET then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                    reaper.SetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS", info.baseline_offset)
                    reaper.UpdateItemInProject(info.item)
                end
            end
        elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
            for _, info in ipairs(gui_state.selected_targets) do
                if reaper.ValidatePtr(info.item, "MediaItem*") then
                    reaper.SetMediaItemInfo_Value(info.item, "D_POSITION", info.baseline_offset)
                    reaper.UpdateItemInProject(info.item)
                end
            end
        end
        reaper.UpdateArrange()
        
        -- Commit final offsets in a single undo block
        local undo_msg = ""
        if gui_state.adjust_mode == MODE_TRACK_OFFSET then
            undo_msg = string.format("Set track media playback offset to %.1f ms", gui_state.slider_value)
        elseif gui_state.adjust_mode == MODE_TAKE_OFFSET then
            undo_msg = string.format("Set take source start offset to %.1f ms", gui_state.slider_value)
        elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
            undo_msg = string.format("Move items timeline position by %.1f ms", gui_state.slider_value)
        end
        
        reaper.Undo_BeginBlock2(0)
        apply_offset_to_targets(gui_state.slider_value)
        reaper.Undo_EndBlock2(0, undo_msg, -1)
        
        if gui_state.adjust_mode == MODE_TRACK_OFFSET then
            reaper.TrackList_AdjustWindows(false)
        end
        
        -- Update baselines
        if gui_state.adjust_mode == MODE_TRACK_OFFSET or gui_state.adjust_mode == MODE_TAKE_OFFSET then
            local final_val_sec = gui_state.slider_value / 1000.0
            for _, info in ipairs(gui_state.selected_targets) do
                info.baseline_offset = final_val_sec
            end
        elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
            local final_val_sec = gui_state.slider_value / 1000.0
            for _, info in ipairs(gui_state.selected_targets) do
                info.baseline_offset = info.baseline_offset + final_val_sec
            end
            gui_state.slider_value = 0.0
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

    -- Display details depending on current target mode
    local first_info = gui_state.selected_targets[1]
    if first_info then
        if gui_state.adjust_mode == MODE_TAKE_OFFSET then
            if reaper.ValidatePtr(first_info.take, "MediaItem_Take*") then
                local cur_offset_sec = reaper.GetMediaItemTakeInfo_Value(first_info.take, "D_STARTOFFS")
                local display_name = first_info.name
                if num_targets > 1 then
                    display_name = string.format("%s (+ %d others)", first_info.name, num_targets - 1)
                end
                reaper.ImGui_Text(ctx, "Take: " .. display_name)
                reaper.ImGui_Text(ctx, string.format("Current Take Start Offset: %.1f ms (%.4fs)", cur_offset_sec * 1000.0, cur_offset_sec))
            end
        elseif gui_state.adjust_mode == MODE_TRACK_OFFSET then
            if reaper.ValidatePtr(first_info.track, "MediaTrack*") then
                local cur_offset_sec = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
                local display_name = first_info.name
                if num_targets > 1 then
                    display_name = string.format("%s (+ %d others)", first_info.name, num_targets - 1)
                end
                reaper.ImGui_Text(ctx, "Track: " .. display_name)
                reaper.ImGui_Text(ctx, string.format("Current Track Playback Offset: %.1f ms (%.4fs)", cur_offset_sec * 1000.0, cur_offset_sec))
            end
        elseif gui_state.adjust_mode == MODE_ITEM_POSITION then
            if reaper.ValidatePtr(first_info.item, "MediaItem*") then
                local cur_pos_sec = reaper.GetMediaItemInfo_Value(first_info.item, "D_POSITION")
                local display_name = first_info.name
                if num_targets > 1 then
                    display_name = string.format("%s (+ %d others)", first_info.name, num_targets - 1)
                end
                reaper.ImGui_Text(ctx, "Item: " .. display_name)
                reaper.ImGui_Text(ctx, string.format("Current Item Timeline Position: %.3f s", cur_pos_sec))
            end
        end
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
        update_targets_list()
    end

    -- Redo (Ctrl+Y or Cmd+Shift+Z)
    if (is_ctrl_down and not is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Y, false)) or
       (is_super_down and is_shift_down and reaper.ImGui_IsKeyPressed(ctx, imgui.Key_Z, false)) then
        reaper.Undo_DoRedo2(0)
        update_targets_list()
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
    update_targets_list()

    -- Set size constraints
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 420, 200, 700, 300)

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
