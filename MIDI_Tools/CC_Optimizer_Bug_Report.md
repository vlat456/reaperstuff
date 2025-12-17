# Bug Report: MIDI_Toolbox_CC_Optimizer.lua

## Summary

This report documents bugs and potential issues found in the MIDI_Toolbox_CC_Optimizer.lua file after thorough analysis of the code logic, error handling, memory management, and GUI state management.

## Critical Bugs

### 1. Logic Error in remove_redundant_ccs() Function (Lines 233-246)

**Location**: Lines 233-246 in `remove_redundant_ccs()`
**Issue**: The `first_event_in_lane` flag is incorrectly managed. It's set to `false` outside the conditional block (line 244), which means it will always be false after processing the first CC event, regardless of whether that event was in the target lane or not.

**Current Code**:

```lua
for i = 0, cc_count - 1 do
    local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
    if cc == lane then
        if not first_event_in_lane and math.abs(val - last_event_value) <= gui_state.cc_redundancy_threshold then
            table.insert(redundant_indices, i)
        else
            last_event_value = val
            first_event_in_lane = false
        end
    end
    first_event_in_lane = false  -- BUG: This line should be inside the if block
end
```

**Fix**: Move line 244 inside the conditional block:

```lua
for i = 0, cc_count - 1 do
    local _, _, _, _, _, _, cc, val = reaper.MIDI_GetCC(gui_state.take, i, false, false, 0, 0, 0, 0, 0)
    if cc == lane then
        if not first_event_in_lane and math.abs(val - last_event_value) <= gui_state.cc_redundancy_threshold then
            table.insert(redundant_indices, i)
        else
            last_event_value = val
            first_event_in_lane = false  -- Move this line here
        end
    end
end
```

### 2. Inconsistent Undo Block Management (Lines 373, 466, 503)

**Location**: Multiple functions use `UNDO_MANAGER.begin_undo_block()` but never call `UNDO_MANAGER.end_undo_block()`
**Issue**: The undo blocks are started but never properly closed, which could lead to undo state issues in Reaper.

**Affected Functions**:

- `apply_smoothed_values()` (line 373)
- `apply_noise_filtered_values()` (line 466)
- `convert_to_bezier()` (line 503)

**Fix**: Add `UNDO_MANAGER.end_undo_block()` after the operations are complete:

```lua
-- Example for apply_smoothed_values()
function apply_smoothed_values(smoothed_values)
    if not gui_state.take or #smoothed_values == 0 then return end

    UNDO_MANAGER.begin_undo_block("CC smoothing operation")

    -- Apply all changes in batch
    for i = 2, #gui_state.cc_list_cache - 1 do
        local cc_event = gui_state.cc_list_cache[i]
        if smoothed_values[i] then
            reaper.MIDI_SetCC(gui_state.take, cc_event.idx, true, false, nil, nil, nil, nil, smoothed_values[i], false)
        end
    end

    reaper.MIDI_Sort(gui_state.take)
    UNDO_MANAGER.end_undo_block("CC smoothing operation")  -- ADD THIS LINE

    MIDI_UTILS.register_undo(reaper.GetMediaItemTake_Item(gui_state.take), "Smooth CC events", UNDO_MANAGER)
    reaper.UpdateArrange()
end
```

## Moderate Issues

### 3. Potential Memory Leak in Cache Management (Lines 718-724)

**Location**: `loop()` function, lines 718-724
**Issue**: The cache clearing logic has a condition that might prevent cache clearing in large dataset mode, potentially leading to memory buildup.

**Current Code**:

```lua
if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #gui_state.cc_list_cache > 0 then
    if not gui_state.large_dataset_mode then
        invalidate_all_caches()
    end
end
```

**Issue**: In large dataset mode, the cache is never cleared when the slider becomes inactive, which could lead to memory consumption over time.

**Fix**: Add a periodic cache clearing mechanism for large datasets:

```lua
if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #gui_state.cc_list_cache > 0 then
    if not gui_state.large_dataset_mode then
        invalidate_all_caches()
    else
        -- For large datasets, clear cache periodically (e.g., every 30 seconds)
        local current_time = reaper.time_precise()
        if not gui_state.last_cache_clear or current_time - gui_state.last_cache_clear > 30 then
            invalidate_all_caches()
            gui_state.last_cache_clear = current_time
        end
    end
end
```

