-- @noindex
-- Mock REAPER API for UI drawing
local imgui_calls = {}

_G.imgui = {
    Col_Text = 1
}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_RadioButton = function(ctx, label, active)
        table.insert(imgui_calls, { type = "RadioButton", label = label, active = active })
        return false
    end,
    ImGui_Text = function(ctx, text)
        table.insert(imgui_calls, { type = "Text", text = text })
    end,
    ImGui_BeginDisabled = function(ctx, disabled)
        table.insert(imgui_calls, { type = "BeginDisabled", disabled = disabled })
    end,
    ImGui_EndDisabled = function(ctx)
        table.insert(imgui_calls, { type = "EndDisabled" })
    end,
    ImGui_Spacing = function(ctx) end,
    ImGui_Separator = function(ctx) end,
    ImGui_SameLine = function(ctx) end,
    ImGui_PushStyleColor = function(ctx, col, val) end,
    ImGui_PopStyleColor = function(ctx, count) end,
    ImGui_ColorConvertDouble4ToU32 = function(r, g, b, a) return 0 end,
    ImGui_SliderDouble = function(ctx, label, val, min, max, format)
        table.insert(imgui_calls, { type = "SliderDouble", label = label, val = val })
        return false, val
    end,
    ImGui_InputDouble = function(ctx, label, val, step, step_fast, format)
        table.insert(imgui_calls, { type = "InputDouble", label = label, val = val })
        return false, val
    end,
    ImGui_Button = function(ctx, label)
        table.insert(imgui_calls, { type = "Button", label = label })
        return false
    end,
    ImGui_IsItemActive = function(ctx) return false end,
    ImGui_IsItemActivated = function(ctx) return false end,
    ImGui_IsItemDeactivatedAfterEdit = function(ctx) return false end,
    ImGui_SetNextItemWidth = function(ctx, width) end,
    ImGui_GetWindowWidth = function(ctx) return 500 end,
    ImGui_GetStyleVar = function(ctx, var) return 4, 4 end,
    ImGui_CalcTextSize = function(ctx, text) return 50, 15 end,
    ImGui_SetTooltip = function(ctx, text) end,
    ImGui_IsItemHovered = function(ctx) return false end,
    ImGui_TextDisabled = function(ctx, text)
        table.insert(imgui_calls, { type = "TextDisabled", text = text })
    end
}

_G.imgui.Col_Button = 2
_G.imgui.Col_ButtonHovered = 3
_G.imgui.Col_ButtonActive = 4
_G.imgui.StyleVar_FramePadding = 5
_G.imgui.StyleVar_ItemSpacing = 6

local ui_renderer = require("modules.ui_renderer")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

