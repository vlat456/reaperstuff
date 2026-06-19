-- @noindex

local reaper = reaper
local offset_engine = require("offset_engine")

local TargetManager = {}

-- Helper to check if a pitch is used as a keyswitch in any preset
function TargetManager.is_keyswitch_pitch(pitch, gui_state, presets_ks_pitch)
    if not gui_state or not gui_state.write_keyswitches then
        return false
    end
    if not presets_ks_pitch then return false end
    for name, ks_pitch in pairs(presets_ks_pitch) do
        if ks_pitch == pitch then
            return true
        end
    end
    return false
end

-- Helper to auto-detect matching preset for a selected MIDI note
function TargetManager.detect_preset_for_note(take, target_idx, target_vel, target_start_ppq, target_chan, gui_state, presets_ks_pitch, presets, presets_note_vel_min, presets_note_vel_max)
    -- 1. Collect candidate keyswitches
    local candidates = {}
    local _, total_notes = reaper.MIDI_CountEvts(take)
    
    -- Scan backwards
    local i = target_idx - 1
    local count = 0
    while i >= 0 and count < 1000 do
        local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if not retval then break end
        if target_start_ppq - startppq > 960.0 then break end -- Limit keyswitch search to 960 ticks (1 beat) to prevent inheriting previous notes' keyswitches
        if chan == target_chan and TargetManager.is_keyswitch_pitch(pitch, gui_state, presets_ks_pitch) then
            table.insert(candidates, { pitch = pitch, vel = vel, startppq = startppq, dist = target_start_ppq - startppq })
        end
        i = i - 1
        count = count + 1
    end
    
    -- Scan forwards for coincident notes
    local j = target_idx + 1
    count = 0
    while j < total_notes and count < 1000 do
        local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, j)
        if not retval then break end
        if startppq ~= target_start_ppq then break end
        if chan == target_chan and TargetManager.is_keyswitch_pitch(pitch, gui_state, presets_ks_pitch) then
            table.insert(candidates, { pitch = pitch, vel = vel, startppq = startppq, dist = 0.0 })
        end
        j = j + 1
        count = count + 1
    end
    
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    
    local best_preset = ""
    local best_score = -1
    
    for name, offset in pairs(presets) do
        local ks_pitch = presets_ks_pitch[name] or -1
        local note_vel_min = presets_note_vel_min[name] or -1
        local note_vel_max = presets_note_vel_max[name] or -1
        
        local has_ks = (ks_pitch >= 0)
        local has_vel = (note_vel_min >= 0 and note_vel_max >= 0)
        
        if has_ks or has_vel then
            local matched = true
            local score = 0
            
            if has_ks then
                if #candidates == 0 or candidates[1].pitch ~= ks_pitch then
                    matched = false
                else
                    score = score + 2
                end
            end
            
            if matched and has_vel then
                if target_vel < note_vel_min or target_vel > note_vel_max then
                    matched = false
                else
                    score = score + 1
                end
            end
            
            if matched then
                if score > best_score then
                    best_score = score
                    best_preset = name
                end
            end
        end
    end
    
    return best_preset
end

