-- Copyright (C) by Jianhao Dai (Toruneko)

local clock = require "resty.influx.util.clock"

local setmetatable = setmetatable
local str_format = string.format
local concat = table.concat
local str_gsub = string.gsub
local tonumber = tonumber
local pairs = pairs
local type = type

local _M = { _VERSION = '0.0.2' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

-- InfluxDB line protocol escaping rules:
--   measurement: escape "," and " "
--   tag key / tag value / field key: escape ",", "=" and " "
--   string field value: escape backslash and double quote
local function escape_measurement(str)
    return (str_gsub(tostring(str), "[, ]", "\\%0"))
end

local function escape_tag(str)
    return (str_gsub(tostring(str), "[,= ]", "\\%0"))
end

local function escape_value(str)
    return (str_gsub(tostring(str), "[\\\"]", "\\%0"))
end

local function concatenated_tags(tags)
    local tab = new_tab(20, 0)

    for key, value in pairs(tags) do
        tab[#tab + 1] = ","
        tab[#tab + 1] = escape_tag(key)
        tab[#tab + 1] = "="
        tab[#tab + 1] = escape_tag(value)
    end
    tab[#tab + 1] = " "

    return concat(tab, "")
end

local function concatenate_metrics(metrics)
    local tab = new_tab(0, 100)

    for key, value in pairs(metrics) do
        tab[#tab + 1] = escape_tag(key)
        tab[#tab + 1] = "="
        if type(value) == "string" then
            tab[#tab + 1] = "\""
            tab[#tab + 1] = escape_value(value)
            tab[#tab + 1] = "\""
        elseif type(value) == "number" then
            tab[#tab + 1] = tonumber(value)
        elseif type(value) == "boolean" then
            tab[#tab + 1] = value and "true" or "false"
        else
            tab[#tab + 1] = value
        end
        tab[#tab + 1] = ","
    end
    tab[#tab] = " "

    return concat(tab, "")
end

local function formated_time()
    return str_format("%16d", clock.usec_time())
end

function _M.new(name)
    return setmetatable({
        name = name,
        tags = new_tab(0, 10),
        metrics = new_tab(0, 100)
    }, mt)
end

function _M.tag(self, tags)
    for name, value in pairs(tags) do
        self.tags[name] = value == "" and "-" or value
    end
end

function _M.add(self, name, metrics)
    self.metrics[name] = metrics
end

function _M.lineProtocol(self)
    local tab = new_tab(4, 0)
    -- measurement
    tab[#tab + 1] = escape_measurement(self.name)
    -- tags
    tab[#tab + 1] = concatenated_tags(self.tags)
    -- metrics
    tab[#tab + 1] = concatenate_metrics(self.metrics)
    -- time
    tab[#tab + 1] = formated_time()

    return concat(tab, "")
end

return _M