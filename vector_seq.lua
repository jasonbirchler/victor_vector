-- scriptname: Vector Sequencer for Norns based on https://dmachinery.net/2013/01/05/the-vector-sequencer/
-- v1.0.0 @hugenerd
-- llllllll.co/t/??????

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

-- Vector movement parameters (global)
vectors = {
    reset_x = 1,
    reset_y = 1,
    xt = 1,
    x = 1,
    yt = 1,
    y = 0
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
    active_notes = {}
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
        { name = "OUTPUT", key = "output", options = {"engine", "midi"}, default = 1 }
    },
    [PAGES.NOTE] = {
        { name = "CELL X", key = "cell_x", min = 1, max = 5, default = 1, format = "%d" },
        { name = "CELL Y", key = "cell_y", min = 1, max = 5, default = 1, format = "%d" },
        { name = "NOTE", key = "note", min = 0, max = 127, default = 60, format = "%d" },
        { name = "VELOCITY", key = "velocity", min = 0, max = 127, default = 100, format = "%d" },
        { name = "DURATION", key = "duration", min = 0.1, max = 4.0, default = 0.5, format = "%.2f" },
        { name = "ACTIVE", key = "active", options = {"off", "on"}, default = 2 },
        { name = "PLAY POS", key = "play_pos", read_only = true },
        { name = "RESET X", key = "reset_x", min = 1, max = 5, default = 1, format = "%d" },
        { name = "RESET Y", key = "reset_y", min = 1, max = 5, default = 1, format = "%d" },
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

-- Grid offset for centering 5x5 on 8x8
local GRID_OFFSET_X = 2
local GRID_OFFSET_Y = 2

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
                velocity = 100,
                duration = 0.5,
                active = (x + y) % 3 ~= 0 -- Some cells active by default
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

            -- Check X movement
            if state.tick_count % vectors.xt == 0 then
                state.pos_x = wrap_position(state.pos_x + vectors.x, 1, 5)
            end

            -- Check Y movement
            if state.tick_count % vectors.yt == 0 then
                state.pos_y = wrap_position(state.pos_y + vectors.y, 1, 5)
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
        -- Check if start/stop button (8,8)
        if x == 8 and y == 8 then
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

        -- Check if in 5x5 area (columns 2-6, rows 2-6)
        local grid_x = x - GRID_OFFSET_X + 1
        local grid_y = y - GRID_OFFSET_Y + 1

        if grid_x >= 1 and grid_x <= 5 and grid_y >= 1 and grid_y <= 5 then
            state.sel_x = grid_x
            state.sel_y = grid_y
            ui.current_page = PAGES.NOTE
            grid_redraw()
            redraw()
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
        g:led(8, 8, 15)
    else
        g:led(8, 8, state.playing and 7 or 3)
    end

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
        elseif param.key == "reset_x" then
            vectors.reset_x = util.clamp(vectors.reset_x + delta, param.min, param.max)
        elseif param.key == "reset_y" then
            vectors.reset_y = util.clamp(vectors.reset_y + delta, param.min, param.max)
        elseif param.key == "xt" then
            vectors.xt = util.clamp(vectors.xt + delta, param.min, param.max)
        elseif param.key == "x" then
            vectors.x = util.clamp(vectors.x + delta, param.min, param.max)
        elseif param.key == "yt" then
            vectors.yt = util.clamp(vectors.yt + delta, param.min, param.max)
        elseif param.key == "y" then
            vectors.y = util.clamp(vectors.y + delta, param.min, param.max)
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
            -- Reset playback position to reset vector
            state.pos_x = vectors.reset_x
            state.pos_y = vectors.reset_y
            state.tick_count = 0
            grid_redraw()
            redraw()
        end
    end
end

-- Get current parameter value for display
function get_param_value(param)
    if ui.current_page == PAGES.GLOBAL then
        if param.key == "tempo" then
            return string.format(param.format, params:get("clock_tempo"))
        elseif param.key == "output" then
            return state.output_mode:upper()
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
        elseif param.key == "reset_x" then
            return string.format(param.format, vectors.reset_x)
        elseif param.key == "reset_y" then
            return string.format(param.format, vectors.reset_y)
        elseif param.key == "xt" then
            return string.format(param.format, vectors.xt)
        elseif param.key == "x" then
            return string.format(param.format, vectors.x)
        elseif param.key == "yt" then
            return string.format(param.format, vectors.yt)
        elseif param.key == "y" then
            return string.format(param.format, vectors.y)
        end
    end
    return ""
end

-- Screen redraw function
function redraw()
    screen.clear()
    screen.level(15)

    local page_names = {"GLOBAL", "NOTE"}
    local params_list = page_params[ui.current_page]

    -- Page title
    screen.move(5, 10)
    screen.text("VECTOR SEQ - " .. page_names[ui.current_page])

    -- Draw parameters
    local start_y = 20
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

    -- Page indicator at bottom
    -- screen.level(5)
    -- screen.move(5, 60)
    -- screen.text("E1:PAGE  E2:SELECT  E3:ADJ")

    -- Playing indicator
    screen.move(110, 60)
    screen.text(state.playing and "PLAY" or "STOP")

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
