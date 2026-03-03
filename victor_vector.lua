-- Victor Vector.
-- A vector sequencer for Norns
--
-- v1.0.0 @hugenerd
-- llllllll.co/t/??????
--
-- ENC1 = Change Pages
-- ENC2 = Scroll params
-- ENC3 = Change param value
--
-- K2 = Toggle cell state
-- K3 = Reset start point

engine.name = "PolyPerc"

-- Grid setup with midigrid fallback
local grid = util.file_exists(_path.code.."midigrid") and require "midigrid/lib/midigrid" or grid
g = grid.connect()

-- MIDI setup
local midi_out = nil
local midi_device = nil

-- 5x5 grid cell data
-- cells[x][y] = { note, velocity, duration, active }
cells = {}

-- Vector reset position (global - where playback resets to)
reset_pos = {
    reset_x = 1,
    reset_y = 1
}

-- Playback and UI state
state = {
    -- Current playback position (1-5, 1-5)
    pos_x = 1,
    pos_y = 1,
    -- Currently selected cell for editing (1-5, 1-5)
    sel_x = 1,
    sel_y = 1,
    -- Clock tick counter
    tick_count = 0,
    -- Sequencer running state
    playing = false,
    -- Output mode: "engine" or "midi"
    output_mode = "engine",
    -- Currently playing notes (for note off tracking)
    active_notes = {},
    -- Grid modifier key state (1,3 held for toggling active state)
    modifier_held = false,
    -- Playback reset button state
    playback_reset_pressed = false
}

-- UI Pages
PAGES = {
    GLOBAL = 1,
    NOTE = 2
}

-- Page parameters for each page
page_params = {
    [PAGES.GLOBAL] = {
        { name = "TEMPO", key = "tempo", min = 20, max = 300, default = 120, format = "%d" },
        { name = "OUTPUT", key = "output", options = {"engine", "midi"}, default = 1 },
        { name = "RESET X", key = "reset_x", min = 1, max = 5, default = 1, format = "%d" },
        { name = "RESET Y", key = "reset_y", min = 1, max = 5, default = 1, format = "%d" }
    },
    [PAGES.NOTE] = {
        { name = "CELL X", key = "cell_x", min = 1, max = 5, default = 1, format = "%d" },
        { name = "CELL Y", key = "cell_y", min = 1, max = 5, default = 1, format = "%d" },
        { name = "NOTE", key = "note", min = 0, max = 127, default = 60, format = "%d" },
        { name = "VELOCITY", key = "velocity", min = 0, max = 127, default = 64, format = "%d" },
        { name = "DURATION", key = "duration", min = 0.1, max = 4.0, default = 0.5, format = "%.2f" },
        { name = "ACTIVE", key = "active", options = {"off", "on"}, default = 2 },
        { name = "PLAY POS", key = "play_pos", read_only = true },
        { name = "XT", key = "xt", min = 1, max = 16, default = 1, format = "%d" },
        { name = "X STEP", key = "x", min = 0, max = 4, default = 1, format = "%d" },
        { name = "YT", key = "yt", min = 1, max = 16, default = 1, format = "%d" },
        { name = "Y STEP", key = "y", min = 0, max = 4, default = 0, format = "%d" }
    }
}

-- Current page and selected parameter
ui = {
    current_page = PAGES.NOTE,
    selected_param = 1
}

-- Screen display constants
local SCREEN_WIDTH = 128
local PAGE_INDICATOR_Y = 6
local PAGE_INDICATOR_PADDING = 4

-- Grid offset for centering 5x5 on 8x8 (rows/cols 3-7)
local GRID_OFFSET_X = 3
local GRID_OFFSET_Y = 3

-- Blink timer for start/stop indicator
local blink_state = false
local blink_counter = 0

-- Note names for display
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

