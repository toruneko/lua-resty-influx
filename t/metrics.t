# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_socket_log_errors off;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    lua_shared_dict metrics  1m;
    init_worker_by_lua_block {
        local resty_reporter = require "resty.influxdb.reporter"
        local reporter = resty_reporter.new("http://127.0.0.1:12354", "user", "pass", "nginx", {
            tags = {
                host = "127.0.0.1"
            },
            async = true
        })
        local resty_registry = require "resty.registry"
        _G.registry = resty_registry.new("metrics", {reporter})
    }
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: metrics test
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
            for j = 1, 10 do
                local measurement = registry:measurement("request" .. j, "partner", "damai")
                local context = measurement:timer("rt"):time()

                for i = 1, 10 do
                    measurement:counter("tps"):mark(i)
                    measurement:averager("size"):update(i)
                end

                context:stop()
            end

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
--- no_error_log
[error]