-- Helper to clean up note offsets and presets metadata from a take (both P_EXT and Text Events)
function TargetManager.cleanup_take_note_offsets(take, gui_state, presets_ks_pitch)
    if not take or not reaper.TakeIsMIDI(take) then return end
    local retval, notes_count, ccs_count, sysex_count = reaper.MIDI_CountEvts(take)
    
    -- 1. Build a quick lookup list of existing note start positions (excluding keyswitches)
    local existing_note_ppqs = {}
    for idx = 0, notes_count - 1 do
        local r, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, idx)
        if r and not TargetManager.is_keyswitch_pitch(pitch, gui_state, presets_ks_pitch) then
            table.insert(existing_note_ppqs, startppq)
        end
    end
    
    -- 2. Find and delete orphaned Text Events (offset and preset events with no matching note)
    local text_events_to_delete = {}
    for idx = 0, sysex_count - 1 do
        local r, selected, muted, ppqpos, type_val, msg = reaper.MIDI_GetTextSysexEvt(take, idx)
        if r and type_val == 1 then
            if msg:sub(1, 2) == "O:" or msg:sub(1, 2) == "A:" or msg:sub(1, 13) == "WalterPreset:" then
                local note_found = false
                for _, n_ppq in ipairs(existing_note_ppqs) do
                    if math.abs(n_ppq - ppqpos) < 5 then
                        note_found = true
                        break
                    end
                end
                if not note_found then
                    table.insert(text_events_to_delete, idx)
                end
            end
        end
    end
    for d = #text_events_to_delete, 1, -1 do
        reaper.MIDI_DeleteTextSysexEvt(take, text_events_to_delete[d])
    end
    
    -- Recount after text event deletions to keep indexes correct
    local _, notes_count_new = reaper.MIDI_CountEvts(take)
    local offsets = offset_engine.get_take_note_offsets(take)
    local note_presets = offset_engine.get_take_note_presets(take)
    
    -- Build a quick lookup map of existing notes by pitch_chan:ppq
    local existing_notes = {}
    for idx = 0, notes_count_new - 1 do
        local r, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, idx)
        if r then
            local lookup_key = string.format("%d_%d", pitch, chan)
            if not existing_notes[lookup_key] then
                existing_notes[lookup_key] = {}
            end
            table.insert(existing_notes[lookup_key], startppq)
        end
    end
    
    local cleaned_offsets = {}
    local cleaned_presets = {}
    local changed = false
    
    for key, offset_ms in pairs(offsets) do
        local o_pitch, o_chan, o_orig_ppq = key:match("^(%d+)_(%d+)_(%d+)$")
        if o_pitch and o_chan and o_orig_ppq then
            o_pitch = tonumber(o_pitch)
            o_chan = tonumber(o_chan)
            o_orig_ppq = tonumber(o_orig_ppq)
            
            local orig_time = reaper.MIDI_GetProjTimeFromPPQPos(take, o_orig_ppq)
            local current_time_expected = orig_time + (offset_ms / 1000.0)
            local expected_current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, current_time_expected)
            
            local lookup_key = string.format("%d_%d", o_pitch, o_chan)
            -- Check if any note matches the expected current position
            local found = false
            local ppqs = existing_notes[lookup_key]
            if ppqs then
                for _, startppq in ipairs(ppqs) do
                    if math.abs(startppq - expected_current_ppq) < 5 then
                        found = true
                        break
                    end
                end
            end
            
            if found then
                cleaned_offsets[key] = offset_ms
                if note_presets[key] then
                    cleaned_presets[key] = note_presets[key]
                end
            else
                changed = true
            end
        end
    end
    
    if changed then
        offset_engine.save_take_note_offsets(take, cleaned_offsets)
        offset_engine.save_take_note_presets(take, cleaned_presets)
    end
end

