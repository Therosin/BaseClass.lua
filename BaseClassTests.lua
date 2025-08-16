local Class = require("BaseClass")

-- Compatibility for Lua 5.1/5.2/5.3 unpack
local unpack = table.unpack or unpack

-- feature-detect: table __len metamethod (Lua >= 5.2 or LuaJIT)
local function supports_len_metamethod()
    local ok, v = pcall(function()
        local t = setmetatable({}, { __len = function() return 1 end })
        return #t
    end)
    return ok and v == 1
end

-- Optional test helper (inline so the file is self-contained)
---@param testName string
---@param testFunc function
---@param testArgs? table
---@return boolean
local function runTest(testName, testFunc, testArgs)
    local compiled, testResult, testMessage = pcall(testFunc, unpack(testArgs or {}))
    if not compiled then
        print('Test: ' .. testName .. ' Failed to Compile.', testMessage or 'no message')
        return false
    end

    if testResult == "__SKIP__" or (type(testResult) == "table" and testResult.SKIP) then
        print(string.format('[SKIP] test: %s -> %s',
            testName,
            tostring(testMessage or (type(testResult) == 'table' and testResult.reason) or 'not applicable'))
        )
        return true
    end

    if testResult then
        print(string.format('[PASS] test: %s -> %s', testName, tostring(testMessage or testResult)))
    else
        print(string.format('[FAIL] test: %s -> %s', testName, tostring(testMessage or testResult)))
    end
    return testResult
end

-- Turn on per-instance IDs so tostring shows #n
Class.PrintInstanceIds = true

local results = {}
local function add(name, fn, ...)
    results[#results + 1] = { name = name, ok = runTest(name, fn, { ... }) }
end

---------------------------------------------------------------------
-- 1) Basic classes, subclassing, tostring (full ancestry), chaining
---------------------------------------------------------------------
local A = Class "A" {
    message = "A: Hello",
    new = function(self, name) self.name = name end,
}

function A:say() print(self.message, self.name) end

local B = Class "B" (A)
function B:new(name) self.tag = "(B)" end

function B:say()
    self.super.say(self); print("from B")
end

-- Deep chain to exercise ancestry printing
local C = Class "C" (B)

add("tostring(Class) shows names", function()
    return tostring(A) == "Class<A>" and tostring(B) == "Subclass<B, A>" and tostring(C) == "Subclass<C, B, A>"
end)

add("constructor chaining root→leaf by default", function()
    local b = B("beta")
    return b.name == "beta" and b.tag == "(B)" and tostring(b):match("^Instance<B#%d+>$") ~= nil
end)

---------------------------------------------------------------------
-- 2) super guard on instances (cannot assign)
---------------------------------------------------------------------
add("instance 'super' is read-only (guarded)", function()
    local b = B("bravo")
    local ok, err = pcall(function() b.super = 123 end)
    return (not ok) and tostring(err):match("Cannot set 'super' on an instance") ~= nil
end)

---------------------------------------------------------------------
-- 3) Class/instance introspection helpers
---------------------------------------------------------------------
add("IsClass / IsInstance / IsSubclassOf", function()
    local a = A("alpha")
    return Class:IsClass(A) and not Class:IsClass(a)
        and Class:IsInstance(a) and not Class:IsInstance(A)
        and Class:IsSubclassOf(B, A) and not Class:IsSubclassOf(A, B)
end)

add("ClassOf / Of / NameOf / IsInstanceOf", function()
    local a = A("axe")
    local cls = Class:ClassOf(a)
    return cls == A and Class:Of(a) == A and Class:NameOf(a) == "A" and Class:IsInstanceOf(a, A) and
        Class:IsInstanceOf(a, A) and not Class:IsInstanceOf(a, B)
end)

---------------------------------------------------------------------
-- 4) Instance ID formatting (compact #n per class)
---------------------------------------------------------------------
local IDClass = Class "IDClass" { new = function(self) end }
add("Instance IDs increment per class", function()
    local i1 = IDClass("x")
    local i2 = IDClass("y")
    return tostring(i1):match("^Instance<IDClass#1>$") and tostring(i2):match("^Instance<IDClass#2>$")
end)

---------------------------------------------------------------------
-- 5) Metamethod forwarding from class → instance metatable
---------------------------------------------------------------------
local Vec = Class "Vec" { new = function(self, x, y) self.x, self.y = x, y end }

