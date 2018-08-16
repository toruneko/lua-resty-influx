-- Copyright (C) by Jianhao Dai (Toruneko)

local error = error
local ngx_now = ngx.now
local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(timer)
    return setmetatable({
        timer = timer,
        start = ngx_now() * 1000,
        stopped = false
    }, mt)
end

function _M.stop(self)
    if self.stopped then
        error("timer context already stopped")
    end
    self.stopped = true
    local elapsed = ngx_now() * 1000 - self.start
    self.timer:update(elapsed)
    return elapsed
end

return _M