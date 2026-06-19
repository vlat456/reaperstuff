-- @noindex
-- Mock REAPER API for info panel drawing
local imgui_calls = {}

_G.imgui = {}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_Spacing = function(ctx) end,
    ImGui_Separator = function(ctx) end,
    ImGui_Text = function(ctx, text)
        table.insert(imgui_calls, { type = "Text", text = text })
    end,
    ImGui_SameLine = function(ctx, x) end,
    ValidatePtr = function(ptr, type_str)
        if ptr == "fake_track" or ptr == "fake_take" or ptr == "fake_item" then
            return true
        end
        return false
    end,
    GetMediaTrackInfo_Value = function(track, field) return -0.01 end,
    GetTrackName = function(track) return true, "Violins" end,
    GetMediaItemTakeInfo_Value = function(take, field) return 0.05 end,
    GetTakeName = function(take) return "Staccato" end,
    GetMediaItemTake_Item = function(take) return "fake_item" end,
    GetSetMediaItemInfo_String = function(item, field, val, is_set)
        return true, "-10.0"
    end,
    GetActiveTake = function(item) return "fake_take" end
}

package.path = "modules/?.lua;" .. package.path
local ui_info_panel = require("modules.ui_info_panel")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_draw_info_panel()
    imgui_calls = {}
    local gui_state = {
        selected_targets = {}
    }
    local modes = {
        MODE_TRACK_OFFSET = 1,
        MODE_TAKE_OFFSET = 2,
        MODE_ITEM_POSITION = 3,
        MODE_MIDI_NOTES = 4
    }

    ui_info_panel.draw_info_panel(
        "fake_ctx",
        gui_state,
        0,
        1,
        "fake_track",
        "fake_take",
        false,
        nil,
        modes
    )

    -- It should print Track, Take, Item, MIDI Notes offsets
    assert_eq(#imgui_calls >= 4, true, "Should output details")
    assert_eq(imgui_calls[1].text:find("Track %(Violins%)") ~= nil, true, "Should display track name")
end

print("Running ui_info_panel tests...")
test_draw_info_panel()
print("All ui_info_panel tests passed!")
