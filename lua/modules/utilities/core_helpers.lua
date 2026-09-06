--- Shared utility functions, type definitions, constants, and state for the Neovim configuration.

---@class _my.core_helpers
---@field ENGLISH_LANGUAGE string The Neovim `:help` language tag for English.
---@field BOOKMARK_MINIMUM integer The lowest bookmark index.
---@field BOOKMARK_MAXIMUM integer The highest bookmark index.
---@field LSP_GROUP integer The augroup that starts LSP servers.
---@field SNIPPET_AUGROUP integer The augroup that drives snippet completion.
---@field TERMINAL_GROUP integer The augroup that customizes terminal behavior.
---@field GIT_EXECUTABLE string The `git` command to run.
---@field RIPGREP_EXECUTABLE string The `rg` command to run.
---@field SESSIONS_DIRECTORY_NAME string The directory that stores branch-aware sessions.
---@field VIM_SESSION_FILE_NAME string The conventional Vim session file name.
---@field VIMSCRIPT_COMMENT_MARKER string The character that starts a Vimscript comment.
---@field SESSIONX_NAME string The VCS-root session file name.
---@field IS_NERDFONT_ALLOWED boolean If `true`, icons may use Nerd Font glyphs.
local M = {}
local _P = {}

---@class _my._datatypes.IntBounds An inclusive or exclusive pair of integers.
---@field first integer The starting value.
---@field last integer The ending value.

---@class _my.comment._TagColumns
---    A description of the first line of a "tagged" inline comment.
---@field tag_text _my._datatypes.IntBounds
---    The exact range where a matched tag's text starts and ends.
---@field tag_bounds _my._datatypes.IntBounds
---    The outer range of "the tag's text + the surrounding characters".
---@field comment_text _my._datatypes.IntBounds
---    The actual user inline comment, without the tag.

---@class _my.completion.Data All Snippet-internal data used during callbacks.
---@field completed vim.v.completed_item | _my.completion.Entry The completed word/phrase.

---@class _my.completion.Entry A Neovim representation of a "row" of auto-complete data.
---@field kind string The type of completion item.
---@field menu string The sub-category / grouping.
---@field word string The word or phrase display text to show in the completion row.

---@alias _my.selector_gui.Value string|integer
---    A raw, un-deserialized selector option, as handed to `select_from_options`.
---    Buffer selectors pass buffer numbers. Everything else passes text.

---@class _my.selector_gui.entry.Deserialized The formatted option used by the selector GUI.
---@field display string The text to show in the pop-up.
-- typer: ignore-next-line[disallowed-any]
---@field value any The original data, unformatted.

---@class _my.selector_gui.HeaderChunk A highlighted bit of selector header text.
---@field text string The text to draw at the top of the selector's results window.
---@field highlight string The highlight group to apply to `text`.

---@class _my.selector_gui.PreviewContent The content to draw in a selector preview window.
---@field lines string[] The lines to show in the preview window.
---@field filetype string? The preview buffer filetype.
---@field buftype string? The preview buffer buftype.

---@class _my.selector_gui.PreviewOptions Preview-window settings for the selector GUI.
---@field location "top"|"right" Where to render the preview window.
---@field min_height integer? Do not render the preview if it would be shorter than this.
---@field height_ratio number? How much editor height to use for a top preview.
---@field width_ratio number? How much selector width to use for a right preview.
---@field render fun(entry: _my.selector_gui.entry.Selection): _my.selector_gui.PreviewContent?

---@alias _my.easymotion.ExtmarksData table<string, {line: integer, column: integer, id: integer}>

---@alias _my.window.Edge "top" | "bottom" | "left" | "right"

---@alias _my.window.Direction "up" | "down" | "left" | "right"

---@class _my.lsp_attach.Result Data from Neovim LspAttach.
---@field buf integer The buffer that has LSP capabilities.
---@field data _my.lsp_attach.Result.parameter Information that Neovim returns during LspAttach.

---@class _my.lsp_attach.Result.parameter Information that Neovim returns during LspAttach.
---@field client_id integer The process ID for Neovim's LSP client. I think.

---@class _my.lsp.ServerDefinition
---    A group of LSP-related settings to initialize with.
---@field name string
---    The name of the LSP.
---@field config vim.lsp.Config|fun(): vim.lsp.Config
---    The config that Neovim should enable for the LSP.

---@class _neovim.commandline.Options Raw data that gets passed from `nvim_create_user_command`
---@field args string The input that a user writes to the command.

---@class _my.selector_gui.State An internal state tracker for the selector floating window.
---@field input string The currently-written user prompt input.
---@field all _my.selector_gui.Value[] All possible options to consider.
---@field filtered _my.selector_gui.entry.Selection[] All options that match with `input`.
---@field selected integer The selected index.
-- typer: ignore-next-line[disallowed-any]
---@field selected_by_value table<any, _my.selector_gui.entry.Selection>
---    Entries explicitly selected in multi-select mode.

---@class _my.selector_gui.entry.Selection : _my.selector_gui.entry.Deserialized
---    The formatted option used by the selector GUI.
---@field score integer
---    How close this entry is to the user's input (0==strong match).

---@class _my.selection_gui.GuiOptions
---    Use this to control the behavior of the selection GUI.
---@field input string?
---    Starting text to being a search, if any.
---@field header _my.selector_gui.HeaderChunk[]?
---    Static, unselectable text chunks to render above the selectable rows.
---@field multiple_selection boolean?
---    If enabled, <Tab> toggles selected entries and confirm sends all selected
---    entries, or the hovered entry if nothing was explicitly selected.
---@field preview _my.selector_gui.PreviewOptions?
---    If provided, render a preview window for the currently selected entry.
---@field cancel (fun(value: _my.selector_gui.entry.Selection): nil)?
---    Custom "close selection GUI" behavior.
---@field confirm fun(value: _my.selector_gui.entry.Selection|_my.selector_gui.entry.Selection[]): nil
---    The function that runs on-selection.
---@field deserialize (fun(value: _my.selector_gui.Value): _my.selector_gui.entry.Deserialized)?
---    Format the incoming data, if needed. This is needed when
---    `_my.selector_gui.entry.Selection.value` and `_my.selector_gui.entry.Selection.display` are differing values.
---@field sort_score (fun(entry: _my.selector_gui.entry.Selection, input: string): number?)?
---    Optional post-filter ranking. Return a larger number to rank earlier.
---@field sort_maximum integer?
---    Only run `sort_score` when the filtered match count is at-or-below this value.

