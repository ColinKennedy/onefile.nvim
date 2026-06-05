- `:Git diff` isn't showing anything. Fix

- Fix CI/CD later - https://github.com/ColinKennedy/onefile.nvim/actions/runs/26374509626/job/77632334991

- Once that neovim remote PR is merged, add that to my git commit / git rebase
  editor command so that I don't get nested Neovims anymore.
`<space>`W

- Add Cli-based mark support
 - Async-update whenever the file is changed
  - e.g. Run `mypy` on a python file

- Add my tmux config at work, for psmux

- Make an AI write my commit messages for me, somehow. SLM?

- trailing whitespace bug
 - adding prefix > lines does not delete trailing whitespace

- Clean the variable names and stuff. Gross

- Add [m, ]m, [c, ]c mappings

- filetype defaults
 - python and lua - 4 spaces, expandtab

```lua
vim.schedule(
    function()
        local modes = { "n", "i", "v", "x", "s", "o", "t", "c" }

        for _, mode in ipairs(modes) do
            for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
                if not map.desc or map.desc == "" then
                    print(
                        string.format(
                            "[%s] %s -> %s",
                            mode,
                            map.lhs,
                            map.rhs or "<Lua>"
                        )
                    )
                end
            end
        end
    end
)
```

write_current_session fails on windows due to path mismatch issues
- e.g. one file has ~, another doesn't
