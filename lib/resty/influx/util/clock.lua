-- Copyright (C) by Jianhao Dai (Toruneko)

local str_format = string.format
local tonumber = tonumber

local ngx_utime = ngx.usec_time
local ngx_time = ngx.time
local ngx_now = ngx.now

local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_null = ffi.null
local C = ffi.C
ffi.cdef [[
    struct clock_timeval_t {
        long int tv_sec;
        long int tv_usec;
    };

    int gettimeofday(struct clock_timeval_t *tv, void *tz);
]]

local _M = { _VERSION = '0.01' }

local function usectime()
    if ngx_utime then
        return tonumber(ngx_time()) .. str_format("%06d", tonumber(ngx_utime()))
    else
        local tm = ffi_new("struct clock_timeval_t")
        C.gettimeofday(tm, ffi_null)
        return tonumber(tm.tv_sec) .. str_format("%06d", tonumber(tm.tv_usec))
    end
end

function _M.sec_time()
    return ngx_time()
end

function _M.msec_time()
    return ngx_now() * 1000
end

function _M.usec_time()
    return tonumber(usectime())
end

return _M