---@class _my.SnippetCondition.parameters Info to pass to `_my.SnippetCondition`.
---@field start_column integer The cursor column that began the trigger snippet.
---@field trigger string The character or phrase that triggered the snippet.

---@alias _my.SnippetCondition fun(details: _my.SnippetCondition.parameters): boolean
---    If return `true`, show the snippet.

---@class _my.Snippet A sparse description of some trigger text + contents.
---@field body string The expanded snippet text, once it is selected.
---@field on _my.SnippetCondition? If this function returns `true`, show the snippet.
---@field description string Documentation for what this snippet does.
---@field kind string? The type/category of snippet.
---@field trigger string The text that is shown in the completion menu.

---@class _my.ToggleTerminal A description of the last-known state of a terminal.
---@field buffer integer The Vim buffer of the terminal.
---@field mode string The last Vim mode (NORMAL, TERMINAL, etc).

---@type string[]
local _ALL_CONTIGUOUS_PROJECT_ROOT_MARKERS = { "CMakeLists.txt", "__init__.py" }
M.ENGLISH_LANGUAGE = "en"

---@type string[]
M.LUA_ROOT_PATHS = {
    ".luacheckrc",
    ".luarc.json",
    ".luarc.jsonc",
    ".stylua.toml",
    "selene.toml",
    "selene.yml",
    "stylua.toml",
}

--- Run `callback` without showing file-info messages.
---
--- This is useful for temporary/special buffers whose internal names should
--- not be echoed as if the user opened a regular file.
---
---@generic T
---@param callback fun(): T? The work to run while file messages are suppressed.
---@return T? # The callback result.
function M.with_file_messages_suppressed(callback)
    local shortmess = vim.o.shortmess

    vim.opt.shortmess:append("F")

    local ok, result = pcall(callback)
    vim.o.shortmess = shortmess

    if not ok then
        error(result, 0)
    end

    return result
end

local _ALL_SINGLE_PROJECT_ROOTS = vim.tbl_deep_extend("force", {}, M.LUA_ROOT_PATHS)
_ALL_SINGLE_PROJECT_ROOTS = vim.list_extend(_ALL_SINGLE_PROJECT_ROOTS, {
    -- Language-Agnostic
    ".editorconfig",
    ".git",

    -- Python
    ".flake8",
    ".pylintrc",
    "Pipfile",
    "Pipfile.lock",
    "poetry.lock",
    "pyproject.toml",
    "pytest.ini",
    "requirements.txt",
    "setup.cfg",
    "setup.py",
    "tox.ini",

    "package.py", -- Rez

    -- (Neo)vim
    "init.lua",
    "init.vim",
})

M.BOOKMARK_MINIMUM = 1
M.BOOKMARK_MAXIMUM = 9

---@type integer?
local _CURRENT_RIPGREP_COMMAND = nil

---@type table<string, string>
M.FILETYPE_TO_TREESITTER = { python = "python" }
M.LSP_GROUP = vim.api.nvim_create_augroup("my.lsp.start", { clear = true })
M.SNIPPET_AUGROUP = vim.api.nvim_create_augroup("my.snippet.completion", { clear = true })
M.TERMINAL_GROUP = vim.api.nvim_create_augroup("my.terminal.behavior", { clear = true })

M.GIT_EXECUTABLE = os.getenv("NEOVIM_GIT_EXECUTABLE_PATH") or "git"
M.RIPGREP_EXECUTABLE = os.getenv("NEOVIM_RIPGREP_EXECUTABLE_PATH") or "rg"

---@type table<string, boolean>
local _LANGUAGES_CACHE = {}

---@type table<string, _my.Snippet[]>
local _SNIPPETS = {}

M.SESSIONS_DIRECTORY_NAME = os.getenv("NEOVIM_SESSIONS_DIRECTORY_NAME") or ".sessions"

-- NOTE: Don't mess with this variable unless you know what you're doing.
---@type table<string, _my.Snippet>
M.TRIGGER_TO_SNIPPET_CACHE = {}

-- NOTE: This is a normal Vim convention for session names.
M.VIM_SESSION_FILE_NAME = "Session.vim"

M.VIMSCRIPT_COMMENT_MARKER = '"'

M.SESSIONX_NAME = "Sessionx.vim"

M.IS_NERDFONT_ALLOWED = true

local _MAXIMUM_QUICK_FIX_LENGTH = 55

-- luacheck: push ignore
local unpack = unpack or table.unpack
-- luacheck: pop

--- Check if `executable` is a command found on `$PATH`.
---
---@param executable string Some command. e.g. `"git"` or `"/path/to/foo.exe"`.
---@return boolean # If found, return `true`.
---
function M.exists_command(executable)
    return vim.fn.executable(executable) == 1
end

--- Check if `directory` has at least one matching subdirectory from `names`.
---
---@param directory string A root directory to search within.
---@param names string[] All of the possible subdirectory names.
---@return boolean # If at least one name is found, return `true`.
---
function _P.has_matching_directory(directory, names)
    for _, name in ipairs(names) do
        local path = vim.fs.joinpath(directory, name)

        if vim.fn.filereadable(path) == 1 then
            return true
        end
    end

    return false
end

--- Check if `name` is registered as a tree-sitter parser, but only once.
---
---@param name string The name of the tree-sitter parser to check.
---@return boolean # If `name` exists, return `true`.
---
function M.has_treesitter_parser(name)
    if _LANGUAGES_CACHE[name] then
        return _LANGUAGES_CACHE[name]
    end

    local success, _ = pcall(function()
        vim.treesitter.get_parser(0, name)
    end)
    _LANGUAGES_CACHE[name] = success

    return _LANGUAGES_CACHE[name]
end

--- Check if Vim `mark` is set already.
---
---@param mark string The Vim mark name. e.g. `"A"`.
---@return boolean # If the mark is defined, return `true`.
---
function _P.is_mark_defined(mark)
    local position = vim.api.nvim_get_mark(mark, {})

    return position[1] ~= 0
end

--- @return boolean # Check if the Neovim is running in tmux right now.
function M.in_tmux()
    return vim.fn.exists("$TMUX") == 1