-- Get Selection Signature
function TargetManager.get_selection_signature(get_effective_mode_cb, has_selected_midi_notes_cb, get_midi_notes_signature_cb, modes)
    local eff_mode, take = get_effective_mode_cb()
    if eff_mode == modes.MODE_MIDI_NOTES then
        if take then
            local has_notes, active_take = has_selected_midi_notes_cb()
            if has_notes and active_take then
                return get_midi_notes_signature_cb(active_take)
            end
        end
        return ""
    elseif eff_mode == modes.MODE_TRACK_OFFSET then
        local signature = ""
        local num_tracks = reaper.CountSelectedTracks(0)
        if num_tracks > 0 then
            if num_tracks > 1000 then num_tracks = 1000 end
            local parts = {}
            for i = 0, num_tracks - 1 do
                local track = reaper.GetSelectedTrack(0, i)
                if track then
                    local offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                    local guid = reaper.GetTrackGUID(track) or ""
                    table.insert(parts, guid .. "_" .. tostring(offset))
                end
            end
            signature = table.concat(parts, ";")
        else
            -- Fallback
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    local item = reaper.GetMediaItemTake_Item(take)
                    if item then
                        local track = reaper.GetMediaItem_Track(item)
                        if track then
                            local offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                            local guid = reaper.GetTrackGUID(track) or ""
                            signature = guid .. "_" .. tostring(offset)
                        end
                    end
                end
            end
        end
        return signature
    elseif eff_mode == modes.MODE_TAKE_OFFSET then
        local signature = ""
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 0 then
            if num_items > 10000 then num_items = 10000 end
            local parts = {}
            for i = 0, num_items - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                if item then
                    local take = reaper.GetActiveTake(item)
                    if take then
                        local offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                        local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                        table.insert(parts, (take_guid or "") .. "_" .. tostring(offset))
                    end
                end
            end
            signature = table.concat(parts, ";")
        else
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    local offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                    local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                    signature = (take_guid or "") .. "_" .. tostring(offset)
                end
            end
        end
        return signature
    elseif eff_mode == modes.MODE_ITEM_POSITION then
        local signature = ""
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 0 then
            if num_items > 10000 then num_items = 10000 end
            local parts = {}
            for i = 0, num_items - 1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                if item then
                    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
                    table.insert(parts, (guid or "") .. "_" .. tostring(pos))
                end
            end
            signature = table.concat(parts, ";")
        else
            local midi_editor = reaper.MIDIEditor_GetActive()
            if midi_editor then
                local take = reaper.MIDIEditor_GetTake(midi_editor)
                if take then
                    local item = reaper.GetMediaItemTake_Item(take)
                    if item then
                        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
                        signature = (guid or "") .. "_" .. tostring(pos)
                    end
                end
            end
        end
        return signature
    end
    return ""
end

