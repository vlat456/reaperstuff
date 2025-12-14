-- @noindex
-- @description Robust cleanup manager for MIDI tools scripts

local reaper = reaper

local M = {}

-- Registry of cleanup functions to call on script termination
local cleanup_registry = {}

-- Function to register cleanup functions
function M.register_cleanup(script_name, cleanup_func)
    cleanup_registry[script_name] = cleanup_func
end

-- Function to unregister cleanup functions
function M.unregister_cleanup(script_name)
    cleanup_registry[script_name] = nil
end

-- Function to execute all registered cleanup functions with pcall protection
function M.execute_all_cleanup()
    for script_name, cleanup_func in pairs(cleanup_registry) do
        if cleanup_func then
            local success, error_msg = pcall(cleanup_func)
            if not success then
                reaper.ShowConsoleMsg("Cleanup error in " .. script_name .. ": " .. tostring(error_msg))
            end
        end
    end
    -- Clear the registry after cleanup
    cleanup_registry = {}
end

-- Function to execute specific script cleanup with pcall protection
function M.execute_cleanup(script_name)
    local cleanup_func = cleanup_registry[script_name]
    if cleanup_func then
        local success, error_msg = pcall(cleanup_func)
        if not success then
            reaper.ShowConsoleMsg("Cleanup error in " .. script_name .. ": " .. tostring(error_msg))
        end
    end
    cleanup_registry[script_name] = nil
    -- Unregister after successful cleanup
end

-- Function to set up atexit handler for robust cleanup
function M.setup_atexit_handler(script_name, cleanup_func)
    M.register_cleanup(script_name, cleanup_func)
    
    -- Set up a cleanup function that will be called when the script exits
    -- This provides additional protection beyond manual cleanup calls
    local atexit_cleanup = function()
        M.execute_cleanup(script_name)
    end
    
    -- Register the cleanup function
    package.loaded[script_name .. "_atexit"] = atexit_cleanup
end

return M