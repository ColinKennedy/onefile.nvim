- Docstrings for the modules still need to exist
- Add gitgutter + git navigation [g + ]g support + multi-file navigation
- Add :Gcd
- Add tests

- Add a "cleanup all buffers except terminal buffers" command. Call if BufOnly
- Add quickscope support
- Add tmux pane swapper logic

- trailing whitespace bug
 - adding prefix > lines does not delete trailing whitespace

- Add a <CR> mapping in normal mode in the selection GUI buffer. It's annoying to have to switch to insert mode to confirm the selection every time

- Add gp mapping
 - It exists but doesn't work with ]p or [p yet. And probably doesn't work with `>p` / `<p` yet. Fix.

- Make startup faster

- Add pairwise mappings. e.g. "", '', ``, etc

- Add deferral magic

- Change NOTE sections to go above the do/end blocks
- Clean the variable names and stuff. Gross

- Consider moving purpose-specific functions into their sections. e.g. grapple-related code goes into its do-block

- Add terminal hjkl mappings so it works with tmux too
- Add [m, ]m, [c, ]c mappings
- <space>E should auto-update without typing a character


```
foo_ba|r_baz    -> civquux -> foo_quux_baz
QU|UX_SPAM      -> civLOTS_OF -> LOTS_OF_SPAM
eggsAn|dCheese  -> civOr -> eggsOrCheese
_privat|e_thing -> civone -> _one_thing

foo_ba|r_baz    -> dav -> foo_baz
QU|UX_SPAM      -> dav -> SPAM
eggsAn|dCheese  -> dav -> eggsCheese
_privat|e_thing -> dav -> _thing
```

- Add av / iv text objects for text subobjects
- Add aa (args) text object
- Add noice.nvim (TODO, FIXME, IMPORTANT, NOTE, XXX, PERF)

- Add auto-= sign

- Add Cli-based mark support
 - Async-update whenever the file is changed
  - e.g. Run `mypy` on a python file

- Fix the <C-hjkl> mappings
 - needs to work
  - with terminal, tmux swapping, window snapping

- fix annoying M-hjkl issue where there is no vertical split

- git mappings - ]g / [g to go to the next or previous git hunk

- git signs
- git reset / add / checkout hunks

- Update statusline
 - Try to make it static functions

- Removing trailing whitespace doesn't actually work. Fix later


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

- tmux switch pane support

- `<leader>gsa` doesn't auto-populate properly unless I type at least one character, which is annoying. Fix

- quickscope
 - don't highlight a character if the cursor is already on the current word

- Make sure <space>e populates without pressing any keys

- Allow multi-selection support
`<leader>`gsa - appears to not be working when the stash applies successfully

escape insert or terminal mode using jk

`<leader>`gsa - add a preview window (diff)

`<space>`W
`<space>`q
- quick-scope
- put-related directional mappings. e.g. [P ]p, piw, etc
`<leader>`iV
`<leader>`iv
| n | `<C-w>`o      | Toggle full-screen or minimize a window.                  |
| n | P    | Prevent text from being put, twice.                                        |
| n | PP   | Put text, like you normally would in Vim, but how [Y]ank does it.          |


Make sure keymaps have descs

```lua
local modes = { "n", "i", "v", "x", "s", "o", "t", "c" }

for _, mode in ipairs(modes) do
    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
        if not map.desc or map.desc == "" then
            print(string.format(
            "[%s] %s -> %s",
            mode,
            map.lhs,
            map.rhs or "<Lua>"
        ))
    end
end
end
```



write_current_session fails on windows due to path mismatch issues
- e.g. one file has ~, another doesn't

Need _LINES[buffer] check, for strip_trailing_whitespace

Need Gcd command

the default terminal goes to WSL, it needs to go to pwsh (make this configurable)

remove trailing whitespace syntax highlighting for terminal buffers

ObsidianToday / Yesterday / Tomorrow commands

Make the git statusline prefer the focused file's git repository first, before falling back to cwd

Git pull isn't working on windows. It could be terminal-related again

Change my company GIT_EDITOR to be neovim

One windows, I don't see the name of the current file anyway. Not even in the buffer line. Fix that

Add any "only these lines" command that is available only during `git add -p`'s `e` mode

the >p <p [p ]p are slightly broken and need fixing

Add il operator

Git statusline should elide a long branch name. Show the jira ticket prefix and the last characters

`<leader>sa` - should be able to inline / outline

- The DEBUGPRINT doesn't give line numbers on Windows, for some reason
- Also the formatter should be `rf""`, not `f""`, because Windows can have backslashes

Rg command takes a long time if there's a really long line. Maybe there's a way to make it faster? e.g. ellide the text?

Rg command doesn't sort the output by path and by line number / column number

Add `:Gcd` command, for git

- `piw` just doesn't work quite right

- Make Vim terminals default to `pwsh`

- `PP` doesn't paste to the line above sometimes
