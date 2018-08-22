-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable
local str_format = string.format
local worker_id = ngx.worker.id

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(key, name)
    return setmetatable({
        key = key,
        name = name,
        count = 0
    }, mt)
end

function _M.mark(self)
    self:mark(1)
end

function _M.mark(self, n)
    self.count = self.count + n
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    return self.count
end

function _M.get_values(self)
end

function _M.clear(self)
    self.count = 0
end

return _M