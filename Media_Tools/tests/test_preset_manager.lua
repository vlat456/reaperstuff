-- @noindex
-- Mock REAPER API
_G.reaper = {
    GetResourcePath = function()
        return "." -- current directory for test output
    end
}

local preset_manager = require("modules.preset_manager")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

-- Test Split Preset Name
local function test_split_preset_name()
    local lib, art = preset_manager.split_preset_name("Library - Articulation")
    assert_eq(lib, "Library", "Library part split correctly")
    assert_eq(art, "Articulation", "Articulation part split correctly")

    local lib2, art2 = preset_manager.split_preset_name("SimpleName")
    assert_eq(lib2, "SimpleName", "Single name library component")
    assert_eq(art2, "", "Single name articulation is empty")

    local lib3, art3 = preset_manager.split_preset_name("")
    assert_eq(lib3, "", "Empty name split")
    assert_eq(art3, "", "Empty name split")

    local lib4, art4 = preset_manager.split_preset_name(nil)
    assert_eq(lib4, "", "Nil name split")
    assert_eq(art4, "", "Nil name split")
end

-- Test Split String
local function test_split_string()
    local parts = preset_manager.split_string("a|b|c", "|")
    assert_eq(#parts, 3, "Split parts count")
    assert_eq(parts[1], "a", "First part")
    assert_eq(parts[2], "b", "Second part")
    assert_eq(parts[3], "c", "Third part")
end

-- Test Load and Save Presets
local function test_load_save_presets()
    -- Clean up if exists
    local file_path = "./Data/Walter_MediaOffset_Presets.txt"
    os.execute("mkdir -p ./Data")
    os.remove(file_path)

    local initial_presets = {
        ["Lib - Art1"] = -15.5,
        ["Lib - Art2"] = 25.0
    }
    local initial_grid = {
        ["Lib - Art1"] = true,
        ["Lib - Art2"] = false
    }

    local init_ks_pitch = { ["Lib - Art1"] = 36, ["Lib - Art2"] = 48 }
    local init_vel_min = { ["Lib - Art1"] = 10, ["Lib - Art2"] = 20 }
    local init_vel_max = { ["Lib - Art1"] = 100, ["Lib - Art2"] = 120 }

    preset_manager.save_presets(initial_presets, initial_grid, init_ks_pitch, init_vel_min, init_vel_max)

    local loaded_presets, keys, show_in_grid, ks_pitch, vel_min, vel_max = preset_manager.load_presets()

    assert_eq(loaded_presets["Lib - Art1"], -15.5, "Loaded preset value 1")
    assert_eq(loaded_presets["Lib - Art2"], 25.0, "Loaded preset value 2")
    assert_eq(show_in_grid["Lib - Art1"], true, "Loaded show_in_grid 1")
    assert_eq(show_in_grid["Lib - Art2"], false, "Loaded show_in_grid 2")
    assert_eq(ks_pitch["Lib - Art1"], 36, "Loaded keyswitch pitch 1")
    assert_eq(ks_pitch["Lib - Art2"], 48, "Loaded keyswitch pitch 2")
    assert_eq(vel_min["Lib - Art1"], 10, "Loaded velocity min 1")
    assert_eq(vel_max["Lib - Art2"], 120, "Loaded velocity max 2")

    -- Clean up
    os.remove(file_path)
    os.execute("rmdir ./Data 2>/dev/null || true")
end

print("Running preset_manager tests...")
test_split_preset_name()
test_split_string()
test_load_save_presets()
print("All preset_manager tests passed!")
