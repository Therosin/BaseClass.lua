--[[
BaseClass.lua — Classic-style OOP (real instances, virtual super) with a registry

Quick start
-----------
local Class = require("BaseClass")

local A = Class "A" { message = "A: Hello" }
function A:new(name) self.name = name end
function A:say() print(self.message, self.name) end

local B = Class "B" (A)
function B:new(name) self.tag = "(B)" end
function B:say() self.super.say(self); print("from B") end

local a = A("alpha")   -- Instance<A>
local b = B("beta")    -- Instance<B> (super.new chained automatically)

Design goals
------------
- Real instances: calling a class returns a fresh table with an instance metatable.
- No self-referential classes: classes don’t point __index at themselves.
- Virtual super: `self.super` is provided via __index (never stored on the table).
- Registry-backed creation:
    * `Class "Name" { members }`            → define root class
    * `Class "Name" (BaseClass)`            → define subclass of BaseClass
  If a class named "Name" already exists and a second argument is provided,
  definition errors (duplicate definition). Lookup is via the non-curried
  API (`BaseClass:Create("Name")`) when needed.

Constructor chaining
--------------------
Instance construction automatically calls `new` from root → … → leaf.
You rarely need `self.super.new(...)` unless you’re doing something nonstandard.

Introspection helpers
---------------------
- `BaseClass:IsClass(x)`      -- true for classes & subclasses
- `BaseClass:IsInstance(x)`   -- true for instances
- `BaseClass:IsSubclassOf(x, base)` -- true if x inherits from base
- `BaseClass:ClassOf(x)`      -- returns the class of an instance (or nil)
- `BaseClass:IsInstanceOf(x, cls)` -- true if instance x is of class/subclass cls
- Aliases: `BaseClass:Of(x)`, `BaseClass:NameOf(x)`

String forms
------------
- `tostring(Class)`     → `Class<A>`
- `tostring(Subclass)`  → `Subclass<B, A, ...>` (full ancestry)
- `tostring(instance)`  → `Instance<A>`  (or `Instance<A#n>` if IDs enabled)

Instance ID toggle
------------------
Per-instance IDs in `tostring` can be enabled without polluting objects:
    `BaseClass.PrintInstanceIds = true`
IDs are stored in a weak side table; instance tables remain clean.

Metamethod forwarding
---------------------
Metamethods defined on a class (e.g. __eq, __add, __len, __concat, bitwise, etc.)
are automatically mirrored into that class’s shared instance metatable so
instances participate in those operators.

Constructor chain caching & opt-out
-----------------------------------
The root→leaf constructor chain is cached per class. To run only the leaf
constructor, set `YourClass.__chain_new = false`.

Error behavior
--------------
- Duplicate definition with a second argument → error("... duplicate definition not allowed")
- Invalid argument types → descriptive errors
- Assigning `super` on classes or instances → errors

Notes
-----
- Class-level lookup falls back up the super chain (useful for constants/defaults).
- Instance metatables are cached per class for performance.
]]
local BaseClass = { KnownClasses = {} }

-- Optional: show per-instance IDs in tostring
BaseClass.PrintInstanceIds = false

-- Weak table to hold instance IDs without polluting instances
local InstanceIds = setmetatable({}, { __mode = "k" })

-- ——— helpers ———
local function mt_of(x) return type(x) == "table" and getmetatable(x) or nil end
local function super_of(x)
    local mt = mt_of(x)
    return mt and mt.__super or nil
end
local function is_classlike(x)
    local mt = mt_of(x)
    return type(mt) == "table" and (mt.__kind == "Class" or mt.__kind == "Subclass")
end

-- Set of class metamethod keys to forward onto the shared instance metatable
local META_FORWARD = {
    __eq=true, __lt=true, __le=true,
    __add=true, __sub=true, __mul=true, __div=true, __mod=true, __pow=true, __unm=true,
    __len=true, __concat=true,
    __idiv=true, -- floor division (Lua 5.3+)
    __band=true, __bor=true, __bxor=true, __bnot=true, __shl=true, __shr=true, -- bitwise (Lua 5.3+)
    __pairs=true, __ipairs=true, -- iteration helpers (Lua 5.2+)
}

-- Forward a class metamethod into its instance metatable if present
local function sync_meta_to_instances(class_tbl, k, v)
    if META_FORWARD[k] then
        local cmt = getmetatable(class_tbl)
        if cmt and cmt.__inst_meta then
            cmt.__inst_meta[k] = v
        end
    end
end

-- instance metatable bound to a specific class (cached per class)
local function make_instance_meta(cls)
    local cls_mt = mt_of(cls)
    local class_name = (cls_mt and cls_mt.__type) or "Anonymous"
    return {
        __type     = class_name, -- instance shows as its class name
        __kind     = "Instance",
        __class    = cls,        -- pointer to the class (for ClassOf/IsInstanceOf)
        __tostring = function(self)
            if BaseClass.PrintInstanceIds then
                local id = InstanceIds[self]
                if id then return string.format("Instance<%s#%d>", class_name, id) end
            end
            return string.format("Instance<%s>", class_name)
        end,
        __index    = function(_, k)
            if k == "super" then return super_of(cls) end -- virtual super on instances
            local c = cls
            while c do
                local v = rawget(c, k)
                if v ~= nil then return v end
                c = super_of(c)
            end
            return nil
        end,
        __newindex = function(t, k, v)
            if k == "super" then error("Cannot set 'super' on an instance", 2) end
            rawset(t, k, v)
        end,
    }
