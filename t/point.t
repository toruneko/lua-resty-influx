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

=== TEST 1: basic line protocol
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local point = require "resty.influx.db.point"
            local p = point.new("cpu")
            p:tag({ host = "127.0.0.1" })
            p:add("value", 42)
            local body, ts = p:lineProtocol():match("^(.-) (%d+)$")
            ngx.say(body)
            ngx.say(#ts)
        }
    }
--- request
GET /t
--- response_body
cpu,host=127.0.0.1 value=42
16
--- error_code: 200

=== TEST 2: escaping for measurement, tags and string fields
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local point = require "resty.influx.db.point"
            local p = point.new("cpu load")
            p:tag({
                ["host name"] = "a b",
                ["k=v"] = "x=y",
                ["c,d"] = "e,f",
            })
            p:add("field key", 'a,b "c" \\ d')
            local lp = p:lineProtocol()
            ngx.say(lp:find("^cpu\\ load,", 1) ~= nil)
            ngx.say(lp:find("host\\ name=a\\ b", 1, true) ~= nil)
            ngx.say(lp:find("k\\=v=x\\=y", 1, true) ~= nil)
            ngx.say(lp:find("c\\,d=e\\,f", 1, true) ~= nil)
            ngx.say(lp:find('field\\ key="a,b \\"c\\" \\\\ d"', 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
true
true
true
true
true
--- error_code: 200

=== TEST 3: integer, float, string, boolean field values
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local point = require "resty.influx.db.point"
            local p = point.new("m")
            p:add("i", 1)
            p:add("f", 2.5)
            p:add("s", "x,y")
            p:add("b", true)
            p:add("bf", false)
            local lp = p:lineProtocol()
            local function has(tok)
                return lp:find(tok, 1, true) ~= nil
            end
            ngx.say(has("i=1") and has("f=2.5") and has('s="x,y"')
                and has("b=true") and has("bf=false"))
        }
    }
--- request
GET /t
--- response_body
true
--- error_code: 200

=== TEST 4: no tags
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local point = require "resty.influx.db.point"
            local p = point.new("m")
            p:add("v", 1)
            ngx.say(p:lineProtocol():match("^(.-) %d+$"))
        }
    }
--- request
GET /t
--- response_body
m v=1
--- error_code: 200

=== TEST 5: duplicate field key, last value wins
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local point = require "resty.influx.db.point"
            local p = point.new("m")
            p:add("v", 1)
            p:add("v", 2)
            ngx.say(p:lineProtocol():match("^(.-) %d+$"))
        }
    }
--- request
GET /t
--- response_body
m v=2
--- error_code: 200

=== TEST 6: empty and numeric tag values
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local point = require "resty.influx.db.point"
            local p = point.new("m")
            p:tag({ host = "", port = 80 })
            p:add("v", 1)
            local body = p:lineProtocol():match("^(.-) %d+$")
            ngx.say(body:find("host=-", 1, true) ~= nil)
            ngx.say(body:find("port=80", 1, true) ~= nil)
        }
    }
--- request
GET /t
--- response_body
true
true
--- error_code: 200
