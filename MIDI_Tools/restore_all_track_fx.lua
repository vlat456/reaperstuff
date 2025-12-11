-- @description Restore track inserts state from saved metadata
-- @author drvlat
-- @version 0.0.1
-- @about
--   This script restores the state of all FX inserts on selected tracks
--   using the metadata saved by the offline script.
--   If FX slots were deleted between offline and online states, they are skipped.

local reaper = reaper

function RestoreTrackFXState(track)
  -- Get the saved state from track metadata
  local retval, saved_state_str = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:OfflineAllFX_State", "", false)

  if not retval or not saved_state_str or saved_state_str == "" then
    return
  end

  -- Parse the saved state
  local saved_states = {}
  local fx_strings = {}

  -- Split by "|" to get individual FX states
  for part in saved_state_str:gmatch("[^|]+") do
    table.insert(fx_strings, part)
  end

  -- Parse each FX state
  for i, fx_str in ipairs(fx_strings) do
    local parts = {}
    for part in fx_str:gmatch("[^,]+") do
      table.insert(parts, part)
    end

    local fx_index = i - 1  -- Convert to 0-based index since we're processing sequentially
    if #parts >= 2 then
      saved_states[fx_index] = {
        bypassed = parts[1] == "true",
        offline = parts[2] == "true",
        name = parts[3] or ""
      }
    end
  end

  -- Get current number of FX
  local current_fx_count = reaper.TrackFX_GetCount(track)

  -- Count how many saved states we have (since # operator doesn't work well with 0-based indices)
  local saved_count = 0
  for k, v in pairs(saved_states) do
    saved_count = saved_count + 1
  end

  local max_index = math.min(saved_count, current_fx_count)

  -- Restore the state for each FX that still exists
  for i = 0, max_index - 1 do
    if saved_states[i] then
      -- Set bypass state (enabled=true means not bypassed)
      if saved_states[i].bypassed then
        reaper.TrackFX_SetEnabled(track, i, false)  -- Set to bypassed
      else
        reaper.TrackFX_SetEnabled(track, i, true)   -- Set to enabled (not bypassed)
      end

      -- Set offline state
      reaper.TrackFX_SetOffline(track, i, saved_states[i].offline)
    end
  end

  -- Clear the saved state from track metadata
  reaper.GetSetMediaTrackInfo_String(track, "P_EXT:OfflineAllFX_State", "", true)
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
        RestoreTrackFXState(track)
      end
    end
  else
    -- Process only selected tracks
    for i = 0, track_count - 1 do
      local track = reaper.GetSelectedTrack(0, i)
      if track then
        RestoreTrackFXState(track)
      end
    end
  end

  reaper.Undo_EndBlock("Restore track FX state from saved metadata", -1)
  reaper.UpdateArrange()
end

main()