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

- Fix the <C-hjkl> mappings
 - needs to work
  - with terminal, tmux swapping, window snapping

- fix annoying M-hjkl issue where there is no vertical split

- git mappings - ]g / [g to go to the next or previous git hunk

- git signs
- git reset / add / checkout hunks

- Update statusline
 - try to make it static functions
- Add env vars for every executable

- Remove the z mapping
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


- quickscope
 - don't highlight a character if the cursor is already on the current word

- Make sure <space>e populates without pressing any keys

- Add keymap desc values

- Clean the variable names and stuff. Gross

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
