# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 2);

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
_EOC_

no_long_string();
run_tests();

__DATA__

=== TEST 1: measurement is cached by key and tags
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local registry = require("resty.influx.registry").new()
            local a = registry:measurement("req", { host = "a", zone = "z" })
            local b = registry:measurement("req", { zone = "z", host = "a" })
            local c = registry:measurement("req", { host = "b", zone = "z" })
            local d = registry:measurement("req")
            ngx.say(a == b)
            ngx.say(a == c)
            ngx.say(a == d)
            ngx.say(a:get_key())
        }
    }
--- request
GET /t
--- response_body
true
false
false
req
--- error_code: 200

=== TEST 2: report clears metrics and resets the registry map
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local registry_mod = require("resty.influx.registry")
            local calls = 0
            local reporter = {
                report = function(self, measurement)
                    calls = calls + 1
                end
            }
            local registry = registry_mod.new({ reporter })
            local m = registry:measurement("req")
            m:counter("c"):mark(5)
            ngx.say(registry:measurement("req") == m)
            registry:report()
            ngx.say(calls)
            ngx.say(m:get_metrics("c") == nil)
            ngx.say(registry:measurement("req") == m)
            ngx.say(registry:measurement("req"):counter("c"):get_value())
        }
    }
--- request
GET /t
--- response_body
true
1
true
false
0
--- error_code: 200

=== TEST 3: measurements created during report are kept
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local registry
            local reporter = {
                report = function(self, measurement)
                    registry:measurement("during"):counter("c"):mark(3)
                end
            }
            registry = require("resty.influx.registry").new({ reporter })
            registry:measurement("before"):counter("c"):mark(1)
            registry:report()
            ngx.say(registry:measurement("during"):counter("c"):get_value())
            ngx.say(registry:measurement("before"):counter("c"):get_value())
        }
    }
--- request
GET /t
--- response_body
3
0
--- error_code: 200

=== TEST 4: every reporter receives every measurement and empty registry works
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local count = 0
            local r1 = { report = function() count = count + 1 end }
            local r2 = { report = function() count = count + 1 end }
            local registry = require("resty.influx.registry").new({ r1, r2 })
            registry:measurement("a"):counter("c"):mark(1)
            registry:measurement("b"):counter("c"):mark(1)
            registry:report()
            ngx.say(count)

            local empty = require("resty.influx.registry").new()
            empty:measurement("a"):counter("c"):mark(1)
            empty:report()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
4
ok
--- error_code: 200

=== TEST 5: measurement keeps cached metrics and only clears valued ones
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local registry = require("resty.influx.registry").new()
            local m = registry:measurement("a")
            local c = m:counter("c")
            local a = m:averager("a")
            ngx.say(m:counter("c") == c, ":", m:averager("a") == a)
            m:counter("c"):mark(1)
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
true:true
a
--- error_code: 200
