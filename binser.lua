-- binser.lua

--[[
Copyright (c) 2015 Calvin Rose

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local assert = assert
local error = error
local select = select
local pairs = pairs
local getmetatable = getmetatable
local setmetatable = setmetatable
local tonumber = tonumber
local type = type
local loadstring = loadstring
local concat = table.concat
local char = string.char
local byte = string.byte
local format = string.format
local sub = string.sub
local dump = string.dump
local floor = math.floor
local frexp = math.frexp
local ldexp = math.ldexp
local unpack = unpack or table.unpack

-- NIL = 202
-- FLOAT = 203
-- TRUE = 204
-- FALSE = 205
-- STRING = 206
-- TABLE = 207
-- REFERENCE = 208
-- CONSTRUCTOR = 209
-- FUNCTION = 210
-- RESOURCE = 211

local mts = {}
local ids = {}
local serializers = {}
local deserializers = {}
local resources = {}
local resources_by_name = {}

local function pack(...)
    return {...}, select("#", ...)
end

local function not_array_index(x, len)
    return type(x) ~= "number" or x < 1 or x > len or x ~= floor(x)
end

local function type_check(x, tp, name)
    assert(type(x) == tp,
        format("Expected parameter %q to be of type %q.", name, tp))
end

-- Copyright (C) 2012-2015 Francois Perrad.
-- number serialization code modified from https://github.com/fperrad/lua-MessagePack
-- Encode a number as a big-endian ieee-754 double (or a single byte)
local function number_to_str(n)
    if n <= 100 and n >= -100 and floor(n) == n then -- int from -100 to 100
        return char(n + 101)
    end
    local sign = 0
    if n < 0.0 then
        sign = 0x80
        n = -n
    end
    local m, e = frexp(n) -- mantissa, exponent
    if m ~= m then
        return char(203, 0xFF, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
    elseif m == 1/0 then
        if sign == 0 then
            return char(203, 0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        else
            return char(203, 0xFF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        end
    end
    e = e + 0x3FE
    if e < 1 then -- denormalized numbers
        m = m * ldexp(0.5, 53 + e)
        e = 0
    else
        m = (m * 2 - 1) * ldexp(0.5, 53)
    end
    return char(203,
                sign + floor(e / 0x10),
                (e % 0x10) * 0x10 + floor(m / 0x1000000000000),
                floor(m / 0x10000000000) % 0x100,
                floor(m / 0x100000000) % 0x100,
                floor(m / 0x1000000) % 0x100,
                floor(m / 0x10000) % 0x100,
                floor(m / 0x100) % 0x100,
                m % 0x100)
end

-- Copyright (C) 2012-2015 Francois Perrad.
-- number deserialization code also modified from https://github.com/fperrad/lua-MessagePack
local function number_from_str(str, index)
    local b = byte(str, index)
    if b > 0 and b < 202 then
        return b - 101, index + 1
    end
    local b1, b2, b3, b4, b5, b6, b7, b8 = byte(str, index + 1, index + 8)
    local sign = b1 > 0x7F and -1 or 1
    local e = (b1 % 0x80) * 0x10 + floor(b2 / 0x10)
    local m = ((((((b2 % 0x10) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    local n
    if e == 0 then
        if m == 0 then
            n = sign * 0.0
        else
            n = sign * ldexp(m / ldexp(0.5, 53), -1022)
        end
    elseif e == 0x7FF then
        if m == 0 then
            n = sign * (1/0)
        else
            n = 0.0/0.0
        end
    else
        n = sign * ldexp(1.0 + m / ldexp(0.5, 53), e - 0x3FF)
    end
    return n, index + 9
end

local types = {}

types["nil"] = function(x, visited, accum)
    accum[#accum + 1] = "\202"
end

function types.number(x, visited, accum)
    accum[#accum + 1] = number_to_str(x)
end

function types.boolean(x, visited, accum)
    accum[#accum + 1] = x and "\204" or "\205"
end

function types.string(x, visited, accum)
    local alen = #accum
    if visited[x] then
        accum[alen + 1] = "\208"
        accum[alen + 2] = number_to_str(visited[x])
    else
        visited[x] = visited.next
        visited.next =  visited.next + 1
        accum[alen + 1] = "\206"
        accum[alen + 2] = number_to_str(#x)
        accum[alen + 3] = x
    end
end

local function check_custom_type(x, visited, accum, alen)
    local res = resources[x]
    if res then
        accum[alen + 1] = "\211"
        types[type(res)](res, visited, accum)
        return true
    end
    local mt = getmetatable(x)
    local id = mt and ids[mt]
    if id then
        if x == visited.temp then
            error("Infinite loop in constructor.")
        end
        visited.temp = x
        accum[alen + 1] = "\209"
        types[type(id)](id, visited, accum)
        alen = #accum
        local args, len = pack(serializers[id](x))
        accum[alen + 1] = number_to_str(len)
        for i = 1, len do
            local arg = args[i]
            types[type(arg)](arg, visited, accum)
        end
        visited[x] = visited.next
        visited.next = visited.next + 1
        return true
    end
end

function types.userdata(x, visited, accum)
    local alen = #accum
    if visited[x] then
        accum[alen + 1] = "\208"
        accum[alen + 2] = number_to_str(visited[x])
    else
        if check_custom_type(x, visited, accum, alen) then return end
        error("Cannot serialize this userdata.")
    end
end

function types.table(x, visited, accum)
    local alen = #accum
    if visited[x] then
        accum[alen + 1] = "\208"
        accum[alen + 2] = number_to_str(visited[x])
    else
        if check_custom_type(x, visited, accum, alen) then return end
        visited[x] = visited.next
        visited.next =  visited.next + 1
        accum[alen + 1] = "\207"
        accum[alen + 2] = false -- temporary value
        local array_len, array_value = 0
        while true do
            array_value = x[array_len + 1]
            if array_value == nil then break end
            types[type(array_value)](array_value, visited, accum)
            array_len = array_len + 1
        end
        accum[alen + 2] = number_to_str(array_len)
        local non_array_keys = #accum + 1
        accum[non_array_keys] = false -- temporary value
        local key_count = 0
        for k, v in pairs(x) do
            if not_array_index(k, array_len) then
                key_count = key_count + 1
                types[type(k)](k, visited, accum)
                types[type(v)](v, visited, accum)
            end
        end
        accum[non_array_keys] = number_to_str(key_count)
    end
end

types["function"] = function(x, visited, accum)
    local alen = #accum
    if visited[x] then
        accum[alen + 1] = "\208"
        accum[alen + 2] = number_to_str(visited[x])
    else
        if check_custom_type(x, visited, accum, alen) then return end
        visited[x] = visited.next
        visited.next =  visited.next + 1
        local str = dump(x)
        accum[alen + 1] = "\210"
        accum[alen + 2] = number_to_str(#str)
        accum[alen + 3] = str
    end
end

types.cdata = function(x, visited, accum)
    local alen = #accum
    if visited[x] then
        accum[alen + 1] = "\208"
        accum[alen + 2] = number_to_str(visited[x])
    else
        -- TODO implement custom cdata serialization for luajit
        if check_custom_type(x, visited, accum, alen) then return end
        error("Cannot serialize this cdata.")
    end
end

types.thread = function() error("Cannot serialize threads.") end

local function deserialize_value(str, index, visited)
    local t = byte(str, index)
    if not t then return end
    if t > 0 and t < 202 then
        return t - 101, index + 1
    elseif t == 202 then
        return nil, index + 1
    elseif t == 203 then
        return number_from_str(str, index)
    elseif t == 204 then
        return true, index + 1
    elseif t == 205 then
        return false, index + 1
    elseif t == 206 then
        local length, dataindex = deserialize_value(str, index + 1, visited)
        local nextindex = dataindex + length
        local substr = sub(str, dataindex, nextindex - 1)
        visited[#visited + 1] = substr
        return substr, nextindex
    elseif t == 207 then
        local count, nextindex = number_from_str(str, index + 1)
        local ret = {}
        visited[#visited + 1] = ret
        for i = 1, count do
            ret[i], nextindex = deserialize_value(str, nextindex, visited)
        end
        count, nextindex = number_from_str(str, nextindex)
        for i = 1, count do
            local k, v
            k, nextindex = deserialize_value(str, nextindex, visited)
            v, nextindex = deserialize_value(str, nextindex, visited)
            ret[k] = v
        end
        return ret, nextindex
    elseif t == 208 then
        local ref, nextindex = number_from_str(str, index + 1)
        return visited[ref], nextindex
    elseif t == 209 then
        local count
        local name, nextindex = deserialize_value(str, index + 1, visited)
        count, nextindex = number_from_str(str, nextindex)
        local args = {}
        for i = 1, count do
            args[i], nextindex = deserialize_value(str, nextindex, visited)
        end
        local ret = deserializers[name](unpack(args))
        visited[#visited + 1] = ret
        return ret, nextindex
    elseif t == 210 then
        local length, dataindex = deserialize_value(str, index + 1, visited)
        local nextindex = dataindex + length
        return loadstring(sub(str, dataindex, nextindex - 1)), nextindex
    elseif t == 211 then
        local res, nextindex = deserialize_value(str, index + 1, visited)
        return resources_by_name[res], nextindex
    end
end

local function serialize(...)
    local visited = {next = 1}
    local accum = {}
    for i = 1, select("#", ...) do
        local x = select(i, ...)
        types[type(x)](x, visited, accum)
    end
    return concat(accum)
end

local function deserialize(str)
    assert(type(str) == "string", "Expected string to deserialize.")
    local vals = {}
    local index = 1
    local visited = {}
    local len = 0
    local val
    while index do
        val, index = deserialize_value(str, index, visited)
        if index then
            len = len + 1
            vals[len] = val
        end
    end
    return unpack(vals, 1, len)
end

local function default_deserialize(metatable)
    return function(...)
        local ret = {}
        for i = 1, select("#", ...), 2 do
            ret[select(i, ...)] = select(i + 1, ...)
        end
        return setmetatable(ret, metatable)
    end
end

local function default_serialize(x)
    assert(type(x) == "table",
        "Default serialization for custom types only works for tables.")
    local args = {}
    local len = 0
    for k, v in pairs(x) do
        args[len + 1], args[len + 2] = k, v
        len = len + 2
    end
    return unpack(args, 1, len)
end

local function register(metatable, name, serialize, deserialize)
    name = name or metatable.name
    serialize = serialize or metatable._serialize
    deserialize = deserialize or metatable._deserialize
    if not serialize then
        if not deserialize then
            serialize = default_serialize
            deserialize = default_deserialize(metatable)
        else
            serialize = metatable
        end
    end
    type_check(metatable, "table", "metatable")
    type_check(name, "string", "name")
    type_check(serialize, "function", "serialize")
    type_check(deserialize, "function", "deserialize")
    assert(not ids[metatable], "Metatable already registered.")
    assert(not mts[name], ("Name %q already registered."):format(name))
    mts[name] = metatable
    ids[metatable] = name
    serializers[name] = serialize
    deserializers[name] = deserialize
    return metatable
end

local function unregister(item)
    local name, metatable
    if type(item) == "string" then -- assume name
        name, metatable = item, mts[item]
    else -- assume metatable
        name, metatable = ids[item], item
    end
    type_check(name, "string", "name")
    type_check(metatable, "table", "metatable")
    mts[name] = nil
    ids[metatable] = nil
    serializers[name] = nil
    deserializers[name] = nil
    return metatable
end

local function registerClass(class, name)
    name = name or class.name
    if class.__instanceDict then -- middleclass
        register(class.__instanceDict, name)
    else -- assume 30log or similar library
        register(class, name)
    end
    return class
end

local function registerResource(resource, name)
    type_check(name, "string", "name")
    assert(not resources[resource],
        "Resource already registered.")
    assert(not resources_by_name[name],
        format("Resource %q already exists.", name))
    resources_by_name[name] = resource
    resources[resource] = name
    return resource
end

local function unregisterResource(name)
    type_check(name, "string", "name")
    assert(resources_by_name[name], format("Resource %q does not exist.", name))
    local resource = resources_by_name[name]
    resources_by_name[name] = nil
    resources[resource] = nil
    return resource
end

return {
    s = serialize,
    d = deserialize,
    serialize = serialize,
    deserialize = deserialize,
    register = register,
    unregister = unregister,
    registerResource = registerResource,
    unregisterResource = unregisterResource,
    registerClass = registerClass
}
