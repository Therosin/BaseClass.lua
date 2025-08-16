# BaseClass.lua

> **Classic-style OOP for Lua** — real instances, virtual `super`, registry-backed classes.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ✨ Features

* **Real instances** — calling a class returns a fresh table with its own instance metatable.
* **Virtual `super`** — no stored references; `self.super` is resolved on demand.
* **Automatic constructor chaining** — calls `new` from root → … → leaf.
* **Registry-backed creation** — all classes are tracked by name to prevent accidental re-definition.
* **Clean instances** — no hidden fields; IDs are optional and stored out-of-band.
* **Metamethod forwarding** — operators (`__add`, `__eq`, `__len`, etc.) defined on a class apply to its instances.
* **Cached constructor chains** — no re-walking the hierarchy each instantiation.
* **Opt-out** — disable constructor chaining per class with `__chain_new = false`.

---

## 🚀 Quick Start

```lua
local Class = require("BaseClass")

-- Root class
local A = Class "A" { message = "A: Hello" }
function A:new(name) self.name = name end
function A:say() print(self.message, self.name) end

-- Subclass
local B = Class "B" (A)
function B:new(name) self.tag = "(B)" end
function B:say()
    self.super.say(self)
    print("from B")
end

local a = A("alpha")   -- Instance<A>
local b = B("beta")    -- Instance<B>, calls A:new then B:new

a:say()  --> A: Hello   alpha
b:say()  --> A: Hello   beta
          --> from B
```

---

## 🔍 Introspection Helpers

```lua
Class:IsClass(x)          -- true if x is a class or subclass
Class:IsInstance(x)       -- true if x is an instance
Class:IsSubclassOf(x, A)  -- true if class x inherits from A
Class:ClassOf(obj)        -- returns the class of an instance
Class:IsInstanceOf(obj, A)-- true if obj is an A or subclass of A
Class:Of(obj)             -- alias for ClassOf
Class:NameOf(obj)         -- get the string name of a class/instance
```

---

## 📝 String Representations

* `tostring(Class)` → `Class<A>`
* `tostring(Subclass)` → `Subclass<B, A, ...>` (full ancestry chain)
* `tostring(instance)` → `Instance<A>` or `Instance<A#n>` (if IDs enabled)

Enable IDs:

```lua
Class.PrintInstanceIds = true
print(A("alpha"))
-- Instance<A#1>
```

---

## ⚙️ Error Handling

* Defining the same class twice → `error("duplicate definition not allowed")`
* Passing wrong argument types → descriptive error messages
* Attempting to assign to `super` (on classes or instances) → error

---

## 📚 Notes

* Class-level lookup falls back up the super chain (useful for constants).
* Instance metatables are cached per class for performance.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
