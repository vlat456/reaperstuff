-- @noindex
-- Mock REAPER API
_G.reaper = {
    GetResourcePath = function()
        return "." -- current directory for test output
    end
}

local config_manager = require("modules.config_manager")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function assert_colors_eq(actual, expected, msg)
    assert_eq(#actual, 3, msg .. " length")
    for i = 1, 3 do
        local diff = math.abs(actual[i] - expected[i])
        if diff > 0.0001 then
            error(string.format("ASSERTION FAILED: %s at index %d\n  Expected: %f\n  Actual:   %f", msg, i, expected[i], actual[i]), 2)
        end
    end
end

-- Test Load and Save Config
local function test_load_save_config()
    local file_path = "./Data/Walter_MediaOffset_Settings.txt"
    os.execute("mkdir -p ./Data")
    os.remove(file_path)

    local initial_themes = {
        theme_bg          = {0.1, 0.2, 0.3},
        theme_accent      = {0.4, 0.5, 0.6},
        theme_text        = {0.7, 0.8, 0.9},
        theme_danger      = {0.11, 0.22, 0.33},
        theme_positive    = {0.44, 0.55, 0.66},
        theme_slider_grab = {0.77, 0.88, 0.99},
        theme_apply_btn   = {0.12, 0.23, 0.34},
        theme_frame_bg    = {0.45, 0.56, 0.67},
        theme_check_mark  = {0.78, 0.89, 0.91},
        settings_write_keyswitches = true
    }
    local initial_memory_stack = {
        { value = 10.5, name = "" },
        { value = -20.0, name = "Brass Staccato" },
        { value = 300.2, name = "" }
    }

    config_manager.save_settings(initial_themes, initial_themes.settings_write_keyswitches, initial_memory_stack)

    -- Prepare target variables/table to load settings into
    local themes = {}
    local settings_write_keyswitches = false
    local memory_stack = {}

    themes, settings_write_keyswitches, memory_stack = config_manager.load_settings()

    assert_colors_eq(themes.theme_bg, {0.1, 0.2, 0.3}, "bg color")
    assert_colors_eq(themes.theme_accent, {0.4, 0.5, 0.6}, "accent color")
    assert_colors_eq(themes.theme_text, {0.7, 0.8, 0.9}, "text color")
    assert_colors_eq(themes.theme_danger, {0.11, 0.22, 0.33}, "danger color")
    assert_colors_eq(themes.theme_positive, {0.44, 0.55, 0.66}, "positive color")
    assert_colors_eq(themes.theme_slider_grab, {0.77, 0.88, 0.99}, "slider grab color")
    assert_colors_eq(themes.theme_apply_btn, {0.12, 0.23, 0.34}, "apply button color")
    assert_colors_eq(themes.theme_frame_bg, {0.45, 0.56, 0.67}, "frame bg color")
    assert_colors_eq(themes.theme_check_mark, {0.78, 0.89, 0.91}, "check mark color")
    assert_eq(settings_write_keyswitches, true, "write keyswitches setting")
    
    assert_eq(#memory_stack, 3, "memory stack count")
    assert_eq(memory_stack[1].value, 10.5, "memory stack value 1")
    assert_eq(memory_stack[1].name, "", "memory stack name 1")
    assert_eq(memory_stack[2].value, -20.0, "memory stack value 2")
    assert_eq(memory_stack[2].name, "Brass Staccato", "memory stack name 2")
    assert_eq(memory_stack[3].value, 300.2, "memory stack value 3")
    assert_eq(memory_stack[3].name, "", "memory stack name 3")

    -- Clean up
    os.remove(file_path)
    os.execute("rmdir ./Data 2>/dev/null || true")
end

print("Running config_manager tests...")
test_load_save_config()
print("All config_manager tests passed!")
