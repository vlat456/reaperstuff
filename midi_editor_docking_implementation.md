# MIDI Editor Docking and Conditional Window Display Implementation

This document explains how to dock a window to the top of the MIDI editor and show/hide it conditionally based on note selection in REAPER using Lua and ReaImGui.

## Overview

The implementation includes:
- Pinning a custom window to the top of the MIDI editor
- Showing the window only when exactly 2 notes are selected
- Proper focus handling and docking detection

## Complete Source Code

### 1. Main Application File (app.lua)

```lua
-- @noindex
-- @author Ben 'Talagan' Babut (adapted for general use)
-- @license MIT
-- @description MIDI Editor Window Docking Implementation

-- Import required modules
local ImGui = require "imgui"
local utils = require "utils"
local settings = require "settings"

local ctx = nil
local LTContext = {}

-- Load settings
LTContext.snap_piano_roll = settings.getSetting("PinToMidiEditor")

-----------------------
-- Conditional Display Logic
-----------------------

-- Returns true only if exactly 2 notes are selected
local function needsImGuiContext()
    return #LTContext.notes == 2
end

-----------------------
-- Main Application Logic
-----------------------

local function app()

    -- Check if MIDI editor is active
    local me = reaper.MIDIEditor_GetActive()
    if not me then 
        ctx = nil 
        return 
    end

    local take = reaper.MIDIEditor_GetTake(me)
    if not take then 
        ctx = nil 
        return 
    end

    LTContext.take = take

    -- Monitor for changes in MIDI take (hash changes when notes are modified/selected)
    local _, th = reaper.MIDI_GetHash(take, true)
    if th ~= LTContext.last_hash then
        LTContext.last_hash = th

        -- Collect only selected notes
        local notes = {}
        local note_idx = 0
        while true do
            -- Get note properties: (take, index) -> (valid, selected, muted, start_ppq, end_ppq, chan, pitch, vel)
            local valid, selected, _, startppq, endppq, _, _, _ = reaper.MIDI_GetNote(take, note_idx)

            if not valid then 
                break -- No more notes in take
            end

            -- Only store selected notes
            if selected then
                notes[#notes+1] = {
                    idx       = note_idx,  -- Note index in take
                    startppq  = startppq,  -- Start position in PPQ
                    endppq    = endppq     -- End position in PPQ
                }
            end
            
            note_idx = note_idx + 1
        end

        LTContext.notes = notes
    end

    -- Show/hide window based on note selection condition
    if needsImGuiContext() then

        -- Create ImGui context if it doesn't exist
        if not ctx then
            ctx = ImGui.CreateContext("CustomTool", ImGui.ConfigFlags_NoKeyboard)
        end

        -- Set window constraints (width: 200-2000px, height: 35px)
        ImGui.SetNextWindowSizeConstraints(ctx, 200, 35, 2000, 35)

        -- Set up window flags
        local flags = ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoTitleBar
        -- Detect if MIDI editor is docked in main window
        local dock = utils.GetHwndDock(me)

        if not dock then
            -- Special handling for floating MIDI editor windows
            -- Ensure this window stays on top of the MIDI editor
            local focused = reaper.JS_Window_GetFocus()
            if me == focused or reaper.JS_Window_IsChild(me, focused) then
                flags = flags | ImGui.WindowFlags_TopMost
            end
        end

        -- Handle pinned positioning (if enabled)
        if LTContext.snap_piano_roll then
            -- Get the piano roll area window handle (REAPER's piano roll child window)
            local piano_roll_hwnd = reaper.JS_Window_FindChildByID(me, 1001)
            
            -- Get bounds of the piano roll area
            local pr_bounds = utils.JS_Window_GetBounds(piano_roll_hwnd, true)
            
            -- Convert coordinates to ImGui's coordinate system
            local x, y = ImGui.PointConvertNative(ctx, pr_bounds.l, pr_bounds.t)
            
            -- Position our window at the top of the piano roll area
            ImGui.SetNextWindowSize(ctx, pr_bounds.w, 35)  -- Match width, set height to 35px
            ImGui.SetNextWindowPos(ctx, x, y-2)            -- Position just above piano roll (y-2px)
            flags = flags | ImGui.WindowFlags_NoResize     -- Prevent resizing when pinned
        end

        -- Begin ImGui window
        local visible, open = ImGui.Begin(ctx, "CustomTool", true, flags)
        
        if visible then
            -- Focus handling: Return focus to MIDI editor when our window gains focus
            -- This ensures keyboard shortcuts still work in the MIDI editor
            if ImGui.IsWindowFocused(ctx) then
                if not LTContext.focus_timer or ImGui.IsAnyMouseDown(ctx) then
                    -- Reset timer when there's activity in the window
                    LTContext.focus_timer = reaper.time_precise()
                end

                -- After 0.1 seconds of inactivity, return focus to MIDI editor
                if (reaper.time_precise() - LTContext.focus_timer > 0.1) then
                    reaper.JS_Window_SetFocus(reaper.MIDIEditor_GetActive())
                end
            else
                LTContext.focus_timer = nil
            end

            -- Optional: Add a pin button to toggle docking behavior
            local act_col = LTContext.snap_piano_roll
            
            if act_col then
                -- Highlight button when pinned
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0091fbff)
            end

            if ImGui.Button(ctx, "P") then  -- "P" for Pin
                LTContext.snap_piano_roll = not LTContext.snap_piano_roll
                settings.setSetting("PinToMidiEditor", LTContext.snap_piano_roll)
            end

            if act_col then 
                ImGui.PopStyleColor(ctx) 
            end

            if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then
                ImGui.SetTooltip(ctx, "Pin to the top of the MIDI Editor")
            end

            ImGui.SameLine(ctx)

            -- Add your custom controls here
            -- For example, a simple text label:
            ImGui.Text(ctx, "Active when 2 notes selected")

            ImGui.End(ctx)
        end

        -- Handle window close event
        if not open then
            LTContext.shouldQuit = true
        end

    else
        -- Hide/disable window when condition is not met
        ctx = nil
    end
end

-- Main application loop function
local function _app()
    app()

    if not LTContext.shouldQuit then
        -- Continue looping until shouldQuit is true
        reaper.defer(_app)
    end
end

-- Entry point function to start the application
local function run()
    -- Initialize context
    LTContext.notes = {}
    LTContext.shouldQuit = false
    
    -- Start the main loop
    reaper.defer(_app)
end

return {
    run = run
}
```

