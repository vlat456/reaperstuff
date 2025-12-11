-- @noindex

local reaper = reaper

function SaveAndOfflineTrackFX(track)
  local num_fx = reaper.TrackFX_GetCount(track)
  local fx_states = {}

  -- Check if we already have saved state - if so, return
  local has_saved_state = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:OfflineAllFX_State", "", false)
  if has_saved_state and has_saved_state ~= "" then
    return num_fx
  end

  -- Get current states of all FX
  for i = 0, num_fx - 1 do
    -- Get if FX is bypassed (TrackFX_GetEnabled returns false when bypassed)
    local is_bypassed = not reaper.TrackFX_GetEnabled(track, i)

    -- Get if FX is offline
    local is_offline = reaper.TrackFX_GetOffline(track, i)

    -- Get FX name for reference
    local _, fx_name = reaper.TrackFX_GetFXName(track, i)

    fx_states[i] = {
      bypassed = is_bypassed,
      offline = is_offline,
      name = fx_name
    }
  end

  -- Save the state to track metadata
  local state_str = ""
  for i = 0, num_fx - 1 do
    if i > 0 then
      state_str = state_str .. "|"
    end
    local state = fx_states[i]
    state_str = state_str .. tostring(state.bypassed) .. "," .. tostring(state.offline) .. "," .. (state.name or "")
  end

  -- Store the original state in the track's extended data using P_EXT
  reaper.GetSetMediaTrackInfo_String(track, "P_EXT:OfflineAllFX_State", state_str, true)

  -- Now offline all FX
  for i = 0, num_fx - 1 do
    reaper.TrackFX_SetOffline(track, i, true)
  end

  return num_fx
end

function main()
  reaper.Undo_BeginBlock()

  local track_count = reaper.CountSelectedTracks(0)
  if track_count == 0 then
    track_count = reaper.CountTracks(0)
    -- If no tracks selected, process all tracks
    for i = 0, track_count - 1 do
      local track = reaper.GetTrack(0, i)
      if track then
        SaveAndOfflineTrackFX(track)
      end
    end
  else
    -- Process only selected tracks
    for i = 0, track_count - 1 do
      local track = reaper.GetSelectedTrack(0, i)
      if track then
        SaveAndOfflineTrackFX(track)
      end
    end
  end

  reaper.Undo_EndBlock("Offline all track FX and save state", -1)
  reaper.UpdateArrange()
end

main()