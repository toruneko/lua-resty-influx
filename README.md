Name
=============

lua-resty-influx - lua influx metrics module for OpenResty/LuaJIT

Status
======

This library is considered production ready.

Build status: [![Travis](https://travis-ci.org/toruneko/lua-resty-influx.svg?branch=master)](https://travis-ci.org/toruneko/lua-resty-influx)

Description
===========

This library requires an nginx build with [ngx_lua module](https://github.com/openresty/lua-nginx-module), and [LuaJIT 2.0](http://luajit.org/luajit.html).

Synopsis
========

```lua
    # nginx.conf:

    lua_package_path "/path/to/lua-resty-influx/lib/?.lua;;";
    lua_shared_dict metrics  1m;

    init_worker_by_lua_block {
        local resty_reporter = require "resty.influx.db.reporter"
        local reporter = resty_reporter.new("http://127.0.0.1:12354", "user", "pass", "nginx", {
            tags = {
                host = "127.0.0.1"
            },
            async = true -- auto flush reported data to influx
        })
        local resty_registry = require "resty.influx.registry"
        _G.registry = resty_registry.new{reporter}

        local func_reporter
        func_reporter = function(registry)
            registry:report()
        
            local ok, err = ngx.timer.at(10, func_reporter, registry)
            if not ok then
                error(err)
            end
        end

        local ok, err = ngx.timer.at(10, func_reporter, _G.registry)
        if not ok then
            error(err)
        end
    }

    server {
        location = /t {
            content_by_lua_block {
                local registry = _G.registry
                local measurement = registry:measurement("request", {tag_key = tag_val})
                local context = measurement:timer("rt"):time()

                pcall(function() 
                    for i = 1, 3 do
                        measurement:counter("tps"):mark(i)
                        measurement:averager("size"):update(i)
                        measurement:histogram("value"):update(i)
                    end
                    ngx.sleep(0.01)
                    ngx.update_time()
                end)

                context:stop()

                -- do report
                registry:report()
            }
        }
    }
    
```

Methods
=======

To load this library,

1. you need to specify this library's path in ngx_lua's [lua_package_path](https://github.com/openresty/lua-nginx-module#lua_package_path) directive. For example, `lua_package_path "/path/to/lua-resty-influx/lib/?.lua;;";`.
2. you use `require` to load the library into a local Lua variable:

```lua
    local resty_registry = require "resty.influx.registry"
```

new
---
`syntax: registry = resty_registry.new(reporters)`

Creates a new registry object instance.

```lua
-- creates a registry object
local resty_registry = require "resty.influx.registry"
local registry = resty_registry.new()
```

Report metrics to the influxdb.

```lua
local resty_reporter = require "resty.influx.db.reporter"
local reporter = resty_reporter.new("http://127.0.0.1:12354", "user", "pass", "nginx")

local resty_registry = require "resty.influx.registry"
local registry = resty_registry.new{ reporter }
```

measurement
----
`syntax: measurement = registry:measurement(key, {tag1= value1, tag2= value2, ... })`

Creates a measurement object instance.

```lua
local measurement = registry:measurement("request")
```

report
------
`syntax: registry:report()`

Report measurement to the reporters.

Author
======

Jianhao Dai (toruneko) <toruneko@outlook.com>


Copyright and License
=====================

This module is licensed under the MIT license.

Copyright (C) 2018, by Jianhao Dai (toruneko) <toruneko@outlook.com>

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


See Also
========
* the ngx_lua module: https://github.com/openresty/lua-nginx-module
