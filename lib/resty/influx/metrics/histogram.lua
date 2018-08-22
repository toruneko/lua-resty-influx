-- Copyright (C) by Jianhao Dai (Toruneko)

local reservoir = require "resty.influx.metrics.histogram.reservoir"

local setmetatable = setmetatable
local str_format = string.format
local worker_id = ngx.worker.id

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(key, name, opts)
    return setmetatable({
        key = key,
        name = name,
        count = 0,
        reservoir = reservoir.new(key, name, opts)
    }, mt)
end

function _M.update(self, value)
    self.count = self.count + 1
    self.reservoir:update(value)
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    return self.count
end

function _M.get_values(self)
    local snapshot = self.reservoir:snapshot()
    return {
        mean = snapshot:mean(),
        max = snapshot:max(),
        min = snapshot:min(),
        p75 = snapshot:p75(),
        p95 = snapshot:p95(),
        p98 = snapshot:p98(),
        p99 = snapshot:p99(),
        p999 = snapshot:p999(),
        median = snapshot:median(),
        std_dev = snapshot:stddev(),
        count = self:get_value()
    }
end

function _M.clear(self)
    self.count = 0
end

return _M