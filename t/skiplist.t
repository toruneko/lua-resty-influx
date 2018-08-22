# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_socket_log_errors off;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: histogram metrics reporter
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local skiplist = require "resty.influx.util.skiplist"
            local list = skiplist.new()
            for i = 1, 200, 1 do
                list:insert(i * 2, i, math.random())
            end
            for i = 1, 100, 1 do
                local value, weight, score = list:first()
                list:delete(score)
            end

            ngx.say(list:length())
        }
    }
--- request
GET /t
--- response_body
100
--- error_code: 200
--- no_error_log
[warn]

