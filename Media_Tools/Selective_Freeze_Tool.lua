-- @description Selective Freeze Tool
-- @author drvlat
-- @version 1.0.0
-- @about
--   An ImGui-based utility to freeze/render selected media items on a track.
--   Allows selectively choosing which plugins in the track FX chain are baked into the render.
--   Allows selecting between Offline (Full-speed) or Online (Real-time) render modes.
--   Allows choosing between Mono or Stereo channel format.
-- @provides
--   [main=main] Selective_Freeze_Tool.lua

local reaper = reaper

-- Check for SWS Extension
if not reaper.SNM_GetIntConfigVar or not reaper.SNM_SetIntConfigVar then
  reaper.ShowMessageBox('SWS Extension is not installed or too old. Please install it via ReaPack or from sws-extension.org.', 'Error', 0)
  return
end

-- Check for ReaImGui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

local script_name = "Selective Freeze Tool"
local ctx = reaper.ImGui_CreateContext(script_name)

-- State variables
local checked_fx = {} -- Key: GUID string, Value: boolean
local current_track_guid = nil
local last_fx_count = -1

local gui_state = {
    render_mode = "offline", -- "offline" or "online"
}

-- Push Theme Custom Colors & Styles (matching Track FX Bypass Manager)
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

-- Helper to get selected media items on a specific track
local function get_selected_items_on_track(track)
    local items = {}
    local count = reaper.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item and reaper.GetMediaItem_Track(item) == track then
            table.insert(items, item)
        end
    end
    return items
end

-- Core Render/Freeze Function
local function freeze_selected_items(track, selected_items, mode)
    local num_fx = reaper.TrackFX_GetCount(track)
    
    -- 1. Save original global workrender preference (speed)
    local original_workrender = reaper.SNM_GetIntConfigVar("workrender", 0)
    
    -- 2. Modify bit 8 based on desired mode (online/offline)
    local target_workrender = original_workrender
    if mode == "online" then
        target_workrender = original_workrender | 8   -- Enable realtime render limit
    else
        target_workrender = original_workrender & ~8  -- Disable realtime render limit (offline)
    end
    reaper.SNM_SetIntConfigVar("workrender", target_workrender)

    -- 3. Save original item selection in the project to target only items on this track
    local orig_selection = {}
    local total_selected = reaper.CountSelectedMediaItems(0)
    for i = 0, total_selected - 1 do
        table.insert(orig_selection, reaper.GetSelectedMediaItem(0, i))
    end

    -- 4. Select ONLY the selected items on our active track
    reaper.SelectAllMediaItems(0, false)
    for _, item in ipairs(selected_items) do
        reaper.SetMediaItemSelected(item, true)
    end
    reaper.UpdateArrange()

    -- 5. Open Undo block & save original FX bypass states
    reaper.Undo_BeginBlock()
    
    local orig_enabled = {}
    for i = 0, num_fx - 1 do
        local guid = reaper.TrackFX_GetFXGUID(track, i)
        if guid then
            local active = reaper.TrackFX_GetEnabled(track, i)
            orig_enabled[guid] = active
            
            -- If user unchecked the plugin, bypass it BEFORE rendering so it's not baked
            if not checked_fx[guid] then
                reaper.TrackFX_SetEnabled(track, i, false)
            end
        end
    end

    -- 6. Trigger rendering action: Render items to new take (mono/stereo based on original track format)
    local action_id = 40209 -- Default to Stereo: Item: Apply track/take FX to items (stereo output)
    if #selected_items > 0 then
        local first_item = selected_items[1]
        local active_take = reaper.GetActiveTake(first_item)
        if active_take and not reaper.TakeIsMIDI(active_take) then
            local source = reaper.GetMediaItemTake_Source(active_take)
            if source then
                local num_channels = reaper.GetMediaSourceNumChannels(source)
                if num_channels == 1 then
                    action_id = 40361 -- Mono: Item: Apply track/take FX to items (mono output)
                end
            end
        end
    end
    
    reaper.Main_OnCommand(action_id, 0)

    -- 7. Restore track FX states to pre-freeze state
    for i = 0, num_fx - 1 do
        local guid = reaper.TrackFX_GetFXGUID(track, i)
        if guid and orig_enabled[guid] ~= nil then
            reaper.TrackFX_SetEnabled(track, i, orig_enabled[guid])
        end
    end

    reaper.Undo_EndBlock("Freeze selected items with custom FX", -1)

    -- 8. Restore original item selection in project
    reaper.SelectAllMediaItems(0, false)
    for _, item in ipairs(orig_selection) do
        reaper.SetMediaItemSelected(item, true)
    end
    reaper.UpdateArrange()

    -- 9. Restore original workrender preference
    reaper.SNM_SetIntConfigVar("workrender", original_workrender)
end

