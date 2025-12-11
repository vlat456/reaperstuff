# FX State Management Scripts Documentation

This project contains two REAPER scripts for managing the state of track FX inserts:

## Script 1: offline_all_track_inserts.lua

This script:
1. Saves the current state of all FX on selected tracks (or all tracks if none selected)
2. The saved state includes:
   - Whether each FX slot was bypassed
   - Whether each FX slot was already offline
   - The name of each FX
3. Offlines all FX inserts on the processed tracks
4. Stores the original state in track metadata using P_EXT property
5. Works on selected tracks, or all tracks if none are selected

## Script 2: restore_track_inserts_state.lua

This script:
1. Reads the saved FX state from track metadata
2. Restores the bypass and offline state of each FX that still exists
3. Skips any FX slots that were removed between offline and restore operations
4. Clears the saved state from track metadata after restoration
5. Works on selected tracks, or all tracks if none are selected

## How to Use

1. First, arrange your tracks with the FX configuration you want to temporarily offline
2. Run "offline_all_track_inserts.lua" to save states and offline all FX
3. Perform your audio processing without FX load
4. Run "restore_track_inserts_state.lua" to restore all FX to their previous state

## Features

- Preserves original bypass states
- Preserves original offline states  
- Handles missing FX slots gracefully
- Works with selected tracks or all tracks
- Proper undo support
- Metadata stored in track properties for persistence
