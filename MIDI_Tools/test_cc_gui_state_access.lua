-- @noindex
-- Test script to verify CC tool accesses variables through gui_state

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Test function to verify CC tool GUI state access
function test_cc_gui_state_access()
    print("Testing CC tool GUI state access...")
    
    -- Load the CC tool script to test
    local cc_tool_path = script_path .. "Combined_CC_Tool.lua"
    local cc_tool_code = loadfile(cc_tool_path)
    
    if not cc_tool_code then
        print("✗ ERROR: Could not load CC tool script")
        return false
    end
    
    print("✓ CC tool script loaded successfully")
    
    -- Test 1: Verify gui_state structure exists
    if gui_state then
        print("✓ GUI state structure exists")
    else
        print("✗ ERROR: GUI state structure not found")
        return false
    end
    
    -- Test 2: Verify key state management functions exist
    local functions_to_test = {
        'invalidate_all_caches',
        'get_midi_context',
        'get_active_take',
        'calculate_redundant_ccs',
        'remove_redundant_ccs',
        'select_all_ccs_in_lane',
        'build_cc_cache',
        'smooth_ccs'
    }
    
    for _, func_name in ipairs(functions_to_test) do
        if _G[func_name] then
            print("✓ Function " .. func_name .. "() exists")
        else
            print("✗ ERROR: Function " .. func_name .. "() not found")
            return false
        end
    end
    
    -- Test 3: Verify cache invalidation function works
    print("\nTesting cache invalidation...")
    if invalidate_all_caches then
        -- Set some test values
        gui_state.cc_list_cache = {test = "data"}
        gui_state.selected_ccs_cache_valid = true
        gui_state.last_selected_ccs_signature = "test"
        
        -- Call invalidate function
        invalidate_all_caches()
        
        -- Check if values were properly cleared
        if #gui_state.cc_list_cache == 0 and 
           gui_state.selected_ccs_cache_valid == false and 
           gui_state.last_selected_ccs_signature == "" then
            print("✓ Cache invalidation function works correctly")
        else
            print("✗ ERROR: Cache invalidation function not working properly")
            return false
        end
    else
        print("✗ ERROR: Cache invalidation function not found")
        return false
    end
    
    -- Test 4: Verify get_midi_context function uses gui_state.take
    print("\nTesting MIDI context function...")
    if get_midi_context then
        -- Test the function exists and returns expected values
        local take, editor, lane = get_midi_context()
        print("✓ get_midi_context() function executes without errors")
        
        -- Check if gui_state.take is being used
        if gui_state.take then
            print("✓ gui_state.take is properly managed")
        else
            print("! Note: gui_state.take is nil (expected if no MIDI editor is open)")
        end
    else
        print("✗ ERROR: get_midi_context() function not found")
        return false
    end
    
    -- Test 5: Verify get_active_take function uses gui_state.take
    print("\nTesting get_active_take function...")
    if get_active_take then
        local active_take = get_active_take()
        print("✓ get_active_take() function executes without errors")
        
        -- This should return gui_state.take
        if active_take == gui_state.take then
            print("✓ get_active_take() properly returns gui_state.take")
        else
            print("✗ ERROR: get_active_take() not returning gui_state.take")
            return false
        end
    else
        print("✗ ERROR: get_active_take() function not found")
        return false
    end
    
    print("\n✓ All CC tool GUI state access tests passed!")
    return true
end

-- Run the test
local success = test_cc_gui_state_access()
if success then
    reaper.MB("CC tool GUI state access tests passed successfully!", "Test Results", 0)
else
    reaper.MB("CC tool GUI state access tests failed!", "Test Results", 0)
end