-- GUI Drawing Logic
local function draw_gui()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then
        reaper.ImGui_Text(ctx, "Please select a track to view its FX chain.")
        current_track_guid = nil
        last_fx_count = -1
        return
    end

    local track_guid = reaper.GetTrackGUID(track)
    local num_fx = reaper.TrackFX_GetCount(track)

    -- Detect track change or FX count change to reset checked_fx state (initially checked)
    if track_guid ~= current_track_guid or num_fx ~= last_fx_count then
        current_track_guid = track_guid
        last_fx_count = num_fx
        checked_fx = {}
        for i = 0, num_fx - 1 do
            local guid = reaper.TrackFX_GetFXGUID(track, i)
            if guid then
                checked_fx[guid] = true
            end
        end
    end

    local _, track_name = reaper.GetTrackName(track)
    reaper.ImGui_Text(ctx, "Track: " .. (track_name or "Unnamed Track"))
    reaper.ImGui_SameLine(ctx, reaper.ImGui_GetWindowWidth(ctx) - 130)
    reaper.ImGui_TextDisabled(ctx, string.format("(%d FX found)", num_fx))
    
    reaper.ImGui_Separator(ctx)

    if num_fx == 0 then
        reaper.ImGui_Text(ctx, "No FX found on this track.")
        return
    end

    -- Bulk Check / Clear buttons
    if reaper.ImGui_Button(ctx, "Check All") then
        for i = 0, num_fx - 1 do
            local guid = reaper.TrackFX_GetFXGUID(track, i)
            if guid then
                checked_fx[guid] = true
            end
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_Button(ctx, "Clear All") then
        for i = 0, num_fx - 1 do
            local guid = reaper.TrackFX_GetFXGUID(track, i)
            if guid then
                checked_fx[guid] = false
            end
        end
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Re-enable All") then
        reaper.Undo_BeginBlock()
        for i = 0, num_fx - 1 do
            reaper.TrackFX_SetEnabled(track, i, true)
        end
        reaper.Undo_EndBlock("Re-enable all FX on track", -1)
    end

    -- FX checklist child window
    reaper.ImGui_BeginChild(ctx, "fx_list_child", 0, -110, reaper.ImGui_ChildFlags_Borders())
    for i = 0, num_fx - 1 do
        local guid = reaper.TrackFX_GetFXGUID(track, i)
        if guid then
            local _, fx_name = reaper.TrackFX_GetFXName(track, i)
            fx_name = fx_name or "Initializing..."
            local is_enabled = reaper.TrackFX_GetEnabled(track, i)
            
            if checked_fx[guid] == nil then
                checked_fx[guid] = true
            end
            
            -- Checkbox
            local chg, new_val = reaper.ImGui_Checkbox(ctx, "##chk_" .. guid, checked_fx[guid])
            if chg then
                checked_fx[guid] = new_val
            end
            
            reaper.ImGui_SameLine(ctx)
            
            -- Display plugin name
            local disp_name = string.format("%d: %s", i + 1, fx_name)
            local color_pushed = false
            if not is_enabled then
                reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1.0))
                color_pushed = true
            end
            
            reaper.ImGui_Selectable(ctx, disp_name, false)
            
            if color_pushed then
                reaper.ImGui_PopStyleColor(ctx)
            end
        end
    end
    reaper.ImGui_EndChild(ctx)

    reaper.ImGui_Separator(ctx)

    -- Render options section
    reaper.ImGui_Text(ctx, "Render Speed:")
    reaper.ImGui_SameLine(ctx, 110)
    local rb_off = reaper.ImGui_RadioButton(ctx, "Offline", gui_state.render_mode == "offline")
    if rb_off then gui_state.render_mode = "offline" end
    reaper.ImGui_SameLine(ctx)
    local rb_on = reaper.ImGui_RadioButton(ctx, "Online (1x)", gui_state.render_mode == "online")
    if rb_on then gui_state.render_mode = "online" end



    -- Check item selections on selected track
    local selected_items = get_selected_items_on_track(track)
    local has_selection = #selected_items > 0
    
    if not has_selection then
        reaper.ImGui_BeginDisabled(ctx)
    end

    local button_label = "Freeze Items"
    if has_selection then
        button_label = string.format("Freeze %d Selected Items", #selected_items)
    else
        button_label = "Freeze (No Items Selected)"
    end

    if reaper.ImGui_Button(ctx, button_label, -1, 0) then
        freeze_selected_items(track, selected_items, gui_state.render_mode)
    end

    if not has_selection then
        reaper.ImGui_EndDisabled(ctx)
    end
end

-- Defer Loop
local function loop()
    push_theme()
    
    local window_flags = reaper.ImGui_WindowFlags_None()
    reaper.ImGui_SetNextWindowSize(ctx, 380, 380, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Selective Freeze Tool', true, window_flags)
    if visible then
        draw_gui()
    end
    reaper.ImGui_End(ctx)
    
    pop_theme()
    
    if open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)
