-- Copyright (C) by Jianhao Dai (Toruneko)
local point = require "resty.influxdb.point"
local http = require "resty.http"

local setmetatable = setmetatable
local pairs = pairs

local DEFAULT_RETENTION_POLICY = "default"

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(url, username, password, database, tags)
    local reporter = setmetatable({
        url = url,
        username = username,
        password = password,
        database = database,
        tags = tags
    }, mt)

    reporter:query(database, "CREATE DATABASE \"" + database + "\" WITH DURATION 2w REPLICATION 1 NAME \"default\"")

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
        self:write(self.database, DEFAULT_RETENTION_POLICY, p)
    end
end

function _M.write(self, db, rp, point)
    local httpc = http:new()
    httpc:set_timeout(5000)

    local response = httpc:request_uri(self.url, {
        path = "write",
        method = "POST",
        headers = {
            ["Content-Type"] = "text/plain"
        },
        query = {
            u = self.username,
            p = self.password,
            db = db,
            rp = rp,
            precision = "n",
            consistency = "one"
        },
        body = point:lineProtocol()
    })
end

function _M.query(self, db, q)
    local httpc = http.new()
    httpc:set_timeout(5000)
    local response = httpc:request_uri(self.url, {
        path = "query",
        method = "POST",
        query = {
            u = self.username,
            p = self.password,
            db = db,
            q = q
        }
    })
end

return _M