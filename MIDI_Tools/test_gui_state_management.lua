-- @noindex
-- Test script for simplified GUI state management system

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Import the modules we want to test
local LEGATO_COMMON = require "legato_common"

-- Test function to verify GUI state management
function test_gui_state_management()
    print("Testing GUI state management system...")
    
    -- Test 1: Verify unified state structure exists
    if gui_state then
        print("✓ GUI state structure initialized successfully")
    else
        print("✗ ERROR: GUI state structure not found")
        return false
    end
    
    -- Test 2: Verify state management functions exist
    local functions_to_test = {
        'invalidate_all_caches',
        'update_note_count',
        'update_overlay_count',
        'handle_take_change',
        'handle_selection_change'
    }
    
    for _, func_name in ipairs(functions_to_test) do
        if _G[func_name] then
            print("✓ Function " .. func_name .. "() exists")
        else
            print("✗ ERROR: Function " .. func_name .. "() not found")
            return false
        end
    end
    
    -- Test 3: Verify cache invalidation works
    print("\nTesting cache invalidation...")
    
    -- Get initial state
    local initial_note_count = LEGATO_COMMON.count_selected_notes()
    print("Initial note count:", initial_note_count)
    
    -- Test cache invalidation
    if gui_state.invalidate_all_caches then
        gui_state.invalidate_all_caches()
        print("✓ Cache invalidation function called")
    else
        print("✗ ERROR: Cache invalidation function not found")
        return false
    end
    
    -- Test 4: Verify note count update
    print("\nTesting note count update...")
    gui_state.needs_note_count_update = true
    local updated_count = gui_state.update_note_count()
    print("Updated note count:", updated_count)
    
    -- Test 5: Verify overlay count update
    print("\nTesting overlay count update...")
    gui_state.needs_overlay_count_update = true
    local updated_overlay = gui_state.update_overlay_count()
    print("Updated overlay count:", updated_overlay)
    
    -- Test 6: Verify state consistency
    print("\nTesting state consistency...")
    if gui_state.selected_note_count == updated_count and 
       gui_state.overlay_count == updated_overlay then
        print("✓ State consistency maintained")
    else
        print("✗ ERROR: State inconsistency detected")
        return false
    end
    
    print("\n✓ All GUI state management tests passed!")
    return true
end

-- Run the test
local success = test_gui_state_management()
if success then
    reaper.MB("GUI state management tests passed successfully!", "Test Results", 0)
else
    reaper.MB("GUI state management tests failed!", "Test Results", 0)
end