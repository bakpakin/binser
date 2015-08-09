# binser - Customizable Lua Serializer

[![Build Status](https://travis-ci.org/bakpakin/binser.png?branch=master)](https://travis-ci.org/bakpakin/binser)

There already exists a number of serializers for lua, each with their own uses,
limitations, and quirks. binser is yet another robust, pure lua serializer that
specializes in serializing lua data with lots of userdata and custom classes
and types. binser is a binary serializer and does not serialize data into
human readable representation or use the lua parser to read expressions. This
makes it safer than many other serializers and fast, especially on Luajit.
binser also handles cycles, self-references, and metatables.

## How to Use

### Example
```lua
local binser = require "binser"

print(binser.serialize(45, {4, 8, 12, 16}, "Hello, World!"))
-- N45|TZ|N4|N8|N12|N16|||SHello, World!|

print(binser.deserialize(binser.serialize(45, {4, 8, 12, 16}, "Hello, World!")))
-- 45	table: 0x7fa60054bdb0	Hello, World!
```

### Serializing and Deserializing
```lua
local str = binser.serialize(...)
```
Serialize (almost) any lua data into a lua string. Numbers, strings, tables,
booleans, and nil are all fully supported by default. Custom userdata and custom
types, both identified by metatables, can also be supported by specifying a
custom serialization function. Unserializable data should throw an error.

```lua
local ... = binser.deserialize(str)
```
Deserialize any string previously serialized by binser. Unrecognized data should
throw an error.

### Custom types
```lua
local metatable = binser.register(metatable, name, serialize, deserialize)
```
Registers a custom type, identified by its metatable, to be serialzed.
Registering types has two main purposes. First, it allows custom serialization
and deserialization for userdata and tables that contain userdata, which can't
otherwise be serialized in a uniform way. Second, it allows efficient
serialization of small tables with large metatables, as regsistered metatables
are not serialized.

The `metatable` parameter is the metatable the identifies the type. The `name`
parameter is the type name used in serialization. The only requirement for names
is that they are unique. The `serialize` and `deserialize` parameters are
a pair of functions that construct and destruct and instance of the type.
`serialize` can return any number of serializable lua objects, and
`deserialize` should accept the arguments returned by `serialize`.
`serialize` and `deserialize` can also be specified in `metatable._serialize`
and `metatable._deserialize` respectively.

```lua
local class = binser.registerClass(class[, name])
```
Registers a class as a custom type. binser currently supports 30log and
middleclass. `name` is an optional parameter that defaults to `class.name`.

```lua
local metatable = binser.unregister(name)
```
Users should seldom need this, but to explicitly unregister a type, call this.

## Why
Most lua serializers serialize into valid lua code, which while very useful,
makes it impossible to do things like custom serialization and
deserialization. binser was originally written as a way to save game levels
with images and other native resources, but is extremely general.

## Testing
binser uses [busted](http://olivinelabs.com/busted/) for testing. Install and
run `busted` from the command line to test.

## Notes
Serialized strings are not necessarily safe to write to files in text mode. If a
string is unsafe to write to a file (strange characters), the serialized string
will also be unsafe. Its recommended to write to files in binary mode. Also,
serialized data can be appended to other serialized data. (Cool :))

## Bugs
Pull requests are welcome, please help me squash bugs!
