# Legato Tool.lua Audit Report

## Overview
An audit of the Legato Tool.lua script to identify potential flaws, issues, and areas for improvement.

## Identified Issues

### 1. Potential Infinite Loop in MIDI Processing
**Location:** `get_selected_notes()` and `build_notes_cache()` functions
**Issue:** The `reaper.MIDI_EnumSelNotes()` function is used in a while loop, but if there are issues with the MIDI data structure, this could potentially cause an infinite loop.
**Recommendation:** Add a safety counter to prevent infinite loops.

### 2. Potential Race Conditions with Caching
**Location:** Cache handling in the main loop
**Issue:** The `notes_cache` and related variables are accessed and modified in multiple parts of the main loop without explicit synchronization. While this might be safe in REAPER's single-threaded context, it could lead to unexpected behavior in edge cases.
**Recommendation:** Better state management and validation of cache state.

### 3. Memory Leak Potential
**Location:** Cache management
**Issue:** If the script encounters errors or unexpected states, the caches may not be properly cleared, potentially leading to memory accumulation over time.
**Recommendation:** Ensure cache cleanup in error scenarios and add cache size monitoring.

### 4. Incorrect Delta Calculation Logic
**Location:** `apply_legato()` function
**Issue:** The delta calculation `delta_ms = legato_amount - drag_start_legato_amount` may not correctly handle all scenarios where the drag_start_legato_amount is updated outside of dragging sessions.
**Recommendation:** Review the state transitions between dragging, applying, and resetting.

### 5. Boundary Checking Logic
**Location:** `apply_legato()` function, item boundary constraint
**Issue:** The item boundary constraint only limits to the item's end time but doesn't consider the item's start time. This could cause issues if notes are moved before the item start.
**Recommendation:** Add constraint for both start and end boundaries.

### 6. Tempo Change Handling
**Location:** `apply_legato()` function where tempo is used for MS to PPQ conversion
**Issue:** The script fetches tempo using `reaper.Master_GetTempo()` which gets the tempo at the project's start, not necessarily the tempo at the specific time where the MIDI item is located, which could be incorrect if the project has tempo changes.
**Recommendation:** Use time-based tempo functions to get the correct tempo at the item's location.

### 7. Missing Error Handling
**Location:** Throughout the script
**Issue:** Several API calls don't have proper error checking. For example, `reaper.MIDI_GetNote()` and other MIDI functions can fail, but the script doesn't check return values.
**Recommendation:** Add error checking for all critical API calls.

### 8. State Inconsistency
**Location:** Variable reset on Apply button press
**Issue:** When Apply button is pressed, only `drag_start_legato_amount` and `legato_amount` are reset, but `drag_start_note_states` is updated. This could lead to state inconsistency issues.
**Recommendation:** Clear or reset all related state variables consistently.

### 9. Performance Concerns
**Location:** `apply_legato()` function when dragging
**Issue:** The function processes all notes in the loop, which could be slow for MIDI items with many notes. This is called frequently during dragging.
**Recommendation:** Optimize for performance or consider limiting update frequency.

### 10. PPQ Position Validation
**Location:** Throughout the script when calculating new end positions
**Issue:** New end positions are calculated but not validated against valid ranges or checked for potential integer overflow in PPQ values.
**Recommendation:** Add validation for PPQ position calculations.

## Code Quality Issues

### 11. Unused Variable
**Location:** `last_clicked_cc_lane` variable
**Issue:** This variable is set but appears unused in the current implementation (inherited from the skeleton code).
**Recommendation:** Remove unused variable or implement its intended functionality.

### 12. Hardcoded Tempo Assumption
**Location:** MS to PPQ conversion in `apply_legato()`
**Issue:** The conversion assumes 480 PPQ at 120 BPM, which may not be accurate for all projects.
**Recommendation:** Use `reaper.MIDI_GetPPQ()` or similar functions to get the actual PPQ value.

## Recommendations

1. Add comprehensive error handling for all Reaper API calls
2. Implement safety mechanisms to prevent infinite loops
3. Add validation for all PPQ position calculations
4. Improve tempo handling for projects with tempo changes
5. Optimize performance for large MIDI files
6. Add proper state management and cleanup
7. Validate PPQ boundaries on both start and end
8. Remove unused variables
9. Add proper documentation for all functions
10. Add unit tests for critical functions

## Severity Assessment

- **Critical:** Issues 1, 4, 6 - Could cause crashes or incorrect behavior
- **High:** Issues 3, 5, 7, 8 - Could cause data corruption or incorrect results
- **Medium:** Issues 2, 9 - Could cause performance or consistency issues
- **Low:** Issues 10, 11 - Minor code quality issues