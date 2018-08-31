-- Copyright (C) by Jianhao Dai (Toruneko)

local clock = require "resty.influx.util.clock"
local skiplist = require "resty.influx.util.skiplist"
local snapshot = require "resty.influx.metrics.histogram.snapshot"

local setmetatable = setmetatable
local random = math.random
local sort = table.sort
local ipairs = ipairs
local exp = math.exp

local _M = { _VERSION = '0.0.1' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

local DEFAULT_EXACT = false
local DEFAULT_ALPHA = 0.015
local DEFAULT_SIZE = 1028
local DEFAULT_RESCALE_TIME = 1 * 3600 * 1000 * 1000

function _M.new(key, name, opts)
    local alpha = (opts and opts.alpha) or DEFAULT_ALPHA
    local size = (opts and opts.size) or DEFAULT_SIZE
    local exact = (opts and opts.exact) or DEFAULT_EXACT
    local values = exact and skiplist.new() or new_tab(size, 0)
    return setmetatable({
        key = key,
        name = name,
        count = 0,
        alpha = alpha,
        size = size,
        exact = exact,
        values = values,
        start_time = clock.sec_time(),
        next_scale_time = clock.usec_time() + DEFAULT_RESCALE_TIME
    }, mt)
end

local function no_exact_update(self, value)
    local ts = clock.sec_time()
    local t = ts - self.start_time
    local weight = exp(self.alpha * t)
    local index = (self.count % self.size) + 1

    self.count = self.count + 1

    self.values[index] = { value = value, weight = weight }
end

function _M.update(self, value)
    if not self.exact then
        return no_exact_update(self, value)
    end

    local now = clock.usec_time()
    local next = self.next_scale_time
    if now >= next then
        self:rescale(now, next);
    end

    local ts = clock.sec_time()
    local t = ts - self.start_time
    local weight = exp(self.alpha * t)
    local priority = weight / random()

    self.count = self.count + 1
    if self.count <= self.size then
        self.values:insert(value, weight, priority)
    else
        local v, w, s = self.values:first()
        if s < priority then
            local x = self.values:select(priority)
            if not x then
                self.values:insert(value, weight, priority)

                while self.values:length() > self.size and
                        not self.values:delete(s) do
                    v, w, s = self.values:first()
                end
            end
        end
    end
end

local function no_exact_snapshot(self)
    local length = #self.values
    local copy = new_tab(length, 0)
    for i, data in ipairs(self.values) do
        copy[i] = { value = data.value, weight = data.weight }
    end
    sort(copy, function(a, b)
        return a.value < b.value
    end)
    return snapshot.new(copy, length)
end

function _M.snapshot(self)
    if not self.exact then
        return no_exact_snapshot(self)
    end

    local length = self.values:length()
    local copy = new_tab(length, 0)
    for i, value, weight in self.values:iterator() do
        copy[i] = { value = value, weight = weight }
    end

    sort(copy, function(a, b)
        return a.value < b.value
    end)

    return snapshot.new(copy, length)
end

function _M.rescale(self, now, next)
    self.next_scale_time = now + DEFAULT_RESCALE_TIME
    local old_start_time = self.start_time
    self.start_time = clock.sec_time()

    local scaling = exp(-self.alpha * (self.start_time - old_start_time))

    local values = skiplist.new()
    for _, value, wegiht, score in self.values:iterator() do
        values:insert(value, wegiht * scaling, score * scaling)
    end

    self.values = values
    self.count = self.values:length()
end

return _M