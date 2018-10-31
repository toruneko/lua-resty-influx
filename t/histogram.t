# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

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
qr/histogram,host=127.0.0.1 size.p999=7,size.p99=7,size.count=3,rt=1\d,size.median=7,size.std_dev=1.8856180831641,size.p75=7,size.p98=7,size=3,size.mean=5.6666666666667,size.min=3,size.max=7,size.p95=7 \d+/
--- no_error_log
[warn]

