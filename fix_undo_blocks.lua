-- Corrected undo block management for slider interaction
-- This fixes the misleading undo names and incomplete undo block management

-- Add a variable to track undo state globally in the script
local undo_block_active = false

-- Function to safely begin an undo block
function safe_undo_begin(description)
    if not undo_block_active then
        reaper.Undo_BeginBlock()
        undo_block_active = true
    end
end

-- Function to safely end an undo block
function safe_undo_end(description)
    if undo_block_active then
        reaper.Undo_EndBlock(description or "Legato Tool Operation", -1)
        undo_block_active = false
    end
end

-- Function to ensure all active undo blocks are closed (for script termination)
function ensure_undo_blocks_closed()
    if undo_block_active then
        reaper.Undo_EndBlock("Legato Tool (cancelled)", -1)
        undo_block_active = false
    end
end

-- Modified slider interaction code (replacing lines ~949-979):
-- Handle legato slider interaction for real-time feedback
local value_changed = new_legato_amount ~= legato_amount
local is_activated = imgui.IsItemActivated(ctx)
local is_active = imgui.IsItemActive(ctx)
local is_deactivated_after_edit = imgui.IsItemDeactivatedAfterEdit(ctx)

-- Build cache when slider interaction starts (when starting to drag)
if is_activated then
    safe_undo_begin("Adjust legato amount")
    drag_start_legato_amount = legato_amount  -- Store the value at drag start
    drag_start_note_states = build_notes_cache()  -- Store the note states at drag start
    notes_cache = drag_start_note_states  -- Use the drag start states as the reference
end

if value_changed then
    -- Update legato_amount first
    legato_amount = new_legato_amount

    if selected_note_count >= 2 then
        if is_active and #notes_cache > 0 then
            -- Currently dragging, apply delta from initial state
            apply_legato(notes_cache)
        else
            -- Not dragging, apply to current state (no delta)
            local temp_cache = build_notes_cache()
            apply_legato(temp_cache)
        end
    end
end

-- Clear the cache when the slider is not active to prevent memory buildup
-- But only when not actively dragging (to preserve the cache during dragging)
if not imgui.IsItemActive(ctx) and not imgui.IsItemActivated(ctx) and #notes_cache > 0 then
    notes_cache = {}
end

if is_deactivated_after_edit then
    -- End the undo block that was started on activation
    safe_undo_end("Adjust legato amount")
end

-- Apply button after legato slider - also needs to use safe functions
if selected_note_count >= 2 then
    if imgui.Button(ctx, "Apply") then
        safe_undo_begin("Apply legato changes")
        -- Update the drag start reference to current state for future delta calculations
        drag_start_legato_amount = legato_amount  -- Set baseline to current value
        drag_start_note_states = build_notes_cache()  -- Capture current visual state
        legato_amount = 0  -- Reset slider to 0
        humanize_strength = 0  -- Reset humanize strength to default

        -- Also reset any other drag-related states to maintain consistency
        -- If we're currently dragging, make sure to clear the cache
        if #notes_cache > 0 then
            notes_cache = {}
        end
        safe_undo_end("Apply legato changes")
    end
end

-- In the main loop function, add cleanup for script termination:
function loop()
    if not script_running then
        -- Ensure any active undo blocks are closed before terminating
        ensure_undo_blocks_closed()

        -- Clean up caches when the script is terminated to prevent memory leaks
        notes_cache = {}
        drag_start_note_states = {}
        -- Reset all state variables when script terminates
        legato_amount = 0
        humanize_strength = 0
        return
    end

    -- Rest of the existing loop function code...