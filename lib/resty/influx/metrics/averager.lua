-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(name, cache)
    return setmetatable({
        cache = cache,
        total = "metrics:avg:total:" .. name,
        count = "metrics:avg:count:" .. name
    }, mt)
end

function _M.update(self, num)
    self.cache:incr(self.total, num, 0)
    self.cache:incr(self.count, 1, 0)
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    local total = self.cache:get(self.total)
    local count = self.cache:get(self.count)
    if not count or count == 0 then
        return 0
    end
    return total / count
end

function _M.get_values(self)
end

function _M.clear(self)
    self.cache:delete(self.total)
    self.cache:delete(self.count)
end

return _M