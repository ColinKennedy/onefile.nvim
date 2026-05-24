- Add :Dispatch support
- The selector GUI filter isn't that great, still

- If I load a session with a terminal, it starts the wrong buffer in INSERT
  mode (it tries to add insert mode for the terminal but touches the current
  buffer instead)

- The aerial window when no tree-sitter parser is found is kind of useless
  (e.g. in Python). Is there a way to fix that?
```python
# Some comments
@another.line(
    args = 10
)
def function(
    some: str,
    text: str
) -> blah:
    """Something."""
```

- Once that neovim remote PR is merged, add that to my git commit / git rebase
  editor command so that I don't get nested Neovims anymore.
- A <M-S-{1,2,3,4}> for grapple
`<space>`W
`<space>`q
- Add :Gcd
| n | `<C-w>`o      | Toggle full-screen or minimize a window.                  |

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

One windows, I don't see the name of the current file anyway. Not even in the buffer line. Fix that

Add any "only these lines" command that is available only during `git add -p`'s `e` mode
- <leader>gph / <leader>gpl needs to update the buffer
 - I think I already added this
