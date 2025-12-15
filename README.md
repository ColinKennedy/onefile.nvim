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
If you have an existing Neovim configuration that you don't want to touch, you can "try
out" this configuration by doing ...

```sh
root=`nvim --clean --headless --cmd 'lua print(vim.fn.stdpath("config"))' --cmd 'quit'`
parent=`dirname $root`
mkdir -p $parent/noplugins
cp ./init.lua $parent/noplugins/init.lua
```

This will create a separate Neovim app directory, located at `~/config/noplugins` (or
wherever your `$XDG_CONFIG_HOME` is set to)

Now run it with

```sh
NVIM_APPNAME=noplugins nvim
```


## Testing
```sh
eval $(luarocks path --lua-version 5.1 --bin)
make test
# or
busted .
```
