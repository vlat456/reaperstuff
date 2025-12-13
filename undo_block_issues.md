# Undo Block Management Issues in Legato Tool.lua

## Complete List of Undo Block Issues

### 1. Misleading Undo Names
- **Location**: Lines 949 and 979 in the slider interaction code
- **Issue**: `reaper.Undo_EndBlock("", -1)` creates an undo block with an empty string name
- **Current Code**:
  ```lua
  if imgui.IsItemActivated(ctx) then
      reaper.Undo_BeginBlock()
      -- ... slider activation code ...
  end

  -- Later in the code:
  if imgui.IsItemDeactivatedAfterEdit(ctx) then
      -- End the undo block that was started on activation
      reaper.Undo_EndBlock("", -1)  -- Empty string name!
  end
  ```

### 2. Incomplete Undo Block Management
- **Location**: Slider interaction code (lines ~949-979)
- **Issue**: There's no proper error handling or completion logic if the slider interaction is interrupted (e.g., if the script is terminated while dragging)
- **Current Code Pattern**:
  ```lua
  -- Undo block begins on activation
  if imgui.IsItemActivated(ctx) then
      reaper.Undo_BeginBlock()
      -- ... code ...
  end

  -- Undo block ends on deactivation
  if imgui.IsItemDeactivatedAfterEdit(ctx) then
      reaper.Undo_EndBlock("", -1)
  end
  ```
- **Problem**: If the script terminates while dragging (e.g., user closes window during drag), the undo block never gets closed, which could corrupt the undo stack.

### 3. Duplicate Undo Operations 
- **Location**: Lines 986-987 in the Apply button handler
- **Issue**: The Apply button both creates a new undo block and then immediately ends it, but the slider may already have an active undo block from dragging
- **Current Code**:
  ```lua
  if imgui.Button(ctx, "Apply") then
      -- Create an undo point for the current state
      reaper.Undo_BeginBlock()
      reaper.Undo_EndBlock("Apply legato changes", -1)
      -- ... more code ...
  end
  ```

### 4. Potential Nested Undo Blocks
- **Issue**: The script could potentially create nested undo blocks if a slider change triggers operations that also create undo blocks
- **Example**: Slider dragging calls `apply_legato()` which modifies notes, but there's already an undo block active from the slider activation

## Recommended Fixes

### 1. Fix Empty Undo Names
Replace `reaper.Undo_EndBlock("", -1)` with a descriptive name:
```lua
if imgui.IsItemDeactivatedAfterEdit(ctx) then
    reaper.Undo_EndBlock("Adjust legato amount", -1)
end
```

### 2. Add Proper Cleanup for Script Termination
Add cleanup code in the main loop to ensure undo blocks are closed if the script exits during an active operation:
```lua
function cleanup_on_exit()
    if undo_block_active then  -- Track this state
        reaper.Undo_EndBlock("Legato Tool (cancelled)", -1)
    end
end
```

### 3. Prevent Nested Undo Blocks
Track undo state to avoid creating nested blocks:
```lua
local undo_block_active = false

-- When starting undo:
if not undo_block_active then
    reaper.Undo_BeginBlock()
    undo_block_active = true
end

-- When ending undo:
if undo_block_active then
    reaper.Undo_EndBlock("description", -1)
    undo_block_active = false
end
```

### 4. Handle Script Exit Scenarios
Ensure that if the script exits during dragging (e.g., via Escape key), any active undo blocks are properly closed.