-- @noindex
-- Mock REAPER API for trigger editor drawing
local imgui_calls = {}

_G.imgui = {}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_Spacing = function(ctx) end,
    ImGui_CollapsingHeader = function(ctx, label)
        table.insert(imgui_calls, { type = "CollapsingHeader", label = label })
        return true -- return true to draw fields inside header
    end,
    ImGui_Text = function(ctx, text)
        table.insert(imgui_calls, { type = "Text", text = text })
    end,
    ImGui_SameLine = function(ctx, offset) end,
    ImGui_SetNextItemWidth = function(ctx, width) end,
    ImGui_BeginCombo = function(ctx, label, preview)
        table.insert(imgui_calls, { type = "BeginCombo", label = label, preview = preview })
        return false -- Do not open dropdown
    end,
    ImGui_EndCombo = function(ctx) end,
    ImGui_DragIntRange2 = function(ctx, label, current_min, current_max, speed, min_limit, max_limit, format_min, format_max)
        table.insert(imgui_calls, { type = "DragIntRange2", label = label })
        return false, current_min, current_max
    end
}

package.path = "modules/?.lua;" .. package.path
local ui_trigger_editor = require("modules.ui_trigger_editor")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_draw_trigger_editor()
    imgui_calls = {}
    local combo_preset_name = "Spitfire - Long"
    local presets_state = {
        presets = { ["Spitfire - Long"] = -20.0 },
        presets_show_in_grid = { ["Spitfire - Long"] = true },
        presets_ks_pitch = { ["Spitfire - Long"] = 24 },
        presets_note_vel_min = { ["Spitfire - Long"] = 1 },
        presets_note_vel_max = { ["Spitfire - Long"] = 127 }
    }
    local callbacks = {
        save_presets = function() end
    }

    ui_trigger_editor.draw_trigger_editor("fake_ctx", combo_preset_name, presets_state, callbacks)

    assert_eq(#imgui_calls, 7, "Number of draw trigger editor ImGui calls")
    assert_eq(imgui_calls[1].type, "CollapsingHeader", "First call is CollapsingHeader")
    assert_eq(imgui_calls[1].label, "MIDI Triggers: Spitfire - Long", "Collapsing header label")
    assert_eq(imgui_calls[2].type, "Text", "Second call is Text")
    assert_eq(imgui_calls[3].type, "BeginCombo", "Third call is BeginCombo for trigger mode")
    assert_eq(imgui_calls[3].preview, "Note + Velocity", "Trigger mode preview should be Note + Velocity")
end

print("Running ui_trigger_editor tests...")
test_draw_trigger_editor()
print("All ui_trigger_editor tests passed!")
