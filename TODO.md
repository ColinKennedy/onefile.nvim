- `:Git diff` isn't showing anything. Fix

- Add an error-check if the fallback AI, `claude -p`, is not accessible. Abort early



- change the env vars to be neovim-ish
- Also document any env vars that aren't documented
````
- `VIM_LOG_LEVEL` - Sets the minimum `vim.notify` level shown by Neovim. It
  defaults to `2`, which hides `DEBUG` notifications unless you opt in with
  a lower value.

- `VIM_ENABLE_NOTIFY_LOGGING` - Enables notification logging when set to
  a non-zero value. When enabled, notifications are appended to a temporary log
````


takes the current buffer as-text, stores it somewhere,
  and then makes a new buffer (probably as a new tab). And then I can type
  whatever I want there (speech to text) and then press the mapping again to
  merge the original text with that buffer's text
 - Useful for when I have a lot of tickets to go through, in the grill-me step
 - Under the hood, use a temporary file with the merged text + `claude -p 'Read the instructions in @C:\tmp\that\file.txt and respond'`
 - Probably the storage shoudl be a variable that is tab-number aware. Like a `table<integer, str>`, the key is the tab and the str is the original text




- A text object for comment blocks. e.g. `yic`

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
