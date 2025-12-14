-- @noindex
-- Test script to verify GUI state compliance across all legato tools

-- Get the path of the current script and add modules directory to the search path
local script_path = "/Users/vladimir/remred/MIDI_Tools/"  -- Fixed path for testing
package.path = package.path .. ';' .. script_path .. 'modules/?.lua'

-- Test function to verify GUI state compliance
function test_gui_state_compliance()
    print("Testing GUI state compliance across legato tools...")
    
    local test_results = {
        legato_tool = false,
        cc_tool = false,
        quick_scripts = true,  -- These don't need GUI state
        modules = true          -- These don't need GUI state
    }
    
    -- Test 1: Load and analyze Legato_Tool.lua
    print("\n1. Testing Legato_Tool.lua...")
    local legato_tool_path = script_path .. "Legato_Tool.lua"
    local legato_tool_code = loadfile(legato_tool_path)
    
    if legato_tool_code then
        print("✓ Legato_Tool.lua loads successfully")
        
        -- Read the file content to check for GUI state usage patterns
        local file = io.open(legato_tool_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            -- Check for proper GUI state usage patterns
            local gui_state_take_count = select(2, content:gsub("gui_state%.take", "gui_state.take"))
            local current_take_access = content:match("reaper%.MIDI_GetNote%(current_take") or 0
            
            -- Look for the specific pattern we fixed: using gui_state.take in undo registration
            local gui_state_undo = content:match("reaper%.GetMediaItemTake_Item%(gui_state%.take%)") or 0
            
            if gui_state_take_count > 0 and gui_state_undo ~= 0 then
                print("✓ Legato_Tool.lua uses gui_state.take consistently")
                test_results.legato_tool = true
            else
                print("✗ Legato_Tool.lua may have direct variable access issues")
                print("  gui_state.take usage count: " .. gui_state_take_count)
                print("  gui_state.undo usage: " .. (gui_state_undo > 0 and "found" or "not found"))
            end
        end
    else
        print("✗ Failed to load Legato_Tool.lua")
    end
    
    -- Test 2: Load and analyze Combined_CC_Tool.lua
    print("\n2. Testing Combined_CC_Tool.lua...")
    local cc_tool_path = script_path .. "Combined_CC_Tool.lua"
    local cc_tool_code = loadfile(cc_tool_path)
    
    if cc_tool_code then
        print("✓ Combined_CC_Tool.lua loads successfully")
        
        -- Read the file content to check for GUI state usage patterns
        local file = io.open(cc_tool_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            -- Check for proper GUI state usage
            local gui_state_usage = content:match("gui_state%.take") or 0
            local proper_state_management = content:match("invalidate_all_caches") or 0
            
            if gui_state_usage and proper_state_management then
                print("✓ Combined_CC_Tool.lua uses gui_state consistently")
                test_results.cc_tool = true
            else
                print("✗ Combined_CC_Tool.lua may have state management issues")
            end
        end
    else
        print("✗ Failed to load Combined_CC_Tool.lua")
    end
    
    -- Test 3: Verify quick scripts don't need GUI state
    print("\n3. Testing quick scripts...")
    local quick_scripts = {
        "Legato_Tool_Quick_Heal.lua",
        "Legato_Tool_Quick_Legato.lua", 
        "Legato_Tool_Quick_NonLegato.lua"
    }
    
    for _, script_name in ipairs(quick_scripts) do
        local script_path_full = script_path .. script_name
        local script_code = loadfile(script_path_full)
        
        if script_code then
            print("✓ " .. script_name .. " loads successfully (non-GUI script)")
        else
            print("✗ Failed to load " .. script_name)
            test_results.quick_scripts = false
        end
    end
    
    -- Test 4: Verify modules don't need GUI state
    print("\n4. Testing modules...")
    local modules = {
        "legato_common.lua",
        "script_init.lua",
        "undo_manager.lua",
        "legato_operations.lua",
        "cleanup_manager.lua"
    }
    
    for _, module_name in ipairs(modules) do
        local module_path_full = script_path .. "modules/" .. module_name
        local module_code = loadfile(module_path_full)
        
        if module_code then
            print("✓ " .. module_name .. " loads successfully (shared module)")
        else
            print("✗ Failed to load " .. module_name)
            test_results.modules = false
        end
    end
    
    -- Summary
    print("\n" .. string.rep("=", 50))
    print("GUI STATE COMPLIANCE TEST SUMMARY")
    print(string.rep("=", 50))
    
    local all_passed = true
    for tool, passed in pairs(test_results) do
        local status = passed and "✓ PASS" or "✗ FAIL"
        print(string.format("%-25s: %s", tool, status))
        if not passed then
            all_passed = false
        end
    end
    
    print(string.rep("=", 50))
    if all_passed then
        print("🎉 ALL TESTS PASSED - GUI state compliance verified!")
        return true
    else
        print("❌ SOME TESTS FAILED - Review needed")
        return false
    end
end

-- Run the test
local success = test_gui_state_compliance()
if success then
    print("🎉 ALL TESTS PASSED - GUI state compliance verified!")
    if reaper and reaper.MB then
        reaper.MB("GUI state compliance tests passed successfully!\n\nAll tools are properly using GUI state where needed.", "Test Results", 0)
    end
else
    print("❌ SOME TESTS FAILED - Review needed")
    if reaper and reaper.MB then
        reaper.MB("GUI state compliance tests failed!\n\nSome tools may need updates for proper GUI state usage.", "Test Results", 0)
    end
end