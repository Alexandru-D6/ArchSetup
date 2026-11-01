-- Exercise the rendered gesture callbacks without changing real audio or workspaces.
local gestures, commands, config = {}, {}, {}
local noop = setmetatable({}, {
    __index = function(self) return self end,
    __call = function() end,
})
hl = setmetatable({
    dsp = setmetatable({}, { __index = function() return noop end }),
    gesture = function(gesture) gestures[gesture.direction] = gesture end,
    config = function(settings) if settings.gestures then config = settings.gestures end end,
    exec_cmd = function(command) table.insert(commands, command) end,
}, { __index = function() return noop end })
dofile(arg[1])

assert(gestures.horizontal.fingers == 3)
assert(gestures.horizontal.action == "workspace")
assert(config.workspace_swipe_use_r == true)
assert(config.workspace_swipe_create_new == true)
assert(gestures.vertical.fingers == 3)
local volume = gestures.vertical.action
local event = function(y) return {delta = {x = 0, y = y}} end
local expect = function(amount)
    local shell = string.format("%q", arg[1]:gsub("/hyprland.lua$", "/shell"))
    assert(table.remove(commands, 1) == "qs -p " .. shell .. " ipc call desktop changeVolume " .. amount)
    assert(#commands == 0)
end

-- Small movements accumulate, then change volume while fingers are still down.
volume.start(event(-7))
volume.update(event(-7))
assert(#commands == 0)
volume.update(event(-7))
expect("5")
volume.update(event(-39))
expect("10")
-- Reversing the same gesture lowers volume immediately after crossing a step.
volume.update(event(20))
expect("-5")
volume.finish({cancelled = false})

-- A new gesture includes its initial motion and drops the previous remainder.
volume.start(event(19))
assert(#commands == 0)
volume.finish({cancelled = true})
volume.start(event(1))
assert(#commands == 0)
volume.update(event(19))
expect("-5")
volume.finish({cancelled = false})
volume.start(event(-20))
expect("5")
volume.finish({cancelled = false})
volume.start(event(-800))
expect("100")
volume.finish({cancelled = false})
print("ARCHSETUP_TOUCHPAD_GESTURES_PASSED")