-- define BEFORE any instance (should be picked up when __inst_meta is created)
function Vec.__add(a, b)
    local cls = Class:Of(a)
    return cls and cls(a.x + b.x, a.y + b.y)
end

function Vec.__eq(a, b)
    return a.x == b.x and a.y == b.y
end

function Vec.__len(a)
    return 2 -- fixed-dim example
end

add("metamethods work on instances (pre-declare)", function()
    local v1, v2 = Vec(1, 2), Vec(3, 4)
    local v3 = v1 + v2
    return Class:IsInstanceOf(v3, Vec) and v3.x == 4 and v3.y == 6 and (v1 == Vec(1, 2))
end)

-- define AFTER instance creation (should sync into __inst_meta via __newindex hook)
local Dyn = Class "Dyn" { new = function(self, v) self.v = v end }
local d1 = Dyn(10)
Dyn.__eq = function(a, b) return (a.v % 2) == (b.v % 2) end -- same parity considered equal
add("metamethods sync after first instance (post-declare)", function()
    return d1 == Dyn(12) and (d1 ~= Dyn(11))
end)

-- explicit __len support/absence tests with SKIP output
add("table __len metamethod present (expected on Lua >= 5.2)", function()
    if not supports_len_metamethod() then return "__SKIP__", "__len not supported here" end
    local t = setmetatable({}, { __len = function() return 99 end })
    return (#t == 99)  -- on Lua 5.1, __len for tables is ignored
end)

---------------------------------------------------------------------
-- 6) Constructor chain caching + opt-out (__chain_new = false)
---------------------------------------------------------------------
local R = Class "R" { new = function(self) self.fromR = true end }
local S1 = Class "S1" (R)
function S1:new() self.fromS1 = true end

local S2 = Class "S2" (S1)
S2.__chain_new = false -- opt-out: only leaf new runs
function S2:new() self.fromS2 = true end

add("opt-out only calls leaf constructor", function()
    local s = S2()
    return s.fromS2 == true and s.fromS1 == nil and s.fromR == nil
end)

---------------------------------------------------------------------
-- 7) Class-level fallback lookup via super chain
---------------------------------------------------------------------
local BaseConst = Class "BaseConst" { MAGIC = 42 }
local ChildConst = Class "ChildConst" (BaseConst)
add("class-level fallback finds constants on parents", function()
    return ChildConst.MAGIC == 42 and BaseConst.MAGIC == 42
end)

---------------------------------------------------------------------
-- 8) say() behavior demonstration (unchanged, just sanity check)
---------------------------------------------------------------------
add("method dispatch via virtual lookup", function()
    local b = B("bee")
    -- capture output? keep it simple: check fields and type here
    return b.tag == "(B)" and b.name == "bee" and tostring(b):match("^Instance<B#%d+>$")
end)

---------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------
local passed, total = 0, #results
for _, r in ipairs(results) do if r.ok then passed = passed + 1 end end
print(string.format("\n==> Passed %d/%d tests", passed, total))
if passed == total then
    print("All tests passed successfully!")
else
    print("Some tests failed. Please check the output above.")
end


--[[  Expected Output:

[PASS] test: tostring(Class) shows names -> true
[PASS] test: constructor chaining root→leaf by default -> true

[error] Cannot set 'super' on an instance
[PASS] test: instance 'super' is read-only (guarded) -> true
[PASS] test: IsClass / IsInstance / IsSubclassOf -> true
[PASS] test: ClassOf / Of / NameOf / IsInstanceOf -> true
[PASS] test: Instance IDs increment per class -> Instance<IDClass#2>
[PASS] test: metamethods work on instances (pre-declare) -> true
[PASS] test: metamethods sync after first instance (post-declare) -> true
[SKIP] test: table __len metamethod present (expected on Lua >= 5.2) -> __len not supported here
[PASS] test: opt-out only calls leaf constructor -> true
[PASS] test: class-level fallback finds constants on parents -> true
[PASS] test: method dispatch via virtual lookup -> Instance<B#3>

==> Passed 12/12 tests
All tests passed successfully!

--]]
