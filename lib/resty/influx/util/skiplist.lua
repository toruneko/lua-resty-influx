-- Copyright (C) by Jianhao Dai (Toruneko)

local setmetatable = setmetatable
local tonumber = tonumber
local random = math.random

local bit = require "bit"
local bor = bit.bor
local band = bit.band

local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_null = ffi.null
local C = ffi.C

ffi.cdef [[
typedef struct skiplistdata {
    long    value;
    double  weight;
} skiplistdata;

typedef struct skiplistnode {
    double                 score;
    skiplistdata          *data;
    struct skiplistnode   *backward;

    struct skiplistlevel {
        struct skiplistnode    *forward;
        unsigned int            span;
    } *level;
} skiplistnode;

typedef struct skiplist {
    skiplistnode     *header, *tail;
    unsigned long     length;
    int               level;
} skiplist;
]]
local skiplist_type = ffi.typeof("skiplist")
local node_type = ffi.typeof("skiplistnode")
local node_ptr_arr_type = ffi.typeof("skiplistnode*[?]")
local data_type = ffi.typeof("skiplistdata")
local level_arr_type = ffi.typeof("struct skiplistlevel[?]")

local SKIPLIST_MAXLEVEL = 32
local SKIPLIST_P = 0.25

local function data_create(value, weight)
    local data = ffi_new(data_type)
    data.value = value
    data.weight = weight

    return data
end

local function node_create(level, score, data)
    local node = ffi_new(node_type)
    node.score = score
    node.data = data
    node.level = ffi_new(level_arr_type, level)

    return node
end

local function list_create()
    local list = ffi_new(skiplist_type)
    list.level = 1
    list.length = 0
    list.header = node_create(SKIPLIST_MAXLEVEL, 0, ffi_null)
    for i = 0, SKIPLIST_MAXLEVEL - 1, 1 do
        list.header.level[i].forward = ffi_null
        list.header.level[i].span = 0
    end
    list.header.backward = ffi_null
    list.tail = ffi_null

    return list
end

local function random_level()
    local level = 1
    while band(random(), 0xFFFF) < (SKIPLIST_P * 0xFFFF) do
        level = level + 1
        return level < SKIPLIST_MAXLEVEL and level or SKIPLIST_MAXLEVEL
    end
end

local function list_insert(list, score, data)
    local update = ffi_new(node_ptr_arr_type, SKIPLIST_MAXLEVEL)
    local rank = ffi_new("unsigned int[?]", SKIPLIST_MAXLEVEL)
    local x, i, level

    local x = list.header
    for i = list.level - 1, 0, -1 do
        rank[i] = i == (list.level - 1) and 0 or rank[i + 1]
        while x.level[i].forward ~= ffi_null and
                x.level[i].forward.score < score do
            rank[i] = rank[i] + x.level[i].span
            x = x.level[i].forward
        end
        update[i] = x
    end

    local level = random_level()
    if level > list.level then
        for i = list.level, level - 1, 1 do
            rank[i] = 0
            update[i] = list.header
            update[i].level[i].span = list.length
        end
        list.level = level
    end

    local x = node_create(level, score, data)
    for i = 0, level - 1, 1 do
        x.level[i].forward = update[i].level[i].forward
        update[i].level[i].forward = x;

        -- update span covered by update[i] as x is inserted here
        x.level[i].span = update[i].level[i].span - (rank[0] - rank[i]);
        update[i].level[i].span = (rank[0] - rank[i]) + 1;
    end

    for i = level, list.level - 1, 1 do
        update[i].level[i].span = update[i].level[i].span + 1
    end

    x.backward = (update[0] == list.header) and ffi_null or update[0]
    if x.level[0].forward ~= ffi_null then
        x.level[0].forward.backward = x
    else
        list.tail = x
    end
    list.length = list.length + 1
    return x
end