-- Initialize the script
function init()
    -- Initialize cells
    for x = 1, 5 do
        cells[x] = {}
        for y = 1, 5 do
            cells[x][y] = {
                note = 36 + (x-1) * 12 + (y-1) * 2, -- Pentatonic-ish distribution
                velocity = 64,
                duration = 0.5,
                active = (x + y) % 3 ~= 0, -- Some cells active by default
                -- Vector movement parameters (per-cell)
                xt = 1,  -- X trigger interval
                x = 1,   -- X step size
                yt = 1,  -- Y trigger interval
                y = 0    -- Y step size
            }
        end
    end

    -- Ensure some notes stay in valid range
    for x = 1, 5 do
        for y = 1, 5 do
            cells[x][y].note = util.clamp(cells[x][y].note, 24, 96)
        end
    end

    -- Initialize MIDI
    midi_out = midi.connect(1)
    midi_out.event = function(data) end -- Not handling input

    -- Set initial tempo
    params:set("clock_tempo", 120)

    -- Start clock
    clock.run(sequencer_clock)
    clock.run(blink_clock)

    -- Initial redraw
    grid_redraw()
    redraw()
end

-- Blink clock for start/stop indicator
function blink_clock()
    while true do
        clock.sleep(0.25)
        blink_counter = blink_counter + 1
        if blink_counter % 2 == 0 then
            blink_state = not blink_state
            grid_redraw()
        end
    end
end

