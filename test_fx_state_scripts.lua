-- @description Test script to verify FX state saving/restoring functionality
-- @author Vladimir
-- @version 1.0
-- @about
--   This script creates a simple test environment to verify that
--   the offline and restore scripts work correctly.

local reaper = reaper

function main()
  reaper.Undo_BeginBlock()
  
  -- Create a new track for testing
  reaper.InsertTrackAtIndex(0, true)  -- Create a new track at index 0
  local track = reaper.GetTrack(0, 0)  -- Get the first track
  
  if track then
    reaper.SetTrackName(track, "Test Track for FX State Scripts")
    
    -- Add a simple ReaEQ to the track (if available) so we have an FX to test with
    reaper.TrackFX_AddByName(track, "ReaEQ", false, -1)
    
    reaper.ShowMessageBox("Test track created with name 'Test Track for FX State Scripts'.\n\nYou can now test the offline/restore scripts on this track.", "Test Environment Created", 0)
  end
  
  reaper.Undo_EndBlock("Create test environment", -1)
end

main()