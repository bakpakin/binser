local binser = require "binser"

local function test_ser(...)
    local results = { binser.deserialize(binser.serialize(...)) }
    for i = 1, select("#", ...) do
        assert.are.same(results[i], select(i, ...))
    end
end

describe("binser", function()

    it("Serializes numbers", function()
        -- NaN should work, but busted thinks NaN ~= NaN
        test_ser(1, 2, 4, 809, -1290, math.huge, -math.huge)
    end)

    it("Serializes strings", function()
        test_ser("Hello, World!", "1231", "jojo", "binser", "\245897", "#####",
        "#|||||###|#|#|#!@|#|@|!||2121|2", "\000\x34\x67\x56" )
    end)

    it("Serializes booleans", function()
        test_ser(true, false, false, true)
    end)

    it("Serializes nil", function()
        test_ser(nil, nil, true, nil, nil, true, nil)
    end)

    it("Serializes tables", function()
        -- Using tables as keys throws a wrench into busted's "same" assert.
        -- i.e., busted's deep equals seems not to apply to table keys.
        -- This isn't a bug, just annoying.
        test_ser({0, 1, 2, 3, "a", true, nil, ["ranÎØM\000\232"] = "koi"}, {})
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

    it("Serializes custom types", function()
        local mt = {
            name = "MyCoolType"
        }
        test_ser(setmetatable({}, mt), setmetatable({
            a = "a",
            b = "b",
            c = "c"
        }, mt))
    end)

end)
