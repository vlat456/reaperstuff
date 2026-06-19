-- @noindex

local reaper = reaper
local imgui = require('imgui')('0.9.3')

local UIInfoPanel = {}

function UIInfoPanel.draw_info_panel(ctx, gui_state, num_targets, eff_mode, track, take, has_notes, active_take, modes)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- 1. Track Playback Offset (Always visible)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local cur_offset_sec = reaper.GetMediaTrackInfo_Value(track, "D_PLAY_OFFSET")
        local _, name = reaper.GetTrackName(track)
        name = name or "Unnamed Track"
        
        local label = "Track (" .. name .. ")"
        if eff_mode == modes.MODE_TRACK_OFFSET and num_targets > 1 then
            label = string.format("Track (%s + %d others)", name, num_targets - 1)
        end
        reaper.ImGui_Text(ctx, label .. " Playback Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, string.format("%.1f ms (%.4fs)", cur_offset_sec * 1000.0, cur_offset_sec))
    else
        reaper.ImGui_Text(ctx, "Track Playback Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No track selected")
    end
    
    -- 2. Take Start Offset (Always visible)
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local cur_offset_sec = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local name = reaper.GetTakeName(take) or "Unnamed Take"
        
        local label = "Take (" .. name .. ")"
        if eff_mode == modes.MODE_TAKE_OFFSET and num_targets > 1 then
            label = string.format("Take (%s + %d others)", name, num_targets - 1)
        end
        reaper.ImGui_Text(ctx, label .. " Start Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, string.format("%.1f ms (%.4fs)", cur_offset_sec * 1000.0, cur_offset_sec))
    else
        reaper.ImGui_Text(ctx, "Take Start Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No take selected")
    end

    -- 3. Item Position Offset (Always visible, stored in item extension metadata)
    local item
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        item = reaper.GetMediaItemTake_Item(take)
    else
        local num_items = reaper.CountSelectedMediaItems(0)
        if num_items > 0 then
            item = reaper.GetSelectedMediaItem(0, 0)
        end
    end
    
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        local retval, saved_val = reaper.GetSetMediaItemInfo_String(item, "P_EXT:Walter_MediaOffsetTool_offset", "", false)
        local saved_ms = 0.0
        if retval and saved_val ~= "" then
            saved_ms = tonumber(saved_val) or 0.0
        end
        
        local display_name = "Unnamed Item"
        local active_take_item = reaper.GetActiveTake(item)
        if active_take_item then
            display_name = reaper.GetTakeName(active_take_item) or "Unnamed Take"
        end
        
        local label = "Item (" .. display_name .. ")"
        if eff_mode == modes.MODE_ITEM_POSITION and num_targets > 1 then
            label = string.format("Item (%s + %d others)", display_name, num_targets - 1)
        end
        reaper.ImGui_Text(ctx, label .. " Position Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, string.format("%.1f ms", saved_ms))
    else
        reaper.ImGui_Text(ctx, "Item Position Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No item selected")
    end

    -- 4. MIDI Note Offset (Always visible)
    if has_notes and active_take then
        local num_selected = #gui_state.selected_targets
        local display_str = "0.0 ms"
        if num_selected > 0 then
            local first_offset = gui_state.selected_targets[1].offset_ms or 0.0
            local all_same = true
            for i = 2, num_selected do
                local offset = gui_state.selected_targets[i].offset_ms or 0.0
                if math.abs(offset - first_offset) > 0.01 then
                    all_same = false
                    break
                end
            end
            if all_same then
                display_str = string.format("%.1f ms", first_offset)
            else
                display_str = "Multiple values"
            end
        end
        
        local label = string.format("MIDI Notes (%d selected)", num_selected)
        reaper.ImGui_Text(ctx, label .. " Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, display_str)
    else
        reaper.ImGui_Text(ctx, "MIDI Note Offset:")
        reaper.ImGui_SameLine(ctx, 240)
        reaper.ImGui_Text(ctx, "No notes selected")
    end

    -- 5. Dynamic Mode Details (Move Item position)
    if eff_mode == modes.MODE_ITEM_POSITION then
        local first_info = gui_state.selected_targets[1]
        if first_info and reaper.ValidatePtr(first_info.item, "MediaItem*") then
            local cur_pos_sec = reaper.GetMediaItemInfo_Value(first_info.item, "D_POSITION")
            local display_name = first_info.name
            if num_targets > 1 then
                display_name = string.format("%s (+ %d others)", first_info.name, num_targets - 1)
            end
            reaper.ImGui_Text(ctx, "Move Item (" .. display_name .. ") Pos:")
            reaper.ImGui_SameLine(ctx, 240)
            reaper.ImGui_Text(ctx, string.format("%.3f s", cur_pos_sec))
        end
    end
end

return UIInfoPanel
