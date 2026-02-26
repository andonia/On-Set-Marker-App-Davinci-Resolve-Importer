# DaVinci Resolve — Marker Importer

Imports markers from a CSV file into the active DaVinci Resolve timeline, with automatic LTC timecode sync.

## Features

- Parses a CSV of markers and stamps them onto the current timeline
- Auto-detects the sync point from a **Session Start** marker in the CSV
- Sets the timeline start timecode to match the recording device's LTC — so scrubbing footage shows real-world time
- Handles quoted fields, Windows line endings, and UTF-8 BOM
- Re-importing is safe — existing markers at the same frame are replaced

## Requirements

- DaVinci Resolve 17 or later (free or Studio)
- macOS (Windows path not currently included in the installer)

## Installation

### macOS (recommended)

1. Download or clone this repository
2. Open **Terminal** and `cd` into the downloaded folder
3. Run:

```bash
bash install.sh
```

The script is copied to:
```
~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/
```

### Manual install

Copy `marker_importer.lua` to one of these directories:

| Scope  | Path |
|--------|------|
| User   | `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/` |
| System | `/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/` |
| Windows | `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility\` |

## Usage

1. Open a project and activate a timeline in the **Edit** page
2. In Resolve, go to **Workspace ▸ Scripts ▸ Utility ▸ marker_importer**
3. Click **Browse…** and select your CSV file
4. Click **Import Markers**

The script auto-detects the **Session Start** row in the CSV to sync timecodes. If your CSV doesn't have one, check **Manual sync override** and enter the LTC and timeline timecodes manually.

## CSV Format

| Column | Required | Description |
|--------|----------|-------------|
| `timecode` | Yes | LTC timecode of the marker (`HH:MM:SS:FF`) |
| `label` | Yes | Short marker name (can be blank) |
| `color` | Yes | Marker color (see accepted values below) |
| `note` | Yes | Longer description shown in the marker |
| `TC IN` | No | Clip in-point timecode (stored for reference) |
| `TC Out` | No | Clip out-point timecode (stored for reference) |
| `Duration` | No | Marker duration in frames, or `HH:MM:SS:FF` (defaults to 1) |

**Accepted colors:** `blue`, `cyan`, `green`, `yellow`, `red`, `pink`, `purple`, `fuchsia`, `magenta`, `rose`, `lavender`, `sky`, `mint`, `lemon`, `sand`, `cocoa`, `cream`

### Example

```csv
timecode,label,color,note,TC IN,TC Out,Duration
14:30:00:00,Session Start,green,Session Start,,,
14:30:15:12,,red,Camera jitter noticed,14:30:15:12,14:30:18:00,
14:31:04:00,Take 1,blue,Good take,14:31:04:00,14:31:22:10,
```

## How sync works

The **Session Start** row in the CSV provides the LTC timecode at a known reference point. The script maps that timecode to frame 0 of the timeline and adjusts the timeline's start TC to match — so the Resolve ruler reads the same time-of-day as the recording device.

If you need to place the sync point at a specific timeline position (rather than the start), use the **Manual sync override** to enter both the LTC timecode and the timeline timecode for that point.
