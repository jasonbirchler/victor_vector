# Vector Sequencer for Norns - Implementation Plan

## Overview
A 5x5 grid-based vector sequencer for Monome Norns, inspired by the D:Machinery Vector Sequencer concept. The sequencer navigates a toroidal 5x5 grid using vector-based movement, where each cell contains musical parameters.

## Core Architecture

### Data Structures

```lua
-- Cell structure (per grid position)
cells[x][y] = {
    note = 60,        -- MIDI note number (0-127)
    velocity = 100,   -- MIDI velocity (0-127)
    duration = 0.5,   -- Note duration in beats
    active = true     -- Whether cell plays when visited
}

-- Vector movement parameters (global)
vectors = {
    reset_x = 1,      -- Reset position X (1-5)
    reset_y = 1,      -- Reset position Y (1-5)
    xt = 1,           -- X movement interval (every N ticks)
    x = 1,            -- X step size
    yt = 1,           -- Y movement interval (every N ticks)
    y = 0             -- Y step size
}

-- Playback state
state = {
    position = {x=1, y=1},    -- Current grid position
    selected = {x=1, y=1},    -- Currently selected cell for editing
    tick_count = 0,           -- Clock tick counter
    output_mode = "engine",   -- "engine" or "midi"
    playing = false
}
```

### 5x5 Grid on 8x8 Monome
The 5x5 grid is centered on the 8x8 grid:
- Grid columns 2-6 (X: 2,3,4,5,6)
- Grid rows 2-6 (Y: 2,3,4,5,6)
- Grid cell 8,8 used to start/stop sequencer

## UI Interaction Design

### Grid Interaction
- **Press any pad in 5x5 area**: Select that cell for editing
- **Bright LED (15)**: Currently selected cell
- **Medium LED (7)**: Currently playing position (when sequencer running)
- **Dim LED (3)**: Active cells
- **Off**: Inactive cells
- **Blinking Medium LED (7)**: Indicate the sequencer is running; only relevant for cell 8,8

### Norns Screen Layout
## Note Page
```
+--------------------+
| VECTOR SEQUENCER   |  <- Page title
|                    |
| * CELL: [3,4]      |  <- Selected cell coordinates
|   NOTE: C4  (60)   |  <- Note name and MIDI number
|   VEL:  100        |  <- Velocity
|   DUR:  0.5        |  <- Duration
|   ACTIVE: [*]      |  <- Active status
|                    |
|   POS: [2,3]       |  <- Current playback position
|   VECT: Xt=1 X=1   |  <- X movement params
|         Yt=1 Y=0   |  <- Y movement params
+--------------------+
```

## Global Page
```
+------------------+
| Global params    |  <- Page title
|                  |
| * TEMPO: 120     |  
|   OUTPUT: MIDI   |  <- MIDI or Norns engine
+------------------+
```

### Encoder Mapping
- **Enc1**: Navigates pages. Start with 2 pages:
  - Global parameters
    - Tempo
    - Output Mode
  - Note Parameters
    - Cell coordinates
    - Note name and MIDI number
    - Velocity
    - Duration
    - Active status
    - Current playback position
    - Vector params
- **Enc2**: scroll up/down list of params on the selected page. Use an asterisk to indicate currently highlighted param
- **Enc3**: Change the value of the highlighted param

### Key Mapping
- **Key2 (press)**: Toggle active status of selected cell
- **Key3 (press)**: Reset playback position to Reset Vector

### Output Routing
- Global setting to choose between:
  - **PolyPerc engine**: Internal Norns synth
  - **MIDI**: Send note on/off to connected MIDI device

## Vector Movement Algorithm

The sequencer moves through the grid based on the Move Vectors:

1. On each clock tick, increment `tick_count`
2. If `tick_count % xt == 0`, move X by `x` steps (wrap 1-5)
3. If `tick_count % yt == 0`, move Y by `y` steps (wrap 1-5)
4. If new position cell is `active`, trigger note

Example: Xt=2, X=1, Yt=4, Y=1
- Tick 1: Move X (now at [2,1]), Check Yt... no move
- Tick 2: Move X (now at [3,1])
- Tick 3: Move X (now at [4,1])
- Tick 4: Move X (now at [5,1]) AND Move Y (now at [5,2])

## Implementation Phases

### Phase 1: Core Data & Grid
- Define cell data structure
- Implement 5x5 grid display on Monome
- Cell selection via grid presses

### Phase 2: Screen UI & Editing
- Norns screen display of cell data
- Encoder control for pitch/velocity
- Key toggles for active status

### Phase 3: Vector Movement & Playback
- Implement vector movement logic
- Clock-driven playback
- Toroidal wrapping

### Phase 4: Output & Polish
- PolyPerc engine integration
- MIDI output
- Output mode switching
- Final testing

## File Structure
```
vector_seq/
├── vector_seq.lua      # Main script
└── lib/
    └── vseq_utils.lua  # Helper functions (optional)
```

## Norns API References Needed
- `grid` - Grid LED control and key detection
- `screen` - Display drawing
- `clock` - Timing and tempo
- `enc` / `key` - Hardware input handlers
- `engine` - PolyPerc integration
- `midi` - MIDI output
- `params` - Parameter system for settings
