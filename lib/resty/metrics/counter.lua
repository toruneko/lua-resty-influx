-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(name, cache)
    return setmetatable({
        name = name,
        cache = cache,
        count = "metrics:count:" .. name
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
    return self.cache:get(self.count)
end

function _M.get_values(self)
end

function _M.clear(self)
    self.cache:delete(self.count)
end

return _M