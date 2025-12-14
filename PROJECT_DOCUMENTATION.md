# REAPER Scripts Project Documentation

## Project Overview

This project contains a collection of REAPER scripts (ReaScripts) focused on MIDI editing and track FX management. The scripts are distributed via ReaPack with proper versioning and metadata.

## Project Structure

The project is organized into two main categories:

1. **MIDI_Tools** - Scripts for MIDI editing and manipulation
2. **Offline_Restore_FX** - Scripts for managing track FX states

## Detailed Analysis

### 1. MIDI_Tools Category

The MIDI tools provide advanced functionality for MIDI editing within REAPER:

#### Core Scripts:

- **Legato_Tool.lua** - Advanced legato editing tool with UI
- **Combined_CC_Tool.lua** - Tool for removing redundant CCs and smoothing selected CCs
- **Quick Scripts**:
  - Legato_Tool_Quick_Heal.lua - Heal overlapping notes with default settings (no UI)
  - Legato_Tool_Quick_Legato.lua - Fill gaps between selected notes and add 10% legato (no UI)
  - Legato_Tool_Quick_NonLegato.lua - Remove legato effect and add small gaps between notes (no UI)

#### Supporting Module:

- **legato_common.lua** - Shared library containing common functionality used across the legato tools

#### Key Features:

- Legato creation and manipulation with humanization options
- Overlap detection and healing
- Gap filling between notes
- CC (Control Change) event cleanup and smoothing
- Real-time preview of changes during editing
- Undo/redo support
- Selection management and caching for performance

### 2. Offline_Restore_FX Category

Scripts for managing track FX states:

#### Core Scripts:

- **offline_all_track_fx.lua** - Save current FX states and set all tracks to offline
- **restore_all_track_fx.lua** - Restore previously saved FX states from track metadata

#### Key Features:

- Save current FX bypass states to track metadata
- Set all tracks to offline mode
- Restore FX states from saved metadata
- Batch processing of all tracks or selected tracks only

## Package Structure

The project uses ReaPack for distribution with proper package files:

- **legato_package.lua** - Metapackage for MIDI tools
- **offline_restore_package.lua** - Metapackage for FX tools

Both packages include proper metadata, versioning, and changelog information.

## Technical Implementation

- Scripts use ReaImGui for UI components where applicable
- Proper error handling and user feedback
- Efficient caching mechanisms for performance
- Modular design with shared functionality
- Comprehensive undo/redo support

## Recent Improvements

Based on the latest version information in the index.xml file:

### MIDI_Tools (v0.2.4):

- Removed MessageBox warnings for better user experience
- Added Quick_NonLegato script
- Documentation updates
- Extracted common functionality to shared library
- Added quick scripts for common operations
- Implemented guaranteed overlap resolution
- Added non-deterministic humanization

### Combined_CC_Tool (v0.1.5):

- Added redundancy removal quick buttons and visual feedback
- Fixed regression issues
- Implemented working undo functionality

## Distribution

The project appears to be distributed via ReaPack (a REAPER package manager), with the index.xml file containing:

- Package metadata
- Version history
- Source file locations
- Author information (drvlat)

## Potential Future Improvements

1. **Documentation**: Could benefit from more comprehensive inline documentation
2. **Error Handling**: Could implement more robust error recovery mechanisms
3. **User Interface**: Some UI elements could be enhanced for better usability
4. **Performance**: Some operations could be optimized further for large MIDI files
5. **Integration**: Potential for deeper integration between MIDI tools and FX management

## Installation and Usage

### Prerequisites

- REAPER DAW software
- ReaPack package manager
- ReaImGui (for GUI-based scripts)

### Installation

1. Install ReaPack in REAPER if not already installed
2. Add the repository URL to ReaPack
3. Browse and install the desired scripts from the repository

### Usage

- MIDI Tools can be accessed from the REAPER action list or via custom shortcuts
- The Legato Tool provides a GUI for interactive editing
- Quick scripts provide one-click operations without UI
- FX tools can be run from the action list to manage track states

## Code Architecture

### Modular Design

The project follows a modular design pattern with shared functionality extracted into common modules:

- `legato_common.lua` contains shared functions used across multiple legato scripts
- This reduces code duplication and makes maintenance easier

### Caching Strategy

The scripts implement intelligent caching to improve performance:

- Note selection caching to avoid repeated calculations
- Sorted notes caching for efficient processing
- Cache invalidation when MIDI context changes

### Error Handling

The scripts include proper error handling:

- Dependency checking (ReaImGui availability)
- Graceful handling of edge cases (no MIDI editor open, insufficient notes selected)
- User feedback through message boxes and UI indicators

## Conclusion

This project demonstrates good software engineering practices for REAPER scripting, with modular design, proper versioning, and distribution through ReaPack. The scripts provide valuable functionality for MIDI editing and FX management in REAPER, with a focus on user experience and performance.
