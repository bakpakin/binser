local binser = require "binser"

local function test_ser(...)
    local serialized_data = binser.serialize(...)
    local results = { binser.deserialize(serialized_data) }
    for i = 1, select("#", ...) do
        assert.are.same(select(i, ...), results[i])
    end
end

describe("binser", function()

    it("Serializes numbers", function()
        -- NaN should work, but lua thinks NaN ~= NaN
        test_ser(1, 2, 4, 809, -1290, math.huge, -math.huge, 0)
    end)

    it("Serializes numbers with no precision loss", function()
        test_ser(math.ldexp(0.985, 1023), math.ldexp(0.781231231, -1023),
            math.ldexp(0.5, -1021), math.ldexp(0.5, -1022))
    end)

    it("Serializes strings", function()
        test_ser("Hello, World!", "1231", "jojo", "binser", "\245897", "#####",
        "#|||||###|#|#|#!@|#|@|!||2121|2", "", "\000\x34\x67\x56", "\000\255" )
    end)

    it("Serializes booleans", function()
        test_ser(true, false, false, true)
    end)

    it("Serializes nil", function()
        test_ser(nil, nil, true, nil, nil, true, nil)
    end)

    it("Serializes simple tables", function()
        test_ser({0, 1, 2, 3}, {a = 1, b = 2, c = 3})
    end)

    it("Serializes tables", function()
        -- Using tables as keys throws a wrench into busted's "same" assert.
        -- i.e., busted's deep equals seems not to apply to table keys.
        -- This isn't a bug, just annoying.
        test_ser({0, 1, 2, 3, "a", true, nil, ["ranÎØM\000\255"] = "koi"}, {})
    end)

    it("Serializes cyclic tables", function()
        local tab = {
            a = 90,
            b = 89,
            zz = "binser",
        }
        tab["cycle"] = tab
        test_ser(tab, tab)
    end)

    it("Serializes metatables", function()
        local mt = {
            name = "MyCoolType"
        }
        test_ser(setmetatable({}, mt), setmetatable({
            a = "a",
            b = "b",
            c = "c"
        }, mt))
    end)

    it("Serializes custom tyes", function()
        local mt = {
            name = "MyCoolType"
        }
        binser.register(mt)
        test_ser(setmetatable({}, mt), setmetatable({
            a = "a",
            b = "b",
            c = "c"
        }, mt))
        binser.unregister(mt.name)
    end)

    it("Serializes serpent's benchmark data", function()
        -- test data
        local b = {text="ha'ns", ['co\nl or']='bl"ue', str="\"\n'\\\001"}
        local a = {
          x=1, y=2, z=3,
          ['function'] = b, -- keyword as a key
          list={'a',nil,nil, -- shared reference, embedded nils
                [9]='i','f',[5]='g',[7]={}}, -- empty table
          ['label 2'] = b, -- shared reference
          [math.huge] = -math.huge, -- huge as number value
        }
        a.c = a -- self-reference
        local c = {}
        for i = 1, 500 do
           c[i] = i
        end
        a.d = c
        -- test data
        test_ser(a)
    end)

end)
