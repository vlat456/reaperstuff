-- Test script to verify the optimized sorting is in the Legato_Tool.lua file
-- This will verify that the optimized functions are properly integrated

-- Read the file content
local file = io.open("/Users/vladimir/remred/MIDI_Tools/Legato_Tool.lua", "r")
if not file then
    print("ERROR: Could not open Legato_Tool.lua file")
    return
end
local content = file:read("*all")
file:close()

-- Check for key optimized functions and variables
local checks = {
    {"sorted_notes_cache", "Main cache variable from optimized version"},
    {"sorted_notes_cache_valid", "Cache validation flag from optimized version"},
    {"last_cache_take", "Cache take tracking from optimized version"},
    {"last_cache_note_count", "Cache note count tracking from optimized version"},
    {"invalidate_sorted_notes_cache", "New cache invalidation function"},
    {"get_cached_sorted_selected_notes", "Optimized function to get cached sorted notes"},
    {"get_selected_notes_optimized", "Optimized function to get selected notes"},
    {"-- Optimized cached sorted notes system from optimized_sorting.lua", "Comment indicating source"},
}

local all_passed = true

print("Testing optimized sorting integration in Legato_Tool.lua:")
print("-------------------------------------------------------")

for _, check in ipairs(checks) do
    local pattern = check[1]
    local description = check[2]
    
    if string.find(content, pattern) then
        print("✓ Found: " .. pattern .. " (" .. description .. ")")
    else
        print("✗ Missing: " .. pattern .. " (" .. description .. ")")
        all_passed = false
    end
end

print("-------------------------------------------------------")
if all_passed then
    print("SUCCESS: All optimized functions have been integrated!")
else
    print("FAILURE: Some optimized functions are missing.")
end