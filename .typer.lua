--- Configuration for `make typer`.
---
--- typer is "mypy --strict, for Lua": it reports where LuaLS annotations are
--- missing or too vague. Report-only; it never edits files.
return {
  -- Where ambient `---@class` declarations are scanned from, and how
  -- `require("modules.x")` resolves.
  source_roots = { "lua" },

  lua_version = "jit",

  -- `.generated/noplugins-init.lua` is a build artifact containing a copy of
  -- the whole config, so every class in it collides with the real source and
  -- reports as `duplicate-class`.
  --
  -- `.dependencies` is deliberately NOT excluded: the busted and luassert
  -- definitions in there are what make `describe`, `it` and `assert` resolve.
  exclude = {
    "**/.generated/**",
  },
}
