-- Copyright (C) by Jianhao Dai (Toruneko)

local clock = require "resty.influx.util.clock"
local skiplist = require "resty.influx.util.skiplist"
local snapshot = require "resty.influx.metrics.histogram.snapshot"

local setmetatable = setmetatable
local str_format = string.format
local worker_id = ngx.worker.id
local random = math.random
local sort = table.sort
local exp = math.exp

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

local DEFAULT_ALPHA = 0.015
local DEFAULT_SIZE = 1028
local DEFAULT_RESCALE_TIME = 1 * 3600 * 1000 * 1000

function _M.new(m_key, name, cache, opts)
    local alpha = (opts and opts.alpha) or DEFAULT_ALPHA
    local size = (opts and opts.size) or DEFAULT_SIZE
    return setmetatable({
        cache = cache,
        count = str_format("%s%s:%s:%s", m_key, worker_id(), "histo:reservoir", name),
        alpha = alpha,
        size = size,
        start_time = clock.sec_time(),
        next_scale_time = clock.usec_time() + DEFAULT_RESCALE_TIME,
        values = skiplist.new()
    }, mt)
end

function _M.update(self, value)
    local now = clock.usec_time()
    local next = self.next_scale_time
    if now >= next then
        self:rescale(now, next);
    end

    local ts = clock.sec_time()
    local t = ts - self.start_time
    local weight = exp(self.alpha * t)
    local priority = weight / random()

    local new_cnt = self.cache:incr(self.count, 1, 0)
    if not new_cnt then
        return
    end

    if new_cnt <= self.size then
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

function _M.snapshot(self)
    local length = self.values:length()
    local copy = new_tab(length, 0)
    for i, value, weight in self.values:iterator() do
        copy[i] = { value = value, weight = weight }
    end

    sort(copy, function(a, b)
        return a.weight > b.weight
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
    self.cache:set(self.count, self.values:length())
end

return _M