# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * 14;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_socket_log_errors off;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    lua_shared_dict metrics  1m;
    init_worker_by_lua_block {
        local resty_reporter = require "resty.influx.db.reporter"
        local reporter = resty_reporter.new("http://127.0.0.1:12354", "user", "pass", "nginx", {
            tags = {
                host = "127.0.0.1"
            },
            async = true
        })
        local resty_registry = require "resty.influx.registry"
        _G.registry = resty_registry.new{reporter}
    }
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: metrics reporter
--- http_config eval
"$::HttpConfig"
. q{
server {
    listen 12354;
    location = /write {
        content_by_lua_block {
            ngx.req.read_body()
            ngx.log(ngx.ERR, ngx.req.get_body_data())
        }
    }
}
}
--- config
    location = /t {
        content_by_lua_block {
            local registry = _G.registry
            local measurement = registry:measurement("request")
            local context = measurement:timer("rt"):time()

             pcall(function()
                 for i = 1, 3 do
                     measurement:counter("tps"):mark(i)
                     measurement:averager("size"):update(i)
                 end
                 ngx.sleep(0.01)
                 ngx.update_time()
             end)

            context:stop()

            registry:report()
            ngx.sleep(2)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- error_code: 200
--- error_log eval
qr/request,host=127\.0\.0\.1 (?=.*\brt=1\d\b)(?=.*\bsize=2\b)(?=.*\btps=6\b)\S+ \d+/
--- no_error_log
[warn]

=== TEST 2: counter mark, has_value and clear
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local counter = require "resty.influx.metrics.counter"
            local c = counter.new("k", "c")
            ngx.say(tostring(c:has_value()))
            c:mark()
            c:mark(4)
            ngx.say(c:get_value(), ":", c:has_value(), ":", tostring((c:get_values())))
            c:clear()
            ngx.say(c:get_value(), ":", tostring(c:has_value()))
        }
    }
--- request
GET /t
--- response_body
false
5:true:nil
0:false
--- error_code: 200

=== TEST 3: averager update, has_value and clear
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local averager = require "resty.influx.metrics.averager"
            local a = averager.new("k", "a")
            ngx.say(tostring(a:has_value()))
            a:update(0)
            ngx.say(a:has_value(), ":", a:get_value())
            a:update(10)
            ngx.say(a:get_value())
            a:clear()
            ngx.say(a:has_value(), ":", a:get_value())
        }
    }
--- request
GET /t
--- response_body
false
true:0
5
false:0
--- error_code: 200

=== TEST 4: timer context stop and update
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local timer = require "resty.influx.metrics.timer"
            local t = timer.new("k", "t")
            ngx.say(tostring(t:has_value()))
            local ctx = t:time()
            local elapsed = ctx:stop()
            ngx.say(elapsed >= 0, ":", t:has_value())
            local ok, err = pcall(function() ctx:stop() end)
            ngx.say(ok, ":", tostring(err):find("timer context already stopped") ~= nil)
            local t2 = timer.new("k", "t2")
            t2:update(5)
            t2:update(15)
            ngx.say(t2:get_value(), ":", tostring((t2:get_values())))
        }
    }
--- request
GET /t
--- response_body
false
true:true
false:true
10:nil
--- error_code: 200

=== TEST 5: measurement accessors and clear
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local measurement = require "resty.influx.measurement"
            local m = measurement.new("req", { host = "h" })
            ngx.say(m:get_key(), ":", m:get_tags().host)
            local c = m:counter("c")
            ngx.say(m:counter("c") == c, ":", m:get_metrics("c") == c, ":",
                tostring(m:get_metrics("missing")))
            c:mark(1)
            m:averager("a")
            m:clear()
            local names = {}
            for name in pairs(m:get_metricses()) do
                names[#names + 1] = name
            end
            table.sort(names)
            ngx.say(table.concat(names, ","))
        }
    }
--- request
GET /t
--- response_body
req:h
true:true:nil
a
--- error_code: 200

=== TEST 6: zero valued averager is reported
--- http_config eval
"$::HttpConfig"
. q{
server {
    listen 12354;
    location = /write {
        content_by_lua_block {
            ngx.req.read_body()
            ngx.shared.capture:set("body", ngx.req.get_body_data())
        }
    }
}
lua_shared_dict capture 1m;
}
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            local reporter = require "resty.influx.db.reporter"
            local registry = require "resty.influx.registry"
            local rep = reporter.new("http://127.0.0.1:12354", "u", "p", "db", {
                tags = { host = "127.0.0.1" }
            })
            local reg = registry.new({ rep })
            reg:measurement("request"):averager("zero"):update(0)
            reg:report()
            local body = dict:get("body") or ""
            ngx.say(body:find("zero=0", 1, true) ~= nil)
            ngx.say(body:find("^request,host=127.0.0.1", 1) ~= nil)
        }
    }
--- request
GET /t
--- response_body
true
true
--- error_code: 200