-- Main sequencer clock
function sequencer_clock()
    while true do
        clock.sync(1/4) -- 16th notes

        if state.playing then
            state.tick_count = state.tick_count + 1

            -- Get current cell's vector parameters
            local current_cell = cells[state.pos_x][state.pos_y]

            -- Check X movement (using current cell's xt and x)
            if state.tick_count % current_cell.xt == 0 then
                state.pos_x = wrap_position(state.pos_x + current_cell.x, 1, 5)
            end

            -- Check Y movement (using current cell's yt and y)
            if state.tick_count % current_cell.yt == 0 then
                state.pos_y = wrap_position(state.pos_y + current_cell.y, 1, 5)
            end

            -- Trigger note if cell is active
            local cell = cells[state.pos_x][state.pos_y]
            if cell.active then
                trigger_note(cell)
            end

            grid_redraw()
            redraw()
        end
    end
end

-- Wrap position for toroidal grid
function wrap_position(pos, min, max)
    local range = max - min + 1
    return ((pos - min) % range) + min
end

-- Trigger a note (either engine or MIDI)
function trigger_note(cell)
    local hz = midi_to_hz(cell.note)

    if state.output_mode == "engine" then
        -- PolyPerc engine
        engine.hz(hz)
    else
        -- MIDI output
        midi_out:note_on(cell.note, cell.velocity)

        -- Schedule note off
        clock.run(function()
            clock.sleep(cell.duration)
            midi_out:note_off(cell.note, 0)
        end)
    end
end

-- Convert MIDI note to frequency
function midi_to_hz(note)
    return 440 * math.pow(2, (note - 69) / 12)
end

-- Get note name from MIDI number
function note_name(note_num)
    local octave = math.floor(note_num / 12) - 1
    local note_idx = (note_num % 12) + 1
    return NOTE_NAMES[note_idx] .. octave
end

-- Grid key handler
g.key = function(x, y, z)
    if z == 1 then -- Key press
        -- Check if start/stop button (1,1)
        if x == 1 and y == 1 then
            state.playing = not state.playing
            if not state.playing then
                -- Stop all MIDI notes
                if state.output_mode == "midi" then
                    for note = 0, 127 do
                        midi_out:note_off(note, 0)
                    end
                end
            end
            grid_redraw()
            redraw()
            return
        end

        -- Check if modifier button for toggling active state is held
        if x == 1 and y == 5 then
            state.modifier_held = true
            grid_redraw()
            return
        end

        -- Check if reset is pressed
        if x == 1 and y == 3 then
            state.playback_reset_pressed = true
            reset_playback()
            grid_redraw()
            return
        end

        -- Check if in 5x5 area (columns 3-7, rows 3-7)
        local grid_x = x - GRID_OFFSET_X + 1
        local grid_y = y - GRID_OFFSET_Y + 1

        if grid_x >= 1 and grid_x <= 5 and grid_y >= 1 and grid_y <= 5 then
            if state.modifier_held then
                -- Toggle active state of the pressed cell
                cells[grid_x][grid_y].active = not cells[grid_x][grid_y].active
            else
                -- Select the cell for editing
                state.sel_x = grid_x
                state.sel_y = grid_y
                ui.current_page = PAGES.NOTE
            end
            grid_redraw()
            redraw()
        end
    else -- Key release (z == 0)
        -- Check if modifier button (1,5) released
        if x == 1 and y == 5 then
            state.modifier_held = false
            grid_redraw()
            return
        end

        -- Check if reset button (1,3) released
        if x == 1 and y == 3 then
            state.playback_reset_pressed = false
            grid_redraw()
            return
        end
    end
end

-- Grid redraw function
function grid_redraw()
    g:all(0)

    -- Draw 5x5 grid
    for x = 1, 5 do
        for y = 1, 5 do
            local gx = x + GRID_OFFSET_X - 1
            local gy = y + GRID_OFFSET_Y - 1

            local brightness = 0

            -- Currently selected cell
            if x == state.sel_x and y == state.sel_y then
                brightness = 15
            -- Currently playing position
            elseif state.playing and x == state.pos_x and y == state.pos_y then
                brightness = 10
            -- Active cells
            elseif cells[x][y].active then
                brightness = 5
            end

            g:led(gx, gy, brightness)
        end
    end

    -- Start/stop button with blink when playing
    if state.playing and blink_state then
        g:led(1, 1, 15)
    else
        g:led(1, 1, state.playing and 7 or 3)
    end

    -- Active State Modifier button (1,3) indicator
    g:led(1, 5, state.modifier_held and 7 or 3)

    -- Playback reset button (1,5) indicator
    g:led(1, 3, state.playback_reset_pressed and 7 or 3)

    g:refresh()
end

-- Encoder handler
function enc(n, d)
    if n == 1 then
        -- Page navigation
        if d > 0 then
            ui.current_page = math.min(ui.current_page + 1, 2)
        else
            ui.current_page = math.max(ui.current_page - 1, 1)
        end
        ui.selected_param = 1
        redraw()

    elseif n == 2 then
        -- Parameter selection
        local params_list = page_params[ui.current_page]
        if d > 0 then
            ui.selected_param = math.min(ui.selected_param + 1, #params_list)
        else
            ui.selected_param = math.max(ui.selected_param - 1, 1)
        end
        redraw()

    elseif n == 3 then
        -- Parameter value adjustment
        adjust_param(d)
        grid_redraw()
        redraw()
    end
end

-- Adjust the currently selected parameter
function adjust_param(delta)
    local params_list = page_params[ui.current_page]
    local param = params_list[ui.selected_param]

    if param.read_only then
        return
    end

    if ui.current_page == PAGES.GLOBAL then
        if param.key == "tempo" then
            local new_tempo = util.clamp(params:get("clock_tempo") + delta, param.min, param.max)
            params:set("clock_tempo", new_tempo)
        elseif param.key == "output" then
            local current = state.output_mode == "engine" and 1 or 2
            local new_val = delta > 0 and 2 or 1
            state.output_mode = param.options[new_val]
        elseif param.key == "reset_x" then
            reset_pos.reset_x = util.clamp(reset_pos.reset_x + delta, param.min, param.max)
        elseif param.key == "reset_y" then
            reset_pos.reset_y = util.clamp(reset_pos.reset_y + delta, param.min, param.max)
        end
    else -- PAGES.NOTE
        local cell = cells[state.sel_x][state.sel_y]

        if param.key == "cell_x" then
            state.sel_x = util.clamp(state.sel_x + delta, param.min, param.max)
        elseif param.key == "cell_y" then
            state.sel_y = util.clamp(state.sel_y + delta, param.min, param.max)
        elseif param.key == "note" then
            cell.note = util.clamp(cell.note + delta, param.min, param.max)
        elseif param.key == "velocity" then
            cell.velocity = util.clamp(cell.velocity + delta * 5, param.min, param.max)
        elseif param.key == "duration" then
            cell.duration = util.clamp(cell.duration + delta * 0.1, param.min, param.max)
        elseif param.key == "active" then
            cell.active = not cell.active
        elseif param.key == "xt" then
            cell.xt = util.clamp(cell.xt + delta, param.min, param.max)
        elseif param.key == "x" then
            cell.x = util.clamp(cell.x + delta, param.min, param.max)
        elseif param.key == "yt" then
            cell.yt = util.clamp(cell.yt + delta, param.min, param.max)
        elseif param.key == "y" then
            cell.y = util.clamp(cell.y + delta, param.min, param.max)
        end
    end
end

-- Key handler
function key(n, z)
    if z == 1 then -- Key press
        if n == 2 then
            -- Toggle active status of selected cell
            cells[state.sel_x][state.sel_y].active = not cells[state.sel_x][state.sel_y].active
            grid_redraw()
            redraw()
        elseif n == 3 then
            reset_playback()
        end
    end
end

function reset_playback()
    -- Reset playback position to reset vector
    state.pos_x = reset_pos.reset_x
    state.pos_y = reset_pos.reset_y
    state.tick_count = 0
    grid_redraw()
    redraw()
end

-- Get current parameter value for display
function get_param_value(param)
    if ui.current_page == PAGES.GLOBAL then
        if param.key == "tempo" then
            return string.format(param.format, params:get("clock_tempo"))
        elseif param.key == "output" then
            return state.output_mode:upper()
        elseif param.key == "reset_x" then
            return string.format(param.format, reset_pos.reset_x)
        elseif param.key == "reset_y" then
            return string.format(param.format, reset_pos.reset_y)
        end
    else -- PAGES.NOTE
        local cell = cells[state.sel_x][state.sel_y]

        if param.key == "cell_x" then
            return string.format(param.format, state.sel_x)
        elseif param.key == "cell_y" then
            return string.format(param.format, state.sel_y)
        elseif param.key == "note" then
            return note_name(cell.note) .. " (" .. cell.note .. ")"
        elseif param.key == "velocity" then
            return string.format(param.format, cell.velocity)
        elseif param.key == "duration" then
            return string.format(param.format, cell.duration)
        elseif param.key == "active" then
            return cell.active and "ON" or "OFF"
        elseif param.key == "play_pos" then
            return "[" .. state.pos_x .. "," .. state.pos_y .. "]"
        elseif param.key == "xt" then
            return string.format(param.format, cell.xt)
        elseif param.key == "x" then
            return string.format(param.format, cell.x)
        elseif param.key == "yt" then
            return string.format(param.format, cell.yt)
        elseif param.key == "y" then
            return string.format(param.format, cell.y)
        end
    end
    return ""
end

-- Screen redraw function
function redraw()
    screen.clear()
    screen.level(15)

    local page_names = {"GLOBAL", "NOTE"}
    local num_pages = #page_names
    local params_list = page_params[ui.current_page]

    -- Draw page indicator lines at the top
    local line_width = (SCREEN_WIDTH - ((num_pages + 1) * PAGE_INDICATOR_PADDING)) / num_pages
    for i = 1, num_pages do
        local x = PAGE_INDICATOR_PADDING + (i - 1) * (line_width + PAGE_INDICATOR_PADDING)
        if i == ui.current_page then
            screen.level(15) -- Active page: bright
        else
            screen.level(3)  -- Inactive page: dimmed
        end
        screen.move(x, PAGE_INDICATOR_Y)
        screen.line_rel(line_width, 0)
        screen.stroke()
    end
    screen.level(15)

    -- Page title
    screen.move(5, 16)
    screen.text("VECTOR SEQ - " .. page_names[ui.current_page])

    -- Draw parameters
    local start_y = 26
    local line_height = 8
    local visible_count = 5
    local start_idx = 1

    -- Calculate scroll window - keep selected item in view
    if ui.selected_param > visible_count then
        start_idx = ui.selected_param - visible_count + 1
    end
    local end_idx = math.min(start_idx + visible_count - 1, #params_list)

    for i = start_idx, end_idx do
        local y = start_y + (i - start_idx) * line_height
        local param = params_list[i]
        local is_selected = (i == ui.selected_param)

        -- Selection indicator
        if is_selected then
            screen.level(15)
            screen.move(5, y)
            screen.text("*")
        else
            screen.level(5)
            screen.move(5, y)
            screen.text(" ")
        end

        -- Parameter name
        screen.move(12, y)
        screen.text(param.name .. ":")

        -- Parameter value
        local value = get_param_value(param)
        screen.move(65, y)
        screen.text(value)
    end

    screen.update()
end

-- Cleanup on script exit
function cleanup()
    -- Stop all MIDI notes
    if midi_out then
        for note = 0, 127 do
            midi_out:note_off(note, 0)
        end
    end
end
