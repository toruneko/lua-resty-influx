# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 2);

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_socket_log_errors off;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    lua_shared_dict capture 1m;
    server {
        listen 12354;
        location = /write {
            content_by_lua_block {
                ngx.req.read_body()
                local dict = ngx.shared.capture
                dict:incr("write_count", 1, 0)
                dict:set("write_body", ngx.req.get_body_data())
                dict:set("write_args", ngx.var.args or "")
            }
        }
        location = /query {
            content_by_lua_block {
                local dict = ngx.shared.capture
                dict:incr("query_count", 1, 0)
                dict:set("query_args", ngx.var.args or "")
            }
        }
    }
_EOC_

no_long_string();
run_tests();

__DATA__

=== TEST 1: sync reporter writes line protocol with default options
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local reporter = require("resty.influx.db.reporter")
            local registry = require("resty.influx.registry")
            local rep = reporter.new("http://127.0.0.1:12354", "user", "pass", "nginx", {
                tags = { host = "h" }
            })
            local reg = registry.new({ rep })
            reg:measurement("req", { zone = "z" }):counter("c"):mark(2)
            reg:report()

            local args = dict:get("write_args") or ""
            local body = dict:get("write_body") or ""
            ngx.say(dict:get("write_count") or 0)
            ngx.say(args:find("u=user", 1, true) ~= nil and args:find("p=pass", 1, true) ~= nil
                and args:find("db=nginx", 1, true) ~= nil)
            ngx.say(args:find("rp=default", 1, true) ~= nil
                and args:find("precision=u", 1, true) ~= nil
                and args:find("consistency=one", 1, true) ~= nil)
            ngx.say(body:find("^req,", 1) ~= nil and body:find("host=h", 1, true) ~= nil
                and body:find("zone=z", 1, true) ~= nil and body:find("c=2", 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
1
true
true
true
--- error_code: 200

=== TEST 2: client write supports custom options
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local client = require "resty.influx.db.client"
            local c = client.new("http://127.0.0.1:12354", "u2", "p2", "db2")
            c:write({
                lineProtocol = function() return "m v=1" end
            }, {
                rp = "rp2",
                precision = "ms",
                consistency = "all"
            })
            local args = dict:get("write_args") or ""
            ngx.say(dict:get("write_count") or 0)
            ngx.say(args:find("u=u2", 1, true) ~= nil and args:find("db=db2", 1, true) ~= nil
                and args:find("rp=rp2", 1, true) ~= nil
                and args:find("precision=ms", 1, true) ~= nil
                and args:find("consistency=all", 1, true) ~= nil)
            ngx.say(dict:get("write_body"))
        }
    }
--- request
GET /t
--- response_body
1
true
m v=1
--- error_code: 200

=== TEST 3: client query sends the query string
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local client = require "resty.influx.db.client"
            local c = client.new("http://127.0.0.1:12354", "u", "p", "db")
            c:query("select * from m")
            local args = dict:get("query_args") or ""
            ngx.say(dict:get("query_count") or 0)
            ngx.say(args:find("q=select", 1, true) ~= nil
                and args:find("db=db", 1, true) ~= nil
                and args:find("u=u", 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
1
true
--- error_code: 200

=== TEST 4: async reporter flushes buffered points on a timer
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local reporter = require "resty.influx.db.reporter"
            local registry = require "resty.influx.registry"
            local rep = reporter.new("http://127.0.0.1:12354", "u", "p", "db", {
                async = true,
                interval = 0.05,
                size = 100,
                tags = { host = "h" }
            })
            local reg = registry.new({ rep })
            reg:measurement("async"):counter("c"):mark(7)
            reg:report()
            ngx.say(dict:get("write_count") or 0)
            ngx.sleep(0.4)
            local body = dict:get("write_body") or ""
            ngx.say(dict:get("write_count") or 0)
            ngx.say(body:find("async", 1, true) ~= nil and body:find("c=7", 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
0
1
true
--- error_code: 200

=== TEST 5: async reporter flushes when the buffer reaches its size
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local reporter = require "resty.influx.db.reporter"
            local registry = require "resty.influx.registry"
            local rep = reporter.new("http://127.0.0.1:12354", "u", "p", "db", {
                async = true,
                interval = 60,
                size = 2,
                tags = { host = "h" }
            })
            local reg = registry.new({ rep })
            for i = 1, 3 do
                reg:measurement("buf"):counter("c"):mark(i)
                reg:report()
            end
            local body = dict:get("write_body") or ""
            local lines = 0
            for _ in body:gmatch("c=%d+") do
                lines = lines + 1
            end
            ngx.say(dict:get("write_count") or 0)
            ngx.say(lines)
            ngx.say(body:find("c=1", 1, true) ~= nil and body:find("c=2", 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
1
2
true
--- error_code: 200

=== TEST 6: metrics without values are not written
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local reporter = require "resty.influx.db.reporter"
            local registry = require "resty.influx.registry"
            local rep = reporter.new("http://127.0.0.1:12354", "u", "p", "db")
            local reg = registry.new({ rep })
            reg:measurement("empty"):counter("c")
            reg:report()
            ngx.say(dict:get("write_count") or 0)
        }
    }
--- request
GET /t
--- response_body
0
--- error_code: 200

=== TEST 7: measurement tags override reporter tags
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.capture
            dict:flush_all()
            local reporter = require "resty.influx.db.reporter"
            local registry = require "resty.influx.registry"
            local rep = reporter.new("http://127.0.0.1:12354", "u", "p", "db", {
                tags = { host = "global", env = "prod" }
            })
            local reg = registry.new({ rep })
            reg:measurement("m", { host = "local" }):counter("c"):mark(1)
            reg:report()
            local body = dict:get("write_body") or ""
            ngx.say(body:find("host=local", 1, true) ~= nil)
            ngx.say(body:find("host=global", 1, true) == nil)
            ngx.say(body:find("env=prod", 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
true
true
true
--- error_code: 200
