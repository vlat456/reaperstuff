# Sorting Redundancy Issues in Legato Tool.lua

## Functions with Redundant Sorting Operations

The Legato Tool.lua file has 7 separate instances of sorting notes by start position, creating significant redundancy and performance issues. Each of these functions re-sorts the same data when it could potentially be cached in sorted order.

### 1. build_notes_cache() - Line 125
```lua
table.sort(notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

### 2. get_selected_notes() - Line 173
```lua
table.sort(notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

### 3. detect_overlays() - Line 304
```lua
table.sort(selected_notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

### 4. heal_overlays() - Line 373
```lua
table.sort(selected_notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

### 5. detect_overlays_count() - Line 439
```lua
table.sort(selected_notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

### 6. non_legato() - Line 514
```lua
table.sort(selected_notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

### 7. fill_gaps() - Line 558
```lua
table.sort(selected_notes, function(a, b)
    return a.startppqpos < b.startppqpos
end)
```

## Recommended Solution

Instead of repeatedly sorting notes in multiple functions, implement a cached sorted version:

1. **Create a sorted cache**: When notes are initially retrieved, sort them once and store in a cache
2. **Track cache validity**: Invalidate cache when MIDI selection changes
3. **Provide sorted access function**: Instead of sorting in each function, call a function that returns notes already sorted
4. **Minimize re-sorting**: Only re-sort when the note data changes significantly or selection changes

This would change the time complexity from O(k×n log n) where k is the number of functions that sort, to O(1×n log n) for the initial sort plus O(1) access for subsequent operations.