### 4. Inconsistent Error Handling in MIDI Operations

**Location**: Throughout the file
**Issue**: Many MIDI operations don't check return values or handle potential errors, which could cause script failures.

**Examples**:

- `reaper.MIDI_GetCC()` calls don't verify if the operation succeeded
- `reaper.MIDI_SetCC()` calls don't check return values
- `reaper.MIDI_DeleteCC()` calls don't verify deletion success

**Recommendation**: Add error checking for critical MIDI operations using the `MIDI_UTILS.safe_execute()` pattern.

### 5. GUI State Inconsistency (Lines 593-595)

**Location**: `loop()` function, lines 593-595
**Issue**: The cache invalidation condition checks for changes in take or lane, but doesn't account for changes in the actual CC events within the take.

**Current Code**:

```lua
if gui_state.take ~= current_take or gui_state.last_clicked_cc_lane ~= current_lane then
    invalidate_all_caches()
end
```

**Fix**: Add additional checks for CC event changes:

```lua
-- Get current CC count to detect changes
local _, _, current_cc_count, _ = reaper.MIDI_CountEvts(current_take, 0, 0, 0)
if gui_state.take ~= current_take or
   gui_state.last_clicked_cc_lane ~= current_lane or
   gui_state.last_cc_count ~= current_cc_count then
    invalidate_all_caches()
    gui_state.last_cc_count = current_cc_count
end
```

## Minor Issues

### 6. Inefficient Redundant CC Calculation (Lines 204-216)

**Location**: `calculate_redundant_ccs()` function
**Issue**: The function iterates through all CC events in the take, even when only a specific lane is needed. This could be inefficient for takes with many CC events.

**Recommendation**: Consider using `reaper.MIDI_EnumSelCC()` or similar lane-specific enumeration methods when possible.

### 7. Magic Numbers in GUI Layout (Lines 764, 838)

**Location**: GUI button width definitions
**Issue**: Magic numbers are used for button widths without explanation or constants.

**Current Code**:

```lua
local preset_width = 80  -- Line 764
local button_width = 50  -- Line 838
```

**Recommendation**: Define these as named constants at the top of the file for better maintainability.

### 8. Missing Validation in Noise Filter (Lines 427-459)

**Location**: `calculate_noise_filtered_values()` function
**Issue**: The function doesn't validate that `gui_state.cc_list_cache` contains valid CC events before processing.

**Recommendation**: Add validation to ensure all cached CC events have valid values before processing.

## Performance Concerns

### 9. Inefficient Cache Rebuilding

**Location**: Multiple functions rebuild the CC cache unnecessarily
**Issue**: Functions like `select_all_ccs_in_lane()`, `filter_cc_noise()`, and preset buttons in the GUI all rebuild the CC cache independently, which could be inefficient.

**Recommendation**: Implement a centralized cache management system that only rebuilds when necessary.

### 10. Frequent GUI Updates During Operations

**Location**: Multiple functions call `reaper.UpdateArrange()` unnecessarily
**Issue**: Some functions call `reaper.UpdateArrange()` multiple times during operations, which could impact performance.

**Recommendation**: Consolidate GUI updates to occur only once at the end of operations.

## Recommendations

1. **Immediate Fixes Required**:

   - Fix the logic error in `remove_redundant_ccs()` (Bug #1)
   - Add proper undo block termination (Bug #2)

2. **High Priority**:

   - Implement consistent error handling for MIDI operations
   - Fix the memory leak in cache management for large datasets
   - Improve GUI state consistency checks

3. **Medium Priority**:

   - Optimize redundant CC calculation
   - Centralize cache management
   - Reduce unnecessary GUI updates

4. **Low Priority**:
   - Replace magic numbers with named constants
   - Add additional validation in noise filtering

## Testing Recommendations

1. Test the redundant CC removal with various CC patterns to verify the logic fix
2. Test undo/redo functionality after applying the undo block fixes
3. Test with large datasets (500+ CC events) to verify memory management
4. Test with rapidly changing MIDI contexts to verify state management
5. Test edge cases like empty lanes, single CC events, and extreme values

## Conclusion

While the MIDI_Toolbox_CC_Optimizer.lua script provides comprehensive CC manipulation functionality, it contains several bugs that could affect its reliability and performance. The most critical issues are the logic error in the redundant CC removal and the incomplete undo block management. Addressing these issues should significantly improve the script's stability and user experience.
