# AGENTS.md

Guidance for Codex and other coding agents working in this repository.

## Repository Overview

This is a personal "no plugins" Neovim configuration. The primary runtime file is `init.lua`, which defines most editor behavior: options, keymaps, commands, snippets, git and ripgrep helpers, selector UI, statusline behavior, LSP setup, terminal behavior, and supporting utilities.

Keep the configuration self-contained. Do not introduce plugin-manager assumptions or external Neovim plugins unless the user explicitly asks for that direction.

## Tracked Project Structure

- `init.lua`: main Neovim configuration and implementation code.
- `spec/keymap_spec.lua`: Busted specs for keymaps, operators, and buffer-editing behavior.
- `.busted`: Busted configuration. Tests run through `nvim -u init.lua -U NONE -N -i NONE -l`.
- `Makefile`: canonical local task entry points.
- `README.md`: installation and test instructions.
- `TODO.md`: user-maintained backlog and behavior notes.
- `.luacheckrc`: Lua lint settings for LuaJIT with `vim` as a read global.
- `.luarc.json`: Lua language-server configuration for local development.
- `.stylua.toml`: StyLua formatting configuration.
- `queries/python/highlights.scm`: custom Tree-sitter query content.
- `.github/workflows/*.yml`: CI for tests, linting, formatting, llscheck, checkhealth, and commitlint.

Ignore untracked files when deriving repository facts or task guidance unless the user explicitly asks to inspect them.

## Common Commands

Run commands from the repository root: `~/repositories/personal/.config/noplugins`.

```sh
make test
eval $(luarocks path --lua-version 5.1 --bin)
make luacheck
make check-stylua
make stylua
make llscheck
make download-dependencies
```

Before running `make luacheck` or `make llscheck`, you must run `eval $(luarocks path --lua-version 5.1 --bin)` in the same shell so the LuaRocks-installed `luacheck` and `llscheck` executables are in `PATH`.

The README also documents this test setup:

```sh
eval $(luarocks path --lua-version 5.1 --bin)
make test
# or
busted .
```

`make llscheck` needs `nvim` and `llscheck`; it computes `$VIMRUNTIME` from a clean headless Neovim invocation. `make download-dependencies` clones Lua type metadata into `.dependencies/` using SSH GitHub URLs.

For CI, `.github/workflows/llscheck.yml` runs:

```sh
make llscheck CONFIGURATION=.github/workflows/.luarc.json
```

That workflow also rewrites GitHub SSH clone URLs to HTTPS before running llscheck.

## CI Expectations

Tracked workflows cover:

- `make test` on Ubuntu, macOS, and Windows across Neovim `v0.11.0`, stable, and nightly.
- `make luacheck` on Ubuntu.
- `make check-stylua` on Ubuntu.
- `make llscheck CONFIGURATION=.github/workflows/.luarc.json` on Ubuntu with stable Neovim.
- Neovim `:checkhealth` across Ubuntu, macOS, and Windows on Neovim `v0.10.0`, stable, and nightly.
- Commit message linting on pull requests.

## Coding Style

- Follow the existing Lua style: local `_P` helper table, typed LuaCATS annotations, small focused helper functions, and explicit `---@param` / `---@return` docs for nontrivial utilities.
- Preserve the no-plugin philosophy and prefer built-in Neovim APIs, Lua standard library behavior, and shell commands already represented in the config.
- Keep keymaps discoverable: new keymaps should have a clear `desc` unless there is a specific reason they cannot.
- Use `vim.api`, `vim.fn`, `vim.fs`, and `vim.tbl_*` consistently with nearby code.
- Respect existing environment overrides such as `NEOVIM_GIT_EXECUTABLE_PATH`, `NEOVIM_RIPGREP_EXECUTABLE_PATH`, and `NEOVIM_SESSIONS_DIRECTORY_NAME`.
- Avoid broad refactors in `init.lua`; it is a large personal config, so narrow behavior-driven changes are usually safer.

## Testing Guidance

For behavior changes in `init.lua`, prefer adding or updating focused specs in `spec/keymap_spec.lua` when the behavior can be exercised headlessly. The spec helpers already provide temporary buffers, cursor markers via `|cursor|`, and assertions for normal-mode command/key behavior.

Before handing work back, run the smallest useful verification for the task. Typical checks are:

```sh
eval $(luarocks path --lua-version 5.1 --bin)
make test
make luacheck
make check-stylua
```

Run `eval $(luarocks path --lua-version 5.1 --bin)` first, then `make llscheck` when changing annotations, public helper shapes, or language-server-sensitive code, if the required tooling is available.

## Installation / Manual Use

The config can be installed in-place by copying `init.lua` into Neovim's config directory, or side-loaded as an appname config:

```sh
NVIM_APPNAME=noplugins nvim
```

Use headless Neovim for automated checks where possible.

## Agent Safety

- Assume the worktree may contain unrelated user changes and preserve them.
- Do not run destructive cleanup commands such as `git clean`, broad deletes, or resets unless the user explicitly asks.
- Base repository summaries and persistent guidance on tracked files unless the user gives permission to consider untracked files.
- If a task touches platform behavior, check Linux, macOS, and Windows assumptions because tracked CI exercises all three.
