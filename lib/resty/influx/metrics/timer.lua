-- Copyright (C) by Jianhao Dai (Toruneko)
local averager = require "resty.influx.metrics.averager"
local context = require "resty.influx.metrics.timer.context"
local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(name, cache)
    return setmetatable({
        avg = averager.new(name, cache),
    }, mt)
end

function _M.time(self)
    return context.new(self)
end

function _M.update(self, num)
    self.avg:update(num)
end

function _M.has_value(self)
    return self.avg:has_value()
end

function _M.get_value(self)
    return self.avg:get_value()
end

function _M.get_values(self)
    return self.avg:get_values()
end

function _M.clear(self)
    self.avg:clear()
end

return _M