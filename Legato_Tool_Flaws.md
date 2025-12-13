# Legato Tool.lua Flaws and Breakable Pieces Analysis

## Major Issues

### 1. Memory Leaks and Caching Problems
- **Global State Persistence**: Variables like `notes_cache`, `drag_start_note_states`, and `last_selected_note_indices` persist in memory between sessions but may not be properly cleaned up, causing memory leaks over time.
- **Cache Validation Issues**: The `notes_cache_valid` flag is defined but never used to validate the cache, leading to potential use of stale or invalid cached data.

### 2. Safety Counter Limitations
- **Arbitrary Hard Limits**: Multiple functions use a hardcoded `max_notes = 10000` safety counter, which could cause issues if a MIDI take contains more than 10,000 notes.
- **Premature Loop Termination**: When the safety counter is hit, loops break early and return partial results, potentially causing incorrect behavior.

### 3. Race Conditions and State Inconsistencies
- **Race Condition in Undo Operations**: When undo/redo occurs, caches are cleared but the GUI might still reference old data, causing potential inconsistencies.
- **State Confusion**: The script tracks multiple similar state variables (e.g., `drag_start_note_states`, `notes_cache`) that could become out of sync.

### 4. Random Number Generation Issues
- **Inconsistent Seeding**: In the `apply_legato` function, `math.randomseed()` is called with time-based seeds during real-time performance, which could cause inconsistent results when the same operation is repeated.

### 5. Error Handling Deficiencies
- **Inadequate Error Recovery**: When `reaper.MIDI_GetNote()` or `reaper.MIDI_SetNote()` fails, the script shows error messages but continues processing, potentially causing cascading failures.
- **Silent Failures**: Some functions don't properly handle failures in Reaper API calls, leading to silent data corruption.

## Moderate Issues

### 6. Temporal Conversion Inaccuracies
- **Project Tempo Calculation**: The tempo calculation assumes constant tempo throughout the project, not accounting for tempo changes that might occur in different sections of the timeline. The current implementation uses `reaper.Master_GetTempo()` as a fallback and `reaper.TimeMap2_GetDividedBpmAtTime(0, item_pos)` for tempo at specific locations, but this only samples the tempo at the item's start position. For notes at different positions in the timeline, different tempo values may apply.
- **Fixed PPQ Assumption**: The script assumes standard 480 PPQ resolution, which may not be accurate for all MIDI files. The conversion formula `ms * tempo * 480 / (60 * 1000)` is based on the default 480 PPQ setting.
- **Inaccurate Time-to-PPQ Conversion**: The current conversion doesn't account for tempo changes that occur between note positions when extending notes. Each note position should use the tempo at its specific time location.

### 7. Boundary Checking Problems
- **Weak Item Boundary Validation**: When checking media item boundaries, the script returns `0, math.huge` on error, which could lead to unexpected behavior when notes are extended to infinity.

### 8. Overlay Detection Logic Flaw
- **Inefficient Algorithm**: The overlay detection algorithm uses O(n²) nested loops and checks all note pairs, which becomes slow with many notes.
- **Sorting Redundancy**: Notes are repeatedly sorted in multiple functions instead of maintaining a sorted cache.

### 9. Undo Block Management
- **Incomplete Undo Blocks**: Some functions begin undo blocks but don't always properly end them, potentially causing undo system issues.
- **Misleading Undo Names**: After applying legato, the Apply button creates an undo block with an empty string name.

## Minor Issues

### 10. User Interface Problems
- **Click Outside Behavior**: Clicking outside the GUI window closes it, which might be unintentional for some users.
- **No Progress Indication**: For operations on large numbers of notes, there's no feedback to the user about ongoing processing.

### 11. Data Type Assumptions
- **Floating Point Precision**: When converting between milliseconds and PPQ, floating point precision issues could cause timing inaccuracies.
- **Integer PPQ Assumptions**: The script treats PPQ values as integers but they might be floating point in some cases.

### 12. Function Redundancy
- **Duplicate Functionality**: `get_selected_notes()` and `build_notes_cache()` are nearly identical functions that could be consolidated.
- **Inconsistent State Updates**: Different functions reset different sets of variables when selection changes, leading to potential inconsistencies.

## Potential Breaking Scenarios

1. **Large MIDI Files**: Files with >10,000 notes would exceed safety limits and cause incomplete processing.
2. **Extreme Tempo Changes**: Projects with dramatic tempo changes would miscalculate timing conversions.
3. **Corrupted MIDI Data**: Invalid or corrupted MIDI files could cause crashes or unpredictable behavior.
4. **Concurrent Modifications**: If MIDI data is modified externally while the script is active, cached data could become invalid.
5. **Memory Pressure**: Long sessions with frequent undo/redo operations could cause memory exhaustion due to poor cleanup.

## Recommendations for Fixes

### Temporal Conversion Fixes
1. **Dynamic Tempo Sampling**: Instead of using a single tempo value for all conversions, create a function that samples tempo at the specific time of each MIDI event. The current formula `ms * tempo * 480 / (60 * 1000)` should be updated to use `reaper.MIDI_GetPPQPosFromProjTime` and `reaper.MIDI_GetProjTimeFromPPQPos` to handle tempo changes accurately.
2. **Correct Time-to-PPQ Conversion**: Replace the static tempo-based conversion with dynamic conversion that accounts for the actual project timeline. Instead of calculating PPQ manually, use Reaper's built-in functions:
   - Convert note positions to time using `MIDI_GetProjTimeFromPPQPos`
   - Add the desired milliseconds to the time value
   - Convert back to PPQ using `MIDI_GetPPQPosFromProjTime`
3. **Use Project-Specific PPQ**: Rather than assuming 480 PPQ, determine the actual PPQ value for the project using configuration variables or Reaper's time mapping functions.

### Other Fixes
4. Implement proper garbage collection and cache invalidation mechanisms
5. Add better error handling and validation throughout
6. **Overlay Detection Optimization**: Replace the O(n²) nested loop algorithm with an efficient O(n log n) sweep line algorithm that uses event-based processing to detect overlapping notes of the same pitch. This includes:
   - Creating start and end events for each note
   - Sorting events by time position
   - Processing events in chronological order while tracking active notes by pitch
   - Using a hash set to track overlay indices for O(1) lookup instead of using `table_contains()`
7. **Undo Block Management Fixes**: Implement proper undo state tracking to prevent incomplete or nested undo blocks:
   - Track undo state with a `undo_block_active` variable
   - Create safe `begin` and `end` functions to prevent nested blocks
   - Use descriptive names for undo blocks instead of empty strings
   - Add cleanup function to ensure all active undo blocks are closed on script termination
8. Add bounds checking for all Reaper API calls
9. Consolidate duplicate functions (`get_selected_notes()` and `build_notes_cache()`)
10. Implement proper progress indication for long operations
11. Fix random seeding to be deterministic for consistent humanization results
12. Add proper safety mechanisms for large MIDI files (allow user to configure or dynamically adjust safety limits)