### 2. Utilities Module (utils.lua)

```lua
-- @noindex
-- @author Ben 'Talagan' Babut (adapted for general use)
-- @license MIT
-- @description Utility functions for MIDI editor window management

local OS = reaper.GetOS()
local is_windows = OS:match('Win')
local is_linux = OS:match('Other')

-- Helper function to get dock parent window
local function GetHwndDock(hwnd)
    local parent = nil
    local dock = nil

    parent = reaper.JS_Window_GetParent(hwnd)
    while parent do
        if reaper.JS_Window_GetTitle(parent) == "REAPER_dock" then
            dock = parent
            parent = nil
        else
            parent = reaper.JS_Window_GetParent(parent)
        end
    end
    return dock
end

-- Helper function to get window bounds
local function JS_Window_GetBounds(hwnd, full_window)
    local func = (full_window and reaper.JS_Window_GetRect or reaper.JS_Window_GetClientRect)

    local _, left, top, right, bottom = func(hwnd)

    local height = top - bottom

    -- Under Windows and Linux, vertical coordinates are flipped
    if is_windows or is_linux then
        height = bottom - top
    end

    return {
        hwnd = hwnd,
        l = left,
        t = top,
        r = right,
        b = bottom,
        w = (right - left),
        h = height
    }
end

return {
    GetHwndDock = GetHwndDock,
    JS_Window_GetBounds = JS_Window_GetBounds
}
```

### 3. Settings Module (settings.lua)

