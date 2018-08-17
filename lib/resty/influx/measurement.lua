-- Copyright (C) by Jianhao Dai (Toruneko)

local timer = require "resty.influx.metrics.timer"
local counter = require "resty.influx.metrics.counter"
local averager = require "resty.influx.metrics.averager"
local histogram = require "resty.influx.metrics.histogram"

local pairs = pairs
local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

function _M.new(key, tags, cache)
    return setmetatable({
        key = key,
        tags = tags or {},
        cache = cache,
        metrics = new_tab(0, 100)
    }, mt)
end

function _M.counter(self, name)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local cnt = counter.new(self:get_key(), name, self.cache)
    self.metrics[name] = cnt
    return cnt
end

function _M.averager(self, name)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local avg = averager.new(self:get_key(), name, self.cache)
    self.metrics[name] = avg
    return avg
end

function _M.histogram(self, name, opts)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local histo = histogram.new(self:get_key(), name, self.cache, opts)
    self.metrics[name] = histo
    return histo
end

function _M.timer(self, name)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local tm = timer.new(self:get_key(), name, self.cache)
    self.metrics[name] = tm
    return tm
end

function _M.get_metricses(self)
    return self.metrics
end

function _M.get_metrics(self, name)
    return self.metrics[name]
end

function _M.get_tags(self)
    return self.tags
end

function _M.get_key(self)
    return self.key
end

function _M.clear(self)
    for name, metrics in pairs(self.metrics) do
        if metrics:has_value() then
            metrics:clear()
            self.metrics[name] = nil
        end
    end
end

return _M