-- Copyright (C) by Jianhao Dai (Toruneko)
local http = require "resty.http"

local setmetatable = setmetatable

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new(url, username, password, db)
    return setmetatable({
        url = url,
        username = username,
        password = password,
        database = db,
    }, mt)
end

function _M.write(self, point, opts)
    if not opts then
        opts = {}
    end
    opts.rp = opts.rp or "default"
    opts.precision = opts.precision or "u"
    opts.consistency = opts.consistency or "one"

    local httpc = http:new()
    httpc:set_timeout(5000)

    httpc:request_uri(self.url, {
        path = "/write",
        method = "POST",
        headers = {
            ["Content-Type"] = "text/plain"
        },
        query = {
            u = self.username,
            p = self.password,
            db = self.database,
            rp = opts.rp,
            precision = opts.precision,
            consistency = opts.consistency
        },
        body = point:lineProtocol()
    })
end

function _M.query(self, q)
    local httpc = http.new()
    httpc:set_timeout(5000)

    httpc:request_uri(self.url, {
        path = "/query",
        method = "POST",
        query = {
            u = self.username,
            p = self.password,
            db = self.database,
            q = q
        }
    })
end

return _M