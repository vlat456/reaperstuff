-- @noindex
-- Simple test to verify GUI state management is working

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Import the module we want to test
local LEGATO_COMMON = require "legato_common"

-- Test function to verify GUI state management
function test_simple_gui_state()
    print("Testing simple GUI state management...")
    
    -- Test 1: Verify gui_state object exists
    if gui_state then
        print("✓ GUI state structure exists")
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
    
    -- Test 3: Verify basic state operations
    print("\nTesting basic state operations...")
    
    -- Test note count update
    gui_state.needs_note_count_update = true
    local updated_count = gui_state.update_note_count()
    print("Note count update test:", updated_count)
    
    -- Test overlay count update
    gui_state.needs_overlay_count_update = true
    local updated_overlay = gui_state.update_overlay_count()
    print("Overlay count update test:", updated_overlay)
    
    -- Test cache invalidation
    print("\nTesting cache invalidation...")
    if gui_state.invalidate_all_caches then
        gui_state.invalidate_all_caches()
        print("✓ Cache invalidation function called")
    else
        print("✗ ERROR: Cache invalidation function not found")
        return false
    end
    
    print("\n✓ All simple GUI state management tests passed!")
    return true
end

-- Run the test
local success = test_simple_gui_state()
if success then
    reaper.MB("Simple GUI state management tests passed!", "Test Results", 0)
else
    reaper.MB("Simple GUI state management tests failed!", "Test Results", 0)
end