-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable
local str_format = string.format
local worker_id = ngx.worker.id

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(m_key, name, cache)
    return setmetatable({
        cache = cache,
        sum = str_format("%s%s:%s:%s", m_key, worker_id(), "avg:sum", name),
        count = str_format("%s%s:%s:%s", m_key, worker_id(), "avg:cnt", name)
    }, mt)
end

function _M.update(self, value)
    self.cache:incr(self.sum, value, 0)
    self.cache:incr(self.count, 1, 0)
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    local sum = self.cache:get(self.sum)
    local count = self.cache:get(self.count)
    if not count or count == 0 then
        return 0
    end
    return sum / count
end

function _M.get_values(self)
end

function _M.clear(self)
    self.cache:delete(self.sum)
    self.cache:delete(self.count)
end

return _M