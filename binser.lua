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

local getmetatable = getmetatable
local setmetatable = setmetatable
local concat = table.concat
local type = type
local tostring = tostring
local tonumber = tonumber
local unpack = unpack or table.unpack
local select = select
local pairs = pairs
local floor = math.floor
local assert = assert

local NESTED_END_TOKEN = {}

local Z = ("Z"):byte() -- nil type
local N = ("N"):byte() -- number type
local B = ("B"):byte() -- boolean type
local S = ("S"):byte() -- string type
local T = ("T"):byte() -- table type
local R = ("R"):byte() -- table reference type
local C = ("C"):byte() -- constructor type

local A = ("A"):byte()
local SEP = ("|"):byte()
local ESC = ("#"):byte()

local mts = {}
local ids = {}
local serializers = {}
local deserializers = {}

local function pack(...)
    return select("#", ...), {...}
end

local function escape_string(str)
    return str:gsub("#", "#1"):gsub("|", "#2")
end

local function unescape_string(str)
    return str:gsub("#2", "|"):gsub("#1", "#")
end

local function is_array_index(x, len)
    return type(x) == "number" and x == floor(x) and x > 0 and x <= len
end

local function serialize_value(x, next, visited)
    local t = type(x)
    if t == "nil" then
        return "Z|"
    elseif t == "number" then
        return "N" .. tostring(x) .. "|"
    elseif t == "boolean" then
        return "B" .. (x and "t|" or "f|")
    elseif t == "string" then
        return "S" .. escape_string(x) .."|"
    elseif visited[x] then
        return "R" .. tostring(visited[x]) .. "|"
    else
        local mt = getmetatable(x)
        visited[x] = next[1]
        next[1] = next[1] + 1
        if ids[mt] then
            local id = ids[mt]
            local tab = {escape_string(id) .. "|"}
            local len, args = pack(serializers[id](x))
            for i = 1, len do
                tab[i + 1] = serialize_value(args[i], next, visited)
            end
            return "C" .. concat(tab) .. "|"
        elseif t == "table" then
            local tab = {}
            tab[#tab + 1] = serialize_value(mt, next, visited)
            local array_value = true
            local array_len = 0
            while array_value do
                array_len = array_len + 1
                array_value = x[array_len]
                if array_value then
                    tab[#tab + 1] = serialize_value(array_value, next, visited)
                end
            end
            tab[#tab + 1] = "|"
            for k, v in pairs(x) do
                if not is_array_index(k, array_len) then
                    tab[#tab + 1] = serialize_value(k, next, visited)
                    tab[#tab + 1] = serialize_value(v, next, visited)
                end
            end
            return "T" .. concat(tab) .. "|"
        else
            error("Cannot serialize type " .. t .. ".")
        end
    end
end

local function deserialize_value(str, index, visited)
    local t = str:byte(index)
    if t then
        -- find next index - naive approach that ignores nested structures.
        local nindex = index
        local b
        repeat
            nindex = nindex + 1
            b = str:byte(nindex)
        until (not b) or b == SEP
        nindex = nindex + 1
        local data = str:sub(index + 1, nindex - 2)
        if t == SEP then
            return NESTED_END_TOKEN, index + 1
        elseif t == Z then
            return nil, nindex
        elseif t == N then
            local ret
            if data == "nan" then
                ret = 0/0
            elseif data == "inf" then
                ret = 1/0
            elseif data == "-inf" then
                ret = -1/0
            else
                ret = tonumber(data)
            end
            return ret, nindex
        elseif t == B then
            return data == "t", nindex
        elseif t == S then
            return unescape_string(data), nindex
        elseif t == T then
            local ret = {}
            visited[#visited + 1] = ret
            local k, v
            nindex = index + 1
            local mt
            mt, nindex = deserialize_value(str, nindex, visited)
            setmetatable(ret, mt)
            local end_array_part = false
            local array_len = 0
            while not end_array_part do
                v, nindex = deserialize_value(str, nindex, visited)
                if v == NESTED_END_TOKEN then
                    end_array_part = true
                else
                    array_len = array_len + 1
                    ret[array_len] = v
                end
            end
            while true do
                k, nindex = deserialize_value(str, nindex, visited)
                if k == NESTED_END_TOKEN then
                    return ret, nindex
                end
                v, nindex = deserialize_value(str, nindex, visited)
                ret[k] = v
            end
        elseif t == C then
            local visited_index = #visited + 1
            visited[visited_index] = {}
            local id = unescape_string(data)
            local mt = mts[id]
            local ctor = deserializers[id]
            local args = {}
            local arg
            local len = 0
            while true do
                arg, nindex = deserialize_value(str, nindex, visited)
                if arg == NESTED_END_TOKEN then
                    local ret = ctor(unpack(args, 1, len))
                    visited[visited_index] = ret
                    return ret, nindex
                end
                len = len + 1
                args[len] = arg
            end
        elseif t == R then
            return visited[tonumber(data)], nindex
        else
            error("Cannot deserialize type " .. t .. ".")
        end
    else -- no values left
        return
    end
end

local function serialize(...)
    local vals = {}
    local visited = {}
    local next = {1}
    for i = 1, select("#", ...) do
        vals[i] = serialize_value(select(i, ...), next, visited)
    end
    return concat(vals)
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

local function defualt_serialize(x)
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
            serialize = defualt_serialize
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
    if class.__instanceDict then
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
