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

=== TEST 1: clock basic sanity
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local clock = require "resty.influx.util.clock"
            local sec = clock.sec_time()
            local msec = clock.msec_time()
            local usec = clock.usec_time()
            ngx.say(type(sec) == "number" and type(msec) == "number"
                and type(usec) == "number")
            ngx.say(usec > 1.6e15 and usec < 2.0e15)
            ngx.say(msec > 1.6e12)
            local usec2 = clock.usec_time()
            ngx.say(math.abs(usec2 - usec) < 1000000)
        }
    }
--- request
GET /t
--- response_body
true
true
true
true
--- error_code: 200

=== TEST 2: usec_time has microsecond resolution
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local clock = require "resty.influx.util.clock"
            ngx.update_time()
            local usec = clock.usec_time()
            local sec = clock.sec_time()
            ngx.say(math.floor(usec / 1000000) == sec)
            local part = usec - sec * 1000000
            ngx.say(part >= 0 and part < 1000000)
        }
    }
--- request
GET /t
--- response_body
true
true
--- error_code: 200
