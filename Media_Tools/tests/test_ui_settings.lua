-- @noindex
-- Mock REAPER API for UI drawing
local imgui_calls = {}

_G.imgui = {
    Col_Button = 2,
    Col_ButtonHovered = 3,
    Col_ButtonActive = 4
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
    ImGui_Spacing = function(ctx) end,
    ImGui_Separator = function(ctx) end,
    ImGui_SameLine = function(ctx) end,
    ImGui_PushStyleColor = function(ctx, col, val) end,
    ImGui_PopStyleColor = function(ctx, count) end,
    ImGui_ColorConvertDouble4ToU32 = function(r, g, b, a) return 12345 end,
    ImGui_ColorConvertU32ToDouble4 = function(u) return 1.0, 1.0, 1.0, 1.0 end,
    ImGui_Checkbox = function(ctx, label, val)
        table.insert(imgui_calls, { type = "Checkbox", label = label, val = val })
        return false, val
    end,
    ImGui_ColorEdit4 = function(ctx, label, val)
        table.insert(imgui_calls, { type = "ColorEdit4", label = label, val = val })
        return false, val
    end,
    ImGui_Button = function(ctx, label)
        table.insert(imgui_calls, { type = "Button", label = label })
        if label == "Save Settings" then
            return true -- Simulate click
        end
        return false
    end,
    ImGui_TextDisabled = function(ctx, text)
        table.insert(imgui_calls, { type = "TextDisabled", text = text })
    end
}

package.path = "modules/?.lua;" .. package.path
local ui_settings = require("modules.ui_settings")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_draw_settings_panel()
    imgui_calls = {}
    local gui_state = {
        write_keyswitches = true
    }
    local theme_state = {
        bg_u32 = 0xFFFFFFFF,
        accent_u32 = 0xFFFFFFFF,
        text_u32 = 0xFFFFFFFF,
        danger_u32 = 0xFFFFFFFF,
        positive_u32 = 0xFFFFFFFF,
        slider_grab_u32 = 0xFFFFFFFF,
        apply_btn_u32 = 0xFFFFFFFF,
        frame_bg_u32 = 0xFFFFFFFF,
        check_mark_u32 = 0xFFFFFFFF
    }
    local defaults = {
        bg = {0.1, 0.1, 0.1},
        accent = {0.8, 0.2, 0.8},
        text = {1.0, 1.0, 1.0},
        danger = {0.8, 0.1, 0.1},
        positive = {0.1, 0.8, 0.1},
        slider_grab = {0.8, 0.8, 0.8},
        apply_btn = {0.5, 0.5, 0.5},
        frame_bg = {0.2, 0.2, 0.2},
        check_mark = {0.9, 0.9, 0.9}
    }
    
    local save_settings_called = false
    local update_targets_called = false
    
    local callbacks = {
        save_settings = function() save_settings_called = true end,
        update_targets_list = function(val) update_targets_called = true end
    }

    local show_settings = ui_settings.draw_settings_panel(
        "fake_ctx",
        gui_state,
        theme_state,
        defaults,
        callbacks
    )

    assert_eq(show_settings, false, "Clicking Save Settings should hide settings panel")
    assert_eq(save_settings_called, true, "save_settings callback should be called upon clicking Save Settings")
    assert_eq(#imgui_calls > 5, true, "Should make several ImGui calls")
end

print("Running ui_settings tests...")
test_draw_settings_panel()
print("All ui_settings tests passed!")
