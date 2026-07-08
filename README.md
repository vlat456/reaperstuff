# Walter Scripts (reaperstuff)

A collection of advanced ReaScripts for [REAPER DAW](https://reaper.fm), focusing on MIDI editing enhancement, track FX management, and visual alignment tools. These scripts are optimized for performance, include undo/redo integration, and feature responsive, modern user interfaces built with **ReaImGui**.

---

## Repository Packages Overview

The repository is organized into five specialized packages:

### 1. 🎹 MIDI Toolbox (`MIDI_Tools/`)
An advanced suite of tools for MIDI editors.
- **Advanced Legato**: Custom legato adjustments, gap filling, overlap resolution, and legato humanization (non-deterministic timing deviations).
- **CC Optimizer**: Removes redundant CC events and smooths selected CC paths with customizable bezier/linear interpolation options.
- **Find Parallels**: Scans MIDI notes and detects parallel intervals (such as octaves and fifths), helpful for music theory analysis and voice leading checks.
- **Note Mover**: Easily transposes or duplicates selected notes by musical intervals (unison, thirds, fifths, octaves, etc.) with a dedicated ImGui panel.
- **Quick/Macro Scripts**: One-click scripts (`Quick_Heal_Overlays`, `Quick_Legato`, `Quick_NonLegato`) to execute common tasks instantly without opening a GUI window.

### 2. 🎛️ Media Tools (`Media_Tools/`)
Timing adjustment and track freezing scripts.
- **Media Offset Tool**: A micro-timing offset utility supporting four modes:
  1. *Take Start Offset*: Adjusts take start offset (`D_STARTOFFS`) within item bounds.
  2. *Track Playback Offset*: Adjusts track delay or advance (`D_PLAY_OFFSET`).
  3. *Move Item Position*: Shifts items along the timeline (optionally syncing envelope points and automation items).
  4. *MIDI Note Offset*: Automatically overrides normal modes when MIDI notes are selected to shift note start/end positions in the MIDI stream, writing offset (`O:`) and preset (`A:`) metadata directly as MIDI Text Events.
  Includes a hierarchical **Preset Board** (Library → Instrument → Articulation) with drag-and-drop custom reordering.
- **Selective Freeze Tool**: Selectively renders/freezes items on a track by toggling specific FX plugins in the chain, allowing you to bake in certain plugins while leaving others active.

### 3. 🎨 Color Tool (`ColorTool/`)
A custom palette viewer and color picker.
- **Color Tool**: Helps color-code tracks, items, or takes.
- **palettes/**: Contains pre-configured color palettes (70s, 80s, default, Studio One colors, etc.) for quick and clean visual layout organization.

### 4. ⚡ FX Tools (`FX/`)
FX bypass and parameter humanization utilities.
- **Track FX Bypass Manager**: Interactive, grid-based panel showing all FX slots on selected tracks to instantly bypass or enable multiple inserts at once.
- **Kontakt Tune Humanizer**: Humanizes pitch tuning on Native Instruments Kontakt instances using a Gaussian probability distribution for more realistic sample playback.
- **Toggle Bypass FX 1-N**: Macros to quickly toggle bypass state across FX slots 1-4, 1-8, 1-12, or 1-16.

### 5. 💾 Offline/Restore FX (`Offline_Restore_FX/`)
System resources management tools.
- **Offline All Track FX**: Saves the current active/bypass state of all FX inserts to track metadata and offlines them, freeing up CPU and RAM.
- **Restore All Track FX**: Restores the previously saved FX bypass and online states from track metadata.

---

## Requirements

To run these scripts, you must have the following installed in REAPER:
1. **ReaImGui** (v0.9.3 or higher) — Required for all GUI-based scripts. Install via ReaPack.
2. **SWS Extension** (v2.12 or higher) — Required for certain FX and configuration utilities. Get it from [sws-extension.org](https://www.sws-extension.org/).

---

## Installation via ReaPack

You can install all Walter Scripts directly within REAPER using **ReaPack**:

1. In REAPER, navigate to **Extensions** → **ReaPack** → **Import repositories...**
2. Paste the following URL:
   ```text
   https://github.com/vlat456/reaperstuff/raw/main/index.xml
   ```
3. Click **OK**.
4. Go to **Extensions** → **ReaPack** → **Browse packages...**, find **Walter Scripts** (or search for a specific tool like `MIDI Toolbox`), right-click and choose **Install**.
5. Click **Apply** to install the scripts.
6. Open your **REAPER Actions List** (`?`), search for the script names, and run them (or assign them to shortcuts).