end

--- Check if the user's current cursor is at the start of some source-code line.
---
---@param details _my.SnippetCondition.parameters The current trigger context.
---@return boolean # If we are at the start of some source-code line, return `true`.
---
function _P.is_start_of_source_line(details)
    local line = vim.api.nvim_get_current_line()
    local text_up_to_the_trigger = line:sub(1, details.start_column)

    return (text_up_to_the_trigger:match("^%s*$"))
end

--- Remove leading spaces across all snippets.
function _P.dedent_snippets()
    --- Remove all common, leading whitespace from text.
    ---
    ---@param text string Some blob of text that probably contains leading whitespaces.
    ---@return string # Keep internal indentation but remove all common indentation across all lines.
    ---
    local function _dedent(text)
        text = text:gsub("\n[ ]+$", "\n")

        if vim.text and vim.text.indent then
            return (vim.text.indent(0, text))
        end

        ---@type integer
        local minimum_indent

        for line in text:gmatch("[^\n]+") do
            if line:find("%S") then
                local indent = #(line:match("^%s*") or "")

                minimum_indent = math.min(minimum_indent or indent, indent)
            end
        end

        if not minimum_indent or minimum_indent == 0 then
            return text
        end

        return (
            text:gsub("[^\n]+", function(line)
                if not line:find("%S") then
                    return line
                end

                return line:sub(minimum_indent + 1)
            end)
        )
    end

    for _, snippets in pairs(_SNIPPETS) do
        for _, snippet in ipairs(snippets) do
            snippet.body = _dedent(snippet.body)
        end
    end
end

---@type table<string, _my.Snippet[]>
_SNIPPETS = {
    python = {
        -- NOTE: Simple Statement Snippets
        {
            body = "import $1",
            description = "An import statement",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "ii",
        },
        {
            body = "raise $1",
            description = "A raise statement",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "ra",
        },
        {
            body = "return False",
            description = "A quick-return False statement",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "rf",
        },
        {
            body = "return None",
            description = "A quick-return None statement",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "rn",
        },
        {
            body = "return True",
            description = "A quick-return True statement",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "rt",
        },
        {
            body = "yield $1",
            description = "A yield statement",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "y",
        },

        -- NOTE: Decorator Snippets
        {
            body = "@classmethod",
            description = "@classmethod",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "@c",
        },
        {
            body = "@property",
            description = "@property",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "@p",
        },
        {
            body = "@staticmethod",
            description = "@staticmethod",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "@s",
        },

        -- NOTE: Method Snippets
        {
            body = "self.${1:blah}",
            description = "self. prefix",
            kind = "Statement",
            trigger = "s",
        },

        -- NOTE: Block Snippets
        {
            body = [[
            for ${1:item} in ${2:items}:
                ${3:pass}
        ]],
            description = "for item in items:",
            kind = "Statement",
            on = _P.is_start_of_source_line,
            trigger = "for",
        },
        {
            body = [[
            with ${1:open()} as ${2:handler}:
                ${3:pass}
        ]],
            description = "with foo as handler:",
            kind = "Statement",
            trigger = "with",
        },

        -- NOTE: Useful line-starters
        {
            body = "_CURRENT_DIRECTORY = os.path.dirname(os.path.realpath(__file__))",
            description = "Make a variable pointing to this Python file's parent directory.",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "_CURRENT_DIRECTORY",
        },
        {
            body = "_LOGGER = logging.getLogger(${1:__name__})",
            description = "Get a vanilla Python logger.",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "_LOGGER",
        },
        {
            body = [[
            _LOGGER = logging.getLogger(${1:__name__})
            _HANDLER = logging.StreamHandler(sys.stdout)
            _HANDLER.setLevel(logging.INFO)
            _FORMATTER = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
            _HANDLER.setFormatter(_FORMATTER)
            _LOGGER.addHandler(_HANDLER)
            _LOGGER.setLevel(logging.INFO)
        ]],
            description = "Create a basic StreamHandler Python logger",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "_LOGGER_STREAM",
        },
        {
            body = '"""$1.""""',
            description = "Create a triple-quote docstring",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "D",
        },
        {
            body = 'print(sorted(item for item in dir(${1:sequence}) if "$2" in item.lower()))',
            description = "dirgrep the current selection",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "dirgrep",
        },
        {
            body = "# TODO: $1",
            description = "Add a TODO note",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "td",
        },
        {
            body = "# TODO: @ColinKennedy - $1",
            description = "Add a TODO note",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "tdc",
        },
        {
            body = "os.path.$1",
            description = "os.path.",
            kind = "Line-Starter",
            trigger = "osp",
        },
        {
            body = "os.path.join($1)",
            description = "os.path.join(...)",
            kind = "Line-Starter",
            trigger = "ospj",
        },
        {
            body = "atexit.register(functools.partial(os.remove, ${1:path}))",
            description = "Delete a file but only after Python exits.",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "atexit_file",
        },
        {
            body = "atexit.register(functools.partial(shutil.rmtree, ${1:directory}))",
            description = "Delete a folder but only after Python exits.",
            kind = "Line-Starter",
            on = _P.is_start_of_source_line,
            trigger = "atexit_folder",
        },
        {
            body = [[
            @contextlib.contextmanager
            def profile_and_print():
                profiler = profile.Profile()
                profiler.enable()

                try:
                    yield
                finally:
                    profiler.disable()
                    stats = pstats.Stats(profiler)
                    stats.sort_stats("cumulative").print_stats(20)

            with profile_and_print():
                ${1:pass}
        ]],
            description = 'Add a "profile this code and print it" Python context.',
            kind = "Debugging",
            on = _P.is_start_of_source_line,
            trigger = "profile_and_print",
        },

        -- Typing-savers
        {
            body = "'.format($1)",
            description = "Make a format block",
            kind = "Statement",
            trigger = "'.f",
        },
        {
            body = '".format($1)',
            description = "Make a format block",
            kind = "Statement",
            trigger = '".f',
        },

        -- NOTE: Qt Snippets
        {
            body = [[
            parent (Qt.QtCore.QObject, optional):
                An object which, if provided, holds a reference to this instance.
        ]],
            description = "A docstring auto-fill for a common Qt parameter",
            kind = "Debugging",
            on = _P.is_start_of_source_line,
            trigger = "widgetparent",
        },
        {
            -- luacheck: ignore 631
            body = [[
            if hasattr(${1:menu}, "setToolTipsVisible"):
                # Important: Requires Qt 6!
                #
                # Reference: https://doc.qt.io/qtforpython-6/PySide6/QtWidgets/QMenu.html#PySide6.QtWidgets.PySide6.QtWidgets.QMenu.setToolTipsVisible
                #
                $1.setToolTipsVisible(True)
        ]],
            description = "Enable tool-tips for QMenus.",
            trigger = "enable_menu_tooltips",
        },

        -- NOTE: USD Snippets
        {
            body = "print(${1:stage}.GetRootLayer().ExportToString())",
            description = "Get a string that represents the USD.Stage",
            kind = "USD",
            on = _P.is_start_of_source_line,
            trigger = "ExportToString_usd",
        },
    },
}
_P.dedent_snippets() -- NOTE: We make the all snippet body clean

