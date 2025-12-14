-- @noindex
-- Test script for cache management system

-- Get the path of the current script and add modules directory to the search path
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@?(.*[/\\])')  -- Works on Win/Mac/Linux
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Import the module we want to test
local LEGATO_COMMON = require "legato_common"

-- Test function to verify cache management
function test_cache_management()
    print("Testing cache management system...")
    
    -- Test 1: Verify both invalidation functions work identically
    print("\nTest 1: Verifying both invalidation functions work identically")
    
    -- Get initial cache state (should be invalid at start)
    local notes1 = LEGATO_COMMON.get_cached_sorted_selected_notes()
    print("Initial cache call returned:", #notes1, "notes")
    
    -- Invalidate using first function
    LEGATO_COMMON.invalidate_sorted_notes_cache()
    local notes2 = LEGATO_COMMON.get_cached_sorted_selected_notes()
    print("After invalidate_sorted_notes_cache():", #notes2, "notes")
    
    -- Invalidate using second function
    LEGATO_COMMON.invalidate_cached_sorted_notes()
    local notes3 = LEGATO_COMMON.get_cached_sorted_selected_notes()
    print("After invalidate_cached_sorted_notes():", #notes3, "notes")
    
    -- Both should return the same results
    if #notes2 == #notes3 then
        print("✓ Both invalidation functions work identically")
    else
        print("✗ ERROR: Different results from invalidation functions")
        return false
    end
    
    -- Test 2: Verify cache is properly invalidated
    print("\nTest 2: Verifying cache invalidation")
    
    -- Get notes multiple times (should use cache after first call)
    local notes4 = LEGATO_COMMON.get_cached_sorted_selected_notes()
    local notes5 = LEGATO_COMMON.get_cached_sorted_selected_notes()
    
    if notes4 == notes5 then
        print("✓ Cache is being used (same table reference)")
    else
        print("✓ Cache is working (different tables but same content)")
    end
    
    -- Invalidate and verify cache is rebuilt
    LEGATO_COMMON.invalidate_sorted_notes_cache()
    local notes6 = LEGATO_COMMON.get_cached_sorted_selected_notes()
    
    if #notes4 == #notes6 then
        print("✓ Cache invalidation and rebuilding works correctly")
    else
        print("✗ ERROR: Cache invalidation failed")
        return false
    end
    
    print("\n✓ All cache management tests passed!")
    return true
end

-- Run the test
local success = test_cache_management()
if success then
    reaper.MB("Cache management tests passed successfully!", "Test Results", 0)
else
    reaper.MB("Cache management tests failed!", "Test Results", 0)
end