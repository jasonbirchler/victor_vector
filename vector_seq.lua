-- scriptname: Vector Sequencer for Norns based on https://dmachinery.net/2013/01/05/the-vector-sequencer/
-- v1.0.0 @hugenerd
-- llllllll.co/t/??????

engine.name = "PolyPerc"

steps = {}

function init()
    for i=1, 16 do
        table.insert(steps, 1)
    end
    grid_redraw()
    position = 0
    counter = clock.run(count)
  notes = {} -- create a 'notes' table
  selected = {} -- create a 'selected' table to track playing notes
  
  -- lets create a 5x5 square of notes:
  for m = 1,5 do -- a 'for' loop, where m = 1, then m = 2, etc
    notes[m] = {} -- use m as an vertical index for 'notes'
    selected[m] = {} -- use m as a vertical index for 'selected'
    for n = 1,5 do -- another 'for' loop, where n = 1, then n = 2, etc
      -- n is our horizontal index
      notes[m][n] = 55 * 2^((m*12+n*2)/12) -- this is just fancy math to get some notes
      selected[m][n] = false -- all start unselected
    end
  end
  light = 0
  number = 3 -- our maximum number of notes to play at one time
end

local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/midigrid" or grid
g = grid.connect()


function grid_redraw()
  g:all(0)
  for i=1,16 do
    g:led(i,steps[i],i == position and 15 or 4)
  end
  g:refresh()
end

function redraw()
  screen.clear()
  drawgrid()
  
  screen.update()
end

g.key = function(x,y,z)
  if z == 1 then
    steps[x] = y
    grid_redraw()
  end
end

function key(n,z)
  if n == 2 and z == 1 then
    -- clear selected notes
    for x=1,5 do
      for y=1,5 do
        selected[x][y] = false
      end
    end
    -- choose new random notes
    for i=1,number do
      selected[math.random(5)][math.random(5)] = true
    end
  elseif n == 3 then
    -- find notes to play
    if z == 1 then -- key 3 down
      for x=1,5 do
        for y=1,5 do
          if selected[x][y] then
            engine.hz(notes[x][y])
          end
        end
      end
      light = 7 -- adds 7 to the square's screen level
    elseif z == 0 then -- key 3 up
      light = 0 -- adds 0 to the square's screen level
    end
  end
  redraw()
end

function enc(n,d)
  if n==3 then
    -- clamp number of notes from 1 to 4
    number = util.clamp(number + d,1,12)
  end
  redraw()
end

function drawgrid()
  for m = 1,5 do
    for n = 1,5 do
      screen.rect(m*11,n*11,8,8) -- (x,y,width,height)
      l = 2
      if selected[m][n] then
        l = l + 3 + light
      end
      screen.level(l)
      screen.stroke()
    end
  end
end

function count()
  while true do -- while the 'counter' is active...
    clock.sync(1) -- sync every 'beat'
    position = util.wrap(position+1, 1, 16) -- increment the position by 1, wrap it as 1 to 16
    engine.hz(steps[position]*100) -- play a note, based on step position
    grid_redraw() -- and redraw the grid
  end
end