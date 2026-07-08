# reaperstuff — Agent Context

## Project Overview

ReaScripts for [REAPER DAW](https://reaper.fm), distributed via ReaPack.
Repository: `github.com/vlat456/reaperstuff`.

This repository hosts a collection of advanced MIDI editing utilities, track-level media offsets, FX chain control tools, and visual organization utilities for REAPER DAW.

## Codebase Structure

```
/
├── ColorTool/
│   ├── Color_Tool.lua            # Custom color picker & palette manager (ReaImGui)
│   └── palettes/                 # Preset color palettes (.colorpalette)
├── FX/
│   ├── Track_FX_Bypass_Manager.lua  # UI-based FX chain bypass manager (ReaImGui)
│   ├── Kontakt_Tune_Humanizer.lua   # Humanizes Kontakt Tune Host parameter
│   ├── kontakt_tune_humanizer_package.lua  # Package definition
│   └── Toggle_Bypass_FX_*.lua    # Quick scripts to toggle bypass on specific FX slots
├── MIDI_Tools/
│   ├── MIDI_Toolbox_Advanced_Legato.lua # Advanced legato, gap fill, overlap heal (ReaImGui)
│   ├── MIDI_Toolbox_CC_Optimizer.lua    # CC redundancy cleanup & smoothing (ReaImGui)
│   ├── MIDI_Toolbox_Find_Parallels.lua   # Finds parallel intervals (alpha)
│   ├── MIDI_Toolbox_Note_Mover.lua       # Transposes/copies notes by fixed intervals (ReaImGui)
│   ├── MIDI_Toolbox_Quick_Heal_Overlays.lua # Macro to resolve overlaps (no UI)
│   ├── MIDI_Toolbox_Quick_Legato.lua    # Macro to apply default legato (no UI)
│   ├── MIDI_Toolbox_Quick_NonLegato.lua # Macro to clear legato (no UI)
│   ├── MIDI_toolbox_package.lua  # Metapackage description for ReaPack
│   ├── modules/                  # Shared Lua modules (legato_common.lua, parallel_detector.lua, etc.)
│   └── tests/                    # Testing scripts for various MIDI scenarios
├── Media_Tools/
│   ├── Media_Offset_Tool.lua     # Micro-timing offset tool (Take Start, Track Playback, Item Pos, Note Override)
│   ├── Selective_Freeze_Tool.lua # Renders/freezes items selectively by disabling/enabling specific FX plugins
│   ├── modules/                  # Modular Lua UI and engine modules supporting Media_Offset_Tool.lua
│   └── tests/                    # Tests folder for Media Offset functions
├── Offline_Restore_FX/
│   ├── offline_all_track_fx.lua  # Offlines all FX across tracks and saves state in metadata
│   ├── restore_all_track_fx.lua  # Restores track FX bypass/active states from track metadata
│   └── offline_restore_package.lua # Metapackage index for ReaPack
├── api_complete.txt              # REAPER API function signatures (read-only reference)
├── index.xml                     # ReaPack package index
├── PROJECT_DOCUMENTATION.md      # Historical structure documentation
├── GEMINI.md                     # Combined CC Tool historical session summary
├── NoteMover.md                  # Development completion log for Note Mover
├── legato_tool_progress.md       # Legato Tool enhancements log
├── legato_tool_audit.md          # Legato Tool audit findings + fixes
├── Combined_CC_Tool_Analysis.md  # Combined CC Tool analysis + fixes
└── AGENTS.md                     # THIS FILE - agent context
```

## Technical Stack

- **Language**: Lua 5.x (REAPER's embedded Lua)
- **GUI**: ReaImGui (`reaper.ImGui_GetBuiltinPath()` + `require('imgui')('0.9.3')`)
- **Distribution**: ReaPack (via `index.xml` with GitHub raw URLs)
- **Host**: REAPER DAW (Windows/macOS/Linux)

## Coding Conventions

- **Headers**: ReaPack-compatible metadata headers (e.g. `-- @description`, `-- @author`, `-- @version`, `-- @about`, `-- @provides`, `-- @metapackage`) at the top of main and package scripts.
- **ImGui Namespacing**: Use the full `reaper.ImGui_*` prefix for all ImGui calls (e.g., `reaper.ImGui_PushStyleColor`, `reaper.ImGui_ColorConvertDouble4ToU32`), NOT the `imgui.*` shorthand.
- **Context Fetching**: Use unified context fetching functions (like `get_midi_context()`) to retrieve the active editor, take, and selected notes in a single query.
- **Safety Checks**: Always check that `reaper.ImGui_GetBuiltinPath` is available before trying to load ReaImGui. If missing, show a standard REAPER `ShowMessageBox` error.
- **Error Prevention**: Keep safety counters (e.g., `safety < 10000`) on MIDI event loop enumerations to avoid infinite lockups. Null-check values returned by REAPER APIs.
- **Caching**: Implement validation flags (`notes_cache_valid`, etc.) to skip heavy selection re-scans when the user has not modified the selection. Invalidate caches when the active context changes.
- **Undo Management**: Wrap all state-changing operations in `reaper.Undo_BeginBlock2(0)` and `reaper.Undo_EndBlock2(0, "description", -1)`. Ensure guard clauses (checking if targets are present) run *before* opening the undo block to prevent empty undo points.
- **Tempo/PPQ Conversions**: Use `TimeMap2_GetDividedBpmAtTime()` for tempo-dependent conversions rather than the project-wide master tempo, ensuring tempo map adjustments are respected.

## Known Patterns & Gotchas

- `MIDI_EnumNotes` is not a valid REAPER API — use `MIDI_EnumSelNotes` instead to find selected notes.
- Color conversion: Use `reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a)` to pack colors for ImGui.
- **Non-blocking Preview Slider Pattern**:
  - Capture original state on `imgui.IsItemActivated` (or `reaper.ImGui_IsItemActivated`).
  - Compute offset delta and apply temporary values in real-time while `imgui.IsItemActive`.
  - Revert temporary offset, start a clean undo block, and apply the final offset on `IsItemDeactivatedAfterEdit`.
- **Safe deletion**: When deleting MIDI events/CCs, first collect indices of target events in a list, then delete them in reverse index order to avoid index shifts.

## Git Workflow

- `main` is the primary development branch.
- `release` is used for release merges.
- Commits follow conventional commit style (`feat:`, `fix:`, `refactor:`, `cleanup:`).
- Remote: `git@github.com:vlat456/reaperstuff.git`

## When Working Here

1. Read relevant scripts and modules fully before modifying — they are logic-dense.
2. Update `index.xml` using ReaPack indexing tools if scripts are added, renamed, or modified.
3. Test ReaImGui calls by running scripts directly inside REAPER, as LSP diagnostics are not fully available.
4. Keep scripts self-contained. Do not rely on external dependencies beyond ReaImGui or the SWS extension.
5. **After editing files under `Media_Tools/`**, deploy them to the local REAPER script directory:
   ```bash
   rsync -av Media_Tools/Media_Offset_Tool.lua \
     "/Users/vladimir/Library/Application Support/REAPER/Scripts/Walter Scripts/Media_Tools/"
   rsync -av --delete Media_Tools/modules/ \
     "/Users/vladimir/Library/Application Support/REAPER/Scripts/Walter Scripts/Media_Tools/modules/"
   ```