-- Test drawing mode selector
local function test_draw_mode_selector()
    imgui_calls = {}
    local gui_state = {
        adjust_mode = 0 -- MODE_TAKE_OFFSET
    }

    ui_renderer.draw_mode_selector("fake_ctx", gui_state, false)

    assert_eq(#imgui_calls, 6, "Number of ImGui calls")
    assert_eq(imgui_calls[1].type, "Text", "First call is Text")
    assert_eq(imgui_calls[2].type, "BeginDisabled", "Second call starts disabled block")
    assert_eq(imgui_calls[3].label, "Take Start Offset", "First radio button label")
    assert_eq(imgui_calls[3].active, true, "First radio button is active")
    assert_eq(imgui_calls[4].label, "Track Playback Offset", "Second radio button label")
    assert_eq(imgui_calls[4].active, false, "Second radio button is inactive")
end

-- Test drawing offset slider
local function test_draw_offset_slider()
    imgui_calls = {}
    local gui_state = {
        slider_value = 10.5
    }
    local callbacks = {
        apply_offset_to_targets = function(val) end,
        adjust_offset_to_value = function(val) end,
        get_effective_mode = function() return 0 end,
        on_input_changed = function(val) end
    }
    local theme_apply_btn = {1.0, 1.0, 1.0}
    local show_info = false
    local show_settings = false

    local new_show_info, new_show_settings, is_slider_deactivated = ui_renderer.draw_offset_slider("fake_ctx", gui_state, 500.0, callbacks, theme_apply_btn, show_info, show_settings)

    assert_eq(#imgui_calls, 6, "ImGui calls count")
    assert_eq(imgui_calls[1].type, "Text", "First is text label")
    assert_eq(imgui_calls[2].type, "SliderDouble", "Second is SliderDouble")
    assert_eq(imgui_calls[2].val, 10.5, "SliderDouble initial value")
    assert_eq(imgui_calls[3].type, "InputDouble", "Third is InputDouble")
    assert_eq(imgui_calls[3].val, 10.5, "InputDouble initial value")
    assert_eq(imgui_calls[4].label, "Apply", "Fourth is Apply button")
    assert_eq(imgui_calls[5].label, "Information", "Fifth is Information button")
    assert_eq(imgui_calls[6].label, "Settings", "Sixth is Settings button")
end

-- Test drawing preset board
local function test_draw_preset_board()
    imgui_calls = {}
    local gui_state = {
        selected_library = "Spitfire"
    }
    local preset_keys = {"Spitfire - Long", "Spitfire - Short", "Orchestral - Legato"}
    local presets_show_in_grid = {
        ["Spitfire - Long"] = true,
        ["Spitfire - Short"] = true,
        ["Orchestral - Legato"] = true
    }
    local presets = {
        ["Spitfire - Long"] = -20.0,
        ["Spitfire - Short"] = -10.0,
        ["Orchestral - Legato"] = -15.0
    }
    local theme_accent = {1.0, 0.0, 1.0}
    local theme_bg = {0.1, 0.1, 0.1}
    local current_preset_name = "Spitfire - Long"
    local adjusted_preset = nil
    local adjusted_offset = nil
    
    local function adjust_offset_cb(offset, name)
        adjusted_offset = offset
        adjusted_preset = name
    end

    local new_preset_name = ui_renderer.draw_preset_board(
        "fake_ctx",
        gui_state,
        preset_keys,
        presets_show_in_grid,
        presets,
        theme_accent,
        theme_bg,
        current_preset_name,
        adjust_offset_cb
    )

    -- It should have run through rendering logic
    assert_eq(gui_state.selected_library, "Spitfire", "Selected library starts as Spitfire")
end

print("Running ui_renderer tests...")
test_draw_mode_selector()
test_draw_offset_slider()
test_draw_preset_board()

-- Test 3-tier preset board (Library - Instrument - Articulation)
local function test_draw_preset_board_3tier()
    imgui_calls = {}
    local gui_state = { selected_library = "Spitfire" }
    local preset_keys = {
        "Spitfire - Strings - Long",
        "Spitfire - Strings - Short",
        "Spitfire - Brass - Staccato",
        "Orchestral - Legato",          -- legacy 2-part
    }
    local presets_show_in_grid = {
        ["Spitfire - Strings - Long"]  = true,
        ["Spitfire - Strings - Short"] = true,
        ["Spitfire - Brass - Staccato"] = true,
        ["Orchestral - Legato"]        = true,
    }
    local presets = {
        ["Spitfire - Strings - Long"]  = -20.0,
        ["Spitfire - Strings - Short"] = -10.0,
        ["Spitfire - Brass - Staccato"] = -5.0,
        ["Orchestral - Legato"]        = -15.0,
    }
    local theme_accent = {1.0, 0.0, 1.0}
    local theme_bg    = {0.1, 0.1, 0.1}

    -- Should not crash
    local new_preset_name = ui_renderer.draw_preset_board(
        "fake_ctx", gui_state, preset_keys, presets_show_in_grid,
        presets, theme_accent, theme_bg, "", function() end
    )

    -- Library buttons: Orchestral, Spitfire
    local lib_btns = {}
    for _, c in ipairs(imgui_calls) do
        if c.type == "Button" and c.label:match("##lib_") then
            table.insert(lib_btns, c.label)
        end
    end
    assert_eq(#lib_btns, 2, "Two library buttons rendered")

    -- Instrument headers (TextDisabled): "Brass:" and "Strings:" for Spitfire
    local instr_headers = {}
    for _, c in ipairs(imgui_calls) do
        if c.type == "TextDisabled" and c.text:match(":$") and not c.text:match("Libraries") then
            table.insert(instr_headers, c.text)
        end
    end
    assert_eq(#instr_headers, 2, "Two instrument headers (Brass: and Strings:)")
end

test_draw_preset_board_3tier()
print("All ui_renderer tests passed!")

