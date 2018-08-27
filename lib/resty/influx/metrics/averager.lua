-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(key, name)
    return setmetatable({
        key = key,
        name = name,
        sum = 0,
        count = 0
    }, mt)
end

function _M.update(self, value)
    self.sum = self.sum + value
    self.count = self.count + 1
end

function _M.has_value(self)
    return self:get_value() > 0
end

function _M.get_value(self)
    if self.count == 0 then
        return 0
    end
    return self.sum / self.count
end

function _M.get_values(self)
end

function _M.clear(self)
    self.sum = 0
    self.count = 0
end

return _M