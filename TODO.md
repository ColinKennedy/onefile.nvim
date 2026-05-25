- Add :Dispatch support

- `:Git diff` isn't showing anything. Fix

- If I load a session with a terminal, it starts the wrong buffer in INSERT
  mode (it tries to add insert mode for the terminal but touches the current
  buffer instead)

- Fix CI/CD later - https://github.com/ColinKennedy/onefile.nvim/actions/runs/26374509626/job/77632334991

- Once that neovim remote PR is merged, add that to my git commit / git rebase
  editor command so that I don't get nested Neovims anymore.
- A <M-S-{1,2,3,4}> for grapple
`<space>`W
`<space>`q
- Add :Gcd

- Add Cli-based mark support
 - Async-update whenever the file is changed
  - e.g. Run `mypy` on a python file

- Add my tmux config at work, for psmux

- The AI should do a pass to make sure all functions are documented with type
  annotations, it's missing them in several places
 - and also for any {} table definitions

- Make an AI write my commit messages for me, somehow. SLM?

- There's probably greater opportunity for defer-evalling in the codebase. For
  example, each module's private functions don't need to be defined in the same
  modules as the public functions. They could be moved and defer-eval required
  into the relevant spots. This could make startup time faster, but by how much
  I don't know

- Update my LSp setup to use config + start
 - add ty LSP support

- Add tests

- Add a "cleanup all buffers except terminal buffers" command. Call if BufOnly

- trailing whitespace bug
 - adding prefix > lines does not delete trailing whitespace

- Clean the variable names and stuff. Gross

- Add [m, ]m, [c, ]c mappings

- Remove the z mapping (see below, it's broken)
```
vim.keymap.set("n", "J", "mzJ`z", {
    desc = "Keep the cursor in the same position while pressing ``J``.",
})

vim.keymap.set("n", "J", "mzJ`z:delmarks z<cr>")

from this code and from my actual config
```

- filetype defaults
 - python and lua - 4 spaces, expandtab

`<leader>`gsa - appears to not be working when the stash applies successfully
`<leader>`gsa - add a preview window (diff)


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

Change my company GIT_EDITOR to be neovim
