-- @description Toggle Bypass FX 1-16
-- @author drvlat
-- @version 1.0.0
-- @about
--   Toggles the bypass state for the first 16 FX slots (indices 0 to 15) on the selected track.
--   If any of these FX are currently active, they will all be bypassed.
--   If all of them are already bypassed, they will all be enabled.
-- @provides
--   [main=main] Toggle_Bypass_FX_1-16.lua

local reaper = reaper

local function main()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then return end
  
  local num_fx = reaper.TrackFX_GetCount(track)
  if num_fx == 0 then return end
  
  -- Target range: first 16 slots (indices 0 to 15)
  local limit = math.min(num_fx, 16)
  
  -- Determine target state
  local any_enabled = false
  for i = 0, limit - 1 do
    if reaper.TrackFX_GetEnabled(track, i) then
      any_enabled = true
      break
    end
  end
  
  -- Toggle logic
  local target_enabled = not any_enabled
  
  reaper.Undo_BeginBlock()
  for i = 0, limit - 1 do
    reaper.TrackFX_SetEnabled(track, i, target_enabled)
  end
  reaper.Undo_EndBlock("Toggle Bypass FX 1-16", -1)
end

main()
