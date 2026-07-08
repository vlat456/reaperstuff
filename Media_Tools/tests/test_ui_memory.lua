-- @noindex
-- Mock REAPER API for UI drawing
local imgui_calls = {}
local mock_hovered = false
local mock_double_clicked = false
local mock_button_clicked = {}
local last_drawn_selectable = nil

_G.imgui = {
    SelectableFlags_AllowDoubleClick = function() return 1 end
}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_BeginListBox = function(ctx, label, w, h)
        table.insert(imgui_calls, { type = "BeginListBox", label = label, w = w, h = h })
        return true
    end,
    ImGui_EndListBox = function(ctx)
        table.insert(imgui_calls, { type = "EndListBox" })
    end,
    ImGui_Selectable = function(ctx, label, is_selected, flags)
        table.insert(imgui_calls, { type = "Selectable", label = label, is_selected = is_selected })
        last_drawn_selectable = label
        return label == "2:  -20.0 ms", is_selected -- Simulate clicking the second item
    end,
    ImGui_IsItemHovered = function(ctx)
        if last_drawn_selectable == "2:  -20.0 ms" then
            return mock_hovered
        end
        return false
    end,
    ImGui_IsMouseDoubleClicked = function(ctx, button)
        return mock_double_clicked
    end,
    ImGui_Spacing = function(ctx) end,
    ImGui_SameLine = function(ctx) end,
    ImGui_BeginDisabled = function(ctx, disabled)
        table.insert(imgui_calls, { type = "BeginDisabled", disabled = disabled })
    end,
    ImGui_EndDisabled = function(ctx)
        table.insert(imgui_calls, { type = "EndDisabled" })
    end,
    ImGui_Button = function(ctx, label)
        table.insert(imgui_calls, { type = "Button", label = label })
        if mock_button_clicked[label] then
            return true -- Simulate click
        end
        return false
    end,
    ImGui_SetTooltip = function(ctx, text)
        table.insert(imgui_calls, { type = "SetTooltip", text = text })
    end,
    ImGui_SelectableFlags_AllowDoubleClick = function() return 1 end
}

package.path = "modules/?.lua;" .. package.path
local ui_memory = require("ui_memory")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_draw_memory_window_basic()
    imgui_calls = {}
    mock_hovered = false
    mock_double_clicked = false
    mock_button_clicked = {}
    
    local gui_state = {
        memory_stack = {10.5, -20.0, 300.2},
        selected_memory_index = -1
    }
    
    local adjust_val = nil
    local memory_changed = false
    
    local callbacks = {
        adjust_offset_to_value = function(val) adjust_val = val end,
        on_memory_changed = function() memory_changed = true end
    }
    
    ui_memory.draw_memory_window("fake_ctx", gui_state, callbacks)
    
    -- Verify listbox items were drawn
    local selectables_count = 0
    for _, call in ipairs(imgui_calls) do
        if call.type == "Selectable" then
            selectables_count = selectables_count + 1
        end
    end
    assert_eq(selectables_count, 3, "should draw 3 selectables")
    assert_eq(gui_state.selected_memory_index, 2, "second selectable click should update selected index to 2")
end

local function test_draw_memory_window_double_click()
    imgui_calls = {}
    mock_hovered = true
    mock_double_clicked = true
    mock_button_clicked = {}
    
    local gui_state = {
        memory_stack = {10.5, -20.0, 300.2},
        selected_memory_index = -1
    }
    
    local adjust_val = nil
    local callbacks = {
        adjust_offset_to_value = function(val) adjust_val = val end
    }
    
    ui_memory.draw_memory_window("fake_ctx", gui_state, callbacks)
    assert_eq(adjust_val, -20.0, "double click should apply the value -20.0 ms")
end

local function test_draw_memory_window_remove()
    imgui_calls = {}
    mock_hovered = false
    mock_double_clicked = false
    mock_button_clicked = { ["-"] = true }
    
    local gui_state = {
        memory_stack = {10.5, -20.0, 300.2},
        selected_memory_index = 2
    }
    
    local memory_changed = false
    local callbacks = {
        on_memory_changed = function() memory_changed = true end,
        adjust_offset_to_value = function(val) end
    }
    
    ui_memory.draw_memory_window("fake_ctx", gui_state, callbacks)
    assert_eq(#gui_state.memory_stack, 2, "stack should have 2 elements left")
    assert_eq(gui_state.memory_stack[2], 300.2, "second element should now be 300.2")
    assert_eq(memory_changed, true, "on_memory_changed should be called")
end

local function test_draw_memory_window_clear_all()
    imgui_calls = {}
    mock_hovered = false
    mock_double_clicked = false
    mock_button_clicked = { ["Clear All"] = true }
    
    local gui_state = {
        memory_stack = {10.5, -20.0, 300.2},
        selected_memory_index = 2
    }
    
    local memory_changed = false
    local callbacks = {
        on_memory_changed = function() memory_changed = true end,
        adjust_offset_to_value = function(val) end
    }
    
    ui_memory.draw_memory_window("fake_ctx", gui_state, callbacks)
    assert_eq(#gui_state.memory_stack, 0, "stack should be empty")
    assert_eq(gui_state.selected_memory_index, -1, "selected index should reset to -1")
    assert_eq(memory_changed, true, "on_memory_changed should be called")
end

print("Running ui_memory tests...")
test_draw_memory_window_basic()
test_draw_memory_window_double_click()
test_draw_memory_window_remove()
test_draw_memory_window_clear_all()
print("All ui_memory tests passed!")
