# lua-resty-influx

Lua InfluxDB metrics module for OpenResty / LuaJIT.

- **Status:** production ready
- **License:** MIT
- **Main module:** `resty.influx.registry`

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Synopsis](#synopsis)
  - [Asynchronous reporting (recommended)](#asynchronous-reporting-recommended)
  - [Synchronous reporting](#synchronous-reporting)
- [Concepts](#concepts)
- [API Reference](#api-reference)
  - [resty.influx.registry](#restyinfluxregistry)
  - [resty.influx.measurement](#restyinfluxmeasurement)
  - [Metrics](#metrics)
    - [counter](#counter)
    - [averager](#averager)
    - [timer](#timer)
    - [histogram](#histogram)
  - [resty.influx.db.reporter](#restyinfluxdbreporter)
  - [resty.influx.db.client](#restyinfluxdbclient)
  - [resty.influx.db.point](#restyinfluxdbpoint)
  - [resty.influx.util.clock](#restyinfluxutilclock)
- [Line Protocol Details](#line-protocol-details)
- [Notes and Limitations](#notes-and-limitations)
- [Testing](#testing)
- [Author](#author)
- [License](#license)

## Features

- Counter, averager, timer and histogram metrics.
- Metrics are grouped into measurements by name and tags, and reported as
  InfluxDB line protocol points.
- Synchronous or buffered/asynchronous reporting with automatic flushing.
- Measurement tags are merged with global reporter tags; measurement tags win.
- Correct line protocol escaping for measurement names, tag keys/values, field
  keys and string field values.
- Pure Lua/LuaJIT implementation; no shared memory or extra daemon required.

## Requirements

- [OpenResty](https://openresty.org/) with
  [lua-nginx-module](https://github.com/openresty/lua-nginx-module) and LuaJIT.
- [lua-resty-http](https://github.com/pintsized/lua-resty-http) (required by
  `resty.influx.db.client`).
- Optional: the patches under [`patches/`](patches) add `ngx.usec_time` for
  microsecond timestamps on older lua-nginx-module versions. Without them the
  library falls back to `gettimeofday(2)` through LuaJIT FFI.

## Installation

With [OPM](https://opm.openresty.org/):

```bash
opm get toruneko/lua-resty-influx
opm get pintsized/lua-resty-http
```

Or copy `lib/` into your Lua package path:

```nginx
lua_package_path "/path/to/lua-resty-influx/lib/?.lua;/path/to/lua-resty-http/lib/?.lua;;";
```

## Synopsis

### Asynchronous reporting (recommended)

`resty.influx.db.reporter` buffers points in the worker and flushes them on a
timer, so request handling never blocks on the InfluxDB HTTP call.

```nginx
# nginx.conf
lua_package_path "/path/to/lua-resty-influx/lib/?.lua;/path/to/lua-resty-http/lib/?.lua;;";

init_worker_by_lua_block {
    local reporter = require("resty.influx.db.reporter").new(
        "http://127.0.0.1:8086",   -- InfluxDB base URL
        "user", "pass", "metrics", -- username, password, database
        {
            tags = { host = "127.0.0.1" },
            async = true, -- buffer points and flush them on a timer
            size = 100,   -- flush when 100 points are buffered
            interval = 1, -- or every second
        })

    local registry = require("resty.influx.registry").new({ reporter })
    _G.metrics_registry = registry

    -- Report all recorded metrics every 10 seconds.
    local function report(premature)
        if premature then
            return
        end
        registry:report()

        local ok, err = ngx.timer.at(10, report)
        if not ok then
            ngx.log(ngx.ERR, "failed to create metrics timer: ", err)
        end
    end

    local ok, err = ngx.timer.at(10, report)
    if not ok then
        ngx.log(ngx.ERR, "failed to create metrics timer: ", err)
    end
}

server {
    location = /t {
        content_by_lua_block {
            local registry = _G.metrics_registry
            local measurement = registry:measurement("request", { path = ngx.var.uri })

            local ctx = measurement:timer("rt"):time()

            measurement:counter("tps"):mark()
            measurement:averager("size"):update(1024)
            measurement:histogram("value"):update(42)

            ctx:stop()
        }
    }
}
```

### Synchronous reporting

Without `async`, `registry:report()` performs one HTTP write per measurement
inside the calling request (or timer) and blocks until the write completes.

```lua
local reporter = require("resty.influx.db.reporter").new(
    "http://127.0.0.1:8086", "user", "pass", "metrics",
    { tags = { host = "127.0.0.1" } })

local registry = require("resty.influx.registry").new({ reporter })

-- ... record metrics ...

registry:report()
```

## Concepts

```
registry
  └── measurement (name + tags)
        ├── counter
        ├── averager
        ├── timer
        └── histogram
              └── reservoir / snapshot
                    └── reporter → client → InfluxDB /write
```

- **Registry** caches measurement objects by measurement name and tags.
- **Measurement** owns the metrics recorded for a given name + tag set.
- **Metrics** accumulate values until the next report.
- **Reporter** builds one point per measurement and writes it to InfluxDB,
  either immediately or through a buffer.
- `registry:report()` reports every measurement and then resets the recorded
  values, so each report covers the interval since the previous report.

## API Reference

### resty.influx.registry

```lua
local registry_module = require "resty.influx.registry"
local registry = registry_module.new(reporters)
```

`syntax: registry = registry_module.new(reporters)`

Creates a registry. `reporters` is an array of reporter objects; each object
must implement `reporter:report(measurement)`.

`syntax: measurement = registry:measurement(key, tags)`

Returns the cached measurement for `key` and `tags`, creating it if needed.
The cache key is a hash of the measurement name and the sorted tag pairs, so
tag order does not matter:

```lua
local a = registry:measurement("req", { host = "a", zone = "z" })
local b = registry:measurement("req", { zone = "z", host = "a" })
assert(a == b)

local c = registry:measurement("req", { host = "b", zone = "z" })
assert(a ~= c)
```

`syntax: registry:report()`

Reports every cached measurement to every reporter, then clears the recorded
metric values and the measurement cache. Measurements created while reporters
are running (for example during a cosocket yield in an asynchronous write) are
kept for the next report instead of being dropped.

A measurement object obtained before `report()` is detached afterwards; always
fetch the measurement inside the request scope (or re-fetch it after a report).

### resty.influx.measurement

Measurements are normally obtained from `registry:measurement()`.

| Method | Description |
| --- | --- |
| `measurement:counter(name)` | Returns the cached counter, creating it if needed. |
| `measurement:averager(name)` | Returns the cached averager. |
| `measurement:histogram(name, opts)` | Returns the cached histogram; `opts` is only used on creation. |
| `measurement:timer(name)` | Returns the cached timer. |
| `measurement:get_metricses()` | Returns the internal `name → metric` table. |
| `measurement:get_metrics(name)` | Returns one metric or `nil`. |
| `measurement:get_tags()` | Returns the tag table. |
| `measurement:get_key()` | Returns the measurement name. |
| `measurement:clear()` | Clears metrics that have values and removes them. |

A metric name is unique within a measurement regardless of type: calling
`measurement:histogram("x")` after `measurement:counter("x")` returns the
counter object. Do not reuse a name for different metric types.

### Metrics

All metrics implement `has_value()`, `get_value()`, `get_values()` and
`clear()`. Values are reset after every `registry:report()`.

#### counter

```lua
measurement:counter("tps"):mark()      -- add 1
measurement:counter("tps"):mark(5)     -- add 5
```

- `mark(n)` adds `n` (default `1`).
- `get_value()` returns the accumulated count.
- Reported field: `tps=<count>`.

#### averager

```lua
measurement:averager("size"):update(1024)
```

- `update(value)` adds one sample to the average.
- `get_value()` returns `sum / count` (or `0` when there are no samples).
- Reported field: `size=<average>`.
- An averager whose samples average to `0` (for example response size `0`) is
  still reported.

#### timer

```lua
local timer = measurement:timer("rt")
local ctx = timer:time()

-- ... measured code ...

local elapsed_ms = ctx:stop()
```

- `timer:time()` returns a context and records the start time.
- `ctx:stop()` records the elapsed milliseconds and returns it. Calling
  `stop()` twice raises an error.
- `timer:update(ms)` records a duration directly.
- `get_value()` returns the average duration; `get_values()` returns `nil`.
- Reported field: `rt=<average ms>`.
- Timing uses `ngx.now()`, which is cached. Call `ngx.update_time()` before
  `stop()` if you need fresh timing inside a long-running request.

#### histogram

```lua
local hist = measurement:histogram("latency", { size = 1024 })
hist:update(42.5)
local values = hist:get_values()
```

Options (`opts`, used only when the histogram is created):

| Option | Default | Description |
| --- | --- | --- |
| `exact` | `false` | Use the skiplist-backed weighted reservoir instead of the ring buffer. |
| `size` | `1028` | Reservoir capacity (number of retained samples). |
| `alpha` | `0.015` | Exponential decay factor used to weight samples. |

- `update(value)` records one sample.
- `get_value()` returns the number of samples in the current interval.
- `get_values()` returns a table with the distribution statistics:
  `count`, `min`, `max`, `mean`, `median`, `p75`, `p95`, `p98`, `p99`, `p999`,
  `std_dev`.
- `clear()` resets both the sample count and the reservoir, so a new report
  interval never includes samples from previous intervals.

The reporter writes the sample count as `latency=<count>` and every statistic
as `latency.<name>=<value>` (for example `latency.p95=12.5`,
`latency.mean=10.2`, `latency.std_dev=1.8`).

### resty.influx.db.reporter

```lua
local reporter = require("resty.influx.db.reporter").new(
    url, username, password, database, opts)
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `tags` | table | `{}` | Global tags added to every point. |
| `async` | boolean | `false` | Buffer points and flush them in a timer. |
| `size` | number | `100` | Flush when the buffer holds `size` points. |
| `interval` | number | `1` | Flush interval in seconds (async mode). |

Methods:

| Method | Description |
| --- | --- |
| `reporter:report(measurement)` | Builds one point from all metrics that have values and writes it. Empty points are skipped. |
| `reporter:write(point)` | Writes a point now (sync) or appends it to the buffer (async). |
| `reporter:flush()` | Sends all buffered points as one write request; no-op when the buffer is empty. |

Notes:

- Measurement tags are merged on top of the reporter's global tags, so a
  measurement tag with the same name overrides the global one.
- In async mode, flush errors are logged to the nginx error log and the flush
  timer keeps running.
- Buffered points have no retry: points that fail to reach InfluxDB are
  dropped.
- On worker exit, points still in the buffer are not flushed.

### resty.influx.db.client

```lua
local client = require("resty.influx.db.client").new(
    url, username, password, database)
```

`syntax: client:write(point, opts)`

Writes a point to `/write`. `point` is any object implementing
`lineProtocol()`.

| Option | Default | Description |
| --- | --- | --- |
| `rp` | `"default"` | Retention policy. |
| `precision` | `"u"` | Timestamp precision; the library generates microseconds. |
| `consistency` | `"one"` | Write consistency. |

`syntax: client:query(q)`

Sends `q` to `/query` with `POST`.

The client does not inspect the HTTP status; failed writes are silently
dropped. Use a capture/proxy or InfluxDB logs when debugging writes.

### resty.influx.db.point

Low-level line protocol builder used by the reporter.

```lua
local point = require("resty.influx.db.point").new("cpu")
point:tag({ host = "web-1" })
point:add("usage", 42)
point:add("state", "ok")
point:add("healthy", true)
local line = point:lineProtocol()
-- e.g. cpu,host=web-1 usage=42,state="ok",healthy=true 1700000000123456
-- (field order may vary)
```

| Method | Description |
| --- | --- |
| `point_module.new(name)` | Creates a point for a measurement. |
| `point:tag(tags)` | Merges tags; empty tag values become `"-"`. |
| `point:add(name, value)` | Adds a field. Numbers, strings and booleans are supported. |
| `point:lineProtocol()` | Serializes the point, including a microsecond timestamp. |

### resty.influx.util.clock

Internal clock helpers used for timestamps and histogram weights:

- `clock.sec_time()` — current time in seconds.
- `clock.msec_time()` — current time in milliseconds.
- `clock.usec_time()` — current time in microseconds. Uses `ngx.usec_time`
  when the patches under [`patches/`](patches) are applied; otherwise it falls
  back to `gettimeofday(2)` via LuaJIT FFI.

## Line Protocol Details

Measurements and tags are escaped according to the InfluxDB line protocol:

| Element | Escaped characters |
| --- | --- |
| Measurement name | `,` and space |
| Tag keys / tag values | `,`, `=` and space |
| Field keys | `,`, `=` and space |
| String field values | `\` and `"` (the value is double-quoted) |

Other details:

- Empty tag values are written as `-`.
- Timestamps are generated in microseconds and written with
  `precision=u` by default.
- Field order and tag order are not significant and may vary between runs.

## Notes and Limitations

- **Per-worker metrics.** The registry and reporter are plain Lua objects.
  Each nginx worker aggregates and reports its own metrics; nothing is shared
  or aggregated across workers. Add a tag that identifies the worker (for
  example `host`) and aggregate in InfluxDB if you need global values.
- **Async is recommended.** Synchronous reports block the current request or
  timer on the InfluxDB HTTP call.
- **No retries.** In async mode, flush errors are logged to the nginx error
  log; in sync mode HTTP failures are silent. Failed points are not retried.
- **Exact histogram precision.** The `exact` reservoir stores sample values in
  a C `long`, so fractional samples are truncated to integers. Use the default
  `exact = false` if sub-integer precision matters.
- **Timestamps.** Microsecond timestamps rely on `ngx.usec_time` (patched
  builds) or the FFI fallback; `ngx.now()` itself only has millisecond
  resolution.

## Testing

The test suite uses [Test::Nginx](https://github.com/openresty/test-nginx) and
runs against a real OpenResty build:

```bash
# install the test dependency
cpanm Test::Nginx

# run all tests
make test OPENRESTY_PREFIX=/path/to/openresty

# or invoke prove directly
prove -I../test-nginx/lib -r t
```

`TEST_NGINX_BINARY` may be used to point at a specific nginx/openresty binary.
The suite covers the registry, measurement, every metric type, reporter
(sync/async/buffer/tags), client, point escaping, clock, reservoirs and the
skiplist.

## Author

Jianhao Dai (toruneko) <toruneko@outlook.com>

## License

MIT. See [LICENSE](LICENSE) for the full license text.

## See Also

- [lua-nginx-module](https://github.com/openresty/lua-nginx-module)
- [lua-resty-http](https://github.com/pintsized/lua-resty-http)
- [InfluxDB line protocol](https://docs.influxdata.com/influxdb/v1.8/write_protocols/line_protocol_reference/)
