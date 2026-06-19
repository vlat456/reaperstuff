-- @noindex
-- Mock REAPER API for modals drawing
local imgui_calls = {}

_G.imgui = {
    WindowFlags_AlwaysAutoResize = 1
}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_OpenPopup = function(ctx, name)
        table.insert(imgui_calls, { type = "OpenPopup", name = name })
    end,
    ImGui_BeginPopupModal = function(ctx, name, open, flags)
        table.insert(imgui_calls, { type = "BeginPopupModal", name = name })
        return false -- Do not go inside to avoid deep mocking for basic sanity test
    end,
    ImGui_Text = function(ctx, text) end,
    ImGui_Spacing = function(ctx) end,
    ImGui_Checkbox = function(ctx, label, val) return false, val end,
    ImGui_InputText = function(ctx, label, val) return false, val end,
    ImGui_Button = function(ctx, label) return false end,
    ImGui_SameLine = function(ctx) end,
    ImGui_EndPopup = function(ctx) end,
    ImGui_CloseCurrentPopup = function(ctx) end,
    ImGui_BeginCombo = function(ctx, label, preview) return false end,
    ImGui_EndCombo = function(ctx) end,
    ImGui_Selectable = function(ctx, label, selected) return false end,
    ImGui_SetItemDefaultFocus = function(ctx) end,
    ImGui_SetNextItemWidth = function(ctx, width) end
}

package.path = "modules/?.lua;" .. package.path
local ui_modals = require("modules.ui_modals")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_draw_modals()
    imgui_calls = {}
    local modal_state = {
        open_new = true,
        focus_new = true,
        new_lib = "TestLib",
        new_art = "TestArt",
        new_show_grid = true,
        open_rename = false,
        open_delete = false
    }
    local gui_state = {
        slider_value = -10.0
    }
    local presets_state = {
        presets = {},
        presets_show_in_grid = {},
        presets_ks_pitch = {},
        presets_note_vel_min = {},
        presets_note_vel_max = {},
        preset_keys = {},
        current_preset_name = "",
        combo_preset_name = ""
    }
    local callbacks = {
        save_presets = function() end,
        load_presets = function() return {}, {}, {}, {}, {}, {} end,
        save_preset_name_to_targets = function() end,
        split_preset_name = function() return "a", "b" end
    }

    ui_modals.draw_modals("fake_ctx", modal_state, gui_state, presets_state, callbacks)

    assert_eq(#imgui_calls, 4, "Number of popup calls")
    assert_eq(imgui_calls[1].type, "OpenPopup", "First call is OpenPopup")
    assert_eq(imgui_calls[1].name, "New Preset", "First is New Preset popup")
    assert_eq(modal_state.open_new, false, "open_new flag should be set to false after opening popup")
end

print("Running ui_modals tests...")
test_draw_modals()
print("All ui_modals tests passed!")
