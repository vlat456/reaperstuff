carefully analyze MIDI_Advanced_Legato script and all it imports for coding style, quirks and gather context.

- We need to make script with UI. Example is MIDI_Advanced_Legato.
- Script should move or copy selected notes up or down by selected interval.
- There should be radio button "Move" and "Copy". When user choices "Move" - script is moving notes, when choices "Copy" - copies notes.
- There should be row of buttons with intervals. "2nd, third, major third, forth... etc.". All intervals that exist. There should be + or - sing before interval symbol, indicating it will be moved up or down, as described in next entry.
- There should be radio button "+" and "-". When user choices "+" - notes are copied or moved up by selected interval. When choices "-" - notes are copied or moved down by selected interval.
- No MessageBox-es should be shown for warnings
- Existing modules in modules directory should be reused to DRY. No changes are allowed in these modules, they're working perfectly now.
