-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable
local str_format = string.format
local worker_id = ngx.worker.id

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(m_key, name, cache)
    return setmetatable({
        cache = cache,
        count = str_format("%s%s:%s:%s", m_key, worker_id(), "cnt", name)
    }, mt)
end

function _M.mark(self)
    self:mark(1)
end

function _M.mark(self, n)
    self.cache:incr(self.count, n, 0)
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    return self.cache:get(self.count) or 0
end

function _M.get_values(self)
end

function _M.clear(self)
    self.cache:delete(self.count)
end

return _M