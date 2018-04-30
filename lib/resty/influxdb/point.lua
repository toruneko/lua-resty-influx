-- Copyright (C) by Jianhao Dai (Toruneko)


local setmetatable = setmetatable
local shared = ngx.shared
local pairs = pairs
local error = error

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
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

function _M.lineProtocol()
end

return _M