```lua
-- @noindex
-- @author Ben 'Talagan' Babut (adapted for general use)
-- @license MIT
-- @description Settings management for MIDI editor window docking

local ExtStateKey = "CustomTool"  -- Change this to your tool's name

local SettingDefs = {
    PinToMidiEditor = { type = "bool", default = true },  -- Default to pinned
};

-- Helper functions for converting between strings and values
local function unsafestr(str)
    if str == "" then
        return nil
    end
    return str
end

local function serializedStringToValue(str, spec)
    local val = unsafestr(str)

    if val == nil then
        val = spec.default
    else
        if spec.type == 'bool' then
            val = (val == "true")
        elseif spec.type == 'int' then
            val = tonumber(val)
            if val then val = math.floor(val) end
        elseif spec.type == 'double' then
            val = tonumber(val)
        elseif spec.type == 'string' then
            -- No conversion needed
        end
    end

    return val
end

local function valueToSerializedString(val, spec)
    local str = ''
    if spec.type == 'bool' then
        str = (val == true) and "true" or "false"
    elseif spec.type == 'int' then
        str = tostring(val)
    elseif spec.type == 'double' then
        str = tostring(val)
    elseif spec.type == "string" then
        -- No conversion needed
        str = val
    end
    return str
end

-- Get setting from REAPER's extension state
local function getSetting(setting)
    local spec = SettingDefs[setting]

    if spec == nil then
        error("Trying to get unknown setting " .. setting)
    end

    local str = reaper.GetExtState(ExtStateKey, setting)
    return serializedStringToValue(str, spec)
end

-- Set setting in REAPER's extension state
local function setSetting(setting, val)
    local spec = SettingDefs[setting]

    if spec == nil then
        error("Trying to set unknown setting " .. setting)
    end

    if val == nil then
        reaper.DeleteExtState(ExtStateKey, setting, true)
    else
        local str = valueToSerializedString(val, spec)
        reaper.SetExtState(ExtStateKey, setting, str, true)
    end
end

return {
    getSetting = getSetting,
    setSetting = setSetting,
}
```

### 4. Main Script Entry Point (main_script.lua)

```lua
-- @description Custom tool that docks to MIDI editor and shows conditionally
-- @version 1.0
-- @author Your Name
-- @provides
--   [main=midi_editor] .
--   [nomain] modules/**/*.lua
--   [nomain] ext/**/*.lua
--   [nomain] app.lua

-- Get script path
local PATH = debug.getinfo(1,"S").source:match[[^@?(.*[\/])[^\/]-$]]

package.path = PATH .. "/?.lua" .. ";" .. package.path

-- Check dependencies (requires ReaImGui and js_ReaScriptAPI)
if not reaper.APIExists("ImGui_CreateContext") or not reaper.APIExists("JS_ReaScriptAPI_Version") then
    reaper.MB("ReaImGui and js_ReaScriptAPI are required for this script.", "Missing Dependencies", 0)
    return
end

-- Import main application module
local App = require "app"

-- Tell the script to terminate if relaunched
if reaper.set_action_options ~= nil then
    reaper.set_action_options(1)
end

-- Run the application
App.run()
```

## Key Implementation Notes

1. **Conditional Display**: The window only shows when exactly 2 notes are selected (`#LTContext.notes == 2`)
2. **MIDI Editor Detection**: Uses `reaper.MIDIEditor_GetActive()` to get the active MIDI editor window
3. **Selection Monitoring**: Monitors the MIDI take hash to detect when note selections change
4. **Pinning**: Positions the window at the top of the MIDI editor piano roll area when pinned
5. **Focus Handling**: Properly returns focus to the MIDI editor so keyboard shortcuts continue to work
6. **Docking Detection**: Detects whether the MIDI editor is docked or floating to adjust behavior appropriately

## Usage Tips

- The window automatically hides when the selection criteria aren't met
- Users can toggle the "pin to MIDI editor" feature with the "P" button
- The implementation is efficient and runs continuously without impacting performance significantly
- Focus is automatically managed to ensure the MIDI editor remains responsive to keyboard input