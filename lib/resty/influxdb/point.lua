-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable
local str_format = string.format
local concat = table.concat
local tonumber = tonumber
local ngx_time = ngx.time
local pairs = pairs
local error = error
local type = type

local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_null = ffi.null
local C = ffi.C
ffi.cdef [[
    struct timeval {
        long int tv_sec;
        long int tv_usec;
    };

    int gettimeofday(struct timeval *tv, void *tz);
]]

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

-- escape value " ", ",", "=" => "\\ ", "\\,", "\\="
local function escape(value)
    return value
end

local function concatenated_tags(tags)
    local tab = new_tab(20, 0)

    for key, value in pairs(tags) do
        tab[#tab + 1] = ","
        tab[#tab + 1] = escape(key)
        tab[#tab + 1] = "="
        tab[#tab + 1] = escape(value)
    end
    tab[#tab + 1] = " "

    return concat(tab, "")
end

--[[
		NumberFormat numberFormat = NumberFormat.getInstance(Locale.ENGLISH);
		numberFormat.setMaximumFractionDigits(340);
		numberFormat.setGroupingUsed(false);
		numberFormat.setMinimumFractionDigits(1);
 ]]
local function concatenate_metrics(metrics)
    local tab = new_tab(0, 100)

    for key, value in pairs(metrics) do
        tab[#tab + 1] = escape(key)
        tab[#tab + 1] = "="
        if type(value) == "string" then
            tab[#tab + 1] = "\""
            tab[#tab + 1] = escape(value)
            tab[#tab + 1] = "\""
        elseif type(value) == "number" then
            tab[#tab + 1] = tonumber(value)
        else
            tab[#tab + 1] = value
        end
        tab[#tab + 1] = ","
    end
    tab[#tab] = " "

    return concat(tab, "")
end

local function formated_time()
    if ngx.usec_time then
        return (tonumber(ngx_time()) + (tonumber(ngx.usec_time()) / 1000 / 1000)) * 1000 * 1000 * 1000
    else
        local tm = ffi_new("struct timeval")
        C.gettimeofday(tm, ffi_null)
        return (tonumber(tm.tv_sec) + (tonumber(tm.tv_usec) / 1000 / 1000)) * 1000 * 1000 * 1000
    end
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
        self.tags[name] = value
    end
end

function _M.add(self, name, metrics)
    self.metrics[name] = metrics
end

function _M.lineProtocol(self)
    local tab = new_tab(4, 0)
    -- measurement
    tab[#tab + 1] = escape(self.name)
    -- tags
    tab[#tab + 1] = concatenated_tags(self.tags)
    -- metrics
    tab[#tab + 1] = concatenate_metrics(self.metrics)
    -- time
    tab[#tab + 1] = formated_time()

    return concat(tab, "")
end

return _M