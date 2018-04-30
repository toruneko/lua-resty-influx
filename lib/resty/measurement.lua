-- Copyright (C) by Jianhao Dai (Toruneko)

local timer = require "resty.metrics.timer"
local counter = require "resty.metrics.counter"
local averager = require "resty.metrics.averager"

local pairs = pairs
local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

function _M.new(m_key, cache)
    return setmetatable({
        key = m_key,
        cache = cache,
        metrics = new_tab(0, 100)
    }, mt)
end

function _M.counter(self, name)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local cnt = counter.new(name, self.cache)
    self.metrics[name] = cnt
    return cnt
end

function _M.averager(self, name)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local avg = averager.new(name, self.cache)
    self.metrics[name] = avg
    return avg
end

function _M.timer(self, name)
    if self.metrics[name] then
        return self.metrics[name]
    end

    local tm = timer.new(name, self.cache)
    self.metrics[name] = tm
    return tm
end

function _M.get_metrics(self)
    return self.metrics
end

function _M.get_metrics(self, name)
    return self.metrics[name]
end

function _M.get_tags(self)
    return self.m_key.tags
end

function _M.get_key(self)
    return self.m_key.key
end

function _M.clear(self)
    for name, metrics in pairs(self.metrics) do
        if metrics:has_value() then
            metrics:clear()
            self.fields[name] = nil
        end
    end
end

return _M