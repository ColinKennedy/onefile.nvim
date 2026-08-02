This is a "no plugins" Neovim configuration. You run it by calling:


## Install
### In-place Install
Get the path where Neovim loads from by calling this:

```sh
nvim --clean --headless --cmd 'lua print(vim.fn.stdpath("config"))' --cmd 'quit'
```

Linux: `~/.config/nvim`

Copy the `init.lua` to that directory.

```sh
cp ./init.lua `nvim --clean --headless --cmd 'lua print(vim.fn.stdpath("config"))' --cmd 'quit'`
```


### Side-loaded Install
If you have an existing Neovim configuration that you don't want to touch, you
can "try out" this configuration by doing ...

```sh
root=`nvim --clean --headless --cmd 'lua print(vim.fn.stdpath("config"))' --cmd 'quit'`
parent=`dirname $root`
mkdir -p $parent/noplugins
cp ./init.lua $parent/noplugins/init.lua
```

This will create a separate Neovim app directory, located at
`~/config/noplugins` (or wherever your `$XDG_CONFIG_HOME` is set to)

Now run it with

```sh
NVIM_APPNAME=noplugins nvim
```

## Creating An Inlined init.lua
To create a single init.lua that has everything in it, run this:

```sh
python ./.github/workflows/inline_init.py --input ./init.lua --output ./inline_init.lua
# e.g.
python ./.github/workflows/inline_init.py --input ./init.lua --output /mnt/c/Users/korinkite/AppData/Local/noplugins/init.lua
```

Then you can run it with `nvim -u inline_init.lua`


## Environment Variables
- `NEOVIM_LOG_LEVEL` - Sets the minimum `vim.notify` level shown by Neovim. It
  defaults to `2`, which hides `DEBUG` notifications unless you opt in with
  a lower value.

- `NEOVIM_ENABLE_NOTIFY_LOGGING` - Enables notification logging when set to
  a non-zero value. When enabled, notifications are appended to a temporary log
  file that can be opened with `:OpenLogPath`.

- `NEOVIM_AI_QUESTION_RESPONSE_COMMAND` - Overrides the command used by
  `<leader>aa` to turn AI questions plus your rough answers into a formatted
  response. The command receives the prompt on stdin. When unset, Neovim uses
  `claude -p`.

- `NEOVIM_GIT_EXECUTABLE_PATH` - Overrides the `git` executable used by Git
  helpers.

- `NEOVIM_RIPGREP_EXECUTABLE_PATH` - Overrides the `rg` executable used by
  project/file search helpers.

- `NEOVIM_SESSIONS_DIRECTORY_NAME` - Overrides the per-project session
  directory name. It defaults to `.sessions`.

- `NEOVIM_SHELL_COMMAND` - Overrides Neovim's `shell` option when making new
  terminal buffers.

- `NEOVIM_VAULTS_DIRECTORY` - Overrides the root directory used to discover
  Obsidian vaults. It defaults to `~/vaults`.


## Testing
```sh
eval "$(luarocks path --lua-version 5.1 --bin)"
make test
# or
busted .
```

# Tutorial
## Running Formatted Tests
```vim
:Dispatch --display=on_error --jump-first --compiler=vimgrep <command goes here>
:Dispatch --display=on_error --jump-first --compiler=vimgrep make luacheck ARGUMENTS=--no-color
```
