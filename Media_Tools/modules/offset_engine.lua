-- @noindex

local OffsetEngine = {}

-- Helper to build a lookup cache of text events in a take
function OffsetEngine.build_take_text_events_cache(take)
    local cache = {}
    if not take or not reaper.TakeIsMIDI(take) then return cache end
    local retval, notes_count, ccs_count, sysex_count = reaper.MIDI_CountEvts(take)
    for idx = 0, sysex_count - 1 do
        local r, selected, muted, ppqpos, type_val, msg = reaper.MIDI_GetTextSysexEvt(take, idx)
        if r and type_val == 1 then
            local bucket = math.floor(ppqpos / 5)
            if not cache[bucket] then cache[bucket] = {} end
            table.insert(cache[bucket], { idx = idx, ppqpos = ppqpos, msg = msg })
        end
    end
    return cache
end

-- Helper to query text events near a specific PPQ position using the cache
function OffsetEngine.find_text_events_near_ppq(cache, startppq)
    if not cache then return {} end
    local results = {}
    local ks = math.floor(startppq / 5)
    for b = ks - 1, ks + 1 do
        local bucket_events = cache[b]
        if bucket_events then
            for _, ev in ipairs(bucket_events) do
                if math.abs(ev.ppqpos - startppq) < 5 then
                    table.insert(results, ev)
                end
            end
        end
    end
    return results
end

-- Helper to delete/write preset name as a MIDI Text Event
function OffsetEngine.write_note_preset_text_event(take, startppq, preset_name)
    local retval, notes_count, ccs_count, sysex_count = reaper.MIDI_CountEvts(take)
    local events_to_delete = {}
    for idx = 0, sysex_count - 1 do
        local r, selected, muted, ppqpos, type_val, msg = reaper.MIDI_GetTextSysexEvt(take, idx)
        if r and type_val == 1 then
            if math.abs(ppqpos - startppq) < 5 and (msg:sub(1, 13) == "WalterPreset:" or msg:sub(1, 2) == "A:") then
                table.insert(events_to_delete, idx)
            end
        end
    end
    for d = #events_to_delete, 1, -1 do
        reaper.MIDI_DeleteTextSysexEvt(take, events_to_delete[d])
    end
    if preset_name and preset_name ~= "" then
        reaper.MIDI_InsertTextSysexEvt(
            take,
            false, -- selected
            false, -- muted
            startppq,
            1, -- type 1 = Text Event
            "A:" .. preset_name
        )
    end
end

-- Helper to read preset name from MIDI Text Event
function OffsetEngine.read_note_preset_text_event(take, startppq)
    local retval, notes_count, ccs_count, sysex_count = reaper.MIDI_CountEvts(take)
    for idx = 0, sysex_count - 1 do
        local r, selected, muted, ppqpos, type_val, msg = reaper.MIDI_GetTextSysexEvt(take, idx)
        if r and type_val == 1 then
            if math.abs(ppqpos - startppq) < 5 then
                if msg:sub(1, 2) == "A:" then
                    return msg:sub(3)
                elseif msg:sub(1, 13) == "WalterPreset:" then
                    return msg:sub(14)
                end
            end
        end
    end
    return ""
end

-- Helper to delete/write offset as a MIDI Text Event
function OffsetEngine.write_note_offset_text_event(take, startppq, offset_ms)
    local retval, notes_count, ccs_count, sysex_count = reaper.MIDI_CountEvts(take)
    local events_to_delete = {}
    for idx = 0, sysex_count - 1 do
        local r, selected, muted, ppqpos, type_val, msg = reaper.MIDI_GetTextSysexEvt(take, idx)
        if r and type_val == 1 then
            if math.abs(ppqpos - startppq) < 5 and msg:sub(1, 2) == "O:" then
                table.insert(events_to_delete, idx)
            end
        end
    end
    for d = #events_to_delete, 1, -1 do
        reaper.MIDI_DeleteTextSysexEvt(take, events_to_delete[d])
    end
    if offset_ms and math.abs(offset_ms) > 0.001 then
        reaper.MIDI_InsertTextSysexEvt(
            take,
            false, -- selected
            false, -- muted
            startppq,
            1, -- type 1 = Text Event
            "O:" .. tostring(offset_ms)
        )
    end
end

-- Helper to read offset from MIDI Text Event
function OffsetEngine.read_note_offset_text_event(take, startppq)
    local retval, notes_count, ccs_count, sysex_count = reaper.MIDI_CountEvts(take)
    for idx = 0, sysex_count - 1 do
        local r, selected, muted, ppqpos, type_val, msg = reaper.MIDI_GetTextSysexEvt(take, idx)
        if r and type_val == 1 then
            if math.abs(ppqpos - startppq) < 5 then
                if msg:sub(1, 2) == "O:" then
                    return tonumber(msg:sub(3)) or 0.0
                end
            end
        end
    end
    return nil
end

-- Helper to parse note offsets metadata from parent item (namespaced by take GUID)
function OffsetEngine.get_take_note_offsets(take)
    if not take or not reaper.TakeIsMIDI(take) then return {} end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return {} end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return {} end
    
    local _, val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Offsets_" .. guid, "", false)
    local offsets = {}
    if val and val ~= "" then
        for entry in val:gmatch("[^;]+") do
            local key, offset_str = entry:match("^([^:]+):([^:]+)$")
            if key and offset_str then
                offsets[key] = tonumber(offset_str) or 0.0
            end
        end
    end
    return offsets
end

-- Helper to save note offsets metadata to parent item (namespaced by take GUID)
function OffsetEngine.save_take_note_offsets(take, offsets)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return end
    
    local entries = {}
    for key, val in pairs(offsets) do
        if math.abs(val) > 0.001 then
            table.insert(entries, key .. ":" .. tostring(val))
        end
    end
    local val_str = table.concat(entries, ";")
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Offsets_" .. guid, val_str, true)
end

-- Helper to parse note presets metadata from parent item (namespaced by take GUID)
function OffsetEngine.get_take_note_presets(take)
    if not take or not reaper.TakeIsMIDI(take) then return {} end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return {} end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return {} end
    
    local _, val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Presets_" .. guid, "", false)
    local presets_map = {}
    if val and val ~= "" then
        for entry in val:gmatch("[^;]+") do
            local key, preset_name = entry:match("^([^:]+):(.*)$")
            if key and preset_name then
                presets_map[key] = preset_name
            end
        end
    end
    return presets_map
end

-- Helper to save note presets metadata to parent item (namespaced by take GUID)
function OffsetEngine.save_take_note_presets(take, note_presets)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return end
    
    local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not guid or guid == "" then return end
    
    local entries = {}
    for key, val in pairs(note_presets) do
        if val and val ~= "" then
            table.insert(entries, key .. ":" .. val)
        end
    end
    local val_str = table.concat(entries, ";")
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MIDI_Note_Presets_" .. guid, val_str, true)
end

return OffsetEngine
