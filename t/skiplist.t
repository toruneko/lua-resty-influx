# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(1);

plan tests => repeat_each() * 11;

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

=== TEST 2: first, last, select and iterator
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local skiplist = require "resty.influx.util.skiplist"
            local list = skiplist.new()
            for i = 1, 100 do
                list:insert(i, i * 2, i)
            end
            local count = 0
            for _ in list:iterator() do
                count = count + 1
            end
            ngx.say(count, ":", (list:first()), ":", (list:last()))
            ngx.say((list:select(50)), ":", tostring(list:select(101)))
        }
    }
--- request
GET /t
--- response_body
100:1:100
50:nil
--- error_code: 200

=== TEST 3: delete head and tail, then reinsert
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local skiplist = require "resty.influx.util.skiplist"
            local list = skiplist.new()
            for i = 1, 100 do
                list:insert(i, i, i)
            end
            for i = 1, 50 do
                list:delete(i)
            end
            ngx.say(list:length(), ":", (list:first()), ":", (list:last()))
            for i = 51, 100 do
                list:delete(i)
            end
            ngx.say(list:length(), ":", tostring(list:first()), ":", tostring(list:last()))
            for i = 1, 3 do
                list:insert(i, i, i)
            end
            ngx.say(list:length(), ":", (list:first()), ":", (list:last()))
        }
    }
--- request
GET /t
--- response_body
50:51:100
0:nil:nil
3:1:3
--- error_code: 200

=== TEST 4: duplicate scores
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local skiplist = require "resty.influx.util.skiplist"
            local list = skiplist.new()
            list:insert(1, 1, 0.5)
            list:insert(2, 2, 0.5)
            ngx.say(list:length(), ":", list:select(0.5) ~= nil)
            list:delete(0.5)
            ngx.say(list:length(), ":", list:select(0.5) ~= nil)
            list:delete(0.5)
            ngx.say(list:length(), ":", list:select(0.5) == nil)
        }
    }
--- request
GET /t
--- response_body
2:true
1:true
0:true
--- error_code: 200

=== TEST 5: repeated create and delete cycles
--- http_config eval
"$::HttpConfig"
--- config
    location = /t {
        content_by_lua_block {
            local skiplist = require "resty.influx.util.skiplist"
            for n = 1, 100 do
                local list = skiplist.new()
                for i = 1, 20 do
                    list:insert(i, i, math.random())
                end
                for i = 1, 10 do
                    local _, _, score = list:first()
                    list:delete(score)
                end
            end
            collectgarbage()
            collectgarbage()
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- error_code: 200

