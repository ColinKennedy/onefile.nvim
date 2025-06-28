This is a "no plugins" Neovim configuration. You run it by calling:

```sh
NVIM_APPNAME=noplugins nvim
```

It does require you to have LSPs pre-installed though.


## Testing
```sh
eval $(luarocks path --lua-version 5.1 --bin)
make test
# or
busted .
```
