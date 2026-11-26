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

=== TEST 1: histogram metrics reporter
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
            local measurement = registry:measurement("histogram")
            local context = measurement:timer("rt"):time()

             pcall(function()
                 for i = 1, 3 do
                     measurement:histogram("size", { exact = true }):update(math.random() * 10)
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
qr/histogram,host=127\.0\.0\.1 (?=.*\brt=1\d\b)(?=.*\bsize\.p999=7\b)(?=.*\bsize\.p99=7\b)(?=.*\bsize\.p98=7\b)(?=.*\bsize\.p95=7\b)(?=.*\bsize\.p75=7\b)(?=.*\bsize\.count=3\b)(?=.*\bsize\.median=7\b)(?=.*\bsize\.std_dev=1\.8856180831641\b)(?=.*\bsize\.mean=5\.6666666666667\b)(?=.*\bsize\.min=3\b)(?=.*\bsize\.max=7\b)(?=.*\bsize=3\b)\S+ \d+/
--- no_error_log
[warn]

=== TEST 2: non-exact reservoir statistics
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local histogram = require "resty.influx.metrics.histogram"
            local h = histogram.new("k", "h")
            for i = 1, 100 do
                h:update(i)
            end
            local v = h:get_values()
            ngx.say(h:get_value(), ":", v.count)
            ngx.say(v.min, ":", v.max, ":", math.abs(v.mean - 50.5) < 0.001)
        }
    }
--- request
GET /t
--- response_body
100:100
1:100:true
--- error_code: 200

=== TEST 3: exact reservoir exposes all distribution fields
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local histogram = require "resty.influx.metrics.histogram"
            local h = histogram.new("k", "h", { exact = true })
            for i = 1, 100 do
                h:update(i * 2)
            end
            local v = h:get_values()
            local keys = {}
            for key in pairs(v) do
                keys[#keys + 1] = key
            end
            table.sort(keys)
            ngx.say(table.concat(keys, ","))
            ngx.say(v.min, ":", v.max, ":", math.abs(v.mean - 101) < 1e-9,
                ":", v.std_dev > 0)
        }
    }
--- request
GET /t
--- response_body
count,max,mean,median,min,p75,p95,p98,p99,p999,std_dev
2:200:true:true
--- error_code: 200

=== TEST 4: clear drops previously recorded samples
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local histogram = require "resty.influx.metrics.histogram"
            local h = histogram.new("k", "e", { exact = true })
            h:update(1)
            h:update(2)
            h:clear()
            h:update(10)
            local v = h:get_values()
            ngx.say(h:has_value(), ":", h:get_value(), ":", v.min, ":", v.max)

            local r = histogram.new("k", "r")
            r:update(1)
            r:update(2)
            r:clear()
            local rv = r:get_values()
            ngx.say(r:has_value(), ":", r:get_value(), ":", rv.min, ":", rv.max)
        }
    }
--- request
GET /t
--- response_body
true:1:10:10
false:0:0:0
--- error_code: 200

=== TEST 5: empty histogram snapshot
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local histogram = require "resty.influx.metrics.histogram"
            local h = histogram.new("k", "empty")
            local v = h:get_values()
            ngx.say(v.min, ":", v.max, ":", v.mean, ":", v.median,
                ":", v.std_dev, ":", v.count)
            ngx.say(tostring(h:has_value()))
        }
    }
--- request
GET /t
--- response_body
0:0:0:0:0:0
false
--- error_code: 200

=== TEST 6: single sample statistics
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local histogram = require "resty.influx.metrics.histogram"
            local h = histogram.new("k", "one", { exact = true })
            h:update(42)
            local v = h:get_values()
            ngx.say(v.min, ":", v.max, ":", v.mean, ":", v.median, ":", v.std_dev)
            ngx.say(v.p99, ":", v.count)
        }
    }
--- request
GET /t
--- response_body
42:42:42:42:0
42:1
--- error_code: 200

