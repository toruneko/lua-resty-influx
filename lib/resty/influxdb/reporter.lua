-- Copyright (C) by Jianhao Dai (Toruneko)
local point = require "resty.influxdb.point"
local client = require "resty.influxdb.client"

local setmetatable = setmetatable
local timer_at = ngx.timer.at
local concat = table.concat
local tonumber = tonumber
local pairs = pairs
local error = error

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

local do_flush
do_flush = function(premature, reporter)
    reporter:flush()

    local ok, err = timer_at(reporter.interval, do_flush, reporter)
    if not ok then
        error(err)
    end
end

function _M.new(url, username, password, database, opts)
    if not opts then
        opts = {}
    end
    opts.tags = opts.tags or {}
    opts.async = opts.async and true or false
    opts.size = tonumber(opts.size) or 100
    opts.interval = tonumber(opts.interval) or 1000

    local reporter = setmetatable({
        client = client.new(url, username, password, database),
        tags = opts.tags,
        async = opts.async,
        size = opts.size,
        interval = opts.interval,
        buffer = new_tab(opts.size, 0)
    }, mt)

    if reporter.async then
        local ok, err = timer_at(reporter.interval, do_flush, reporter)
        if not ok then
            error(err)
        end
    end

    reporter.client:query("CREATE DATABASE \"" + database + "\" WITH DURATION 2w REPLICATION 1 NAME \"default\"")

    return reporter
end

function _M.report(self, measurement)
    local p = point.new(measurement:get_key())
    p:tag(self.tags)
    p:tag(measurement:get_tags())
    local metricses = measurement:get_metrics()

    local empty = true
    for name, metrics in pairs(metricses) do
        if metrics:has_value() then
            p:add(name, metrics:get_value())
            local values = metrics:get_values()
            if values then
                for key, val in pairs(values) do
                    if val then
                        p:add(name .. "." .. key, val)
                    end
                end
            end
            empty = false
        end
    end
    if not empty then
        self:write(p)
    end
end

function _M.write(self, point)
    if self.async then
        self.buffer[#self.buffer + 1] = point:lineProtocol()
        if #self.buffer > self.size then
            self:flush()
        end
    else
        self.client:write(point)
    end
end

function _M.flush(self)
    if #self.buffer == 0 then
        return
    end

    local buffer = self.buffer
    self.buffer = new_tab(self.size, 0)

    self.client:write({
        lineProtocol = function()
            return concat(buffer, "\n")
        end
    })
end

return _M