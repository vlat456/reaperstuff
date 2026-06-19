# reaperstuff — Agent Context

## Project Overview

ReaScripts for [REAPER DAW](https://reaper.fm), distributed via ReaPack. Repository: `github.com/vlat456/reaperstuff`.

Two MIDI editing tools under `MIDI_Tools/`, each with a ReaImGui GUI:

| Script | Purpose | Key Features |
|---|---|---|
| `Combined_CC_Tool.lua` | MIDI CC cleanup | Remove redundant CCs, smooth selected CCs, redundancy threshold slider |
| `Legato_Tool.lua` | MIDI note legato | Extend note durations, fill gaps between notes, detect/heal overlapped same-pitch notes, boundary constraints |

## Codebase Structure

```
/
├── MIDI_Tools/
│   ├── Combined_CC_Tool.lua      # ~500+ lines - CC removal + smoothing
│   └── Legato_Tool.lua           # ~700+ lines - legato + gap fill + overlay handling
├── GEMINI.md                     # Combined CC Tool development summary
├── legato_tool_progress.md       # Legato Tool enhancements log
├── legato_tool_audit.md          # Legato Tool audit findings + fixes
├── Combined_CC_Tool_Analysis.md  # Combined CC Tool analysis + fixes
├── api_complete.txt              # REAPER API reference (read-only reference)
├── index.xml                     # ReaPack package index
└── AGENTS.md                     # THIS FILE - agent context
```

## Technical Stack

- **Language**: Lua 5.x (REAPER's embedded Lua)
- **GUI**: ReaImGui (`reaper.ImGui_GetBuiltinPath()` + `require('imgui')('0.9.3')`)
- **Distribution**: ReaPack (via `index.xml` with GitHub raw URLs)
- **Host**: REAPER DAW (Windows/macOS/Linux)

## Coding Conventions

- **Headers**: ReaPack-compatible `-- @description`, `-- @author`, `-- @version`, `-- @about` blocks
- **ImGui**: Use `reaper.ImGui_*` prefix for all ImGui calls (e.g., `reaper.ImGui_PushStyleColor`, `reaper.ImGui_ColorConvertDouble4ToU32`), NOT the `imgui.*` shorthand
- **Context**: `get_midi_context()` pattern — fetch active MIDI editor, take, and lane in a single function
- **Safety**: Always check `reaper.ImGui_GetBuiltinPath` before using ImGui; display error MessageBox if missing
- **Error handling**: Safety counters (10k limit) on MIDI enumeration loops; nil-check API returns
- **Caching**: Validate cache state with flags (e.g., `selected_ccs_cache_valid`, `notes_cache_valid`); invalidate on context change
- **Undo**: Wrap destructive operations in `reaper.Undo_BeginBlock()` / `reaper.Undo_EndBlock()`; execute guard clauses before `BeginBlock` to avoid empty undo points
- **PPQ conversions**: Use `TimeMap2_GetDividedBpmAtTime()` for tempo-dependent calculations (not master tempo)

## Known Patterns & Gotchas

- `MIDI_EnumNotes` does NOT exist — use `MIDI_EnumSelNotes` only
- Color conversion: `reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a)` for 32-bit RGBA
- Cached slider drag pattern: capture original state on `imgui.IsItemActivated`, compute delta on each frame while `imgui.IsItemActive`, commit on `IsItemDeactivatedAfterEdit`
- Two-pass deletion pattern for removing CCs: first collect indices, then delete in reverse to avoid index shifting

## Git Workflow

- `main` branch is the primary development branch
- `release` branch exists for release merges
- Commits follow conventional commit style (`feat:`, `fix:`, `refactor:`, `cleanup:`)
- Remote: `git@github.com:vlat456/reaperstuff.git`

## Documentation Files

Non-code files in the root are project documentation, NOT part of the distributed ReaPack package:
- `*_Analysis.md`, `*_audit.md`, `*_progress.md` — development notes and issue tracking
- `api_complete.txt` — REAPER API function signatures (auto-generated reference)
- `GEMINI.md` — historical session summary

## When Working Here

1. Read the relevant script(s) fully before editing — they are moderate length but logic-dense
2. Check `index.xml` if adding new scripts or changing metadata
3. Test ReaImGui calls with `lsp_diagnostics` is not available for Lua — run in REAPER to verify
4. Always preserve ReaPack header comments
5. Keep scripts self-contained (no external module dependencies beyond ReaImGui)
6. **After every edit to `Media_Tools/`**, deploy to the REAPER working directory:
   ```bash
   rsync -av Media_Tools/Media_Offset_Tool.lua \
     "/Users/vladimir/Library/Application Support/REAPER/Scripts/Walter Scripts/Media_Tools/"
   rsync -av --delete Media_Tools/modules/ \
     "/Users/vladimir/Library/Application Support/REAPER/Scripts/Walter Scripts/Media_Tools/modules/"
   ```
