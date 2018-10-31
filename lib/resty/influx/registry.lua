-- Copyright (C) by Jianhao Dai (Toruneko)

local measurement = require "resty.influx.measurement"

local setmetatable = setmetatable
local concat = table.concat
local sort = table.sort
local md5 = ngx.md5
local ipairs = ipairs
local pairs = pairs

local _M = { _VERSION = '0.0.3' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

local function create_key(key, tags)
    if not tags then
        return md5(key)
    end

    local tab = new_tab(10, 0)
    tab[1] = key

    for name, value in pairs(tags) do
        tab[#tab + 1] = name .. ":" .. value
    end

    sort(tab)

    return md5(concat(tab, ","))
end

function _M.new(reporters)
    return setmetatable({
        map = new_tab(0, 100),
        reporters = reporters or {},
    }, mt)
end

function _M.measurement(self, key, tags)
    local hashkey = create_key(key, tags)
    if self.map[hashkey] then
        return self.map[hashkey]
    end

    local m = measurement.new(key, tags)
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