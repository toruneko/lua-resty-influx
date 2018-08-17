-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable
local sqrt = math.sqrt

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

function _M.new(data, length)
    local values = new_tab(length, 0)
    local weights = new_tab(length, 0)
    local quantiles = new_tab(length, 0)
    quantiles[1] = 0

    local sum_weight = 0.0
    for i = 1, length, 1 do
        sum_weight = sum_weight + data[i].weight
    end

    for i = 1, length, 1 do
        values[i] = data[i].value
        weights[i] = data[i].weight / sum_weight
    end

    for i = 2, length, 1 do
        quantiles[i] = quantiles[i - 1] + weights[i - 1]
    end

    return setmetatable({
        length = length,
        values = values,
        weights = weights,
        quantiles = quantiles
    }, mt)
end

function _M.value(self, quantile)
    if not quantile or quantile < 0.0 or quantile > 1.0 then
        return 0.0
    end

    if #self.values == 0 then
        return 0.0
    end

    for i = 1, self.length, 1 do
        if self.quantiles[i] > quantile then
            if i == 1 then
                return self.values[1]
            else
                return self.values[i - 1]
            end
        end
    end

    return self.values[self.length]
end

function _M.max(self)
    if self.length == 0 then
        return 0.0
    end

    return self.values[self.length]
end

function _M.min(self)
    if self.length == 0 then
        return 0.0
    end

    return self.values[1]
end

function _M.mean(self)
    if self.length == 0 then
        return 0.0
    end

    local sum = 0.0
    for i = 1, self.length, 1 do
        sum = sum + (self.values[i] * self.weights[i])
    end

    return sum
end

function _M.median(self)
    return self:value(0.5)
end

function _M.p75(self)
    return self:value(0.75)
end

function _M.p95(self)
    return self:value(0.95)
end

function _M.p98(self)
    return self:value(0.98)
end

function _M.p99(self)
    return self:value(0.99)
end

function _M.p999(self)
    return self:value(0.999)
end

function _M.stddev(self)
    if self.length <= 1 then
        return 0.0
    end

    local mean = self:mean()
    local variance = 0.0

    for i = 1, self.length, 1 do
        local diff = self.values[i] - mean
        variance = variance + self.weights[i] * diff * diff
    end

    return sqrt(variance)
end

return _M