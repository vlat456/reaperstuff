-- @noindex
-- Mock REAPER API for presets dropdown drawing
local imgui_calls = {}

_G.imgui = {}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_Spacing = function(ctx) end,
    ImGui_Text = function(ctx, text)
        table.insert(imgui_calls, { type = "Text", text = text })
    end,
    ImGui_SameLine = function(ctx) end,
    ImGui_SetNextItemWidth = function(ctx, width) end,
    ImGui_BeginCombo = function(ctx, label, preview)
        table.insert(imgui_calls, { type = "BeginCombo", label = label, preview = preview })
        return false
    end,
    ImGui_EndCombo = function(ctx) end,
    ImGui_BeginDisabled = function(ctx) end,
    ImGui_EndDisabled = function(ctx) end,
    ImGui_Button = function(ctx, label)
        table.insert(imgui_calls, { type = "Button", label = label })
        return false
    end,
    ImGui_IsItemHovered = function(ctx) return false end,
    ImGui_SetTooltip = function(ctx, text) end
}

package.path = "modules/?.lua;" .. package.path
local ui_presets_dropdown = require("modules.ui_presets_dropdown")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_draw_presets_dropdown()
    imgui_calls = {}
    local gui_state = {
        slider_value = -20.0,
        selected_library = ""
    }
    local presets_state = {
        presets = { ["Spitfire - Long"] = -20.0 },
        preset_keys = { "Spitfire - Long" },
        presets_show_in_grid = { ["Spitfire - Long"] = true },
        combo_preset_name = "Spitfire - Long"
    }
    local modal_state = {
        new_preset_lib_input = "",
        new_preset_art_input = "",
        new_preset_show_in_grid = true,
        open_new_preset_modal = false,
        open_new_preset_focus = false,
        open_rename_preset_modal = false,
        open_rename_preset_focus = false,
        open_delete_preset_modal = false
    }
    local callbacks = {
        save_presets = function() end,
        load_presets = function() return {}, {}, {}, {}, {}, {} end,
        adjust_offset_to_value = function() end,
        split_preset_name = function() return "Spitfire", "Long" end
    }

    ui_presets_dropdown.draw_presets_dropdown("fake_ctx", gui_state, presets_state, modal_state, callbacks)

    assert_eq(#imgui_calls, 6, "ImGui calls count")
    assert_eq(imgui_calls[1].type, "Text", "First call is Text")
    assert_eq(imgui_calls[2].type, "BeginCombo", "Second call is BeginCombo")
    assert_eq(imgui_calls[3].label, "Save", "Third call is Save button")
    assert_eq(imgui_calls[4].label, "Save As", "Fourth call is Save As button")
    assert_eq(imgui_calls[5].label, "Rn", "Fifth call is Rename button")
    assert_eq(imgui_calls[6].label, "Dl", "Sixth call is Delete button")
end

print("Running ui_presets_dropdown tests...")
test_draw_presets_dropdown()
print("All ui_presets_dropdown tests passed!")