-- Update Targets List
function TargetManager.update_targets_list(ctx, gui_state, presets_state, modes, force, callbacks)
    -- Skip rebuilding selection while the user is actively interacting with the GUI,
    -- unless forced (e.g. on mode change).
    if not force and (reaper.ImGui_IsAnyItemActive(ctx) or gui_state.is_dragging) then
        return
    end
    
    local current_sig = TargetManager.get_selection_signature(callbacks.get_effective_mode, callbacks.has_selected_midi_notes, callbacks.get_midi_notes_signature, modes)
    local selection_changed = current_sig ~= gui_state.last_selection_state
    
    if selection_changed or force then
        gui_state.last_selection_state = current_sig
        gui_state.selected_targets = {}
        
        local eff_mode, take = callbacks.get_effective_mode()
        
        if eff_mode == modes.MODE_MIDI_NOTES then
            -- Clean up stale offsets
            TargetManager.cleanup_take_note_offsets(take, gui_state, presets_state.presets_ks_pitch)
            
            -- Override: selected MIDI notes in active take
            local offsets = offset_engine.get_take_note_offsets(take)
            local note_presets = offset_engine.get_take_note_presets(take)
            local text_cache = offset_engine.build_take_text_events_cache(take)
            local note_idx = -1
            local safety = 0
            while safety < 10000 do
                note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                if note_idx == -1 then break end
                local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
                if retval then
                    -- Ignore keyswitches from being shifted as target notes
                    if not TargetManager.is_keyswitch_pitch(pitch, gui_state, presets_state.presets_ks_pitch) then
                        -- Look up in offsets metadata
                        local found_offset = 0.0
                        local found_preset = ""
                        local original_ppq = startppq
                        
                        -- Prioritize reading from MIDI Text Events
                        local text_events = offset_engine.find_text_events_near_ppq(text_cache, startppq)
                        local found_offset_from_text = nil
                        for _, ev in ipairs(text_events) do
                            if ev.msg:sub(1, 2) == "O:" then
                                found_offset_from_text = tonumber(ev.msg:sub(3)) or 0.0
                            elseif ev.msg:sub(1, 2) == "A:" then
                                found_preset = ev.msg:sub(3)
                            elseif ev.msg:sub(1, 13) == "WalterPreset:" then
                                found_preset = ev.msg:sub(14)
                            end
                        end
                        
                        if found_offset_from_text then
                            found_offset = found_offset_from_text
                            local current_time = reaper.MIDI_GetProjTimeFromPPQPos(take, startppq)
                            local original_time = current_time - (found_offset / 1000.0)
                            original_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjTime(take, original_time) + 0.5)
                        else
                            -- Fallback to the old P_EXT offsets metadata database lookup
                            for key, offset_ms in pairs(offsets) do
                                local o_pitch, o_chan, o_orig_ppq = key:match("^(%d+)_(%d+)_(%d+)$")
                                if o_pitch and o_chan and o_orig_ppq then
                                    o_pitch = tonumber(o_pitch)
                                    o_chan = tonumber(o_chan)
                                    o_orig_ppq = tonumber(o_orig_ppq)
                                    
                                    if o_pitch == pitch and o_chan == chan then
                                        local orig_time = reaper.MIDI_GetProjTimeFromPPQPos(take, o_orig_ppq)
                                        local current_time_expected = orig_time + (offset_ms / 1000.0)
                                        local expected_current_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, current_time_expected)
                                        
                                        if math.abs(startppq - expected_current_ppq) < 5 then
                                            found_offset = offset_ms
                                            if found_preset == "" then
                                                found_preset = note_presets[key] or ""
                                            end
                                            original_ppq = o_orig_ppq
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        
                        -- Original unshifted positions
                        local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, original_ppq)
                        local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, original_ppq + (endppq - startppq))
                        
                        local active_preset_name = found_preset
                        if active_preset_name == "" then
                            active_preset_name = TargetManager.detect_preset_for_note(
                                take, note_idx, vel, startppq, chan, gui_state,
                                presets_state.presets_ks_pitch, presets_state.presets,
                                presets_state.presets_note_vel_min, presets_state.presets_note_vel_max
                            )
                        end
    
                        table.insert(gui_state.selected_targets, {
                            take = take,
                            note_index = note_idx,
                            original_ppq = original_ppq,
                            offset_ms = found_offset,
                            preset_name = active_preset_name,
                            start_time = start_time,
                            end_time = end_time,
                            pitch = pitch,
                            chan = chan,
                            vel = vel,
                            muted = muted
                        })
                    end
                end
                safety = safety + 1
            end
            
            -- Initialize slider_value
            if #gui_state.selected_targets > 0 then
                local first_offset = gui_state.selected_targets[1].offset_ms
                local all_same = true
                for i = 2, #gui_state.selected_targets do
                    if math.abs(gui_state.selected_targets[i].offset_ms - first_offset) > 0.01 then
                        all_same = false
                        break
                    end
                end
                if all_same then
                    gui_state.slider_value = first_offset
                else
                    gui_state.slider_value = 0.0
                end
            else
                gui_state.slider_value = 0.0
            end
            
        elseif eff_mode == modes.MODE_TRACK_OFFSET then
            -- Mode B: Track Playback Offset
            local num_tracks = reaper.CountSelectedTracks(0)
            if num_tracks > 0 then
                if num_tracks > 1000 then num_tracks = 1000 end
                for i = 0, num_tracks - 1 do
                    local track = reaper.GetSelectedTrack(0, i)
                    if track then
                        local _, name = reaper.GetTrackName(track)
                        name = name or "Unnamed Track"
                        local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                        local _, track_preset = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        table.insert(gui_state.selected_targets, {
                            track = track,
                            name = name,
                            baseline_offset = cur_offset,
                            preset_name = track_preset or ""
                        })
                    end
                end
            else
                -- Fallback to active MIDI editor track
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local track = reaper.GetMediaItem_Track(item)
                            if track then
                                local _, name = reaper.GetTrackName(track)
                                name = name or "Unnamed Track"
                                local cur_offset = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
                                local _, track_preset = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                                table.insert(gui_state.selected_targets, {
                                    track = track,
                                    name = name .. " (MIDI Editor)",
                                    baseline_offset = cur_offset,
                                    preset_name = track_preset or ""
                                })
                            end
                        end
                    end
                end
            end
            
            if #gui_state.selected_targets > 0 then
                gui_state.slider_value = gui_state.selected_targets[1].baseline_offset * 1000.0
            else
                gui_state.slider_value = 0.0
            end
            
        elseif eff_mode == modes.MODE_TAKE_OFFSET then
            -- Mode A: Media Take Source Start Offset
            local num_items = reaper.CountSelectedMediaItems(0)
            if num_items > 0 then
                if num_items > 10000 then num_items = 10000 end
                for i = 0, num_items - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if item then
                        local take = reaper.GetActiveTake(item)
                        if take then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            local take_preset = ""
                            local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                            if take_guid and take_guid ~= "" then
                                _, take_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, "", false)
                            end
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name,
                                baseline_offset = cur_offset,
                                preset_name = take_preset or ""
                            })
                        end
                    end
                end
            else
                -- Fallback to active MIDI editor take
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            local take_preset = ""
                            local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
                            if take_guid and take_guid ~= "" then
                                _, take_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, "", false)
                            end
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                take = take,
                                name = name .. " (MIDI Editor)",
                                baseline_offset = cur_offset,
                                preset_name = take_preset or ""
                            })
                        end
                    end
                end
            end
            
            if #gui_state.selected_targets > 0 then
                gui_state.slider_value = gui_state.selected_targets[1].baseline_offset * 1000.0
            else
                gui_state.slider_value = 0.0
            end
            
        elseif eff_mode == modes.MODE_ITEM_POSITION then
            -- Mode C: Move Item Timeline Position
            local num_items = reaper.CountSelectedMediaItems(0)
            if num_items > 0 then
                if num_items > 10000 then num_items = 10000 end
                for i = 0, num_items - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if item then
                        local take = reaper.GetActiveTake(item)
                        local name = take and reaper.GetTakeName(take) or "Empty Item"
                        local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        
                        -- Read saved offset from item metadata
                        local retval, saved_val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                        local saved_offset_sec = 0.0
                        if retval and saved_val ~= "" then
                            saved_offset_sec = (tonumber(saved_val) or 0.0) / 1000.0
                        end
                        
                        -- The original zero position is current position minus saved offset
                        local zero_pos = cur_pos - saved_offset_sec
                        local _, item_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        
                        table.insert(gui_state.selected_targets, {
                            item = item,
                            name = name,
                            zero_position = zero_pos,
                            baseline_offset = cur_pos,
                            preset_name = item_preset or ""
                        })
                    end
                end
            else
                -- Fallback to active MIDI editor item
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local take = reaper.MIDIEditor_GetTake(midi_editor)
                    if take then
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item then
                            local name = reaper.GetTakeName(take) or "Unnamed Take"
                            local cur_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            
                            -- Read saved offset from item metadata
                            local retval, saved_val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                            local saved_offset_sec = 0.0
                            if retval and saved_val ~= "" then
                                saved_offset_sec = (tonumber(saved_val) or 0.0) / 1000.0
                            end
                            
                            local zero_pos = cur_pos - saved_offset_sec
                            local _, item_preset = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                            
                            table.insert(gui_state.selected_targets, {
                                item = item,
                                name = name .. " (MIDI Editor)",
                                zero_position = zero_pos,
                                baseline_offset = cur_pos,
                                preset_name = item_preset or ""
                            })
                        end
                    end
                end
            end
            
            -- Initialize slider value with the saved offset of the first item
            if #gui_state.selected_targets > 0 then
                local first_item = gui_state.selected_targets[1].item
                local retval, saved_val = reaper.GetSetMediaItemInfo_String(first_item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                if retval and saved_val ~= "" then
                    gui_state.slider_value = tonumber(saved_val) or 0.0
                else
                    gui_state.slider_value = 0.0
                end
            else
                gui_state.slider_value = 0.0
            end
        end
        
        -- Determine common preset name on selection change
        local common_preset = ""
        if #gui_state.selected_targets > 0 then
            local first_preset = gui_state.selected_targets[1].preset_name or ""
            local all_same = true
            for i = 2, #gui_state.selected_targets do
                if (gui_state.selected_targets[i].preset_name or "") ~= first_preset then
                    all_same = false
                    break
                end
            end
            if all_same then
                common_preset = first_preset
                if first_preset ~= "" then
                    local lib, instr, art = callbacks.split_preset_name(first_preset)
                    if lib ~= "" then
                        gui_state.selected_library = lib
                    end
                end
            end
        end
        presets_state.current_preset_name = common_preset
        presets_state.combo_preset_name = common_preset
    else
        -- Sync baselines and values if NOT dragging
        local is_slider_active = reaper.ImGui_IsAnyItemActive(ctx) or gui_state.is_dragging
        local is_previewing = (presets_state.combo_preset_name ~= "" and presets_state.combo_preset_name ~= presets_state.current_preset_name)
        if not is_slider_active and #gui_state.selected_targets > 0 then
            local eff_mode, take = callbacks.get_effective_mode()
            if eff_mode == modes.MODE_MIDI_NOTES then
                local offsets = offset_engine.get_take_note_offsets(take)
                local note_presets = offset_engine.get_take_note_presets(take)
                local text_cache = offset_engine.build_take_text_events_cache(take)
                local any_drifted = false
                local note_idx = -1
                
                for _, info in ipairs(gui_state.selected_targets) do
                    note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
                    if note_idx == -1 then break end
                    local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(info.take, note_idx)
                    if retval then
                        info.vel = vel
                        info.pitch = pitch
                        info.chan = chan

                        local detected_preset = TargetManager.detect_preset_for_note(
                            info.take, note_idx, vel, startppq, chan, gui_state,
                            presets_state.presets_ks_pitch, presets_state.presets,
                            presets_state.presets_note_vel_min, presets_state.presets_note_vel_max
                        )
                        local found_preset = ""

                        local orig_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, info.original_ppq)
                        local current_time_expected = orig_time + (info.offset_ms / 1000.0)
                        local expected_current_ppq = reaper.MIDI_GetPPQPosFromProjTime(info.take, current_time_expected)
                        
                        if math.abs(startppq - expected_current_ppq) >= 5 then
                            -- Note has drifted (manually moved). Clean up old metadata entry
                            local old_key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                            offsets[old_key] = nil
                            note_presets[old_key] = nil
                            
                            -- Delete old offset and preset text events at the old expected position
                            offset_engine.write_note_offset_text_event(info.take, expected_current_ppq, 0.0)
                            offset_engine.write_note_preset_text_event(info.take, expected_current_ppq, "")
                            
                            -- Reset baseline to new position
                            info.original_ppq = startppq
                            info.offset_ms = 0.0
                            info.start_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, startppq)
                            info.end_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, endppq)
                            any_drifted = true
                        else
                            -- Sync end_time to preserve manual duration edits
                            local current_end_time = reaper.MIDI_GetProjTimeFromPPQPos(info.take, endppq)
                            info.end_time = current_end_time - (info.offset_ms / 1000.0)
                        end

                        -- Prioritize reading the preset name from the MIDI Text Events at its current position
                        local text_events = offset_engine.find_text_events_near_ppq(text_cache, startppq)
                        for _, ev in ipairs(text_events) do
                            if ev.msg:sub(1, 2) == "A:" then
                                    found_preset = ev.msg:sub(3)
                            elseif ev.msg:sub(1, 13) == "WalterPreset:" then
                                    found_preset = ev.msg:sub(14)
                            end
                        end
                        
                        if found_preset == "" then
                            local old_key = string.format("%d_%d_%d", info.pitch, info.chan, info.original_ppq)
                            found_preset = note_presets[old_key] or ""
                        end

                        if detected_preset ~= "" then
                            info.preset_name = detected_preset
                        else
                            info.preset_name = found_preset
                        end
                    end
                end
                
                if any_drifted then
                    offset_engine.save_take_note_offsets(take, offsets)
                    offset_engine.save_take_note_presets(take, note_presets)
                    
                    local first_offset = gui_state.selected_targets[1].offset_ms
                    local all_same = true
                    for i = 2, #gui_state.selected_targets do
                        if math.abs(gui_state.selected_targets[i].offset_ms - first_offset) > 0.01 then
                            all_same = false
                            break
                        end
                    end
                    if all_same then
                        gui_state.slider_value = first_offset
                    else
                        gui_state.slider_value = 0.0
                    end
                    
                    local first_preset = gui_state.selected_targets[1].preset_name or ""
                    local all_same_preset = true
                    for i = 2, #gui_state.selected_targets do
                        if (gui_state.selected_targets[i].preset_name or "") ~= first_preset then
                            all_same_preset = false
                            break
                        end
                    end
                    presets_state.current_preset_name = all_same_preset and first_preset or ""
                    presets_state.combo_preset_name = presets_state.current_preset_name
                    if presets_state.current_preset_name ~= "" then
                        local lib, instr, art = callbacks.split_preset_name(presets_state.current_preset_name)
                        if lib ~= "" then
                            gui_state.selected_library = lib
                        end
                    end
                end
            elseif eff_mode == modes.MODE_TRACK_OFFSET then
                if not is_previewing then
                    local first_info = gui_state.selected_targets[1]
                    if reaper.ValidatePtr(first_info.track, "MediaTrack*") then
                        local actual_offset = reaper.GetMediaTrackInfo_Value(first_info.track, "D_PLAY_OFFSET")
                        gui_state.slider_value = actual_offset * 1000.0
                    end
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.track, "MediaTrack*") then
                        info.baseline_offset = reaper.GetMediaTrackInfo_Value(info.track, "D_PLAY_OFFSET")
                        local _, track_preset = reaper.GetSetMediaTrackInfo_String(info.track, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        info.preset_name = track_preset or ""
                    end
                end
            elseif eff_mode == modes.MODE_TAKE_OFFSET then
                if not is_previewing then
                    local first_info = gui_state.selected_targets[1]
                    if reaper.ValidatePtr(first_info.take, "MediaItem_Take*") then
                        local actual_offset = reaper.GetMediaItemTakeInfo_Value(first_info.take, "D_STARTOFFS")
                        gui_state.slider_value = actual_offset * 1000.0
                    end
                end
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.take, "MediaItem_Take*") then
                        info.baseline_offset = reaper.GetMediaItemTakeInfo_Value(info.take, "D_STARTOFFS")
                        local take_preset = ""
                        local _, take_guid = reaper.GetSetMediaItemTakeInfo_String(info.take, "GUID", "", false)
                        if take_guid and take_guid ~= "" then
                            local parent_item = reaper.GetMediaItemTake_Item(info.take)
                            if parent_item then
                                _, take_preset = reaper.GetSetMediaItemInfo_String(parent_item, "P_EXT:Walter_MediaOffsetTool_take_preset_" .. take_guid, "", false)
                            end
                        end
                        info.preset_name = take_preset or ""
                    end
                end
            elseif eff_mode == modes.MODE_ITEM_POSITION then
                if not is_previewing then
                    local first_info = gui_state.selected_targets[1]
                    if first_info and reaper.ValidatePtr(first_info.item, "MediaItem*") then
                        local cur_pos = reaper.GetMediaItemInfo_Value(first_info.item, "D_POSITION")
                        local retval, saved_val = reaper.GetSetMediaItemInfo_String(first_info.item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                        local saved_offset_ms = 0.0
                        if retval and saved_val ~= "" then
                            saved_offset_ms = tonumber(saved_val) or 0.0
                        end
                        gui_state.slider_value = saved_offset_ms
                        first_info.zero_position = cur_pos - (saved_offset_ms / 1000.0)
                    end
                end
                
                for _, info in ipairs(gui_state.selected_targets) do
                    if reaper.ValidatePtr(info.item, "MediaItem*") then
                        local cur_pos = reaper.GetMediaItemInfo_Value(info.item, "D_POSITION")
                        info.baseline_offset = cur_pos
                        local retval, saved_val = reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
                        local saved_offset_ms = 0.0
                        if retval and saved_val ~= "" then
                            saved_offset_ms = tonumber(saved_val) or 0.0
                        end
                        info.zero_position = cur_pos - (saved_offset_ms / 1000.0)
                        local _, item_preset = reaper.GetSetMediaItemInfo_String(info.item, "P_EXT:Walter_MediaOffsetTool_preset", "", false)
                        info.preset_name = item_preset or ""
                    end
                end
            end
        end
    end
end

return TargetManager
