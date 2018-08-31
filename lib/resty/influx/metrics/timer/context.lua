-- Copyright (C) by Jianhao Dai (Toruneko)

local clock = require "resty.influx.util.clock"

local setmetatable = setmetatable
local error = error

local _M = { _VERSION = '0.0.1' }
local mt = { __index = _M }

function _M.new(timer)
    return setmetatable({
        timer = timer,
        start = clock.msec_time(),
        stopped = false
    }, mt)
end

function _M.stop(self)
    if self.stopped then
        error("timer context already stopped")
    end
    self.stopped = true
    local elapsed = clock.msec_time() - self.start
    self.timer:update(elapsed)
    return elapsed
end

return _M