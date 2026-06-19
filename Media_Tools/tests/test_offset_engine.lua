-- @noindex
-- Mock REAPER API
local mock_midi_events = {}

local mock_pexts = {}

_G.reaper = {
    TakeIsMIDI = function(take)
        return true
    end,
    MIDI_CountEvts = function(take)
        return true, 0, 0, #mock_midi_events
    end,
    MIDI_GetTextSysexEvt = function(take, idx)
        local evt = mock_midi_events[idx + 1]
        if not evt then return false end
        return true, evt.selected, evt.muted, evt.ppqpos, evt.type, evt.msg
    end,
    MIDI_InsertTextSysexEvt = function(take, selected, muted, ppqpos, type, msg)
        table.insert(mock_midi_events, {
            selected = selected,
            muted = muted,
            ppqpos = ppqpos,
            msg = msg,
            type = type
        })
        return true
    end,
    MIDI_DeleteTextSysexEvt = function(take, idx)
        table.remove(mock_midi_events, idx + 1)
        return true
    end,
    MIDI_EnumSelNotes = function(take, idx)
        return -1
    end,
    GetMediaItemTake_Item = function(take)
        return "fake_item"
    end,
    GetSetMediaItemTakeInfo_String = function(take, desc, val, is_set)
        return true, "fake_guid"
    end,
    GetSetMediaItemInfo_String = function(item, desc, val, is_set)
        if is_set then
            mock_pexts[desc] = val
            return true, val
        else
            return true, mock_pexts[desc] or ""
        end
    end
}

local offset_engine = require("modules.offset_engine")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\n  Expected: %q\n  Actual:   %q", msg or "", tostring(expected), tostring(actual)), 2)
    end
end

-- Test cache and search
local function test_cache_and_search()
    mock_midi_events = {
        { selected = false, muted = false, ppqpos = 960, msg = "O:15.5", type = 1 },
        { selected = false, muted = false, ppqpos = 1920, msg = "A:Legato", type = 1 }
    }

    local cache = offset_engine.build_take_text_events_cache("fake_take")
    
    local offset_results = offset_engine.find_text_events_near_ppq(cache, 960)
    assert_eq(#offset_results, 1, "Should find 1 event")
    assert_eq(offset_results[1].msg, "O:15.5", "Msg matches")

    local preset_results = offset_engine.find_text_events_near_ppq(cache, 1924) -- tolerance check
    assert_eq(#preset_results, 1, "Should find 1 event near 1920")
    assert_eq(preset_results[1].msg, "A:Legato", "Preset matches")

    local none_results = offset_engine.find_text_events_near_ppq(cache, 500)
    assert_eq(#none_results, 0, "No event near 500")
end

-- Test Write/Read Note Offset
local function test_write_read_offset()
    mock_midi_events = {}
    local take = "fake_take"

    -- Initial write
    offset_engine.write_note_offset_text_event(take, 480, -25.5)
    assert_eq(#mock_midi_events, 1, "Event inserted")
    assert_eq(mock_midi_events[1].ppqpos, 480, "PPQ position")
    assert_eq(mock_midi_events[1].msg, "O:-25.5", "Serialized format")

    -- Read back
    local val = offset_engine.read_note_offset_text_event(take, 480)
    assert_eq(val, -25.5, "Read back value")

    -- Overwrite
    offset_engine.write_note_offset_text_event(take, 480, 10.0)
    assert_eq(#mock_midi_events, 1, "Event modified, not duplicated")
    assert_eq(mock_midi_events[1].msg, "O:10.0", "Modified value")
end

-- Test Take Note Offsets & Presets metadata
local function test_take_note_metadata()
    mock_pexts = {}
    local take = "fake_take"

    local initial_offsets = {
        ["36_0_960"] = -10.0,
        ["38_0_1920"] = 15.5
    }
    offset_engine.save_take_note_offsets(take, initial_offsets)

    local loaded_offsets = offset_engine.get_take_note_offsets(take)
    assert_eq(loaded_offsets["36_0_960"], -10.0, "Loaded offset for pitch 36")
    assert_eq(loaded_offsets["38_0_1920"], 15.5, "Loaded offset for pitch 38")

    local initial_presets = {
        ["36_0_960"] = "Legato",
        ["38_0_1920"] = "Staccato"
    }
    offset_engine.save_take_note_presets(take, initial_presets)

    local loaded_presets = offset_engine.get_take_note_presets(take)
    assert_eq(loaded_presets["36_0_960"], "Legato", "Loaded preset for pitch 36")
    assert_eq(loaded_presets["38_0_1920"], "Staccato", "Loaded preset for pitch 38")
end

print("Running offset_engine tests...")
test_cache_and_search()
test_write_read_offset()
test_take_note_metadata()
print("All offset_engine tests passed!")