local function node_delete(list, x, update)
    for i = 0, list.level - 1, 1 do
        if update[i].level[i].forward == x then
            update[i].level[i].span = update[i].level[i].span + x.level[i].span - 1
            update[i].level[i].forward = x.level[i].forward
        else
            update[i].level[i].span = update[i].level[i].span - 1
        end
    end

    if x.level[0].forward ~= ffi_null then
        x.level[0].forward.backward = x.backward
    else
        list.tail = x.backward
    end

    while list.level > 1 and list.header.level[list.level - 1].forward == ffi_null do
        list.level = list.level - 1
    end

    list.length = list.length - 1
end

local function list_delete(list, score)
    local update = ffi_new(node_ptr_arr_type, SKIPLIST_MAXLEVEL)
    local x = list.header
    for i = list.level - 1, 0, -1 do
        while x.level[i].forward ~= ffi_null and
                x.level[i].forward.score < score do
            x = x.level[i].forward
        end
        update[i] = x
    end
    x = x.level[0].forward
    if x ~= ffi_null and score == x.score then
        node_delete(list, x, update)
        return 1
    end

    return 0
end

local function list_first(list)
    local x = list.header.level[0].forward
    if x == ffi_null then
        return ffi_null
    end

    return x
end

local function list_last(list)
    local x = list.header
    for i = list.level - 1, 0, -1 do
        while x.level[i].forward ~= ffi_null do
            x = x.level[i].forward
        end
    end

    if x == ffi_null then
        return ffi_null
    end

    return x
end

local function list_select(list, score)
    local x = list.header
    for i = list.level - 1, 0, -1 do
        while x.level[i].forward ~= ffi_null and
                x.level[i].forward.score < score do
            x = x.level[i].forward
        end
    end

    x = x.level[0].forward
    if x ~= ffi_null and score == x.score then
        return x
    end

    return ffi_null
end

local function list_first_inrange(list, min, max)
    local x = list.header
    for i = list.level - 1, 0, -1 do
        while x.level[i].forward ~= ffi_null and
                x.level[i].forward.score < min do
            x = x.level[i].forward
        end
    end

    x = x.level[0].forward
    if x == ffi_null then
        return ffi_null
    end

    if x.score > max then
        return ffi_null
    end

    return x
end

local function list_last_inrange(list, min, max)
    local x = list.header
    for i = list.level - 1, 0, -1 do
        while x.level[i].forward ~= ffi_null and
                x.level[i].forward.score <= max do
            x = x.level[i].forward
        end
    end

    if x == ffi_null then
        return ffi_null
    end

    if x.score < min then
        return ffi_null
    end

    return x
end

local function iterator(list, index)
    local x = list.header
    local j = 0
    for i = list.level - 1, 0, -1 do
        while x.level[i].forward ~= ffi_null and j < index do
            x = x.level[i].forward
            j = j + 1
        end
    end

    x = x.level[0].forward
    if x == ffi_null then
        return nil, nil
    else
        return index + 1, tonumber(x.data.value), x.data.weight, x.score
    end
end

local _M = { _VERSION = '0.01' }
local mt = { __index = _M }

function _M.new()
    return setmetatable({ list = list_create() }, mt)
end

function _M.insert(self, value, weight, score)
    local data = data_create(value, weight)
    list_insert(self.list, score, data)
end

function _M.delete(self, score)
    return list_delete(self.list, score) == 1
end

function _M.select(self, score)
    local x = list_select(self.list, score)
    if x == ffi_null then
        return nil
    end

    return tonumber(x.data.value), x.data.weight, x.score
end

function _M.iterator(self)
    return iterator, self.list, 0
end

function _M.first(self)
    local x = list_first(self.list)
    if x == ffi_null then
        return nil
    end

    return tonumber(x.data.value), x.data.weight, x.score
end

function _M.last(self)
    local x = list_last(self.list)
    if x == ffi_null then
        return nil
    end

    return tonumber(x.data.value), x.data.weight, x.score
end

function _M.length(self)
    return tonumber(self.list.length)
end

return _M