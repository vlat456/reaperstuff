-- @noindex
-- Mock REAPER API
local push_color_calls = 0
local push_var_calls = 0
local pop_color_calls = 0
local pop_var_calls = 0

_G.reaper = {
    ImGui_ColorConvertDouble4ToU32 = function(r, g, b, a)
        return 4278190080 -- dummy uint32
    end,
    ImGui_ColorConvertU32ToDouble4 = function(u)
        return 0.1, 0.2, 0.3, 1.0
    end,
    ImGui_PushStyleColor = function(ctx, col, val)
        push_color_calls = push_color_calls + 1
    end,
    ImGui_PushStyleVar = function(ctx, var, val1, val2)
        push_var_calls = push_var_calls + 1
    end,
    ImGui_PopStyleColor = function(ctx, count)
        pop_color_calls = pop_color_calls + (count or 1)
    end,
    ImGui_PopStyleVar = function(ctx, count)
        pop_var_calls = pop_var_calls + (count or 1)
    end
}

-- Mock imgui globals
_G.imgui = {
    Col_WindowBg = 1,
    Col_TitleBg = 2,
    Col_TitleBgActive = 3,
    Col_FrameBg = 4,
    Col_FrameBgHovered = 5,
    Col_FrameBgActive = 6,
    Col_SliderGrab = 7,
    Col_SliderGrabActive = 8,
    Col_Button = 9,
    Col_ButtonHovered = 10,
    Col_ButtonActive = 11,
    Col_Text = 12,
    Col_Header = 13,
    Col_HeaderHovered = 14,
    Col_HeaderActive = 15,
    Col_Border = 16,
    Col_CheckMark = 17,
    StyleVar_FrameRounding = 1,
    StyleVar_GrabRounding = 2,
    StyleVar_WindowRounding = 3,
    StyleVar_ItemSpacing = 4
}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

local theme_manager = require("modules.theme_manager")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

-- Test pack and unpack
local function test_pack_unpack()
    local val = theme_manager.theme_pack({0.1, 0.2, 0.3})
    assert_eq(val, 4278190080, "theme_pack returned mock value")

    local tbl = theme_manager.theme_unpack(4278190080)
    assert_eq(tbl[1], 0.1, "theme_unpack red")
    assert_eq(tbl[2], 0.2, "theme_unpack green")
    assert_eq(tbl[3], 0.3, "theme_unpack blue")
end

-- Test Push/Pop Theme
local function test_push_pop_theme()
    push_color_calls = 0
    push_var_calls = 0
    pop_color_calls = 0
    pop_var_calls = 0

    local mock_themes = {
        theme_bg          = {0.1, 0.1, 0.1},
        theme_accent      = {0.5, 0.5, 0.5},
        theme_frame_bg    = {0.2, 0.2, 0.2},
        theme_slider_grab = {0.5, 0.5, 0.5},
        theme_text        = {0.9, 0.9, 0.9},
        theme_check_mark  = {0.5, 0.5, 0.5},
        theme_danger      = {0.8, 0.2, 0.2},
        theme_positive    = {0.2, 0.8, 0.2}
    }

    local ctx = "fake_ctx"
    theme_manager.push_theme(ctx, mock_themes)
    assert_eq(push_color_calls, 17, "Pushed 17 colors")
    assert_eq(push_var_calls, 4, "Pushed 4 vars")

    theme_manager.pop_theme(ctx)
    assert_eq(pop_color_calls, 17, "Popped 17 colors")
    assert_eq(pop_var_calls, 4, "Popped 4 vars")
end

print("Running theme_manager tests...")
test_pack_unpack()
test_push_pop_theme()
print("All theme_manager tests passed!")
