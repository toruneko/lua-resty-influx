-- Copyright (C) by Jianhao Dai (Toruneko)
local point = require "resty.influxdb.point"

local setmetatable = setmetatable
local pairs = pairs

local DEFAULT_RETENTION_POLICY = "default"

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(database, tags)
    return setmetatable({
        database = database,
        tags = tags
    }, mt)
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

function _M.write(self, database, policy, point)

end

return _M