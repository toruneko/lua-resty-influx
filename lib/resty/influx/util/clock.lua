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

if not pcall(ffi.typeof, "struct timeval_t") then
ffi.cdef [[
    typedef struct timeval_s {
        long int tv_sec;
        long int tv_usec;
    } timeval_t;

    int gettimeofday(timeval_t *tv, void *tz);
]]
end

local timeval_type = ffi.typeof("timeval_t")

local _M = { _VERSION = '0.0.2' }

local function usectime()
    if ngx_utime then
        return tonumber(ngx_time()) .. str_format("%06d", tonumber(ngx_utime()))
    else
        local tm = ffi_new(timeval_type)
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