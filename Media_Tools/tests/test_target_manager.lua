-- @noindex
-- Mock REAPER API for TargetManager tests
local imgui_calls = {}

_G.imgui = {}

package.preload['imgui'] = function()
    return function(version)
        return _G.imgui
    end
end

_G.reaper = {
    ImGui_IsAnyItemActive = function(ctx) return false end,
    MIDI_CountEvts = function(take) return true, 1, 0, 0 end,
    MIDI_GetNote = function(take, idx)
        return true, true, false, 480, 960, 0, 60, 100
    end,
    MIDI_EnumSelNotes = function(take, idx)
        if idx == -1 then return 0 end
        return -1
    end,
    MIDI_GetProjTimeFromPPQPos = function(take, ppq) return ppq / 960.0 end,
    MIDI_GetPPQPosFromProjTime = function(take, time) return time * 960.0 end,
    GetMediaItemTake_Item = function(take) return "fake_item" end,
    GetSetMediaItemTakeInfo_String = function(take, field, val, is_set)
        return true, "take_guid"
    end,
    GetSetMediaItemInfo_String = function(item, field, val, is_set)
        return true, ""
    end,
    ValidatePtr = function(ptr, type_str) return true end,
    MIDIEditor_GetActive = function() return nil end,
    TakeIsMIDI = function(take) return true end,
    MIDI_GetTextSysexEvt = function() return false end
}

package.path = "modules/?.lua;" .. package.path
local target_manager = require("modules.target_manager")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

local function test_is_keyswitch_pitch()
    local gui_state = { write_keyswitches = true }
    local presets_ks_pitch = { ["Spitfire - Long"] = 24 }
    
    assert_eq(target_manager.is_keyswitch_pitch(24, gui_state, presets_ks_pitch), true, "Pitch 24 is keyswitch")
    assert_eq(target_manager.is_keyswitch_pitch(60, gui_state, presets_ks_pitch), false, "Pitch 60 is not keyswitch")
end

local function test_update_targets_list()
    local gui_state = {
        last_selection_state = "",
        selected_targets = {},
        is_dragging = false
    }
    local presets_state = {
        presets = {},
        presets_show_in_grid = {},
        presets_ks_pitch = {},
        presets_note_vel_min = {},
        presets_note_vel_max = {},
        current_preset_name = "",
        combo_preset_name = ""
    }
    local modes = {
        MODE_TRACK_OFFSET = 1,
        MODE_TAKE_OFFSET = 2,
        MODE_ITEM_POSITION = 3,
        MODE_MIDI_NOTES = 4
    }
    local callbacks = {
        get_effective_mode = function() return 4, "fake_take" end,
        has_selected_midi_notes = function() return true, "fake_take" end,
        get_midi_notes_signature = function() return "sig123" end,
        split_preset_name = function() return "Spitfire", "Long" end
    }

    target_manager.update_targets_list("fake_ctx", gui_state, presets_state, modes, true, callbacks)

    assert_eq(#gui_state.selected_targets, 1, "Should have 1 target note")
    assert_eq(gui_state.selected_targets[1].pitch, 60, "Pitch of target note")
end

local function test_duration_sync()
    local gui_state = {
        last_selection_state = "sig123",
        selected_targets = {
            {
                take = "fake_take",
                note_index = 0,
                original_ppq = 480,
                offset_ms = 1000.0,
                start_time = 0.5,
                end_time = 1.0,
                pitch = 60,
                chan = 0,
                vel = 100,
                muted = false
            }
        },
        is_dragging = false
    }
    local presets_state = {
        presets = {},
        presets_ks_pitch = {},
        presets_note_vel_min = {},
        presets_note_vel_max = {},
        current_preset_name = "",
        combo_preset_name = ""
    }
    local modes = {
        MODE_TRACK_OFFSET = 1,
        MODE_TAKE_OFFSET = 2,
        MODE_ITEM_POSITION = 3,
        MODE_MIDI_NOTES = 4
    }
    local callbacks = {
        get_effective_mode = function() return 4, "fake_take" end,
        has_selected_midi_notes = function() return true, "fake_take" end,
        get_midi_notes_signature = function() return "sig123" end,
        split_preset_name = function() return "Spitfire", "Long" end
    }

    local original_midi_get_note = _G.reaper.MIDI_GetNote
    _G.reaper.MIDI_GetNote = function(take, idx)
        return true, true, false, 1440, 2880, 0, 60, 100
    end

    target_manager.update_targets_list("fake_ctx", gui_state, presets_state, modes, false, callbacks)

    _G.reaper.MIDI_GetNote = original_midi_get_note

    local expected_end_time = 2.0
    assert_eq(gui_state.selected_targets[1].end_time, expected_end_time, "Sync should update end_time when duration changes")
end

print("Running target_manager tests...")
test_is_keyswitch_pitch()
test_update_targets_list()
test_duration_sync()
print("All target_manager tests passed!")
