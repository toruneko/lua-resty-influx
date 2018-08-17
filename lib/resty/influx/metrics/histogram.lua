-- Copyright (C) by Jianhao Dai (Toruneko)

local reservoir = require "resty.influx.metrics.histogram.reservoir"

local setmetatable = setmetatable
local str_format = string.format
local worker_id = ngx.worker.id

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(m_key, name, cache, opts)
    return setmetatable({
        cache = cache,
        count = str_format("%s%s:%s:%s", m_key, worker_id(), "histo:cnt", name),
        reservoir = reservoir.new(m_key, name, cache, opts)
    }, mt)
end

function _M.update(self, value)
    self.cache:incr(self.count, 1, 0)
    self.reservoir:update(value)
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    return self.cache:get(self.count) or 0
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
    self.cache:delete(self.count)
end

return _M