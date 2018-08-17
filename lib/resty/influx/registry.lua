-- Copyright (C) by Jianhao Dai (Toruneko)

local measurement = require "resty.influx.measurement"

local setmetatable = setmetatable
local concat = table.concat
local shared = ngx.shared
local error = error
local ipairs = ipairs
local pairs = pairs

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

local function create_key(key, tags)
    local tab = new_tab(10, 0)
    tab[1] = key

    for name, value in pairs(tags) do
        tab[#tab + 1] = name .. ":" .. value
    end

    return concat(tab, ",")
end

function _M.new(dict, reporters)
    local cache = shared[dict]
    if not cache then
        error("no shared dict: " .. dict)
    end

    return setmetatable({
        map = new_tab(0, 100),
        reporters = reporters or {},
        cache = cache
    }, mt)
end

function _M.measurement(self, key, tags)
    local hashkey = tags and create_key(key, tags) or key
    if self.map[hashkey] then
        return self.map[hashkey]
    end

    local m = measurement.new(key, tags, self.cache)
    self.map[hashkey] = m
    return m
end

function _M.report(self)
    local measurements = self.map
    for _, measurement in pairs(measurements) do
        for _, reporter in ipairs(self.reporters) do
            reporter:report(measurement)
        end
        measurement:clear()
    end
end

return _M