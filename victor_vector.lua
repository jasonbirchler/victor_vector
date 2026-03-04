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
-- Grid (1,6) = Randomize move vectors (x, y)
-- Grid (1,7) = Randomize clock vectors (xt, yt)
-- Grid (1,8) = Restore vector defaults

engine.name = "PolyPerc"

-- Grid setup with midigrid fallback
local grid = util.file_exists(_path.code.."midigrid") and require "midigrid/lib/midigrid" or grid
g = grid.connect()

-- MIDI setup
local midi_out = nil
local midi_device = nil

-- 5x5 grid cell data
-- cells[x][y] = { note, velocity, duration, active, xt, x, yt, y }
cells = {}

-- Default cell values for restore functionality
-- default_cells[x][y] = { xt, x, yt, y }
default_cells = {}

-- Vector reset position (global - where playback resets to)
reset_pos = {
    reset_x = 1,
    reset_y = 1
}

-- Available output options
OUTPUT_OPTIONS = {"PolyPerc", "MIDI"}

-- Engine parameters for PolyPerc
POLYPERC_PARAMS = {
    { name = "CUTOFF", key = "cutoff", min = 50, max = 8000, default = 800, format = "%d" },
    { name = "RELEASE", key = "release", min = 0.1, max = 10.0, default = 1.0, format = "%.2f" },
    { name = "PW", key = "pw", min = 0.0, max = 1.0, default = 0.5, format = "%.2f" }
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
    -- Output mode: "polyperc" or "midi"
    output_mode = "polyperc",
    -- MIDI settings
    selected_midi_device = "DIN",
    midi_channel = 1,
    -- PolyPerc parameter values (tracked for display)
    polyperc_cutoff = 800,
    polyperc_release = 1.0,
    polyperc_pw = 0.5,
    -- Currently playing notes (for note off tracking)
    active_notes = {},
    -- Grid modifier key state (1,3 held for toggling active state)
    modifier_held = false,
    -- Playback reset button state
    playback_reset_pressed = false,
    -- Vectors randomized state (for visual feedback)
    move_vectors_randomized = false,
    clock_vectors_randomized = false
}

-- UI Pages
PAGES = {
    GLOBAL = 1,
    NOTE = 2,
    OUTPUT = 3
}

-- Page parameters for each page
page_params = {
    [PAGES.GLOBAL] = {
        { name = "TEMPO", key = "tempo", min = 20, max = 300, default = 120, format = "%d" },
        { name = "OUTPUT", key = "output", options = OUTPUT_OPTIONS, default = 1 },
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
        { name = "X STEP", key = "x", min = 0, max = 4, default = 1, format = "%d" },
        { name = "Y STEP", key = "y", min = 0, max = 4, default = 0, format = "%d" },
        { name = "X TIME", key = "xt", min = 1, max = 16, default = 1, format = "%d" },
        { name = "Y TIME", key = "yt", min = 1, max = 16, default = 1, format = "%d" }
    }
}

-- Dynamic OUTPUT page parameters
function get_output_page_params()
    local params_list = {}

    -- Show current output mode as read-only header
    table.insert(params_list, { name = "MODE", key = "current_mode", read_only = true })

    if state.output_mode == "midi" then
        -- MIDI-specific params
        table.insert(params_list, { name = "DEVICE", key = "midi_device", options = get_midi_device_options(), default = 1 })
        table.insert(params_list, { name = "CHANNEL", key = "midi_channel", min = 1, max = 16, default = 1, format = "%d" })
    else
        -- PolyPerc params
        for _, param in ipairs(POLYPERC_PARAMS) do
            table.insert(params_list, param)
        end
    end

    return params_list
end