end

-- class/subclass metatable
local function make_class_meta(cls, name, kind, parent)
    local function tostring_self(self)
        local mt = getmetatable(self)
        if not mt then return "Class<?>" end

        -- Print full ancestry for subclasses
        if mt.__kind == "Class" then
            return string.format("Class<%s>", mt.__type or "Anonymous")
        elseif mt.__kind == "Subclass" then
            local names, p = { mt.__type or "Anonymous" }, mt.__super
            while p do
                local pmt = getmetatable(p)
                names[#names+1] = (pmt and pmt.__type) or "Anonymous"
                p = pmt and pmt.__super or nil
            end
            return ("Subclass<%s>"):format(table.concat(names, ", "))
        else
            return tostring(mt.__kind) -- safety
        end
    end

    local function class_index(_, k)
        if k == "super" then return parent end -- virtual super on classes
        -- Optional: class-level fallback up the chain (constants, defaults)
        local c = parent
        while c do
            local v = rawget(c, k)
            if v ~= nil then return v end
            c = super_of(c)
        end
        return nil
    end

    return {
        __type     = name,   -- the NAME of this class/subclass
        __kind     = kind,   -- "Class" | "Subclass"
        __super    = parent, -- only set for subclasses
        __tostring = tostring_self,
        __index    = class_index,
        __newindex = function(t, k, v)
            if k == "super" then error("Cannot set 'super' on a class", 2) end
            rawset(t, k, v) -- overrides/fields stay on this class
            sync_meta_to_instances(t, k, v)
        end,
        __call     = function(self, ...)
            -- construct a *new instance*
            local cmt = getmetatable(self)
            -- cache the instance metatable per class for perf
            if not cmt.__inst_meta then
                cmt.__inst_meta = make_instance_meta(self)
                -- forward any existing metamethods present on the class at first use
                for k, v in pairs(self) do
                    if META_FORWARD[k] then cmt.__inst_meta[k] = v end
                end
            end
            local inst = setmetatable({}, cmt.__inst_meta)

            -- assign a compact per-instance ID (optional print)
            if BaseClass.PrintInstanceIds then
                cmt.__next_id = (cmt.__next_id or 0) + 1
                InstanceIds[inst] = cmt.__next_id
            end

            -- cache constructor chain once per class (leaf→root)
            if not cmt.__ctor_chain then
                local chain, c = {}, self
                while c do chain[#chain + 1] = c; c = super_of(c) end
                cmt.__ctor_chain = chain
            end

            -- automatic constructor chain: root -> leaf (unless opt-out)
            local chain = cmt.__ctor_chain
            if rawget(self, "__chain_new") == false then
                -- only call leaf new
                local newf = rawget(chain[1], "new")
                if newf then newf(inst, ...) end
            else
                for i = #chain, 1, -1 do -- call root→leaf
                    local newf = rawget(chain[i], "new")
                    if newf then newf(inst, ...) end
                end
            end

            return inst
        end,
    }
end

-- ——— public API ———

-- Create(name, base_or_members?) — define or fetch
function BaseClass:Create(name, base_or_members)
    if name then
        local existing = self.KnownClasses[name]
        if existing and base_or_members ~= nil then
            error(("Class '%s' already exists; duplicate definition not allowed"):format(name), 2)
        end
        if existing then return existing end
    end

    -- Decide: subclass or root class?
    local parent, members = nil, nil
    if is_classlike(base_or_members) then
        parent = base_or_members
    elseif type(base_or_members) == "table" then
        members = base_or_members
    elseif base_or_members ~= nil then
        error("Second argument must be a class or a table of members", 2)
    end

    local cls = {}
    if members then
        for k, v in pairs(members) do cls[k] = v end
    end

    local kind = parent and "Subclass" or "Class"
    setmetatable(cls, make_class_meta(cls, name or "Anonymous", kind, parent))
    if name then self.KnownClasses[name] = cls end
    return cls
end

-- Introspection helpers
function BaseClass:IsClass(x) return is_classlike(x) end

function BaseClass:IsInstance(x)
    local mt = type(x) == "table" and getmetatable(x)
    return type(mt) == "table" and mt.__kind == "Instance"
end

function BaseClass:IsSubclassOf(x, base)
    if type(x) ~= "table" or type(base) ~= "table" then return false end
    local cur = x
    while cur do
        if cur == base then return true end
        cur = super_of(cur)
    end
    return false
end

function BaseClass:ClassOf(x)
    local mt = mt_of(x)
    if mt and mt.__kind == "Instance" then return mt.__class end
    return nil
end

function BaseClass:IsInstanceOf(x, cls)
    local c = self:ClassOf(x)
    while c do
        if c == cls then return true end
        c = super_of(c)
    end
    return false
end

-- Aliases/Helpers
function BaseClass:Of(x) return self:ClassOf(x) end
function BaseClass:NameOf(x)
    local mt = mt_of(x)
    if not mt then return nil end
    if mt.__kind == "Instance" or mt.__kind == "Class" or mt.__kind == "Subclass" then
        return mt.__type
    end
    return nil
end

return setmetatable(BaseClass, {
    __call = function(self, name)
        if type(name) ~= "string" then
            error("First argument must be a class name (string)", 2)
        end
        return function(base_or_members)
            if base_or_members ~= nil and type(base_or_members) ~= "table" and not is_classlike(base_or_members) then
                error("Second argument must be a class or a table of members", 2)
            end
            return self:Create(name, base_or_members)
        end
    end
})