--- Close terminal `buffer` after its process exits.
---
---@param buffer integer A 1-or-more value pointing to the terminal to close.
function M.close_terminal_afterwards(buffer)
    vim.api.nvim_create_autocmd("TermClose", {
        buffer = buffer,
        callback = vim.schedule_wrap(function()
            if vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_buf_delete(buffer, { force = true })
            end
        end),
        once = true,
    })
end

--- Find all snippets that we can complete, using `data`.
---
---@param data {file_type: string, start_column: integer} The cursor + completion prefix.
---@return _my.completion.Entry[] # All found snippet matches, if any.
---
function M.compute_snippet_completion_options(data)
    -- NOTE: Re-populate the cache with snippets which match the completion menu
    ---@type table<string, _my.Snippet>
    M.TRIGGER_TO_SNIPPET_CACHE = {}

    local snippets = _SNIPPETS[data.file_type] or {}

    ---@type string[]
    local output = {}

    for _, snippet in ipairs(snippets) do
        if not snippet.on or snippet.on({ start_column = data.start_column, trigger = snippet.trigger }) then
            table.insert(output, {
                menu = data.file_type,
                kind = snippet.kind or "Snippet",
                word = snippet.trigger,
            })
            M.TRIGGER_TO_SNIPPET_CACHE[snippet.trigger] = snippet
        end
    end

    return output
end

--- Remove `candidates` if they start with `base`.
---
---@param candidates _my.completion.Entry[] All possible text that could match.
---@param base string Some prefix text to search for in each `candidates`.
---@return _my.completion.Entry[] # The found matches, if any.
---
function M.filter_by_text(candidates, base)
    ---@type _my.completion.Entry[]
    local output = {}

    for _, completion in ipairs(candidates) do
        if completion.word:find("^" .. vim.pesc(base)) then
            table.insert(output, completion)
        end
    end

    return output
end

---@return integer
---    A 1-or-more column value that points to the user's "completion trigger
---    text" begins on the line.
---
function _P.find_completion_start()
    -- NOTE: We're being asked where the completion starts
    local line = vim.fn.getline(".")
    local column = vim.fn.col(".")
    local start = column

    while start > 1 and line:sub(start - 1, start - 1):match("[%w_]") do
        start = start - 1
    end

    return start
end

---@return integer
---    A 1-or-more column value that points to the user's "completion trigger
---    text" begins on the line.
---@return string
---    The user's completion trigger text.
---
function M.get_completion_location()
    local start_column = _P.find_completion_start()
    local current_column = vim.fn.col(".")
    local line = vim.fn.getline(".")
    local base = line:sub(start_column, current_column - 1)

    return start_column, base
end

--- Get the direct-parent directory of some `buffer` (assuming the buffer is a file).
---
---@param buffer integer? 0-or-more Vim data buffer number.
---@return string? # The found directory, if any.
---
function _P.get_current_buffer_directory(buffer)
    buffer = buffer or vim.api.nvim_get_current_buf()

    local success, path = pcall(function()
        return vim.api.nvim_buf_get_name(buffer)
    end)

    if not success or path == "" then
        return nil
    end

    return vim.fn.fnamemodify(path, ":h")
end

---@return string # Find the directory of the current file if it's on-disk.
function _P.get_current_directory()
    local buffer = 0
    local path = vim.api.nvim_buf_get_name(buffer)

    if path == "" then
        return vim.fn.getcwd(buffer)
    end

    return vim.fs.dirname(path)
end

--- Run `command` and asynchronously return its results.
---
--- Important:
---     The returned string[] table is special. Its contents are populated
---     while the shell command is executing. So you may iterate over the table
---     once and get a different result if you iterate it again (because it
---     populated more data than last time).
---
---@param command string[] The shell command to run. e.g. `{"ls", "~"}`.
---@param on_fail (fun(obj: vim.SystemCompleted): nil)? If included, a function that runs on-error.
---@param on_update (fun(): nil)? If included, a function that runs after command output is added.
---@return string[] # All returned results.
---
function M.get_deferred_shell_command_results(command, on_fail, on_update)
    ---@param obj vim.SystemCompleted
    local function generic_error(obj)
        vim.notify(
            string.format('Command "%s" failed: "%s".', vim.inspect(command), obj.stderr or "<No stderr found>"),
            vim.log.levels.ERROR
        )
    end

    on_fail = on_fail or generic_error

    ---@type string[]
    local options = {}

    --- Add command stdout lines to `options`.
    ---
    ---@param stdout string? The command stdout text.
    local function append_stdout(stdout)
        for line in vim.gsplit(stdout or "", "\n") do
            if line ~= "" then
                table.insert(options, line)
            end
        end
    end

    vim.system(command, { text = true }, function(obj)
        append_stdout(obj.stdout)

        if on_update then
            vim.schedule(on_update)
        end

        if obj.code ~= 0 then
            vim.schedule(function()
                on_fail(obj)
            end)

            return
        end
    end)

    --- Get the option at `i`, if it has been read from stdout yet.
    ---
    ---@param i integer A 1-or-more index into the found options.
    ---@return string? # The found option, if any.
    ---
    local function generate_value(i)
        return options[i]
    end

    ---@type string[]
    local output = {}

    setmetatable(output, {
        __index = function(t, key)
            local value = generate_value(key)

            if not value then
                return nil -- stop when out of stuff
            end

            rawset(t, key, value)

            return value
        end,
    })

    return output