-- Current page and selected parameter
ui = {
    current_page = PAGES.GLOBAL,
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

-- MIDI device discovery
function get_midi_device_options()
    local options = {}

    -- Add "DIN" for hardware MIDI out port
    table.insert(options, "DIN")

    -- Guard against midi.devices being nil
    if not midi.devices then
        return options
    end

    -- Add connected USB MIDI devices from midi.devices
    for i = 1, #midi.devices do
        local device = midi.devices[i]
        if device and device.name then
            table.insert(options, device.name)
        end
    end

    return options
end

-- Get current MIDI device index
function get_current_midi_device_index()
    local options = get_midi_device_options()
    for i, name in ipairs(options) do
        if name == state.selected_midi_device then
            return i
        end
    end
    return 1
end

-- Connect to selected MIDI device
function connect_midi_device()
    local device_name = state.selected_midi_device

    if device_name == "DIN" then
        -- Connect to hardware DIN MIDI out (port 1)
        midi_out = midi.connect(1)
    else
        -- Find device index by name
        for i = 1, #midi.devices do
            if midi.devices[i] and midi.devices[i].name == device_name then
                midi_out = midi.connect(i)
                break
            end
        end
    end

    if not midi_out then
        -- Fallback to port 1 if device not found
        midi_out = midi.connect(1)
    end
end

-- Select output mode
function select_output_mode(mode_name)
    if mode_name == "MIDI" then
        state.output_mode = "midi"
    else
        state.output_mode = "polyperc"
    end
end

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

    -- Store default vector values for restore functionality
    for x = 1, 5 do
        default_cells[x] = {}
        for y = 1, 5 do
            default_cells[x][y] = {
                xt = cells[x][y].xt,
                x = cells[x][y].x,
                yt = cells[x][y].yt,
                y = cells[x][y].y
            }
        end
    end

    -- Initialize MIDI
    connect_midi_device()
    if midi_out then
        midi_out.event = function(data) end -- Not handling input
    end

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

-- Randomize move vectors (x, y) for all cells
function randomize_move_vectors()
    for x = 1, 5 do
        for y = 1, 5 do
            cells[x][y].x = math.random(0, 4)
            cells[x][y].y = math.random(0, 4)
        end
    end
    state.move_vectors_randomized = true
end

-- Randomize clock vectors (xt, yt) for all cells
function randomize_clock_vectors()
    for x = 1, 5 do
        for y = 1, 5 do
            cells[x][y].xt = math.random(1, 16)
            cells[x][y].yt = math.random(1, 16)
        end
    end
    state.clock_vectors_randomized = true
end

-- Restore vector parameters (xt, x, yt, y) to default values
function restore_vectors()
    for x = 1, 5 do
        for y = 1, 5 do
            cells[x][y].xt = default_cells[x][y].xt
            cells[x][y].x = default_cells[x][y].x
            cells[x][y].yt = default_cells[x][y].yt
            cells[x][y].y = default_cells[x][y].y
        end
    end
    state.move_vectors_randomized = false
    state.clock_vectors_randomized = false
end

-- Trigger a note (either PolyPerc or MIDI)
function trigger_note(cell)
    if state.output_mode == "midi" then
        -- MIDI output
        midi_out:note_on(cell.note, cell.velocity, state.midi_channel)
        clock.run(function()
            clock.sleep(cell.duration)
            midi_out:note_off(cell.note, 0, state.midi_channel)
        end)
    else
        -- PolyPerc output
        if engine.hz then
            engine.hz(midi_to_hz(cell.note))
        end
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
                        midi_out:note_off(note, 0, state.midi_channel)
                    end
                end
            end
            grid_redraw()
            redraw()
            return
        end

        -- Check if modifier button for toggling active state is held
        if x == 1 and y == 3 then
            state.modifier_held = true
            grid_redraw()
            return
        end

        -- Check if reset is pressed
        if x == 3 and y == 1 then
            state.playback_reset_pressed = true
            reset_playback()
            grid_redraw()
            return
        end

        -- Check if randomize button (1,6) is pressed
        if x == 1 and y == 6 then
            randomize_move_vectors()
            grid_redraw()
            redraw()
            return
        end
        
        -- Check if randomize button (1,7) is pressed
        if x == 1 and y == 7 then
            randomize_clock_vectors()
            grid_redraw()
            redraw()
            return
        end

        -- Check if restore defaults button (1,8) is pressed
        if x == 1 and y == 8 then
            restore_vectors()
            grid_redraw()
            redraw()
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
        -- Check if modifier button (1,3) released
        if x == 1 and y == 3 then
            state.modifier_held = false
            grid_redraw()
            return
        end

        -- Check if reset button (3,1) released
        if x == 3 and y == 1 then
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

    -- Active State Modifier button (1,5) indicator
    g:led(1, 3, state.modifier_held and 7 or 3)

    -- Playback reset button (1,3) indicator
    g:led(3, 1, state.playback_reset_pressed and 7 or 3)

    -- Randomize move vector button indicator
    g:led(1, 6, state.move_vectors_randomized and 7 or 3)

    -- Randomize clock vector button indicator
    g:led(1, 7, state.clock_vectors_randomized and 7 or 3)

    -- Restore defaults button (1,8) indicator
    g:led(1, 8, 3)

    g:refresh()
end

-- Encoder handler
function enc(n, d)
    if n == 1 then
        -- Page navigation
        if d > 0 then
            ui.current_page = math.min(ui.current_page + 1, 3)
        else
            ui.current_page = math.max(ui.current_page - 1, 1)
        end
        ui.selected_param = 1
        redraw()

    elseif n == 2 then
        -- Parameter selection
        local params_list = get_params_for_current_page()
        if d > 0 then
            ui.selected_param = math.min(ui.selected_param + 1, #params_list)
        else
            ui.selected_param = math.max(ui.selected_param - 1, 1)
        end
        redraw()

    elseif n == 3 then
        -- Parameter value adjustment
        if ui.current_page == PAGES.OUTPUT then
            adjust_output_param(d)
        else
            adjust_param(d)
        end
        grid_redraw()
        redraw()
    end
end

-- Get parameters for current page
function get_params_for_current_page()
    if ui.current_page == PAGES.OUTPUT then
        return get_output_page_params()
    else
        return page_params[ui.current_page]
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
            local current_idx = state.output_mode == "midi" and 2 or 1
            local new_idx = util.clamp(current_idx + delta, 1, #OUTPUT_OPTIONS)
            select_output_mode(OUTPUT_OPTIONS[new_idx])
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

-- Adjust OUTPUT page parameters
function adjust_output_param(delta)
    local params_list = get_output_page_params()
    local param = params_list[ui.selected_param]

    if param.read_only then
        return
    elseif param.key == "midi_device" then
        local options = get_midi_device_options()
        local current_idx = get_current_midi_device_index()
        local new_idx = util.clamp(current_idx + delta, 1, #options)
        state.selected_midi_device = options[new_idx]
        connect_midi_device()
    elseif param.key == "midi_channel" then
        state.midi_channel = util.clamp(state.midi_channel + delta, param.min, param.max)
    else
        -- PolyPerc numeric parameter
        local current_val = get_polyperc_param_value(param.key)
        local step = 1
        if param.format and string.find(param.format, "%%%.[23]f") then
            step = 0.01
        elseif param.format and string.find(param.format, "%%%.1f") then
            step = 0.1
        end
        local new_val = util.clamp(current_val + (delta * step), param.min, param.max)
        set_polyperc_param(param.key, new_val)
    end
end

-- Get PolyPerc parameter value from state
function get_polyperc_param_value(key)
    if key == "cutoff" then
        return state.polyperc_cutoff
    elseif key == "release" then
        return state.polyperc_release
    elseif key == "pw" then
        return state.polyperc_pw
    end
    return 0
end

-- Set PolyPerc parameter value (update state and engine)
function set_polyperc_param(key, value)
    -- Update state
    if key == "cutoff" then
        state.polyperc_cutoff = value
    elseif key == "release" then
        state.polyperc_release = value
    elseif key == "pw" then
        state.polyperc_pw = value
    end
    -- Send to engine
    if engine[key] then
        engine[key](value)
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
            if state.output_mode == "midi" then
                return "MIDI"
            else
                return "PolyPerc"
            end
        elseif param.key == "reset_x" then
            return string.format(param.format, reset_pos.reset_x)
        elseif param.key == "reset_y" then
            return string.format(param.format, reset_pos.reset_y)
        end
    elseif ui.current_page == PAGES.NOTE then
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
    elseif ui.current_page == PAGES.OUTPUT then
        if param.key == "current_mode" then
            if state.output_mode == "midi" then
                return "MIDI"
            else
                return "PolyPerc"
            end
        elseif param.key == "midi_device" then
            return state.selected_midi_device
        elseif param.key == "midi_channel" then
            return string.format("%d", state.midi_channel)
        else
            -- PolyPerc parameter
            local val = get_polyperc_param_value(param.key)
            if param.format then
                return string.format(param.format, val)
            else
                return tostring(val)
            end
        end
    end
    return ""
end

-- Screen redraw function
function redraw()
    screen.clear()
    screen.level(15)

    local page_names = {"GLOBAL", "NOTE", "OUTPUT"}
    local num_pages = #page_names
    local params_list = get_params_for_current_page()

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
            midi_out:note_off(note, 0, state.midi_channel)
        end
    end
end
