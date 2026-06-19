-- @noindex
-- Mock REAPER API for keyboard shortcuts
local imgui_calls = {}

_G.imgui = {
    Key_LeftCtrl = 1,
    Key_RightCtrl = 2,
    Key_LeftSuper = 3,
    Key_RightSuper = 4,
    Key_LeftShift = 5,
    Key_RightShift = 6,
    Key_Z = 7,
    Key_Y = 8,
    Key_Escape = 9
}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

local key_states = {}
local pressed_keys = {}

_G.reaper = {
    ImGui_IsKeyDown = function(ctx, key)
        return key_states[key] == true
    end,
    ImGui_IsKeyPressed = function(ctx, key, repeat_flag)
        return pressed_keys[key] == true
    end
}

package.path = "modules/?.lua;" .. package.path
local ui_shortcuts = require("modules.ui_shortcuts")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_handle_shortcuts_undo()
    key_states = { [_G.imgui.Key_LeftCtrl] = true }
    pressed_keys = { [_G.imgui.Key_Z] = true }
    
    local undo_called = false
    local callbacks = {
        undo = function() undo_called = true end
    }

    ui_shortcuts.handle_shortcuts("fake_ctx", callbacks)

    assert_eq(undo_called, true, "Undo callback should be called when Ctrl+Z is pressed")
end

local function test_handle_shortcuts_escape()
    key_states = {}
    pressed_keys = { [_G.imgui.Key_Escape] = true }
    
    local exit_called = false
    local callbacks = {
        exit = function() exit_called = true end
    }

    ui_shortcuts.handle_shortcuts("fake_ctx", callbacks)

    assert_eq(exit_called, true, "Exit callback should be called when Escape is pressed")
end

print("Running ui_shortcuts tests...")
test_handle_shortcuts_undo()
test_handle_shortcuts_escape()
print("All ui_shortcuts tests passed!")
