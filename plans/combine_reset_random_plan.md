# Plan: Combine Reset and Random Params into Single Event Param

## Overview
Replace the separate `reset` (boolean) and `rnd_step` (boolean) cell properties with a single `event` property that has three possible values: "none", "reset", and "random step".

## Changes Required

### 1. Cell Data Structure (line 29-30, 233-246)
**Current:**
```lua
cells[x][y] = { note, velocity, duration, active, xt, x, yt, y, reset, rnd_step }
```

**New:**
```lua
cells[x][y] = { note, velocity, duration, active, xt, x, yt, y, event }
```

**Implementation:**
- In the comment on line 29, update to show `event` instead of `reset, rnd_step`
- In `init()` around line 233-246, replace:
  ```lua
  reset = false,
  rnd_step = false,
  ```
  with:
  ```lua
  event = "none",  -- Options: "none", "reset", "random step"
  ```

### 2. Page Parameters (line 99-114)
**Current:**
```lua
[PAGES.CELL] = {
    -- ... other params ...
    { name = "RESET", key = "reset", options = {"off", "on"}, default = 1 },
    -- ... other params ...
    { name = "RND STEP", key = "rnd_step", options = {"off", "on"}, default = 1 },
    -- ... other params ...
}
```

**New:**
```lua
[PAGES.CELL] = {
    -- ... other params ...
    { name = "EVENT", key = "event", options = {"none", "reset", "random step"}, default = 1 },
    -- ... other params (remove RESET and RND STEP entries) ...
}
```

**Implementation:**
- Remove the `RESET` parameter entry (line 106)
- Remove the `RND STEP` parameter entry (line 110)
- Add the new `EVENT` parameter in place of where RESET was:
  ```lua
  { name = "EVENT", key = "event", options = {"none", "reset", "random step"}, default = 1 },
  ```

### 3. Sequencer Clock Logic (lines 323-335)
**Current:**
```lua
-- Randomize x/y step values if rnd_step is enabled
if cell.rnd_step then
    cell.x = math.random(0, 4)
    cell.y = math.random(0, 4)
end

if cell.active then
    trigger_note(cell)
end

if cell.reset then
    reset_playback()
end
```

**New:**
```lua
if cell.active then
    trigger_note(cell)
end

-- Handle event actions
if cell.event == "random step" then
    cell.x = math.random(0, 4)
    cell.y = math.random(0, 4)
elseif cell.event == "reset" then
    reset_playback()
end
```

**Implementation:**
- Combine the random step logic with the reset logic under the event check
- Check `cell.event == "random step"` instead of `cell.rnd_step`
- Check `cell.event == "reset"` instead of `cell.reset`
- Reorder so note triggering happens first, then event actions

### 4. Parameter Adjustment (lines 640-641, 650-651)
**Current:**
```lua
elseif param.key == "reset" then
    cell.reset = not cell.reset
-- ...
elseif param.key == "rnd_step" then
    cell.rnd_step = not cell.rnd_step
```

**New:**
```lua
elseif param.key == "event" then
    local event_options = {"none", "reset", "random step"}
    local current_idx = 1
    for i, opt in ipairs(event_options) do
        if opt == cell.event then
            current_idx = i
            break
        end
    end
    local new_idx = util.clamp(current_idx + delta, 1, #event_options)
    cell.event = event_options[new_idx]
```

**Implementation:**
- Replace both the reset and rnd_step handlers with a single event handler
- Use delta to cycle through the three options

### 5. Parameter Value Display (lines 767-768, 779-780)
**Current:**
```lua
elseif param.key == "reset" then
    return cell.reset and "ON" or "OFF"
-- ...
elseif param.key == "rnd_step" then
    return cell.rnd_step and "ON" or "OFF"
```

**New:**
```lua
elseif param.key == "event" then
    return cell.event:upper()
```

**Implementation:**
- Replace both with a single handler that returns the event value in uppercase

## Summary of Changes

| Location | Change Type | Description |
|----------|-------------|-------------|
| Line 29 | Comment | Update cell data structure comment |
| Line 238-239 | Code | Replace `reset` and `rnd_step` with `event` property in init() |
| Line 106 | Code | Remove RESET parameter definition |
| Line 110 | Code | Remove RND STEP parameter definition |
| Line 106 | Code | Add EVENT parameter with three options |
| Lines 323-335 | Code | Update sequencer logic to use event property |
| Lines 640-641 | Code | Replace reset handler with event handler |
| Lines 650-651 | Code | Remove rnd_step handler |
| Lines 767-768 | Code | Replace reset display with event display |
| Lines 779-780 | Code | Remove rnd_step display |

## Testing Considerations
- Verify that existing cells initialize with event = "none"
- Verify that event cycling works correctly through all three options
- Verify that "random step" randomizes x and y values when triggered
- Verify that "reset" resets playback position when triggered
- Verify that "none" performs no special action
- Verify that the display shows NONE, RESET, or RANDOM STEP correctly
