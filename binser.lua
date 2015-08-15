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
local select = select
local pairs = pairs
local getmetatable = getmetatable
local setmetatable = setmetatable
local tonumber = tonumber
local type = type
local concat = table.concat
local char = string.char
local byte = string.byte
local format = string.format
local sub = string.sub
local floor = math.floor
local unpack = unpack or table.unpack

local NIL = 202
local FLOAT = 203
local TRUE = 204
local FALSE = 205
local STRING = 206
local TABLE = 207
local REFERENCE = 208
local CONSTRUCTOR = 209

local NIL_CHAR = char(NIL)
--local FLOAT_CHAR = char(FLOAT) -- not needed
local TRUE_CHAR = char(TRUE)
local FALSE_CHAR = char(FALSE)
local STRING_CHAR = char(STRING)
local TABLE_CHAR = char(TABLE)
local REFERENCE_CHAR = char(REFERENCE)
local CONSTRUCTOR_CHAR = char(CONSTRUCTOR)

local mts = {}
local ids = {}
local serializers = {}
local deserializers = {}

local function pack(...)
    return {...}, select("#", ...)
end

local function is_array_index(x, len)
    return type(x) == "number" and x > 0 and x <= len and x == floor(x)
end

local function number_to_str(x)
    if x <= 100 and x >= -100 and floor(x) == x then -- int from -100 to 100
        return char(x + 101)
    else -- large ints, floating point numbers
        return format("\203%.17g\203", x)
    end
end

local nonrs = {
    ["inf"] = 1/0,
    ["-inf"] = -1/0,
    ["nan"] = 0/0
}
local function number_from_str(str, index)
    local b = byte(str, index)
    if b > 0 and b < NIL then
        return b - 101, index + 1
    end
    local endindex = index
    repeat
        endindex = endindex + 1
        b = byte(str, endindex)
    until b == 203 or not b
    local substr = sub(str, index + 1, endindex - 1)
    return tonumber(substr) or nonrs[substr], endindex + 1
end

local function serialize_value(x, next, visited, accum)
    local alen = #accum
    local t = type(x)
    if t == "nil" then
        accum[alen + 1] = NIL_CHAR
    elseif t == "number" then
        accum[alen + 1] = number_to_str(x)
    elseif t == "boolean" then
        accum[alen + 1] = x and TRUE_CHAR or FALSE_CHAR
    elseif t == "string" then
        accum[alen + 1] = STRING_CHAR
        accum[alen + 2] = number_to_str(#x)
        accum[alen + 3] = x
    elseif visited[x] then
        accum[alen + 1] = REFERENCE_CHAR
        accum[alen + 2] = number_to_str(visited[x])
    else
        visited[x] = next[1]
        next[1] = next[1] + 1
        local mt = getmetatable(x)
        local id = mt and ids[mt]
        if id then -- Custom type
            accum[alen + 1] = CONSTRUCTOR_CHAR
            serialize_value(id, next, visited, accum)
            alen = #accum
            local args, len = pack(serializers[id](x))
            accum[alen + 1] = number_to_str(len)
            for i = 1, len do
                serialize_value(args[i], next, visited, accum)
            end
        elseif t == "table" then
            accum[alen + 1] = TABLE_CHAR
            accum[alen + 2] = false -- temporary value
            local array_value = true
            local array_len = 0
            while array_value ~= nil do
                array_value = x[array_len]
                if array_value ~= nil then
                    serialize_value(array_value, next, visited, accum)
                end
            end
            accum[alen + 2] = number_to_str(array_len - 1)
            local non_array_keys = #accum + 1
            accum[non_array_keys] = false -- temporary value
            local key_count = 0
            for k, v in pairs(x) do
                if not is_array_index(k, array_len) then
                    key_count = key_count + 1
                    serialize_value(k, next, visited, accum)
                    serialize_value(v, next, visited, accum)
                end
            end
            accum[non_array_keys] = number_to_str(key_count)
        else
            error(("Cannot serialize type %q."):format(t))
        end
    end
end

local function deserialize_value(str, index, visited)
    local t = byte(str, index)
    if not t then return end
    if t > 0 and t < NIL then
        return t - 101, index + 1
    elseif t == NIL then
        return nil, index + 1
    elseif t == TRUE then
        return true, index + 1
    elseif t == FALSE then
        return false, index + 1
    elseif t == STRING then
        local length, dataindex = deserialize_value(str, index + 1, visited)
        assert(type(length) == "number", ("Could not parse string at index %i."):format(index))
        local nextindex = dataindex + length
        return sub(str, dataindex, nextindex - 1), nextindex
    elseif t == FLOAT then
        return number_from_str(str, index)
    elseif t == TABLE then
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
    elseif t == CONSTRUCTOR then
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
    elseif t == REFERENCE then
        local ref, nextindex = number_from_str(str, index + 1)
        return visited[ref], nextindex
    end
end

local function serialize(...)
    local visited = {}
    local next = {1}
    local accum = {}
    for i = 1, select("#", ...) do
        serialize_value(select(i, ...), next, visited, accum)
    end
    return concat(accum)
end

local function deserialize(str)
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

return {
    serialize = serialize,
    deserialize = deserialize,
    register = register,
    unregister = unregister,
    registerClass = registerClass
}
