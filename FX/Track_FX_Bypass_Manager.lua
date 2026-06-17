-- @description Track FX Bypass Manager
-- @author drvlat
-- @version 1.0.2
-- @about
--   An ImGui-based utility for managing track FX (insert plugins).
--   Allows selecting multiple FX via checkboxes and toggling their bypass state simultaneously.
--   Preserves checked selections by FX GUID across tracks.
--   Double-click an FX row to float/unfloat its interface.
-- @provides
--   [main=main] Track_FX_Bypass_Manager.lua

local reaper = reaper

-- Check for ReaImGui
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox('ReaImGui is not installed or the version is too old. Please install/update it via ReaPack.', 'Error', 0)
  return
end

-- Load ReaImGui library
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local imgui = require('imgui')('0.9.3')

local script_name = "Track FX Bypass Manager"
local ctx = reaper.ImGui_CreateContext(script_name)
local checked_fx = {} -- Key: GUID string, Value: boolean
local managed_bypass_active = false
local bypassed_guids = {}
local current_track_guid = nil
local filter_text = ""

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

local function draw_gui()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    reaper.ImGui_Text(ctx, "Please select a track to view its FX chain.")
    managed_bypass_active = false
    bypassed_guids = {}
    current_track_guid = nil
    return
  end

  local track_guid = reaper.GetTrackGUID(track)
  if track_guid ~= current_track_guid then
    current_track_guid = track_guid
    managed_bypass_active = false
    bypassed_guids = {}
  end

  local _, track_name = reaper.GetTrackName(track)
  reaper.ImGui_Text(ctx, "Track: " .. (track_name or "Unnamed Track"))
  
  local num_fx = reaper.TrackFX_GetCount(track)
  
  reaper.ImGui_SameLine(ctx, reaper.ImGui_GetWindowWidth(ctx) - 130)
  reaper.ImGui_TextDisabled(ctx, string.format("(%d FX found)", num_fx))
  
  reaper.ImGui_Separator(ctx)

  if num_fx == 0 then
    reaper.ImGui_Text(ctx, "No FX found on this track.")
    return
  end

  -- Search filter box
  reaper.ImGui_SetNextItemWidth(ctx, -1)
  local changed, new_filter = reaper.ImGui_InputTextWithHint(ctx, "##filter", "Filter FX by name...", filter_text)
  if changed then
    filter_text = new_filter
  end

  -- Auto-reset managed_bypass_active if no managed FX are bypassed anymore
  if managed_bypass_active then
    local any_managed_bypassed = false
    for i = 0, num_fx - 1 do
      local guid = reaper.TrackFX_GetFXGUID(track, i)
      if guid and bypassed_guids[guid] then
        if not reaper.TrackFX_GetEnabled(track, i) then
          any_managed_bypassed = true
          break
        end
      end
    end
    if not any_managed_bypassed then
      managed_bypass_active = false
      bypassed_guids = {}
    end
  end

  -- Bulk check/uncheck buttons (disabled during bypass session)
  if managed_bypass_active then
    reaper.ImGui_BeginDisabled(ctx)
  end

  if reaper.ImGui_Button(ctx, "Check All") then
    local filter_lower = filter_text:lower()
    for i = 0, num_fx - 1 do
      local guid = reaper.TrackFX_GetFXGUID(track, i)
      if guid then
        local _, fx_name = reaper.TrackFX_GetFXName(track, i)
        fx_name = fx_name or "Initializing..."
        if filter_lower == "" or fx_name:lower():find(filter_lower, 1, true) then
          checked_fx[guid] = true
        end
      end
    end
  end
  
  reaper.ImGui_SameLine(ctx)
  
  if reaper.ImGui_Button(ctx, "Clear All") then
    local filter_lower = filter_text:lower()
    for i = 0, num_fx - 1 do
      local guid = reaper.TrackFX_GetFXGUID(track, i)
      if guid then
        local _, fx_name = reaper.TrackFX_GetFXName(track, i)
        fx_name = fx_name or "Initializing..."
        if filter_lower == "" or fx_name:lower():find(filter_lower, 1, true) then
          checked_fx[guid] = false
        end
      end
    end
  end

  if managed_bypass_active then
    reaper.ImGui_EndDisabled(ctx)
  end

  -- Checklist child window
  reaper.ImGui_BeginChild(ctx, "fx_list_child", 0, -45, reaper.ImGui_ChildFlags_Borders())
  
  local filter_lower = filter_text:lower()
  for i = 0, num_fx - 1 do
    local guid = reaper.TrackFX_GetFXGUID(track, i)
    if guid then
      local _, fx_name = reaper.TrackFX_GetFXName(track, i)
      fx_name = fx_name or "Initializing..."
      
      if filter_lower == "" or fx_name:lower():find(filter_lower, 1, true) then
        local is_enabled = reaper.TrackFX_GetEnabled(track, i)
        
        if checked_fx[guid] == nil then
          checked_fx[guid] = false
        end
        
        -- Checkbox (disabled during bypass session)
        if managed_bypass_active then
          reaper.ImGui_BeginDisabled(ctx)
        end
        local chg, new_val = reaper.ImGui_Checkbox(ctx, "##chk_" .. guid, checked_fx[guid])
        if chg then
          checked_fx[guid] = new_val
        end
        if managed_bypass_active then
          reaper.ImGui_EndDisabled(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        
        -- Build display name
        local is_open = reaper.TrackFX_GetOpen(track, i)
        local disp_name = string.format("%d: %s", i + 1, fx_name)
        if is_open then
          disp_name = disp_name .. " [Float]"
        end
        
        -- Push muted style color if bypassed
        local color_pushed = false
        if not is_enabled then
          reaper.ImGui_PushStyleColor(ctx, imgui.Col_Text, reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1.0))
          color_pushed = true
        end
        
        -- Allow double clicks on selectable
        local flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
        reaper.ImGui_Selectable(ctx, disp_name, false, flags)
        
        if color_pushed then
          reaper.ImGui_PopStyleColor(ctx)
        end
        
        -- Open/Close float window on double click (still enabled during bypass session)
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          if is_open then
            reaper.TrackFX_Show(track, i, 2) -- Hide float window
          else
            reaper.TrackFX_Show(track, i, 3) -- Show float window
          end
        end
      end
    end
  end
  
  reaper.ImGui_EndChild(ctx)

  reaper.ImGui_Separator(ctx)

  -- Count checked FX
  local checked_count = 0
  for i = 0, num_fx - 1 do
    local guid = reaper.TrackFX_GetFXGUID(track, i)
    if guid and checked_fx[guid] then
      checked_count = checked_count + 1
    end
  end

  -- Disable button if no FX checked
  if checked_count == 0 then
    reaper.ImGui_BeginDisabled(ctx)
  end

  -- Dynamic button label
  local button_label = "Bypass Checked FX"
  if managed_bypass_active then
    button_label = "Unbypass Checked FX"
  end

  local btn_clicked = reaper.ImGui_Button(ctx, button_label, -1, 0)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Toggles bypass for all checked plugins on this track.")
  end

  if btn_clicked then
    reaper.Undo_BeginBlock()
    if not managed_bypass_active then
      -- Perform Bypass
      for i = 0, num_fx - 1 do
        local guid = reaper.TrackFX_GetFXGUID(track, i)
        if guid and checked_fx[guid] then
          reaper.TrackFX_SetEnabled(track, i, false)
          bypassed_guids[guid] = true
        end
      end
      managed_bypass_active = true
    else
      -- Perform Unbypass
      for i = 0, num_fx - 1 do
        local guid = reaper.TrackFX_GetFXGUID(track, i)
        if guid and bypassed_guids[guid] then
          reaper.TrackFX_SetEnabled(track, i, true)
        end
      end
      bypassed_guids = {}
      managed_bypass_active = false
    end
    reaper.Undo_EndBlock(button_label, -1)
  end

  if checked_count == 0 then
    reaper.ImGui_EndDisabled(ctx)
  end
end

local function loop()
  push_theme()
  
  local window_flags = reaper.ImGui_WindowFlags_None()
  reaper.ImGui_SetNextWindowSize(ctx, 350, 450, reaper.ImGui_Cond_FirstUseEver())
  
  local visible, open = reaper.ImGui_Begin(ctx, 'Track FX Bypass Manager', true, window_flags)
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