end

--- Elide-right the `text`. Make `"something long here"` into `"something long..."`.
---
---@param text string The text to possibly crop.
---@param maximum integer A 3-or-more value indicating the crop position.
---@return string # The `text` is long, it is elided.
---
function _P.get_elided_right_text(text, maximum)
    maximum = maximum or 40
    local count = #text

    if count <= maximum then
        return text
    end

    return text:sub(1, maximum - 3) .. "..."
end

-- TODO: I think the code below make not scale well. Consider replacing with
-- a "tris" algorithm where text blobs are split into 3-letter-chunks and then
-- matched. So that we're typo-tolerant but still fast.
--
--- Score how well a single query matches a single candidate token.
---
---@param query string Some user input to check.
---@param candidate string A possible match to consider.
---@return number? # A 0-to-1 similarity score. 1 means "exact match", 0 means "no match".
---
function M.get_fuzzy_match_score(query, candidate)
    --- Return true if `query_` is one small typo away from `candidate_`.
    ---
    --- This is intentionally bounded. It catches the common interactive-search
    --- mistakes without doing full edit-distance work for every candidate.
    ---
    ---@param query_ string Some normalized user input.
    ---@param candidate_ string Some normalized candidate text.
    ---@return boolean # Whether the typo-tolerant fallback matched.
    ---
    local function is_near_typo(query_, candidate_)
        local query_length = #query_
        local candidate_length = #candidate_

        if query_length == 0 then
            return true
        end

        if math.abs(query_length - candidate_length) > 1 then
            return false
        end

        local query_index = 1
        local candidate_index = 1
        local edits = 0

        while query_index <= query_length and candidate_index <= candidate_length do
            local query_character = query_:sub(query_index, query_index)
            local candidate_character = candidate_:sub(candidate_index, candidate_index)

            if query_character == candidate_character then
                query_index = query_index + 1
                candidate_index = candidate_index + 1
            else
                edits = edits + 1

                if edits > 1 then
                    return false
                end

                local next_query = query_:sub(query_index + 1, query_index + 1)
                local next_candidate = candidate_:sub(candidate_index + 1, candidate_index + 1)

                if query_character == next_candidate and next_query == candidate_character then
                    query_index = query_index + 2
                    candidate_index = candidate_index + 2
                elseif query_length > candidate_length then
                    query_index = query_index + 1
                elseif candidate_length > query_length then
                    candidate_index = candidate_index + 1
                else
                    query_index = query_index + 1
                    candidate_index = candidate_index + 1
                end
            end
        end

        if query_index <= query_length or candidate_index <= candidate_length then
            edits = edits + 1
        end

        return edits <= 1
    end

    --- Score a fuzzy subsequence match in a single pass over `candidate_`.
    ---
    ---@param query_ string Some normalized user input.
    ---@param candidate_ string Some normalized candidate text.
    ---@return number? # A sortable score, or nil if the query does not match.
    ---
    local function subsequence_score(query_, candidate_)
        if query_ == "" then
            return 1
        end

        local direct_start = candidate_:find(query_, 1, true)

        if direct_start then
            return 10000 - direct_start - (#candidate_ - #query_)
        end

        local query_index = 1
        local score = 0
        local streak = 0
        local last_match = 0
        ---@type integer?
        local first_match = nil

        for candidate_index = 1, #candidate_ do
            if query_index > #query_ then
                break
            end

            local query_character = query_:sub(query_index, query_index)
            local candidate_character = candidate_:sub(candidate_index, candidate_index)

            if query_character == candidate_character then
                first_match = first_match or candidate_index

                if candidate_index == last_match + 1 then
                    streak = streak + 1
                else
                    streak = 1
                end

                local previous = candidate_index == 1 and "/"
                    or candidate_:sub(candidate_index - 1, candidate_index - 1)
                local is_boundary = previous:match("[%s%-%_%.%/]") ~= nil

                score = score + 40 + (streak * 12)

                if is_boundary then
                    score = score + 35
                end

                if candidate_index == query_index then
                    score = score + 20
                end

                last_match = candidate_index
                query_index = query_index + 1
            end
        end

        if query_index <= #query_ then
            return nil
        end

        return score - ((first_match or 1) * 2) - (#candidate_ - #query_)
    end

    local normalized_query = query:lower():gsub("[^%w%s%-%_%.%/]", "")
    local normalized_candidate = candidate:lower():gsub("[^%w%s%-%_%.%/]", "")

    local score = subsequence_score(normalized_query, normalized_candidate)

    if score then
        return score
    end

    -- Keep typo tolerance cheap: only compare the query against individual path
    -- pieces whose length is close enough for one edit or transposition.
    for token in normalized_candidate:gmatch("[%w]+") do
        if math.abs(#normalized_query - #token) <= 1 and is_near_typo(normalized_query, token) then
            return 15 - math.abs(#normalized_query - #token) - (#token / 100)
        end
    end

    return nil
end

---@return string[] # Every file or directory on-disk that could be helpfiles.
function M.get_helptag_search_paths()
    -- TODO: Fix type-hint in Neovim core, later
    return vim.fn.globpath(vim.o.runtimepath, "doc/tag*", true, true)
end

---@return table<string, vim.fn.getmarklist.ret.item>
function M.get_marks_mapping()
    ---@type table<string, vim.fn.getmarklist.ret.item>
    local output = {}

    for _, mark in ipairs(vim.fn.getmarklist()) do
        output[mark.mark] = mark
    end

    return output
end

--- Find the start of the project, if any.
---
--- If the project has a known top-level file, e.g. `"setup.py"` then that
--- directory is returned. Otherwise we'll try to find a root by looking for
--- indicators / markers like `"CMakeLists.txt"` files.
---
---@param source string | integer The child directory to search from or the Vim buffer.
---@return string? # The found root, if any.
---
function M.get_nearest_project_root(source)
    local root = vim.fs.root(source, _ALL_SINGLE_PROJECT_ROOTS)

    if root then
        return root
    end

    if type(source) == "number" then
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

        if name ~= "" then
            source = vim.fs.dirname(name)
        else
            source = vim.fn.getcwd()
        end
    end

    ---@cast source string

    return _P.get_topmost_contiguous_project_root_marker(source, _ALL_CONTIGUOUS_PROJECT_ROOT_MARKERS)
end

--- Starting from `directory`, look for `names` to indicate a project root.
---
---@param directory string
---    Some absolute path on-disk.
---@param names string[]
---    A marker that, once found, must be found in every parent directory
---    contiguously. The last parent directory that has the marker is assumed
---    to be the "root" of the project.
---@return string?
---    The found project root, if any.
---
function _P.get_topmost_contiguous_project_root_marker(directory, names)
    local found_yet = false
    local current = directory
    ---@type string?
    local previous = nil

    while current and previous ~= current do
        if not _P.has_matching_directory(current, names) then
            if found_yet then
                return previous
            end
        else
            found_yet = true
        end

        previous = current
        current = vim.fs.dirname(current)
    end

    return nil
end

--- Change our internal grapple bookmark index to a global Vim mark.
---
---@param index integer A 1-to-9 value.
---@return string # The global character mark. e.g. A, B, C, etc.
---
function M.get_vim_mark_from_bookmark_index(index)
    return string.char(64 + index) -- A=65, B=66, etc.
end

--- Find the top-level project, if any, and then cd Neovim to it.
function M.cd_to_parent_project_root()
    local directory = vim.fn.getcwd()
    local root = M.get_nearest_project_root(directory)

    if root then
        vim.cmd(string.format("silent cd %s", root))
        vim.notify(string.format('cd\'ed to "%s"', root), vim.log.levels.INFO)

        return
    end

    vim.notify("No root was found", vim.log.levels.ERROR)
end

--- Allow writing to files asnchronously
---
--- Reference: https://github.com/neovim/neovim/issues/11005#issuecomment-1271575651
---
---@param ok boolean If async writing is okay, this value is `true`.
---@param message string If not `ok`, this has an error message.
---
function M.check_async_write(ok, message)
    vim.schedule(function()
        if ok then
            vim.cmd.checktime()
        elseif message and message ~= "" then
            vim.notify(string.format('Async write failed with "%s" message.', message), vim.log.levels.ERROR)
        else
            vim.notify("Something in the async write failed, not sure what", vim.log.levels.ERROR)
        end
    end)
end

--- Get the auto-completion options for a user's `text` relative file path.
---
---@param text string
---    Text that comes directly from the user's command-line mode. Usually it's
---    the start of a path on-disk.
---@return string[]?
---    All found auto-completion options, if any.
---
function M.complete_relative(text)
    local directory = _P.get_current_buffer_directory()

    if not directory then
        return vim.fn.getcompletion(text, "file")
    end

    local parent = vim.fs.dirname(text)
    local prefix = vim.fs.basename(text)
    local relative_parent = parent == "." and "" or parent
    local search_directory = relative_parent == "" and directory or vim.fs.joinpath(directory, relative_parent)

    if vim.fn.isdirectory(search_directory) ~= 1 then
        return {}
    end

    ---@type string[]
    local output = {}

    for _, name in ipairs(vim.fn.readdir(search_directory)) do
        if vim.startswith(name, prefix) then
            local relative = relative_parent == "" and name or vim.fs.joinpath(relative_parent, name)
            local full = vim.fs.joinpath(search_directory, name)

            if vim.fn.isdirectory(full) == 1 then
                relative = relative .. "/"
            end

            table.insert(output, relative)
        end
    end

    return vim.fn.sort(output)
end

--- Delete all grapple bookmarks (so we can start from scratch).
function M._delete_all_bookmarks()
    for index, _, _ in M.iter_bookmarks() do
        _P.delete_bookmark(index)
    end
end

--- Move to the next or previous diagnostic message in the current buffer.
---
---@param next boolean
---    If `true`, search forwards in the buffer. If `false`, search backwards.
---@param severity (string | integer)?
---    The type of severity to filter for. If no `severity` is given, allow anything.
---@return fun(): nil
---    A callback that does the diagnostic jump when it is called.
---
function M.go_to_diagnostic(next, severity)
    severity = severity and vim.diagnostic.severity[severity] or nil

    if vim.diagnostic.jump then
        ---@type integer
        local count

        if next then
            count = 1
        else
            count = -1
        end

        return function()
            vim.diagnostic.jump({ count = count, float = true, severity = severity })
        end
    end

    -- NOTE: These lines ensure compatibility with older Neovim versions.
    ---@diagnostic disable-next-line deprecated
    local go = next and vim.diagnostic.goto_next or vim.diagnostic.goto_prev

    return function()
        go({ severity = severity })
    end
end

--- Move to the nearest bookmark after moving a relative `offset` distance.
---
---@param offset integer
---    The number of bookmarks to jump. Usually this value is
---    just `1`, meaning "next bookmark" and `-1`, meaning "previous bookmark".
---
function _P.go_to_relative_bookmark(offset)
    --- Open or load an existing Vim `buffer`.
    ---
    ---@param buffer {index: integer, path: string}
    ---
    local function _load_buffer(buffer)
        if buffer.index ~= 0 then
            vim.cmd(string.format("silent! buffer %s", buffer.index))
        else
            vim.cmd(string.format("silent! edit %s", buffer.path))
        end
    end

    ---@type {index: integer, path: string}[]
    local bookmarks = {}

    for _, buffer_number, buffer_path in M.iter_bookmarks() do
        table.insert(bookmarks, { index = buffer_number, path = buffer_path })
    end

    local current_buffer = vim.api.nvim_get_current_buf()
    local count = #bookmarks

    for index, buffer in ipairs(bookmarks) do
        if buffer.index == current_buffer then
            local new_index = ((index - 1 + offset) % count) + 1
            _load_buffer(bookmarks[new_index])

            return
        end
    end

    local fallback_index = (offset % count) + 1
    _load_buffer(bookmarks[fallback_index])
end

--- Iterate over every grapple.nvim bookmark.
---
---@return fun(): integer?, integer?, string?
---    The absolute bookmark (Lua, not Vim buffer) index.
---    The Vim buffer number of the bookmarked file.
---    The full path to the Vim buffer.
---
function M.iter_bookmarks()
    local index = M.BOOKMARK_MINIMUM - 1

    return function()
        while true do
            index = index + 1

            if index > M.BOOKMARK_MAXIMUM then
                return nil
            end

            local mark = M.get_vim_mark_from_bookmark_index(index)
            local position = vim.api.nvim_get_mark(mark, {})

            -- Only return if the mark exists
            if position[1] ~= 0 then
                return index, position[3], position[4]
            end
        end

        -- luacheck: push ignore
        return nil
        -- luacheck: pop
    end
end

--- Create a function that jumps to `mark` or sets it if it doesn't exist.
---
---@param mark string The Vim mark to jump to (or apply) to the current buffer.
---
function _P.mark_current_buffer_as_bookmark(mark)
    if not _P.is_mark_defined(mark) then
        vim.cmd.mark(mark) -- Set the mark
    else
        vim.cmd("normal! `" .. mark) -- Jump to the bookmark
        -- NOTE: Jump to the last cursor position before leaving-
        --
        -- IMPORTANT: If the mark is not defined or the cursor line is out of
        -- range, just ignore the failure.
        --
        pcall(function()
            vim.cmd('normal! `"')
        end)
    end
end

--- Open `text` relative path using the current directory as a root.
---
--- If the current buffer has no directory then this function is treated as
--- a normal `:edit` command.
---
---@param text string Some relative path. e.g. `"foo.txt"` or "../bar.txt"`, etc.
---
function M.open_relative(text)
    local directory = _P.get_current_buffer_directory()

    if not directory then
        -- NOTE: If the current buffer has no directory, just treat `text` like
        -- a regular buffer-open.
        --
        vim.cmd.edit(text)

        return
    end

    vim.cmd.edit(vim.fs.normalize(vim.fs.joinpath(directory, text)))
end

--- Push the current directory's git repository's changes to a stash.
function M.push_stash_by_name()
    vim.ui.input({ prompt = "Enter git stash name: " }, function(input)
        if not input then
            return
        end

        ---@type string[]
        local command = { M.GIT_EXECUTABLE, "stash", "push", "--message", input }

        if not M.exists_command(command[1]) then
            vim.notify("Cannot create state. No `git` command was found.", vim.log.levels.ERROR)

            return
        end

        vim.system(command, { text = true }, function(obj)
            if obj.code ~= 0 then
                vim.schedule(function()
                    vim.notify(
                        string.format(
                            'Command "%s" failed: "%s".',
                            vim.inspect(command),
                            obj.stderr or "<No stderr found>"
                        ),
                        vim.log.levels.ERROR
                    )
                end)

                return
            end
        end)
    end)
end

--- Remove `./` and `.\` prefix from `text`.
---
---@param text string Some absolute or relative file path.
---@return string # The cleaned path.
---
function _P.cleanup_path(text)
    return (text:gsub("^%.[/\\]+", ""))
end

--- Delete the grapple bookmark as `index`.
---
---@param index integer 1-to-9 bookmark logical index.
---
function _P.delete_bookmark(index)
    local mark = M.get_vim_mark_from_bookmark_index(index)
    vim.cmd.delmarks(mark)
end

--- Set `mark` on `buffer`.
---
---@param mark string A Vim mark to set. e.g. `"A"`.
---@param buffer integer | string A 0-or-more buffer to modify
---
function _P.reset_bookmark(mark, buffer)
    --- Save the current buffer, call `caller`, and then return to the current buffer.
    ---
    ---@param caller fun(): nil Something to call and restore later.
    ---
    local function _return_to_current_buffer(caller)
        local current_buffer = vim.api.nvim_get_current_buf()
        local success, message = pcall(caller)

        vim.cmd(string.format("silent buffer %s", current_buffer))

        if not success then
            error(message)
        end
    end

    local type_ = type(buffer)

    -- NOTE: Visit the buffer, then set the mark, then go back to the previous buffer
    if type_ == "string" then
        _return_to_current_buffer(function()
            vim.cmd(string.format("silent edit %s", buffer))
            vim.cmd.mark(mark)
        end)
    elseif type_ == "number" then
        _return_to_current_buffer(function()
            vim.cmd(string.format("silent buffer %s", buffer))
            vim.cmd.mark(mark)
        end)
    else
        vim.notify(string.format('Bug: expected a string or integer but got "%s" value.', buffer), vim.log.levels.ERROR)
    end
end

--- Grow or shrink the current window along one axis.
---
--- This is a dumb executor: the caller decides the axis and the signed amount.
--- `"height"` runs `:resize` (which resizes the whole row of the current window)
--- and `"width"` runs `:vertical resize` (which resizes the current window and
--- its horizontal neighbour). A positive `amount` grows the current window, a
--- negative one shrinks it.
---
---@param axis "height" | "width" Which dimension to change.
---@param amount integer Signed rows/columns to resize by (`+` grows, `-` shrinks).
---
function M.resize_window(axis, amount)
    local argument = (amount >= 0 and "+" or "") .. amount

    if axis == "height" then
        vim.cmd.resize(argument)
    else
        vim.cmd("vertical resize " .. argument)
    end
end

--- Remove whitespace from the start of `text`.
---
---@param text string Some text that has whitespace at the end. e.g. `"    foo"`.
---@return string # The removed text. e.g. `"foo"`.
---
function M.lstrip(text)
    return text:match("^%s*(.-)$")
end

--- Run the git `command` and show an error if it fails for some reason.
---
---@param command string The git command to run. e.g. `"pull"`, `"push"`, etc.
---
function _P.run_git_generic_command(command)
    local directory = _P.get_current_directory()

    --- Print success or failure, depending on `result`.
    ---
    ---@param result vim.SystemCompleted Some CLI command data to check for a return code.
    ---
    local function _notify_on_error(result)
        if result.code == 0 then
            vim.schedule(function()
                vim.notify(string.format("`git %s` completed successfully.", command), vim.log.levels.INFO)
            end)

            return
        end

        vim.schedule(function()
            vim.notify(string.format('`git %s` failed with error: "%s"', command, result.stderr), vim.log.levels.ERROR)
        end)
    end

    vim.system({ M.GIT_EXECUTABLE, "-C", directory, command }, { text = true }, _notify_on_error)
end

--- Call `git pull` from the current working directory.
function M.run_git_pull()
    _P.run_git_generic_command("pull")
end

--- Call `git push` from the current working directory.
function M.run_git_push()
    _P.run_git_generic_command("push")
end

--- Run `git checkout -p` in the current tab's `$PWD` in a new terminal.
function M.run_git_checkout_p()
    vim.cmd.split()
    vim.cmd.terminal(string.format("%s checkout -p", M.GIT_EXECUTABLE))
    vim.cmd.startinsert() -- NOTE: Drop into INSERT mode immediately

    local terminal_buffer = vim.api.nvim_get_current_buf()

    M.close_terminal_afterwards(terminal_buffer)
end

---@class _my.ripgrep.Options
---@field display_root string? Directory that quickfix paths should be displayed relative to.

--- Get an absolute path for a ripgrep result path.
---
---@param path string A path printed by ripgrep.
---@param cwd string The directory where ripgrep was started.
---@return string # The absolute path.
function _P.get_ripgrep_absolute_path(path, cwd)
    if vim.fn.fnamemodify(path, ":p") == path then
        return vim.fs.normalize(path)
    end

    return vim.fs.normalize(vim.fs.joinpath(cwd, path))
end

--- Get the display path for a ripgrep quickfix entry.
---
---@param path string The absolute result path.
---@param display_root string? Directory that quickfix paths should be displayed relative to.
---@return string # The display path.
function _P.get_ripgrep_display_path(path, display_root)
    if not display_root then
        return _P.cleanup_path(path)
    end

    local relative = vim.fs.relpath(vim.fs.normalize(display_root), path)

    return relative or _P.cleanup_path(path)
end

--- Check whether ripgrep stderr only contains filesystem access warnings.
---
---@param stderr string The stderr text printed by ripgrep.
---@return boolean # Whether stderr only has `rg: path: ... (os error N)` warnings.
function _P.is_ripgrep_filesystem_warning(stderr)
    local saw_warning = false

    for line in vim.gsplit(stderr, "\n") do
        line = vim.trim(line)

        if line ~= "" then
            if not line:match("^rg: .+:%s+.*%(os error %d+%)$") then
                return false
            end

            saw_warning = true
        end
    end

    return saw_warning
end

--- Run raw ripgrep `command`.
---
---@param command string[] A raw ripgrep command to run.
---@param options _my.ripgrep.Options? Options for quickfix display.
---
function M.run_ripgrep(command, options)
    options = options or {}
    local cwd = vim.fn.getcwd()
    local display_root = options.display_root or cwd

    if _CURRENT_RIPGREP_COMMAND then
        _CURRENT_RIPGREP_COMMAND = nil
        vim.notify("Search interrupted. Please try your search again.", vim.log.levels.WARN)

        return
    end

    ---@type string[]
    local commands = {
        M.RIPGREP_EXECUTABLE,
        "--vimgrep", -- Format: file:line:column:match
        "--smart-case",
        "--no-messages",
        unpack(command),
    }

    if not M.exists_command(commands[1]) then
        vim.notify("Cannot do search. No `rg` command was found.", vim.log.levels.ERROR)

        return
    end

    local process = vim.system(commands, { text = true }, function(obj)
        if not _CURRENT_RIPGREP_COMMAND then
            -- NOTE: The user interrupted. Stop
            return
        end

        _CURRENT_RIPGREP_COMMAND = nil

        local stdout = obj.stdout or ""
        local stderr = obj.stderr or ""

        if obj.code == 1 and stdout == "" then
            vim.schedule(function()
                vim.fn.setqflist({}, "r", { title = vim.fn.join(commands, " "), items = {} })
                vim.cmd("silent! cclose")
                vim.notify("No ripgrep matches found.", vim.log.levels.INFO)
            end)

            return
        end

        if obj.code ~= 0 and stdout == "" and not _P.is_ripgrep_filesystem_warning(stderr) then
            vim.schedule(function()
                local fallback = string.format("<No stderr found; exit code %d>", obj.code)

                vim.notify("Ripgrep failed: " .. (stderr ~= "" and stderr or fallback), vim.log.levels.ERROR)
            end)

            return
        end

        ---@type vim.quickfix.entry[]
        local entries = {}

        for line in vim.gsplit(stdout, "\n") do
            local filename, matched_line, column, text = string.match(line, "([^:]+):(%d+):(%d+):(.*)")
            line = matched_line

            if filename and line and column and text then
                local path = _P.get_ripgrep_absolute_path(filename, cwd)

                table.insert(entries, {
                    filename = path,
                    module = _P.get_ripgrep_display_path(path, display_root),
                    lnum = tonumber(line),
                    col = tonumber(column),
                    text = text,
                })
            end
        end

        table.sort(entries, function(left, right)
            return left.filename < right.filename
        end)

        vim.schedule(function()
            local full_title = vim.fn.join(commands, " ")
            local title = _P.get_elided_right_text(full_title, _MAXIMUM_QUICK_FIX_LENGTH)

            vim.fn.setqflist({}, " ", { title = title, items = entries })
            M.with_file_messages_suppressed(function()
                vim.cmd.copen()
            end)
        end)
    end)

    _CURRENT_RIPGREP_COMMAND = process.pid
end

--- Run `ripgrep` using Neovim.
---
---@param opts _neovim.commandline.Options
function M.run_ripgrep_command(opts)
    if opts.args == "" then
        vim.notify("Usage: :Rg <pattern>", vim.log.levels.WARN)

        return
    end

    M.run_ripgrep(require("modules.features.core_editor_setup").split_quoted_string(opts.args))
end

--- Show, Select, and Navigate to a buffer from a list of buffers.
function M.select_buffer()
    ---@type integer[]
    local buffers = {}

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buffer].buflisted then
            table.insert(buffers, buffer)
        end
    end

    local core_editor_setup = require("modules.features.core_editor_setup")
    local window = core_editor_setup.get_selector_target_window()

    core_editor_setup.select_from_options(buffers, {
        multiple_selection = true,
        sort_maximum = 200,
        sort_score = core_editor_setup.get_file_selector_sort_score,
        deserialize = function(choice)
            ---@cast choice integer

            local display = vim.api.nvim_buf_get_name(choice)

            if display == "" then
                display = "[No Name]"
            else
                local root = vim.fn.getcwd()
                local relative = vim.fs.relpath(root, display)

                if relative then
                    display = relative
                end
            end

            return { display = display, value = choice }
        end,
        confirm = function(entries)
            vim.api.nvim_set_current_win(window)

            for _, entry in ipairs(entries) do
                vim.cmd.buffer(entry.value)
            end
        end,
    })
end

return M
