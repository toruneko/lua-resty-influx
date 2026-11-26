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

=== TEST 1: exact reservoir rescales after the rescale interval
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local clock = require "resty.influx.util.clock"
            local real_sec, real_usec = clock.sec_time, clock.usec_time
            local base = 1700000000
            clock.sec_time = function() return base end
            clock.usec_time = function() return base * 1000000 end

            local reservoir = require "resty.influx.metrics.histogram.reservoir"
            local r = reservoir.new("k", "r", { exact = true, size = 100 })
            for i = 1, 100 do
                r:update(i)
            end

            base = base + 7200
            clock.sec_time = function() return base end
            clock.usec_time = function() return base * 1000000 end
            for i = 1, 10 do
                r:update(50)
            end

            local s = r:snapshot()
            ngx.say(s.length > 0 and s:mean() > 0)
            ngx.say(s:mean() == s:mean() and s:stddev() == s:stddev())

            clock.sec_time = real_sec
            clock.usec_time = real_usec
        }
    }
--- request
GET /t
--- response_body
true
true
--- error_code: 200

=== TEST 2: non-exact reservoir statistics stay finite after long uptime
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local clock = require "resty.influx.util.clock"
            local real_sec, real_usec = clock.sec_time, clock.usec_time
            local base = 1700000000
            clock.sec_time = function() return base end
            clock.usec_time = function() return base * 1000000 end

            local reservoir = require "resty.influx.metrics.histogram.reservoir"
            local r = reservoir.new("k", "n", { size = 100 })
            for i = 1, 10 do
                r:update(i)
            end

            -- more than 13 hours later the old weight formula overflowed to inf
            base = base + 50000
            clock.sec_time = function() return base end
            clock.usec_time = function() return base * 1000000 end
            for i = 1, 10 do
                r:update(i)
            end

            local s = r:snapshot()
            ngx.say(s:mean() == s:mean())
            ngx.say(s:stddev() == s:stddev())
            ngx.say(s.length, ":", s:max())

            clock.sec_time = real_sec
            clock.usec_time = real_usec
        }
    }
--- request
GET /t
--- response_body
true
true
20:10
--- error_code: 200
