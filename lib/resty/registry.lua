-- Copyright (C) by Jianhao Dai (Toruneko)

local measurement = require "resty.measurement"

local setmetatable = setmetatable
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

local function create_key(key, ...)
    local arr = {...}
    local tags = new_tab(0, #arr / 2)
    for i = 1, #arr / 2 do
        tags[arr[i * 2 - 1]] = arr[i * 2]
    end
    return {
        key = key,
        tags = tags
    }
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

function _M.measurement(self, key, ...)
    local m_key = create_key(key, ...)
    if self.map[m_key] then
        return self.map[m_key]
    end

    local m = measurement.new(m_key, self.cache)
    self.map[m_key] = m
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