# MIDI Note Overlap Resolution Analysis

## Current Implementation in Legato Tool

### Functions Analyzed
- `detect_overlays()` - Finds overlapping notes and selects them
- `heal_overlays()` - Resolves same-pitch overlaps by truncating earlier notes
- `detect_overlays_count()` - Counts overlapping notes without changing selection

### Current Algorithm Details
- Uses sorted selected notes (by start position)
- Nested loop with early termination optimization
- Time complexity: O(n²) worst case, often better due to early termination
- Each same-pitch overlap causes the earlier note to end when the later note starts

## Issues with Current Approach

### Potential Limitations
1. **Complex Overlapping Scenarios**: May not resolve all overlaps in a single pass if there are multiple overlapping notes with complex interdependencies
2. **Convergence**: Single-pass algorithm might miss some edge cases in complex overlap patterns
3. **Guarantee**: No strict guarantee that all overlaps are eliminated after one call

## Recommended Solution for Guaranteed Overlap Elimination

### Iterative Healing Algorithm
To guarantee all overlaps are eliminated with reasonable time complexity:

```lua
function heal_all_overlaps_guaranteed()
    local iterations = 0
    local max_iterations = 100  -- Safety limit
    
    repeat
        invalidate_cached_sorted_notes()  -- Important: invalidate cache after modifications
        
        local initial_overlay_count = detect_overlays_count()
        
        if initial_overlay_count == 0 then
            break  -- No overlaps remain
        end
        
        heal_overlays()  -- Apply healing pass
        
        iterations = iterations + 1
        
        if iterations >= max_iterations then
            reaper.MB("Maximum iterations reached in overlap healing", "Warning", 0)
            break
        end
        
    until detect_overlays_count() == 0
end
```

### Key Points for Implementation
1. **Cache Invalidations**: Must invalidate sorted notes cache after each healing pass
2. **Safety Limits**: Use iteration limits to prevent potential infinite loops
3. **Convergence**: Each healing pass should reduce total overlap duration, ensuring convergence
4. **Performance**: Should converge quickly in typical scenarios

### Iterative Process Details

The algorithm works as follows for each iteration:

1. **Cache Invalidation**: Clear the cached sorted notes to ensure fresh data access after previous modifications
2. **Check for Overlaps**: Count current overlaps using `detect_overlaps_count()`
3. **Early Exit**: If no overlaps detected, terminate the loop
4. **Heal Pass**: Execute one pass of the overlap healing algorithm (`heal_overlaps()`)
5. **Safety Check**: Increment iteration counter and check against maximum allowed iterations
6. **Repeat**: Continue until no overlaps remain or maximum iterations reached

### Handling Complex Overlap Scenarios

#### Single Note with Multiple Overlaps (Overlap Stack)
Example scenario:
- Note A: starts at 0, ends at 1000 (long note)
- Note B: starts at 200, ends at 300 (shorter note)
- Note C: starts at 250, ends at 400 (overlaps with both A and B)

In the first iteration:
- Note A gets shortened to end at 200 (where B starts)
- Note B gets shortened to end at 250 (where C starts)

Subsequent iterations resolve any remaining overlaps until none exist.

#### Multiple Simultaneous Overlaps
Example scenario:
- Note A: starts at 0, ends at 300
- Note B: starts at 100, ends at 200
- Note C: starts at 150, ends at 250

In this case, Note A overlaps with both B and C. The chronological processing ensures proper resolution where each note ends when the next one starts.

#### Iteration Convergence
- Each iteration reduces the total overlap duration
- The algorithm is guaranteed to converge since each healing pass eliminates at least one overlap
- In typical musical content, convergence happens quickly (often in 1-3 iterations)
- Worst-case scenarios with pathological overlap patterns are prevented by the iteration limit

### Edge Cases to Consider

#### Zero-Length Notes
- Healing might create notes where `start_ppqpos ≥ end_ppqpos`
- Should either delete such notes or skip creating them
- Check should be implemented in the note modification step

#### Maximum Iterations Exceeded
- If safety limit reached with overlaps still remaining, warn user
- Consider showing a message box with the number of remaining overlaps
- Algorithm should gracefully terminate

#### Empty Selection
- Handle gracefully when no notes are selected
- Should either return immediately or show appropriate status

#### Single Note Selected
- No overlaps possible with just one note
- Should exit immediately without processing

#### Identical Start Times
- Two notes starting at the same PPQ position need special handling
- Current algorithm should handle this since it checks `note1.endppqpos > note2.startppqpos`
- May require specific tie-breaking logic

#### Dense Overlap Patterns
- Many overlapping notes in a small time window
- Could require many iterations in pathological cases
- Monitor performance with these patterns

#### Mute Status Consideration
- Algorithm may need to respect mute status of notes
- Consider whether to process muted notes the same as unmuted ones
- Could add option to only process unmuted notes

#### Invalid MIDI Data
- Notes with invalid properties (negative durations, out-of-bounds values)
- Should validate note data before processing
- Implement error handling and graceful degradation

## Why BSP Trees Are Not Recommended

### For MIDI Note Overlap Detection:
- BSP trees are designed for multi-dimensional spatial partitioning, not 1D interval problems
- Current sorted array approach with early termination is more efficient for typical MIDI scenarios
- Complexity overhead exceeds benefits for MIDI note counts (typically < 1000)
- Current approach is cache-friendly and already well-optimized

## Performance Characteristics
- **Current approach**: O(n²) worst case but typically much better for musical content
- **Iterative approach**: Still polynomial but with guaranteed convergence to zero overlaps
- **Memory usage**: Minimal additional memory required beyond existing implementation
- **Typical execution time**: Should be instantaneous for normal MIDI note counts

## Recommendations
1. Implement the iterative healing function for guaranteed results
2. Maintain current single-pass function for quick operations where guarantee isn't critical
3. Always invalidate caches after note modifications
4. Add safety mechanisms to prevent infinite loops
5. Consider user feedback during longer operations if needed