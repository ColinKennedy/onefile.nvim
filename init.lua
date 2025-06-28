local _P = {}

---@class _my.completion.Data All Snippet-internal data used during callbacks.
---@field completed vim.v.completed_item The completed word/phrase.

---@class _my.completion.Entry A Neovim representation of a "row" of auto-complete data.
---@field kind string The type of completion item.
---@field menu string The sub-category / grouping.
---@field word string The word or phrase display text to show in the completion row.

---@class _my.selector_gui.entry.Deserialized The formatted option used by the selector GUI.
---@field display string The text to show in the pop-up.
---@field value any The original data, unformatted.

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
---@field filetypes string[] | string
---    The Vim filetype(s) that the LSp is meant for.
---@field callback fun(event: _my.lsp.ServerDefinition.callback.parameter): nil
---    The function that sets up the LSP.

---@class _my.lsp.ServerDefinition.callback.parameter All details to handle LSP setup.
---@field buf integer The Vim buffer to attach the LSP server onto.

---@class _neovim.commandline.Options Raw data that gets passed from `nvim_create_user_command`
---@field args string The input that a user writes to the command.

---@class _my.selector_gui.State An internal state tracker for the selector floating window.
---@field input string The currently-written user prompt input.
---@field all string[] All possible options to consider.
---@field filtered _my.selector_gui.entry.Selection[] All options that match with `input`.
---@field selected integer The selected index.

---@class _my.selector_gui.entry.Selection : _my.selector_gui.entry.Deserialized
---    The formatted option used by the selector GUI.
---@field score integer
---    How close this entry is to the user's input (0==strong match).

---@class _my.selection_gui.GuiOptions
---    Use this to control the behavior of the selection GUI.
---@field input string?
---    Starting text to being a search, if any.
---@field cancel (fun(value: _my.selector_gui.entry.Selection): nil)?
---    Custom "close selection GUI" behavior.
---@field confirm fun(value: _my.selector_gui.entry.Selection): nil
---    The function that runs on-selection.
---@field deserialize (fun(value: any): _my.selector_gui.entry.Deserialized)?
---    Format the incoming data, if needed. This is needed when
---    `_my.selector_gui.entry.Selection.value` and `_my.selector_gui.entry.Selection.display` are differing values.

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

---@class _neovim.quickfix.BaseEntry
---@field col integer
---@field filename string
---@field lnum integer
---@field text string

---@class _neovim.quickfix.Entry : _neovim.quickfix.BaseEntry
---@field bufnr integer

local _ALL_CONTIGUOUS_PROJECT_ROOT_MARKERS = { "CMakeLists.txt", "__init__.py" }
local _ENGLISH_LANGUAGE = "en"

local _LUA_ROOT_PATHS = {
    ".luacheckrc",
    ".luarc.json",
    ".luarc.jsonc",
    ".stylua.toml",
    "selene.toml",
    "selene.yml",
    "stylua.toml",
}

local _ALL_SINGLE_PROJECT_ROOTS = vim.tbl_deep_extend("force", {}, _LUA_ROOT_PATHS)
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

local _BOOKMARK_MINIMUM = 1
local _BOOKMARK_MAXIMUM = 9

---@type integer?
local _CURRENT_RIPGREP_COMMAND = nil

local _FILETYPE_TO_TREESITTER = { python = "python" }
local _LSP_GROUP = vim.api.nvim_create_augroup("UserLspStart", { clear = true })
local _SNIPPET_AUGROUP = vim.api.nvim_create_augroup("CustomSnippetCompletion", { clear = true })
local _TERMINAL_GROUP = vim.api.nvim_create_augroup("TerminalBehavior", { clear = true })

---@type table<string, boolean>
local _LANGUAGES_CACHE = {}

local _SNIPPETS

--- NOTE: Don't mess with this variable unless you know what you're doing.
---@type table<string, _my.Snippet>
local _TRIGGER_TO_SNIPPET_CACHE = {}

-- luacheck: push ignore
unpack = unpack or table.unpack
-- luacheck: pop

--- Check if `executable` is a command found on `$PATH`.
---
---@param executable string Some command. e.g. `"git"` or `"/path/to/foo.exe"`.
---@return boolean # If found, return `true`.
---
function _P.exists_command(executable)
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
function _P.has_treesitter_parser(name)
    if _LANGUAGES_CACHE[name] then
        return _LANGUAGES_CACHE[name]
    end

    local success, _ = pcall(function()
        vim.treesitter.get_parser(0, name)
    end)
    _LANGUAGES_CACHE[name] = success

    return _LANGUAGES_CACHE[name]
end

--- Check if `left` and `right` have the same contents.
---
--- Note: Order does not matter.
---
---@generic T: any
---@param left T[] Some flat array to check.
---@param right T[] Another flat array to check.
---@return boolean # If `left` and `right` have the same contents return `true`.
---
function _P.is_arrays_equal(left, right)
    if #left ~= #right then
        return false
    end

    ---@generic T: any
    ---@type table<T, boolean>
    local lookup = {}

    for _, value in ipairs(left) do
        lookup[value] = true
    end

    for _, value in ipairs(right) do
        if not lookup[value] then
            return false
        end
    end

    return true
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
function _P.in_tmux()
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

--- Check if `text` is 100% whitespace.
---
---@param text string Some line of text.
---@return boolean # If `text` has any non-whitespace, return `false`.
---
function _P.is_whitespace(text)
    return string.match(text, "^%s*$") ~= nil
end

--- Remove leading spaces across all snippets.
function _P.dedent_snippets()
    local function _dedent(text)
        text = text:gsub("\n[ ]+$", "\n")

        return (vim.text.indent(0, text))
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
function _P.close_terminal_afterwards(buffer)
    vim.api.nvim_create_autocmd("TermClose", {
        buffer = buffer,
        callback = vim.schedule_wrap(function()
            vim.api.nvim_buf_delete(buffer, { force = true })
        end),
        once = true,
    })
end

--- Find all snippets that we can complete, using `data`.
---
---@param data {file_type: string, start_column: integer} The cursor + completion prefix.
---@return _my.completion.Entry[] # All found snippet matches, if any.
---
function _P.compute_snippet_completion_options(data)
    -- NOTE: Re-populate the cache with snippets which match the completion menu
    _TRIGGER_TO_SNIPPET_CACHE = {}

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
            _TRIGGER_TO_SNIPPET_CACHE[snippet.trigger] = snippet
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
function _P.filter_by_text(candidates, base)
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
function _P.get_completion_location()
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
---@return string[] # All returned results.
---
function _P.get_deferred_shell_command_results(command, on_fail)
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

    vim.system(command, { text = true }, function(obj)
        if obj.code ~= 0 then
            vim.schedule(function()
                on_fail(obj)
            end)

            return
        end

        for line in vim.gsplit(obj.stdout or "", "\n") do
            if line ~= "" then
                table.insert(options, line)
            end
        end
    end)

    -- TODO: Inline this later?
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

--- Rate how closely `target` matches `input`.
---
---@param input string
---    Some user text to look for. e.g. `"fb"`.
---@param target string
---    The possible text to match against. e.g. `"football"`.
---@return integer?
---    If no match, return `nil`. If a strong match, return `0`. Weaker matches
---    will be higher numbers.
---
function _P.get_fuzzy_match_score(input, target)
    local input_lower = input:lower()
    local target_lower = target:lower()
    local position = 1
    local score = 0
    local last_match = 0

    for index = 1, #input_lower do
        local character = input_lower:sub(index, index)
        local found = false

        while position <= #target_lower do
            if target_lower:sub(position, position) == character then
                if last_match > 0 then
                    score = score + (position - last_match)
                end

                last_match = position
                position = position + 1
                found = true

                break
            end

            position = position + 1
        end

        if not found then
            return nil
        end
    end

    return score
end

---@return string # The Neovim statusline for saved grapple buffers
function _P.get_grapple_statusline()
    ---@type string[]
    local output = {}
    local current_buffer = vim.api.nvim_get_current_buf()

    for index, buffer_number, buffer_path in _P.iter_bookmarks() do
        local buffer_name = vim.fs.basename(buffer_path)
        local group = "%#StatusGrappleInactive#"

        if buffer_number == current_buffer then
            group = "%#StatusGrappleActive#"
        end

        table.insert(output, group)
        table.insert(output, string.format("%s. %s", index, buffer_name))
    end

    if vim.tbl_isempty(output) then
        return ""
    end

    return " " .. table.concat(output, " ") .. " "
end

---@return string[] # Every file or directory on-disk that could be helpfiles.
function _P.get_helptag_search_paths()
    -- TODO: Fix type-hint in Neovim core, later
    return vim.fn.globpath(vim.o.runtimepath, "doc/tag*", true, true)
end

---@return table<string, vim.fn.getmarklist.ret.item>
function _P.get_marks_mapping()
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
function _P.get_nearest_project_root(source)
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
function _P.get_vim_mark_from_bookmark_index(index)
    return string.char(64 + index) -- A=65, B=66, etc.
end

---@retrn _my.window.Edge[] Get all edges of the screen that the current window touches.
function _P.get_window_edges()
    local window = vim.api.nvim_get_current_win()
    local screen_width = vim.o.columns
    local screen_height = vim.o.lines - vim.o.cmdheight

    local configuration = vim.api.nvim_win_get_config(window)

    if not configuration.relative or configuration.relative ~= "" then
        -- NOTE: We skip floating windows
        return nil
    end

    local pos = vim.api.nvim_win_get_position(window)
    local row = pos[1]
    local col = pos[2]
    local height = vim.api.nvim_win_get_height(window)
    local width = vim.api.nvim_win_get_width(window)

    ---@type _my.window.Edge[]
    local edges = {}

    if row == 0 then
        table.insert(edges, "top")
    end

    if (row + height + 1) == screen_height then
        table.insert(edges, "bottom")
    end

    if col == 0 then
        table.insert(edges, "left")
    end

    if (col + width) == screen_width then
        table.insert(edges, "right")
    end

    return edges
end

--- Find the top-level project, if any, and then cd Neovim to it.
function _P.cd_to_parent_project_root()
    local directory = vim.fn.getcwd()
    local root = _P.get_nearest_project_root(directory)

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
function _P.check_async_write(ok, message)
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
function _P.complete_relative(text)
    local directory = _P.get_current_buffer_directory()

    if not directory then
        vim.cmd.edit(text)

        return nil
    end

    local options = _P.enable_autochdir(function()
        return vim.fn.getcompletion("edit ", "cmdline")
    end)

    ---@type string[]
    local output = {}

    for _, item in ipairs(options or {}) do
        if vim.startswith(item, text) then
            table.insert(output, item)
        end
    end

    return vim.fn.sort(output)
end

--- Delete all grapple bookmarks (so we can start from scratch).
function _P.delete_all_bookmarks()
    for index, _, _ in _P.iter_bookmarks() do
        _P.delete_bookmark(index)
    end
end

--- Save `:h autochdir`, run `caller`, and then restore it.
---
---@generic T : any
---@param caller fun(): T Some function to call and (hopefully) return.
---@return T? # The return value of `caller`, assuming it did not error.
---
function _P.enable_autochdir(caller)
    local original = vim.o.autochdir
    vim.o.autochdir = true
    local success, result = pcall(caller)
    vim.o.autochdir = original

    if not success then
        vim.notify(result, vim.log.levels.ERROR)

        return nil
    end

    return result
end

--- Move to the next or previous diagnostic message in the current buffer.
---
---@param next boolean
---    If `true`, search forwards in the buffer. If `false`, search backwards.
---@param severity (string | integer)?
---    The type of severity to filter for. If no `severity` is given, allow anything.
---
function _P.go_to_diagnostic(next, severity)
    severity = severity and vim.diagnostic.severity[severity] or nil

    if vim.diagnostic.jump then
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

    for _, buffer_number, buffer_path in _P.iter_bookmarks() do
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
function _P.iter_bookmarks()
    local index = _BOOKMARK_MINIMUM - 1

    return function()
        while true do
            index = index + 1

            if index > _BOOKMARK_MAXIMUM then
                return nil
            end

            local mark = _P.get_vim_mark_from_bookmark_index(index)
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

--- Find the next-available bookmark number and set the current buffer to it.
function _P.mark_current_buffer_as_next_bookmark()
    local maximum

    for index = _BOOKMARK_MINIMUM, _BOOKMARK_MAXIMUM do
        local mark = _P.get_vim_mark_from_bookmark_index(index)

        if _P.is_mark_defined(mark) then
            maximum = index
        end
    end

    local next_index = 1

    if maximum then
        next_index = ((maximum + 1) % _BOOKMARK_MAXIMUM) + 1
    end

    _P.mark_current_buffer_as_bookmark(_P.get_vim_mark_from_bookmark_index(next_index))
end

--- Open `text` relative path using the current directory as a root.
---
--- If the current buffer has no directory then this function is treated as
--- a normal `:edit` command.
---
---@param text string Some relative path. e.g. `"foo.txt"` or "../bar.txt"`, etc.
---
function _P.open_relative(text)
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
function _P.push_stash_by_name()
    vim.ui.input({ prompt = "Enter git stash name: " }, function(input)
        if not input then
            return
        end

        local command = { "git", "stash", "push", "--message", input }

        if not _P.exists_command(command[1]) then
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
    local mark = _P.get_vim_mark_from_bookmark_index(index)
    vim.cmd.delmarks(mark)
end

--- Set `mark` on `buffer`.
---
---@param mark string A Vim mark to set. e.g. `"A"`.
---@param buffer integer | string A 0-or-more buffer to modify
---
function _P.reset_bookmark(mark, buffer)
    local function _return_to_current_buffer(caller)
        local current_buffer = vim.api.nvim_get_current_buf()
        local success, message = pcall(caller)

        vim.cmd.buffer(current_buffer)

        if not success then
            error(message)
        end
    end

    local type_ = type(buffer)

    -- NOTE: Visit the buffer, then set the mark, then go back to the previous buffer
    if type_ == "string" then
        _return_to_current_buffer(function()
            vim.cmd.edit(buffer)
            vim.cmd.mark(mark)
        end)
    elseif type_ == "number" then
        _return_to_current_buffer(function()
            vim.cmd.buffer(buffer)
            vim.cmd.mark(mark)
        end)
    else
        vim.notify(string.format('Bug: expected a string or integer but got "%s" value.', buffer), vim.log.levels.ERROR)
    end
end

--- Resize the current window `distance` along `direction`.
---
---@param direction _my.window.Direction top/down/left/right movement of the current window.
---@param distance integer How far to resize the window.
---
function _P.resize_window(direction, distance)
    local edges = _P.get_window_edges()

    if not edges then
        return
    end

    local sign = "+"

    if direction == "up" then
        if vim.tbl_contains(edges, "top") and vim.tbl_contains(edges, "bottom") then
            -- NOTE: There is no split that we can resize in this direction. Stop early.
            return
        end

        if vim.tbl_contains(edges, "top") then
            sign = "-"
        end

        vim.cmd.resize(sign .. distance)
    elseif direction == "down" then
        if vim.tbl_contains(edges, "top") and vim.tbl_contains(edges, "bottom") then
            -- NOTE: There is no split that we can resize in this direction. Stop early.
            return
        end

        if vim.tbl_contains(edges, "bottom") then
            sign = "-"
        end

        vim.cmd.resize(sign .. distance)
    elseif direction == "left" then
        if vim.tbl_contains(edges, "left") and vim.tbl_contains(edges, "right") then
            -- NOTE: There is no split that we can resize in this direction. Stop early.
            return
        end

        if vim.tbl_contains(edges, "left") then
            sign = "-"
        end

        vim.cmd(string.format("vertical resize %s%s", sign, distance))
    elseif direction == "right" then
        if vim.tbl_contains(edges, "left") and vim.tbl_contains(edges, "right") then
            -- NOTE: There is no split that we can resize in this direction. Stop early.
            return
        end

        if vim.tbl_contains(edges, "right") then
            sign = "-"
        end

        vim.cmd(string.format("vertical resize %s%s", sign, distance))
    end
end

--- Remove whitespace from the start of `text`.
---
---@param text string Some text that has whitespace at the end. e.g. `"    foo"`.
---@return string # The removed text. e.g. `"foo"`.
---
function _P.lstrip(text)
    return text:match("^%s*(.-)$")
end

--- Remove whitespace from the end of `text`.
---
---@param text string Some text that has whitespace at the end. e.g. `"foo    "`.
---@return string # The removed text. e.g. `"foo"`.
---
function _P.rstrip(text)
    return text:match("^(.-)%s*$")
end

--- Run `git add -p` in the current tab's `$PWD` in a new terminal.
function _P.run_git_add_p()
    vim.cmd.split()
    vim.cmd.terminal("git add -p")
    vim.cmd.startinsert() -- NOTE: Drop into INSERT mode immediately

    local terminal_buffer = vim.api.nvim_get_current_buf()

    _P.close_terminal_afterwards(terminal_buffer)
end

--- Run raw ripgrep `command`.
---
---@param command string[] A raw ripgrep command to run.
---
function _P.run_ripgrep(command)
    if _CURRENT_RIPGREP_COMMAND then
        _CURRENT_RIPGREP_COMMAND = nil
        vim.notify("Search interrupted. Please try your search again.", vim.log.levels.WARN)

        return
    end

    local commands = {
        "rg",
        "--vimgrep", -- Format: file:line:column:match
        "--smart-case",
        unpack(command),
    }

    if not _P.exists_command(commands[1]) then
        vim.notify("Cannot do search. No `rg` command was found.", vim.log.levels.ERROR)

        return
    end

    local process = vim.system(commands, { text = true }, function(obj)
        if not _CURRENT_RIPGREP_COMMAND then
            -- NOTE: The user interrupted. Stop
            return
        end

        _CURRENT_RIPGREP_COMMAND = nil

        if obj.code ~= 0 then
            vim.schedule(function()
                vim.notify("Ripgrep failed: " .. (obj.stderr or "<No stderr found>"), vim.log.levels.ERROR)
            end)

            return
        end

        ---@type _neovim.quickfix.BaseEntry[]
        local entries = {}

        for line in vim.gsplit(obj.stdout or "", "\n") do
            local filename, matched_line, column, text = string.match(line, "([^:]+):(%d+):(%d+):(.*)")
            line = matched_line

            if filename and line and column and text then
                filename = _P.cleanup_path(filename)

                table.insert(entries, {
                    filename = filename,
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
            vim.fn.setqflist({}, " ", { title = vim.fn.join(commands, " "), items = entries })
            vim.cmd.copen()
        end)
    end)

    _CURRENT_RIPGREP_COMMAND = process.pid
end

--- Run `ripgrep` using Neovim.
---
---@param opts _neovim.commandline.Options
---
function _P.run_ripgrep_command(opts)
    if opts.args == "" then
        vim.notify("Usage: :Rg <pattern>", vim.log.levels.WARN)

        return
    end

    _P.run_ripgrep(_P.split_quoted_string(opts.args))
end

-- Keep track of the current layout, on-close. Create a Vim Session.vim file.
function _P.save_session()
    if vim.v.this_session ~= "" then
        vim.cmd("mksession! " .. vim.v.this_session)
    end
end

--- Show, Select, and Navigate to a buffer from a list of buffers.
function _P.select_buffer()
    ---@type string[]
    local buffers = {}

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buffer].buflisted then
            table.insert(buffers, buffer)
        end
    end

    local window = vim.api.nvim_get_current_win()

    _P.select_from_options(buffers, {
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
        confirm = function(entry)
            vim.api.nvim_set_current_win(window)
            vim.cmd.buffer(entry.value)
        end,
    })
end

do -- NOTE: Search Neovim's :help, quickly and easily
    --- Find all Vim helptag files, for all languages.
    ---
    ---@param paths string[] The potential files to filter out.
    ---@return table<string, string[]> # Each language and their found tag files.
    ---
    function _P.get_tag_files(paths)
        ---@type table<string, string[]>
        local output = {}

        for _, path in ipairs(paths) do
            local name = vim.fs.basename(path)
            local found_language

            if name == "tags" then
                found_language = _ENGLISH_LANGUAGE
                output[found_language] = (output[found_language] or {})
                table.insert(output[found_language], path)
            elseif name:match("^tags%-..$") then
                found_language = name:sub(-2)
                output[found_language] = (output[found_language] or {})
                table.insert(output[found_language], path)
            end
        end

        return output
    end

    --- Search all helptag files and display their tags in a floating window.
    ---
    ---@param vim_options _neovim.commandline.Options The Neovim user command data.
    ---
    function _P.select_helptag(vim_options)
        --- Read `path` into a buffer and run `callback` for that buffer, asynchronously.
        ---
        ---@param path string Some path on-disk to read.
        ---@param callback fun(lines: string[]): nil The callback to run for all lines.
        ---
        local function _read_file_lines_async(path, callback)
            vim.uv.fs_open(path, "r", 438, function(error_open, handler)
                assert(not not error_open, error_open)

                if not handler then
                    error(string.format('Path "%s" could be opened.', path), 0)
                end

                vim.uv.fs_fstat(handler, function(error_stat, stat)
                    assert(not not error_stat, error_stat)

                    if not stat then
                        error(string.format('Path "%s" could not be stat.', path), 0)
                    end

                    vim.uv.fs_read(handler, stat.size, 0, function(error_read, data)
                        assert(not not error_read, error_read)

                        if not data then
                            error(string.format('Path "%s" has no data.', path), 0)
                        end

                        vim.uv.fs_close(handler, function()
                            ---@type string[]
                            local lines = {}

                            for line in data:gmatch("([^\n]*)\n?") do
                                table.insert(lines, line)
                            end

                            callback(lines)
                        end)
                    end)
                end)
            end)
        end

        local search_paths = _P.get_helptag_search_paths()
        local tag_paths = _P.get_tag_files(search_paths)

        ---@type string[]
        local options = {}

        for _, path in ipairs(tag_paths[_ENGLISH_LANGUAGE]) do
            _read_file_lines_async(path, function(lines)
                for _, line in ipairs(lines) do
                    if line:match("%s+") then
                        table.insert(options, line)
                    end
                end
            end)
        end

        local input

        if vim_options.args ~= "" then
            input = vim_options.args
        end

        _P.select_from_options(options, {
            input = input,
            confirm = function(entry)
                vim.cmd.help(entry.value)
            end,
            deserialize = function(choice)
                ---@cast choice string

                -- Example: `choice = "vim.system()\tlua.txt\t/*vim.system()*"`
                -- Example: `display = "vim.system()"`
                --
                local value = choice:match("^(%S+)")

                return { display = choice, value = value }
            end,
        })
    end

    vim.api.nvim_create_user_command(
        "Helptags",
        _P.select_helptag,
        { nargs = "?", desc = "Live-Grep and then search Neovim's :help command." }
    )
end

do
    local _BUILTINS = {
        ["False"] = true,
        ["None"] = true,
        ["True"] = true,
        ["and"] = true,
        ["as"] = true,
        ["assert"] = true,
        ["break"] = true,
        ["class"] = true,
        ["continue"] = true,
        ["def"] = true,
        ["del"] = true,
        ["elif"] = true,
        ["else"] = true,
        ["except"] = true,
        ["finally"] = true,
        ["for"] = true,
        ["from"] = true,
        ["global"] = true,
        ["if"] = true,
        ["import"] = true,
        ["in"] = true,
        ["is"] = true,
        ["lambda"] = true,
        ["nonlocal"] = true,
        ["not"] = true,
        ["or"] = true,
        ["pass"] = true,
        ["raise"] = true,
        ["return"] = true,
        ["try"] = true,
        ["while"] = true,
        ["with"] = true,
        ["yield"] = true,
    }

    --- Check if this "last `character` in the Python source code line" can have a = sign appended to it.
    ---
    ---@param character string Some text to check.
    ---@return boolean # If `true` then `character` is allowed assignments with = sign.
    ---
    function _P.has_expected_last_character(character)
        if
            character:match("[%w_]") -- Reference: https://stackoverflow.com/a/12118024/3626104
        then
            return true
        end

        if character:match("]") then
            return true
        end

        if character:match("}") then
            return true
        end

        return false
    end

    --- Check if `text` is a python source code line that supports a = sign.
    ---
    ---@param text string Some Python source code to check.
    ---@return boolean # If `text` cannot assign with =, return `false`.
    ---
    function _P.is_assignable(text)
        local _, count = string.gsub(text, "%s+", "")

        if count ~= 0 then
            return false
        end

        if not _P.has_expected_last_character(text:sub(-1)) then
            return false
        end

        if _P.is_builtin_keyword(text:gsub("%s+", "")) then
            -- Strip whitespace of `text` and check if it's a built-in keyword
            return false
        end

        if _P.is_blacklisted_context() then
            return false
        end

        return true
    end

    ---@return boolean # Check if the current cursor's okay run the "compute = sign".
    function _P.is_blacklisted_context()
        return vim.treesitter.get_node({ buffer = 0 }):type() == "string_content"
    end

    --- Check if `text` is a Python keyword.
    ---
    ---@param text string Some Python source to test.
    ---@return boolean # If `text` is owned by Python, return `true`.
    ---
    function _P.is_builtin_keyword(text)
        return _BUILTINS[text] ~= nil
    end

    --- Remove unneeded syntax markers (to compute the equal sign).
    ---
    ---@param text string The original Python source-code.
    ---@return string # The stripped text.
    ---
    local function _strip_braces_characters(text)
        text = text:gsub("%(.+%)", "()")
        text = text:gsub("%[.+%]", "[]")

        return text
    end

    ---@return string # Append an `=` sign to the current line if it is needed.
    function _P.add_equal_sign_if_needed_python()
        local _, cursor_row, cursor_column, _ = unpack(vim.fn.getpos("."))
        local current_line = vim.fn.getline(cursor_row)

        if cursor_column <= #current_line then
            -- If the cursor isn't at the end of the line, stop. There's no
            -- container data-type in Python where `=` are expected so this is
            -- always supposed to be a space.
            --
            return " "
        end

        local current_line_up_until_cursor = current_line:sub(1, cursor_column)
        local stripped = _strip_braces_characters(current_line_up_until_cursor)

        if not _P.is_assignable(_P.lstrip(stripped)) then
            return " "
        end

        return " = "
    end

    if _P.has_treesitter_parser("python") then
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "python",
            callback = function()
                vim.keymap.set("i", "<Space>", _P.add_equal_sign_if_needed_python, {
                    buffer = true,
                    desc = "Add = signs when needed.",
                    expr = true,
                })
            end,
        })
    end
end

--- Find, select, and replace the current window with a new file.
---
--- Important:
---     This function requires [ripgrep](https://github.com/BurntSushi/ripgrep).
---
---@param root string?
---    A starting directory to searcn within, if any. If no directory is given,
---    Vim's current directory (`vim.fn.getcwd()`) is used instead.
---
function _P.select_file_in_directory(root)
    if root then
        if vim.fn.isdirectory(root) ~= 1 then
            vim.notify(string.format('Value "%s" is not a directory.', root), vim.log.levels.ERROR)

            return
        end
    end

    root = root or vim.fn.getcwd()
    local command = { "rg", "--files", root }

    if not _P.exists_command(command[1]) then
        vim.notify("Cannot do search. No `rg` command was found.", vim.log.levels.ERROR)

        return
    end

    local window = vim.api.nvim_get_current_win()

    local options = _P.get_deferred_shell_command_results(command, function(obj)
        if obj.stdout == "" then
            -- NOTE: This happens when No files were found.
            vim.notify(string.format('Rg command found no files at "%s" directory.', root), vim.log.levels.ERROR)

            return
        end

        vim.notify(string.format('Rg command failed. See "%s" for details.', vim.inspect(obj)), vim.log.levels.ERROR)
    end)

    _P.select_from_options(options, {
        confirm = function(entry)
            vim.api.nvim_set_current_win(window)
            vim.cmd.edit(entry.value)
        end,
        deserialize = function(choice)
            ---@cast choice string

            local display = choice
            root = root or vim.fn.getcwd()
            local relative = vim.fs.relpath(root, display)

            if relative then
                display = relative
            end

            return { display = display, value = choice }
        end,
    })
end

--- Find the top of the project, if any, and then search for files.
function _P.select_file_from_project_root()
    local buffer = vim.api.nvim_get_current_buf()
    local root = _P.get_nearest_project_root(buffer)

    if not root then
        vim.notify(string.format('Buffer "%s" has no root.', buffer), vim.log.levels.ERROR)

        return
    end

    _P.select_file_in_directory(root)
end

--- Run `callback` on a single selection of `options`.
---
--- This function creates a "telescope.nvim-lite" floating window picker.
---
---@param values string[]
---    The possible values to select from.
---@param options _my.selection_gui.GuiOptions
---    A function run to run on-selection. e.g. "open the file in a buffer".
---
function _P.select_from_options(values, options)
    ---@generic T: any
    --- A dynamic `ipairs`.
    ---
    --- It can iterate over a table that is growing asynchronously at the same
    --- time as it is iterating.
    ---
    ---@param table_ T[] Some values to iterate over.
    ---@return fun(): [integer, T]? # A function that iterates over `table_` (basically `ipairs`).
    ---
    local function _dynamic_ipairs(table_)
        local index = 0

        return function()
            index = index + 1
            local value = table_[index]

            if value == nil then
                return nil
            end

            return index, value
        end
    end

    ---@type _my.selector_gui.State
    local state = { input = "", all = values, filtered = {}, selected = 1 }

    local columns = vim.o.columns
    local lines = vim.o.lines

    local margin = 0.05 -- NOTE: Apply a 5% margin to the floating window
    local margin_x = math.floor(columns * margin)
    local margin_y = math.floor(lines * margin)

    -- List window dimensions
    local list_width = columns - (margin_x * 2) - 2
    local list_height = lines - (margin_y * 2) - 5
    local list_row = margin_y + 1
    local list_column = margin_x + 1

    -- Prompt window dimensions
    local prompt_width = list_width
    local prompt_height = 1
    local prompt_row = list_row - 2
    local prompt_column = list_column

    -- Create list buffer and window
    local list_buffer = vim.api.nvim_create_buf(false, true)
    local list_window = vim.api.nvim_open_win(list_buffer, true, {
        relative = "editor",
        width = list_width,
        height = list_height,
        row = list_row,
        col = list_column,
        style = "minimal",
        border = "single",
    })

    -- Create prompt buffer and window
    local prompt_buffer = vim.api.nvim_create_buf(false, true)
    local prompt_window = vim.api.nvim_open_win(prompt_buffer, false, {
        relative = "editor",
        width = prompt_width,
        height = prompt_height,
        row = prompt_row,
        col = prompt_column,
        style = "minimal",
        border = "single",
    })
    vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "" })
    vim.bo[prompt_buffer].modifiable = false

    -- Start in insert mode in prompt
    vim.api.nvim_set_current_win(prompt_window)
    vim.cmd("startinsert")

    if options.input and options.input ~= "" then
        vim.api.nvim_feedkeys(options.input, "i", false)
    end

    -- Redraw the current, filtered list.
    local function _redraw()
        -- TODO: Don't redraw the whole buffer. This is slow.
        vim.api.nvim_buf_set_lines(list_buffer, 0, -1, false, {})

        for index, item in ipairs(state.filtered) do
            local prefix = (index == state.selected) and "> " or "  "
            vim.api.nvim_buf_set_lines(list_buffer, index, index, false, { prefix .. item.display })
        end
    end

    -- Populate filtered items.
    local function _update_filter()
        local line = vim.api.nvim_buf_get_lines(prompt_buffer, 0, 1, false)[1]
        state.input = line or ""
        state.filtered = {}

        ---@type _my.selector_gui.entry.Selection[]
        local matches = {}

        if options.deserialize then
            for _, item in _dynamic_ipairs(state.all) do
                local entry = options.deserialize(item)
                local score = _P.get_fuzzy_match_score(state.input, entry.display or entry.value)

                if score then
                    table.insert(matches, { display = entry.display, score = score, value = entry.value })
                end
            end
        else
            for _, item in _dynamic_ipairs(state.all) do
                local score = _P.get_fuzzy_match_score(state.input, item)

                if score then
                    table.insert(matches, { display = tostring(item), score = score, value = item })
                end
            end
        end

        table.sort(matches, function(left, right)
            return left.score < right.score
        end)

        for _, entry in ipairs(matches) do
            table.insert(state.filtered, entry)
        end

        state.selected = math.min(state.selected, #state.filtered)

        if state.selected < 1 then
            state.selected = 1
        end

        _redraw()
    end

    local function _close_all()
        vim.api.nvim_win_close(list_window, true)
        vim.api.nvim_win_close(prompt_window, true)
    end

    local function _confirm_selection()
        _close_all()

        local entry = state.filtered[state.selected]
        options.confirm(entry)
    end

    local function _cancel()
        _close_all()

        local entry = state.filtered[state.selected]

        if options.cancel then
            options.cancel(entry)
        else
            vim.notify("Selection Cancelled", vim.log.levels.INFO)
        end
    end

    -- Set up keymaps for list window navigation
    local function _setup_keys()
        local opts = { noremap = true, silent = true, buffer = prompt_buffer }
        local confirm_options = vim.tbl_deep_extend("force", opts, { desc = "Confirm your current selection." })
        vim.keymap.set("n", "<CR>", vim.schedule_wrap(_confirm_selection), confirm_options)
        vim.keymap.set("i", "<CR>", function()
            -- Exit to NORMAL mode first before confirming the slection
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
            vim.schedule(_confirm_selection)
        end, confirm_options)

        local cancel_options = vim.tbl_deep_extend("force", opts, { desc = "Cancel and quit." })
        vim.keymap.set("n", "q", _cancel, cancel_options)
        vim.keymap.set("n", "<Esc>", _cancel, cancel_options)

        local select_down = function()
            state.selected = math.min(state.selected + 1, #state.filtered)
            _redraw()
        end

        local select_up = function()
            state.selected = math.max(state.selected - 1, 1)
            _redraw()
        end

        local down_options =
            vim.tbl_deep_extend("force", opts, { desc = "Select the item below the current selection." })
        local up_options = vim.tbl_deep_extend("force", opts, { desc = "Select the item above the current selection." })
        vim.keymap.set("n", "j", select_down, down_options)
        vim.keymap.set("i", "<C-n>", select_down, down_options)

        vim.keymap.set("n", "k", select_up, up_options)
        vim.keymap.set("i", "<C-p>", select_up, up_options)
    end

    _setup_keys()
    _redraw()

    -- This creates a "live-update" of options while the user is typing
    -- TODO: Consider a debounce here, maybe
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "TextChanged", "TextChangedI" }, {
        buffer = prompt_buffer,
        callback = vim.schedule_wrap(_update_filter),
    })
end

--- Write Lua source code that shows how to save/restore bookmarks.
---
---@param directory string? The folder on-disk where all mark files will be relative to.
---@return string[] # All of the Lua source-code.
---
function _P.serialize_mark_code(directory)
    ---@type string[]
    local output = {}
    local marks = _P.get_marks_mapping()

    for index, _, _ in _P.iter_bookmarks() do
        local mark_character = _P.get_vim_mark_from_bookmark_index(index)

        local mark = marks["'" .. mark_character]

        if mark and mark.file ~= "" then
            local path = mark.file

            if directory then
                local relative = vim.fs.relpath(directory, mark.file)

                if not relative then
                    error(
                        string.format('Path "%s" could not be made relative to "%s" directory.', mark.file, directory)
                    )
                end

                path = relative
            end

            local _, line, column, _ = unpack(mark.pos)

            table.insert(
                output,
                string.format(
                    'buffer = vim.fn.bufnr("%s", true)\nvim.fn.bufload(buffer)\nvim.api.nvim_buf_set_mark(buffer, "%s", %d, %d, {})\n\n',
                    path,
                    mark_character,
                    line,
                    column
                )
            )
        end
    end

    if vim.tbl_isempty(output) then
        table.insert(output, 0, "local buffer")
        table.insert(output, 0, "local original_buffer = vim.api.nvim_get_current_buf()")
        table.insert(output, "vim.cmd.buffer(original_buffer)")
    end

    return output
end

--- Add LSP keymaps and auto-completion.
---
--- Run this function on-LSP-initialization. See `:help LspAttach`.
---
---@param args _my.lsp_attach.Result Data from Neovim LspAttach.
---
function _P.setup_lsp_details(args)
    local buffer = vim.api.nvim_get_current_buf()

    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, {
        buffer = buffer,
        desc = "[g]o to all [D]eclarations of the current function, class, whatever.",
    })

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, {
        buffer = buffer,
        desc = "[g]o to [d]efinition of the function / class.",
    })

    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, {
        buffer = buffer,
        desc = "Find and [g]o to the [i]mplementation of some header / declaration.",
    })

    local identifier = args.data.client_id
    local client =
        assert(vim.lsp.get_client_by_id(identifier), string.format('Identifier "%s" has no LSP client.', identifier))

    if client:supports_method("textDocument/completion") then
        -- NOTE: Automatic LSP auto-complete + we can still use <C-x><C-o>
        -- to trigger manually (because we have `:set
        -- omnifunc=v:lua.vim.lsp.omnifunc`)
        --
        vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        vim.opt_local.completeopt = "fuzzy,menuone,noinsert"
    end
end

--- Assign a range selection in Vim (a 2-cursor bounding box).
---
---@param start_line integer A 1-or-more value, the first source code line.
---@param start_column integer A 1-or-more value. The position in the start line.
---@param end_line integer A 1-or-more value, the last source code line.
---@param end_column integer A 1-or-more value. The position in the end line.
---
function _P.set_text_object_marks(start_line, start_column, end_line, end_column)
    vim.api.nvim_buf_set_mark(0, "<", start_line, start_column, {})
    vim.api.nvim_buf_set_mark(0, ">", end_line, end_column, {})

    local mode = vim.api.nvim_get_mode().mode

    if mode == "V" then
        vim.cmd("normal! gV")
    else
        vim.cmd("normal! gv")
    end
end

--- Load current bookmarks into the quickfix list.
function _P.show_bookmarks()
    ---@type _neovim.quickfix.Entry[]
    local quickfix_entries = {}

    for index = _BOOKMARK_MINIMUM, _BOOKMARK_MAXIMUM do
        local mark = _P.get_vim_mark_from_bookmark_index(index)
        local position = vim.api.nvim_get_mark(mark, {})

        if position[1] ~= 0 then
            table.insert(quickfix_entries, {
                bufnr = position[3],
                filename = position[4],
                lnum = position[1],
                col = position[2],
                text = index,
            })
        end
    end

    -- Set the quickfix list
    vim.fn.setqflist(quickfix_entries)

    -- Open the quickfix window if there are bookmarks
    if #quickfix_entries > 0 then
        vim.cmd("copen")
    else
        vim.cmd("cclose")
    end
end

--- Show all git stashes in the repository in a floating window, if any.
function _P.show_git_stashes()
    local command = { "git", "stash", "list" }

    if not _P.exists_command(command[1]) then
        vim.notify("Cannot create state. No `git` command was found.", vim.log.levels.ERROR)

        return
    end

    local options = _P.get_deferred_shell_command_results(command)

    _P.select_from_options(options, {
        deserialize = function(value)
            local separator = ":"
            local parts = vim.fn.split(value, separator)

            if #parts < 3 then
                error(
                    string.format(
                        'Got unexpected "%s" parts from "%s" value. ' .. "Expected a stash index and stash name.",
                        vim.inspect(parts),
                        value
                    )
                )
            end

            ---@type string[]
            local name_parts = {}

            for index = 3, #parts do
                table.insert(name_parts, parts[index])
            end

            local name = vim.fn.join(name_parts, separator)
            local index = parts[1]

            return { display = name, value = { index = index, name = name } }
        end,
        confirm = function(entry)
            local stash = entry.value.index
            local process = vim.system({ "git", "stash", "apply", stash }):wait()

            if process.code == 0 then
                return
            end

            -- NOTE: For some reason the error is in stdout
            local error_message = process.stdout

            vim.notify(string.format("Git stash apply failed. See below:\n\n%s", error_message), vim.log.levels.ERROR)
        end,
    })
end

--- Load snippets and show them, if possible.
function _P.show_snippet_completion()
    --- Remove the original trigger text (so we can replace it with the completed text).
    ---
    --- Important:
    ---     This function assumes that
    ---     1. We just triggered snippet completion.
    ---     2. The cursor is located at the *end* of the trigger text.
    ---
    ---@param window integer The Vim window to affect.
    ---@param start_column integer A 1-or-more Lua value.
    ---
    local function _delete_trigger_text(window, start_column)
        local row, column = unpack(vim.api.nvim_win_get_cursor(window))
        local line = vim.api.nvim_get_current_line()

        line = line:sub(1, start_column) .. line:sub(column + 1)
        vim.api.nvim_set_current_line(line)
        vim.api.nvim_win_set_cursor(0, { row, start_column })
    end

    --- Expand the snippet found in `data`.
    ---
    ---@param data _my.completion.Data
    ---
    local function _expand_snippet(data)
        local snippet = _TRIGGER_TO_SNIPPET_CACHE[data.completed.word]

        if not snippet then
            return
        end

        vim.snippet.expand(snippet.body)
    end

    --- Delete the initial trigger text and expand the snippet
    ---
    ---@param start_column integer A 1-or-more Lua value where `callback` runs from.
    ---@param callback fun(data: _my.completion.Data): nil Run this on-completion.
    ---
    local function _handle_complete_done(start_column, callback)
        local completed = vim.v.completed_item

        if not completed or completed.word == "" then
            return
        end

        local window = 0 -- NOTE: The current window
        _delete_trigger_text(window, start_column)

        callback({ completed = completed })
    end

    local start_column, base = _P.get_completion_location()
    local candidates =
        _P.compute_snippet_completion_options({ file_type = vim.o.filetype, start_column = start_column - 1 })
    local matches = _P.filter_by_text(candidates, base)
    table.sort(matches, function(left, right)
        return left.word < right.word
    end)

    vim.fn.complete(start_column, matches)

    vim.api.nvim_create_autocmd("CompleteDone", {
        group = _SNIPPET_AUGROUP,
        callback = function()
            _handle_complete_done(start_column - 1, _expand_snippet)
        end,
        once = true,
    })
end

-- TODO: I'm shocked that Neovim doesn't have a function for this already
--- Parse a string like `foo "bar fizz" buzz"` into `{"foo", "bar fizz", "buzz"}`.
---
--- Reference: https://stackoverflow.com/a/28664691/3626104
---
---@param text string Some raw command string.
---@return string[] # The parsed text.
---
function _P.split_quoted_string(text)
    local spat, epat = [=[^(['"])]=], [=[(['"])$]=]
    local buf
    local quoted

    ---@type string[]
    local output = {}

    for str in text:gmatch("%S+") do
        local squoted = str:match(spat)
        local equoted = str:match(epat)
        local escaped = str:match([=[(\*)['"]$]=])

        if squoted and not quoted and not equoted then
            buf, quoted = str, squoted
        elseif buf and equoted == quoted and #escaped % 2 == 0 then
            str, buf, quoted = buf .. " " .. str, nil, nil
        elseif buf then
            buf = buf .. " " .. str
        end

        if not buf then
            table.insert(output, (str:gsub(spat, ""):gsub(epat, "")))
        end
    end

    if buf then
        table.insert(output, buf)
    end

    return output
end

--- Strip the leading whitespace of `text`.
---
---@param text string Some text to strip. e.g. `"    foo"`.
---@return string # The stripped text. e.g. `"foo"`.
---
function _P.strip_left(text)
    return (text:gsub("^%s*", ""))
end

--- Unset the bookmark if it is set or set it if it's not set.
function _P.toggle_bookmark_in_current_buffer()
    local function _refresh_all_bookmark_values()
        ---@type {index: integer?, path: string?}[]
        local buffers = {}

        for _, buffer_number, buffer_path in _P.iter_bookmarks() do
            if buffer_number == 0 then
                table.insert(buffers, { path = buffer_path })
            else
                table.insert(buffers, { index = buffer_number })
            end
        end

        _P.delete_all_bookmarks()

        for new_index, buffer in ipairs(buffers) do
            local value = buffer.index or buffer.path

            if not value then
                error(string.format('Buffer "%s" has no index or path.', vim.inspect(buffer)), 0)
            end

            local mark = _P.get_vim_mark_from_bookmark_index(new_index)
            _P.reset_bookmark(mark, value)
        end
    end

    local function _add_current_buffer_if_needed()
        local current_buffer = vim.api.nvim_get_current_buf()
        ---@type integer[]
        local current_buffer_bookmarks = {}

        for index, buffer_number, _ in _P.iter_bookmarks() do
            -- NOTE: Don't add the current buffer because it's already in the list
            if buffer_number == current_buffer then
                table.insert(current_buffer_bookmarks, index)

                break
            end
        end

        if vim.tbl_isempty(current_buffer_bookmarks) then
            _P.mark_current_buffer_as_next_bookmark()
        else
            for _, mark_index in ipairs(current_buffer_bookmarks) do
                local mark = _P.get_vim_mark_from_bookmark_index(mark_index)
                vim.cmd.delmarks(mark)
            end
        end
    end

    _add_current_buffer_if_needed()
    _refresh_all_bookmark_values()

    if vim.g.initial_cwd then
        _P.write_all_marks_if_possible(vim.fs.joinpath(vim.g.initial_cwd, ".nvim.marks.lua"))
    end
end

--- Open or close the QuickFix window (don't move the cursor to the window).
function _P.toggle_quickfix()
    local current_window = vim.api.nvim_get_current_win()

    for _, window in ipairs(vim.fn.getwininfo()) do
        if window.quickfix == 1 then
            vim.cmd.cclose()

            return
        end
    end

    vim.cmd.copen()

    -- NOTE: If we were on a non-quickfix window, go back to that window
    local info = vim.fn.getwininfo(current_window)

    if info[1] and info[1].quickfix ~= 1 then
        vim.api.nvim_set_current_win(current_window)
    end
end

--- Write mark instructions to-disk at thnge project directory.
---
---@param path string The path on-disk to write.
---@param mode string? A Lua write mode. e.g. "w" / "a".
---
function _P.write_all_marks_if_possible(path, mode)
    mode = mode or "w"
    local handler, message, _ = vim.uv.fs_open(path, mode, 438)

    if not handler then
        error(("Failed to open: %s\n%s"):format(path, message), 0)

        return
    end

    local data = _P.serialize_mark_code(vim.fs.dirname(path))
    local ok
    ok, message, _ = vim.uv.fs_write(handler, data, 0)

    if not ok then
        message = ("Failed to write: %s\n%s"):format(path, message)
        assert(vim.uv.fs_close(handler), 'Path "%s" could not be closed.', path)
        error(message, 0)
    end

    assert(vim.uv.fs_close(handler), 'Path "%s" could not be closed.', path)
end

--- Write `data` to `filename`.
---
---@param filename string The file on-disk to write to.
---@param data string[] The file contents to write.
---@return boolean # If the write worked, return `true`.
---@return string # If the write failed, this is the error message.
---
function _P.write_async(filename, data)
    local status = true
    local message = ""
    local handler, open_error, _ = vim.uv.fs_open(filename, "w", 438)

    if not handler then
        status, message = false, ("Failed to open: %s\n%s"):format(filename, open_error)
    else
        local ok, write_error, _ = vim.uv.fs_write(handler, data, 0)

        if not ok then
            status, message = false, ("Failed to write: %s\n%s"):format(filename, write_error)
        end

        assert(vim.uv.fs_close(handler), 'Path "%s" could not be closed.', filename)
    end

    return status, message
end

---@return string # Get the current Git branch.
-- luacheck: push ignore
function get_git_branch_safe()
    -- luacheck: pop
    local command = { "git", "rev-parse", "--abbrev-ref", "HEAD" }

    if not _P.exists_command(command[1]) then
        return "<No git command>"
    end

    local process = vim.system(command, { text = true }):wait()

    if process.code ~= 0 then
        return "<Git command failed>"
    end

    local branch = process.stdout:gsub("\n", "")

    if branch == "" then
        return "<No git branch found>"
    end

    return " " .. branch
end

---@return string # Get the position in the current file.
-- luacheck: push ignore
function get_window_line_progress()
    -- luacheck: pop
    local current_line = vim.fn.line(".")
    local total_lines = vim.fn.line("$")

    if current_line == 1 then
        return "Top"
    end

    if current_line == total_lines then
        return "Bot"
    end

    local percent = math.floor((current_line / total_lines) * 100)

    return percent .. "%"
end

-- Example Run: PATH=/home/selecaoone/.local/bin:$PATH NVIM_APPNAME=noplugins nvim ~/temp/class_test.py

vim.g.mapleader = ","

-- Enable messages during File operations
--
-- Reference: https://vi.stackexchange.com/a/26492
-- Reference: https://neovim.io/doc/user/faq.html#faq
--
vim.cmd("set shortmess-=F")

---------- Auto-Commands [Start] ----------
local is_ignoring_syntax_events = function()
    for _, value in pairs(vim.opt.eventignore) do
        if value == "Syntax" then
            return true
        end
    end

    return false
end

-- Remove the column-highlight on QuickFix & LocationList buffers
vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    command = "setlocal nonumber colorcolumn=",
})

vim.api.nvim_create_autocmd("FileType", {
    callback = function()
        vim.keymap.set("n", "<leader>ct", function()
            local current_name = vim.fn.getqflist({ title = true, winid = true }).title
            local name = vim.fn.input("New Name: ", current_name)

            if name == "" then
                return
            end

            vim.fn.setqflist({}, "r", { title = name, winid = true })

            local success, winbar = pcall(require, "winbar")

            if success then
                winbar.run_on_current_buffer()
            end
        end, {
            buffer = true,
            desc = "[c]hange Quickfix [t]itle.",
        })
    end,
    pattern = "qf",
})

-- Reference: https://stackoverflow.com/questions/12485981
--
-- Enable syntax highlighting when buffers are displayed in a window through
-- :argdo and :bufdo, which disable the Syntax autocmd event to speed up
-- processing.
--
local _SYNTAX_HIGHLIGHTING_GROUP = vim.api.nvim_create_augroup("EnableSyntaxHighlighting", { clear = true })

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    callback = function()
        if not vim.fn.exists("syntax_on") then
            return
        end

        if vim.fn.exists("b:current_syntax") then
            return
        end

        if not vim.bo.filetype then
            return
        end

        if is_ignoring_syntax_events() then
            return
        end

        vim.cmd("syntax enable")
    end,
    nested = true,
    pattern = "*",
    group = _SYNTAX_HIGHLIGHTING_GROUP,
})

-- The above does not handle reloading via :bufdo edit!, because the
-- b:current_syntax variable is not cleared by that. During the :bufdo,
-- 'eventignore' contains "Syntax", so this can be used to detect this
-- situation when the file is re-read into the buffer. Due to the
-- 'eventignore', an immediate :syntax enable is ignored, but by clearing
-- b:current_syntax, the above handler will do this when the reloaded buffer
-- is displayed in a window again.
--
vim.api.nvim_create_autocmd("BufRead", {
    callback = function()
        if not vim.fn.exists("b:current_syntax") then
            return
        end

        -- TODO: Check if this is needed
        if not vim.fn.exists("syntax_on") then
            return
        end

        -- TODO: Check if this is needed
        if vim.bo.filetype then
            return
        end

        -- TODO: Check if this is needed
        if not is_ignoring_syntax_events() then
            return
        end

        vim.cmd("unlet! b:current_syntax")
    end,
    pattern = "*",
})

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Highlight when yanking (copying) text",
    group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

--- @return boolean # Check if the current buffer is an fzf prompt
local is_fzf_terminal = function()
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local ending = ";#FZF"

    return name:sub(-#ending) == ending
end

-- Switch from the terminal window back to other buffers quickly
-- Reference: https://github.com/junegunn/fzf.vim/issues/544#issuecomment-457456166
--
vim.api.nvim_create_autocmd("TermOpen", {
    callback = function()
        if is_fzf_terminal() then
            return
        end

        vim.keymap.set("t", "<ESC><ESC>", "<C-\\><C-n>", {
            buffer = true,
            desc = "Exit the terminal by pressing <ESC> twice in a row.",
            noremap = true,
        })
    end,
    group = _TERMINAL_GROUP,
    pattern = "*",
})

vim.api.nvim_create_autocmd("VimLeave", { callback = _P.save_session })
---------- Auto-Commands [End] ----------

---------- Auto-Commands 2 [Start] ----------
vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = vim.schedule_wrap(function()
        -- In the future these will be default values.
        --
        -- Reference: https://github.com/neovim/neovim/commit/52481eecf0dfc596a4d8df389c901f46cd3b6661
        --
        if vim.bo.buftype == "terminal" then
            vim.opt_local.relativenumber = false
            vim.opt_local.number = false
            vim.opt_local.signcolumn = "no"
        end
    end),
})
---------- Auto-Commands 2 [End] ----------

---------- Fix Terminal Padding [Start] ----------
--- Remove the weird padding around the terminal and the Neovim instance.
---
--- The technical details are a bit lost on me but the jist apparently is that
--- we mess with the terminal UI event to extend the colorscheme a bit further
--- than normal. But this must run *before* a colorscheme is loaded.
---
--- Reference: https://www.reddit.com/r/neovim/comments/1ehidxy/you_can_remove_padding_around_neovim_instance
---

vim.api.nvim_create_autocmd({ "UIEnter", "ColorScheme" }, {
    callback = function()
        local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
        if not normal.bg then
            return
        end

        if _P.in_tmux() then
            io.write(string.format("\027Ptmux;\027\027]11;#%06x\007\027\\", normal.bg))
        else
            io.write(string.format("\027]11;#%06x\027\\", normal.bg))
        end
    end,
})

vim.api.nvim_create_autocmd("UILeave", {
    callback = function()
        if _P.in_tmux() then
            io.write("\027Ptmux;\027\027]111;\007\027\\")
        else
            io.write("\027]111\027\\")
        end
    end,
})
---------- Fix Terminal Padding [End] ----------

---------- Initialization [Start] ----------
vim.opt.ttyfast = true -- Makes certain terminals scroll faster

-- Command-line completion, use '<Tab>' to move and '<CR>' to validate.
vim.opt.wildmenu = true

-- Ignore compiled/backup files when displaying files
vim.opt.wildignore = "*.o,*~,*.pyc,.git,.hg,.svn,*/.hg/*,*/.svn/*,*/.DS_Store"

-- Always show current position at the given line
vim.opt.ruler = true

-- Set the height of the command bar
vim.opt.cmdheight = 2

-- A buffer becomes hidden when it is abandoned, even if it has modifications
vim.opt.hidden = true

-- In many terminal emulators the mouse works just fine, thus enable it.
if vim.fn.has("mouse") then
    vim.opt.mouse = "a"
end

-- Ignore case when searching
vim.opt.ignorecase = true

-- When searching try to be smart about cases
vim.opt.smartcase = true

-- Makes regular characters act as they do in grep, during searches
vim.opt.magic = true

-- Show matching brackets when text indicator is over them
vim.opt.showmatch = true

-- How many tenths of a second to blink when matching brackets
vim.opt.mat = 2

-- Add a bit extra margin to the gutter
vim.opt.foldcolumn = "1"

-- Only let Vim wait for user input (characters) for 0.3 seconds. Gotta go fast!
vim.opt.timeoutlen = 300
-- Wait very little for key sequences
vim.opt.ttimeoutlen = 10

-- Return to last edit position when opening files (You want this!)
vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function()
        local line = vim.fn.line("'\"")

        if line > 0 and line <= vim.fn.line("$") then
            vim.cmd([[execute "normal! g`\""]])
        end
    end,
})

-- Remember info about open buffers on close
vim.cmd("set viminfo^=%")

-- Always show the status line
vim.opt.laststatus = 2

-- Show relative line numbers
vim.opt.relativenumber = true
vim.opt.number = true

-- Show weird characters (tabs, trailing whitespaces, etc)
vim.opt.list = true
vim.opt.listchars = "tab:> ,trail: ,nbsp:+"

-- Auto-save whenever you switch buffers - potentially dangerous
vim.opt.autowrite = true
vim.opt.autowriteall = true
vim.api.nvim_create_autocmd({ "FocusLost", "WinLeave" }, {
    -- Write all files before navigating away from Vim
    pattern = "*",
    command = ":silent! wa",
})

-- In vimdiff mode, make diffs open as vertical buffers
-- Seriously. Why is this not the default
--
vim.opt.diffopt:append({ "vertical" })

-- This makes joining lines more intelligent
--
-- Example:  without this patch - (X) is the cursor position
-- example_document.vim
-- 1
-- 2 " I am a multiline comment (X)
-- 3 " and here is more info
-- 4
--
-- press Shift+j
--
-- 1
-- 2 " I am a multiline comment (X) " and here is more info
-- 3
--
-- Nooo!! whyyyyy!
--
-- Example:
-- 1
-- 2 " I am a multiline comment (X) and here is more info
-- 3
--
-- Works with other coding languages, too, like Python!
-- Reference: kinbiko.com/vim/my-shiniest-vim-gems
--
if vim.v.version > 703 then
    vim.opt.formatoptions:append({ "j" })
end

-- Disable tag completion (TAB)
--
-- Reference: https://stackoverflow.com/a/13232327/3626104
--
vim.cmd("set complete-=t")

-- Common typos that I want to automatically fix
vim.cmd("abbreviate hte the")
vim.cmd("abbreviate het the")
vim.cmd("abbreviate chnage change")

-- Nvim does not have special `t_XX` options nor <t_XX> keycodes to configure
-- terminal capabilities. Instead Nvim treats the terminal as any other UI,
-- e.g. 'guicursor' sets the terminal cursor style if possible.
--
vim.opt.guicursor = "n-v-c:block-Cursor"

-- Allow sentences to start with "E.g.". Don't mark them as bad sentences
vim.opt.spellcapcheck = [[.?!]\_[\])'"\t ]\+,E.g.,I.e.]]

-- Don't auto-resize buffers when a buffer is opened or closed
--
-- Reference: https://stackoverflow.com/a/33388054/3626104
--
vim.opt.equalalways = false
---------- Initialization [End] ----------

do -- NOTE: Filetype-specific details
    vim.api.nvim_create_autocmd("FileType", {
        pattern = { "lua", "python" },
        callback = function()
            vim.bo.shiftwidth = 4
            vim.bo.tabstop = 4
            vim.bo.expandtab = true
        end,
    })
end

---------- Keymaps [Start] ----------
local options = { expr = true, noremap = true, silent = true }
local move_description = function(direction)
    return vim.tbl_deep_extend("force", options, { desc = string.format('Move to the "%s" window.', direction) })
end
vim.keymap.set("n", "<C-h>", "<C-w>h", move_description("left"))
vim.keymap.set("n", "<C-j>", "<C-w>j", move_description("bottom"))
vim.keymap.set("n", "<C-k>", "<C-w>k", move_description("top"))
vim.keymap.set("n", "<C-l>", "<C-w>l", move_description("right"))

local resize_description = function(direction)
    return vim.tbl_deep_extend("force", options, { desc = string.format('Resize the "%s" window.', direction) })
end
vim.keymap.set("n", "<M-h>", function()
    _P.resize_window("left", 5)
end, resize_description("left"))
vim.keymap.set("n", "<M-j>", function()
    _P.resize_window("down", 2)
end, resize_description("down"))
vim.keymap.set("n", "<M-k>", function()
    _P.resize_window("up", 2)
end, resize_description("up"))
vim.keymap.set("n", "<M-l>", function()
    _P.resize_window("right", 5)
end, resize_description("right"))

-- Add numbered j/k movements to Vim's jumplist
-- Reference: https://www.reddit.com/r/neovim/comments/1k3lhac/tiny_quality_of_life_rebind_make_j_and_k/
vim.keymap.set("n", "j", function()
    if vim.v.count > 0 then
        return 'm"' .. vim.v.count .. "j"
    end

    return "j"
end, { desc = "Add numbered j movements (e.g. 20j) to VIm's jumplist.", expr = true })

vim.keymap.set("n", "k", function()
    if vim.v.count > 0 then
        return 'm"' .. vim.v.count .. "k"
    end

    return "k"
end, { desc = "Add numbered k movements (e.g. 20k) to VIm's jumplist.", expr = true })

-- Select the most recent text change you've made
vim.keymap.set("n", "gp", "`[v`]", { desc = "Select the most recent text [p]ut you've done." })

vim.keymap.set("v", ".", "<cmd>norm.<CR>", {
    desc = "Make `.` work with visually selected lines.",
})

vim.keymap.set("i", "jk", "<Esc>", { desc = "Escape to NORMAL mode." })
vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Escape to NORMAL mode." })

vim.keymap.set("n", "<leader>ss", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/<Right>", {
    desc = "[s]ubstitute [s]election (in-file search/replace) for the word under your cursor.",
})

-- When typing in INSERT mode, pass through : if the cursor is to the left of it.
vim.cmd("inoremap <expr> : search('\\%#:', 'n') ? '<Right>' : ':'")

vim.keymap.set(
    "n",
    "<leader>j",
    "j:s/^\\s*//<CR>kgJ",
    { desc = "[j]oin this line with the line below, without whitespace." }
)

-- Basic mappings that can be used to make Vim "magic" by default
-- Reference: https://stackoverflow.com/q/3760444
-- Reference: http://vim.wikia.com/wiki/Simplifying_regular_expressions_using_magic_and_no-magic
--
local description = { desc = 'Make Vim\'s search more "magic", by default.' }
vim.keymap.set("n", "/", "/\\v", description)
vim.keymap.set("v", "/", "/\\v", description)
vim.keymap.set("c", "%s/", "%smagic/", description)
vim.keymap.set("c", ">s/", ">smagic/", description)

-- Copies the current file to the clipboard
vim.cmd('command! CopyCurrentFile :let @+=expand("%:p")<bar>echo "Copied " . expand("%:p") . " to the clipboard"')
vim.keymap.set("n", "<leader>cc", "<cmd>CopyCurrentFile<CR>", {
    desc = "[c]opy the [c]urrent file in the current window to the system clipboard. Assuming +clipboard.",
    silent = true,
})

-- Delete the current line, without the ending newline character, but
-- still delete the line. This is useful for when you want to delete a
-- line and insert it somewhere else without introducing extra newlines.
-- e.g. `<leader>dilpi(` will delete the current line and then paste it
-- within the next pair of parentheses.
--
vim.keymap.set(
    "n",
    "<leader>dil",
    '^v$hd"_dd',
    { desc = "[d]elete [i]nside the current [l]ine, without the ending newline character." }
)

-- A mapping that quickly expands to the current file's folder. Much
-- easier than cd'ing to the current folder just to edit a single file.
--
vim.keymap.set("n", "<leader>e", ":Cedit ", { desc = "[e]xpand to the current file's folder." })

vim.keymap.set(
    "n",
    "<leader>cd",
    "<cmd>lcd %:p:h<cr>:pwd<CR>",
    { desc = "[c]hange the [d]irectory (`:pwd`) to the directory of the current open window." }
)

vim.keymap.set("n", "<space>C", "<cmd>close<CR>", { desc = "[C]lose the current window." })

vim.keymap.set("n", "J", "mzJ`z", {
    desc = "Keep the cursor in the same position while pressing ``J``.",
})

vim.keymap.set("n", "QQ", "<cmd>qall!<CR>", { desc = "Exit Vim without saving." })

-- Reference: https://www.reddit.com/r/neovim/comments/16ztjvl/comment/k3hd4i1/?utm_source=share&utm_medium=web2x&context=3
vim.keymap.set("x", "/", "<Esc>/\\%V", { desc = "Search for text some within a visual selection" })

-- Change Vim to add numbered j/k  movement to the jumplist. It makes <C-o> and
-- <C-i> remember more cursor positions.
--
vim.cmd([[nnoremap <expr> k (v:count > 1 ? "m'" . v:count : '') . 'k']])
vim.cmd([[nnoremap <expr> j (v:count > 1 ? "m'" . v:count : '') . 'j']])

-- Reference: https://github.com/neovim/neovim/issues/21422#issue-1497443707
vim.keymap.set(
    "x",
    "Q",
    "<cmd>normal @<C-r>=reg_recorded()<CR><CR>",
    { desc = "Repeat the last recorded register on all selected lines." }
)

-- Reference: https://www.joshmedeski.com/posts/underrated-square-bracket
vim.keymap.set("n", "]e", _P.go_to_diagnostic(true, "ERROR"), { desc = "Next diagnostic [e]rror." })
vim.keymap.set("n", "[e", _P.go_to_diagnostic(false, "ERROR"), { desc = "Previous diagnostic [e]rror." })
vim.keymap.set("n", "]w", _P.go_to_diagnostic(true, "WARN"), { desc = "Next diagnostic [w]arning." })
vim.keymap.set("n", "[w", _P.go_to_diagnostic(false, "WARN"), { desc = "Previous diagnostic [w]arning." })

vim.keymap.set("n", "[d", _P.go_to_diagnostic(false, nil), { desc = "Previous diagnostic issue." })
vim.keymap.set("n", "]d", _P.go_to_diagnostic(true, nil), { desc = "Previous diagnostic issue." })

vim.keymap.set("n", "=d", function()
    vim.diagnostic.open_float({ source = true })
end, { desc = "Open the [d]iagnostics window for the current cursor." })

vim.diagnostic.config({ virtual_text = false })

-- Auto-Replace :cd to :tcd, which is better, all around
--
-- Reference: https://vim.fandom.com/wiki/Replace_a_builtin_command_using_cabbrev
--
vim.cmd("cabbrev cd <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'tcd' : 'cd')<CR>")

vim.keymap.set("n", "QA", function()
    vim.cmd("wqall")
end, { desc = "[w]rite and [q]uit [all] buffers." })

vim.keymap.set("n", "<leader>rs", "<cmd>normal 1z=<CR>", {
    desc = "[r]eplace word with [s]uggestion.",
    silent = true,
})
---------- Keymaps [End] ----------

do -- NOTE: Diagnostic symbols and colors
    -- The ctermfg colors are determined by your terminal (``echo $TERM``). Mine is
    -- ``screen-256color`` at the time of writing. Their chart is located here:
    --
    -- References:
    --     https://www.ditig.com/256-colors-cheat-sheet
    --     https://vim.fandom.com/wiki/Xterm256_color_names_for_console_Vim
    --
    vim.cmd("highlight DiagnosticVirtualTextError ctermfg=DarkRed guifg=DarkRed")
    vim.cmd("highlight DiagnosticVirtualTextWarn ctermfg=94 guifg=#875f00") -- Mustard-y
    vim.cmd("highlight DiagnosticVirtualTextInfo ctermfg=25 guifg=DeepSkyBlue4") -- Dark, desaturated blue
    vim.cmd("highlight link DiagnosticVirtualTextHint Comment") -- Dark gray

    vim.cmd("highlight DiagnosticError ctermfg=Red guifg=Red")
    vim.cmd("highlight DiagnosticWarn ctermfg=94 guifg=Orange")
    vim.cmd("highlight DiagnosticInfo ctermfg=26 guifg=DeepSkyBlue2") -- Lighter-ish blue
    vim.cmd("highlight DiagnosticSignHint ctermfg=7 guifg=#c0c0c0") -- Silver (gray)

    -- Reference: https://www.reddit.com/r/neovim/comments/l00zzb/improve_style_of_builtin_lsp_diagnostic_messages
    -- Errors in Red
    vim.cmd("highlight LspDiagnosticsVirtualTextError guifg=Red ctermfg=Red")
    -- Warnings in Yellow
    vim.cmd("highlight LspDiagnosticsVirtualTextWarning guifg=Yellow ctermfg=Yellow")
    -- Info and Hints in White
    vim.cmd("highlight LspDiagnosticsVirtualTextInformation guifg=White ctermfg=White")
    vim.cmd("highlight LspDiagnosticsVirtualTextHint guifg=White ctermfg=White")

    -- Underline the offending code
    vim.cmd("highlight LspDiagnosticsUnderlineError guifg=NONE ctermfg=NONE cterm=underline gui=underline")
    vim.cmd("highlight LspDiagnosticsUnderlineWarning guifg=NONE ctermfg=NONE cterm=underline gui=underline")
    vim.cmd("highlight LspDiagnosticsUnderlineInformation guifg=NONE ctermfg=NONE cterm=underline gui=underline")
    vim.cmd("highlight LspDiagnosticsUnderlineHint guifg=NONE ctermfg=NONE cterm=underline gui=underline")

    -- Add icons for the left-hand sign gutter
    if vim.fn.has("nvim-0.10") then
        vim.diagnostic.config({
            -- Reference: https://github.com/neovim/neovim/commit/ad191be65e2b1641c181506166b1037b548d14a8
            -- Reference: https://www.reddit.com/r/neovim/comments/10jh2jm/comment/j5koxew/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
            --
            severity_sort = true,
            signs = {
                numhl = {
                    [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
                    [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
                    [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
                    [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
                },
                text = {
                    -- Reference: www.nerdfonts.com/cheat-sheet
                    [vim.diagnostic.severity.ERROR] = "",
                    [vim.diagnostic.severity.HINT] = "",
                    [vim.diagnostic.severity.INFO] = "",
                    [vim.diagnostic.severity.WARN] = "⚠",
                },
                texthl = {
                    [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
                    [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
                    [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
                    [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
                },
            },
        })
    else
        -- NOTE: Remove this once we've dropped Neovim 0.9 support
        vim.fn.sign_define("DiagnosticSignError", {
            text = "", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignError",
            texthl = "DiagnosticSignError",
        })
        vim.fn.sign_define("DiagnosticSignWarn", {
            text = "⚠", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignWarn",
            texthl = "DiagnosticSignWarn",
        })
        vim.fn.sign_define("DiagnosticSignInfo", {
            text = "", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignInfo",
            texthl = "DiagnosticSignInfo",
        })
        vim.fn.sign_define("DiagnosticSignHint", {
            text = "", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignHint",
            texthl = "DiagnosticSignHint",
        })
    end

    -- Add a bordered frame around the diagnostics window
    -- TODO: I think this is no longer needed now that Neovim has default border styles.
    vim.lsp.handlers["textDocument/signatureHelp"] = function()
        vim.lsp.buf.signature_help({ border = "rounded", close_events = { "BufHidden", "InsertLeave" } })
    end

    -- TODO: I think this is no longer needed now that Neovim has default border styles.
    vim.lsp.handlers["textDocument/hover"] = function()
        vim.lsp.buf.hover({ border = "rounded" })
    end

    vim.diagnostic.config({ float = { border = "rounded" } })
end

---------- Saver [Start] ----------
-- NOTE: Create the :AsyncWrite command (for writing without blocking Neovim)
vim.api.nvim_create_user_command("AsyncWrite", function()
    local work = vim.loop.new_work(_P.write_async, _P.check_async_write)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    work:queue(vim.api.nvim_buf_get_name(0), table.concat(lines, "\n"))
end, { desc = "Write all buffer lines to-disk in a separate thread." })
---------- Saver [End] ----------

---------- Settings [Start] ----------
vim.opt.scrolloff = 999 -- Center the cursor vertically on the screen

vim.opt.guicursor = "" -- Keeps the "fat cursor" in INSERT Mode

-- Allow a large undo history. Don't use swap files. Those are so 80's
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
local temporary_directory = os.getenv("HOME") or os.getenv("APPDATA")
vim.opt.undodir = temporary_directory .. "/.vim/undodir"
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*",
    command = "execute 'wundo ' . escape(undofile(expand('%')),'% ')",
})

vim.opt.cmdheight = 2

-- Enables 24-bit RGB color
vim.opt.termguicolors = true

-- TODO: Set this differently depending on if in Python or not
vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("ColorColumn", { clear = true }),
    pattern = { "lua", "python" },
    callback = function()
        vim.opt_local.colorcolumn = "88"
    end,
})

vim.g.python_host_prog = "/bin/python"
-- Reference: https://www.inmotionhosting.com/support/server/linux/install-python-3-9-centos-7/
-- vim.g.python3_host_prog = "/usr/local/bin/python3.7"
vim.g.python3_host_prog = "/bin/python3.10"

-- Force Neovim to have one statusline for all buffers (rather than one-per-buffer)
--
-- Reference: https://github.com/neovim/neovim/pull/17266
--
vim.opt.laststatus = 3

-- Don't allow editor config files that I don't use for accidentally causing issues.
--
-- Reference: https://youtu.be/3TRouzuWOuQ?t=107
--
vim.g.editorconfig = false
---------- Settings [End] ----------

-- NOTE: If you need to override the shell, use $NEOVIM_SHELL_COMMAND
vim.opt.shell = os.getenv("NEOVIM_SHELL_COMMAND") or vim.opt.shell

---@type _my.lsp.ServerDefinition[]
local servers = {
    {
        name = "basedpyright",
        filetypes = "python",
        callback = function(event)
            local command = "basedpyright-langserver"

            if vim.fn.executable(command) ~= 1 then
                vim.notify(
                    string.format('Cannot load LSP. There is no "%s" executable.', command),
                    vim.log.levels.ERROR
                )

                return
            end

            vim.lsp.start({
                name = "basedpyright",
                cmd = { command, "--stdio" },
                settings = {
                    basedpyright = {
                        disableOrganizeImports = true,
                        analysis = {
                            typeCheckingMode = "basic",
                        },
                    },
                },
            }, { bufnr = event.buf })
        end,
    },
    {
        name = "lua_ls",
        filetypes = { "lua" },
        callback = function(event)
            local paths = vim.tbl_deep_extend("force", {}, _LUA_ROOT_PATHS)
            table.insert(paths, ".git")

            local command = "lua-language-server"

            if vim.fn.executable(command) ~= 1 then
                vim.schedule(function()
                    vim.notify(
                        string.format('Cannot load LSP. There is no "%s" executable.', command),
                        vim.log.levels.ERROR
                    )
                end)

                return
            end

            vim.lsp.start({
                cmd = { command },
                name = "lua-language-server",
                root_dir = vim.fs.root(0, paths),
            }, { bufnr = event.buf })
        end,
    },
}

do -- NOTE: Autocommands
    for _, data in ipairs(servers) do
        vim.api.nvim_create_autocmd("FileType", {
            group = _LSP_GROUP,
            pattern = data.filetypes,
            callback = data.callback,
        })
    end

    -- Add tree-sitter highlighting if a parser is found
    vim.api.nvim_create_autocmd("FileType", {
        callback = function()
            local treesitter = require("vim.treesitter")

            local buffer = vim.api.nvim_get_current_buf()
            local filetype = vim.bo[buffer].filetype
            local treesitter_language = _FILETYPE_TO_TREESITTER[filetype] or filetype

            local success, result = pcall(function()
                treesitter.query.get(treesitter_language, "highlights")
            end)

            if not success then
                return
            end

            -- NOTE: If there are tree-sitter highlights, use it. If not, use Vim regex.
            if not result then
                vim.bo[buffer].syntax = "on"
            else
                pcall(function()
                    vim.treesitter.start(buffer, treesitter_language)
                end)
            end
        end,
    })

    vim.api.nvim_create_autocmd("LspAttach", { callback = _P.setup_lsp_details, group = _LSP_GROUP })

    -- NOTE: Make sure long lines do not wrap to the next line
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "qf",
        callback = function()
            vim.opt_local.wrap = false
            vim.opt_local.relativenumber = false
            vim.opt_local.number = false
            vim.opt_local.signcolumn = "no"
        end,
    })
end

do -- NOTE: Commands
    vim.api.nvim_create_user_command("Rg", _P.run_ripgrep_command, { nargs = 1, desc = "Search using ripgrep." })
    vim.api.nvim_create_user_command(
        "Pcd",
        _P.cd_to_parent_project_root,
        { nargs = 0, desc = "Change directory to the top of the project." }
    )
    vim.api.nvim_create_user_command("Cedit", function(opts)
        _P.open_relative(opts.args)
    end, {
        complete = function(text)
            return _P.complete_relative(text)
        end,
        nargs = 1,
        desc = "Open a file using a relative file path.",
    })
end

do -- NOTE: Keymaps
    vim.keymap.set(
        "n",
        "<space>E",
        _P.select_file_from_project_root,
        { desc = "Search And [E]dit a file from the project root." }
    )
    vim.keymap.set(
        "n",
        "<space>e",
        _P.select_file_in_directory,
        { desc = "Search and [e]dit from the current directory." }
    )
    vim.keymap.set("n", "<space>B", _P.select_buffer, { desc = "Select a [B]uffer and swtich to it." })
    vim.keymap.set("n", "<leader>tq", _P.toggle_quickfix, { desc = "Open or close the [q]uickfix buffer." })
    vim.keymap.set(
        "i",
        "<C-Space>",
        _P.show_snippet_completion,
        { noremap = true, desc = "Trigger snippet completion." }
    )

    vim.keymap.set({ "i", "n", "s" }, "<C-j>", function()
        if vim.snippet.active({ direction = 1 }) then
            return "<Cmd>lua vim.snippet.jump(1)<CR>"
        else
            return "<C-w>j"
        end
    end, { desc = "Jump to the next snippet tabstop, if active.", expr = true, silent = true })

    vim.keymap.set({ "i", "n", "s" }, "<C-k>", function()
        if vim.snippet.active({ direction = -1 }) then
            return "<Cmd>lua vim.snippet.jump(-1)<CR>"
        else
            return "<C-w>k"
        end
    end, { desc = "Jump to the previous snippet tabstop, if active.", expr = true, silent = true })

    vim.keymap.set("n", "<leader>td", function()
        vim.diagnostic.config({ virtual_lines = not vim.diagnostic.config().virtual_lines })
    end, { desc = "[t]oggle [d]iagnostic as virtual_lines." })
end

do -- NOTE: git-related keymaps
    --- Run `git add` on the current Vim buffer.
    function _P.git_add_current_buffer()
        local buffer = 0
        local path = vim.api.nvim_buf_get_name(buffer)
        local directory = vim.fs.dirname(path)

        _P.run_git_command({ "add", "--force", path }, directory)
    end

    --- Run `git commit` on the repository of the current working directory.
    function _P.git_commit_current_repository()
        local message = vim.fn.input("Enter a commit message: ")

        if message == "" then
            vim.notify(string.format("User cancelled the git commit", vim.log.levels.INFO))

            return
        end

        _P.run_git_command({ "commit", "-m", message }, vim.fn.getcwd())
    end

    --- Run `git reset` on all hunks on the current buffer.
    function _P.git_reset_current_buffer()
        local buffer = 0
        local path = vim.api.nvim_buf_get_name(buffer)
        local directory = vim.fs.dirname(path)

        _P.run_git_command({ "reset", path }, directory)
    end

    --- Run git sub-`command` on `directory`.
    ---
    ---@param command string[]
    ---    Some git command. e.g. `{"add", "-u"}`, from a "git add -u" command.
    ---@param directory string
    ---    The path on-disk that is on or underneath a git repository.
    ---
    function _P.run_git_command(command, directory)
        local function _on_fail(object)
            vim.notify(string.format('Command failed: Got "%s" error.', vim.inspect(object)))
        end

        ---@type string[]
        local full_command = {}
        vim.list_extend(full_command, { "git", "-C", directory })
        vim.list_extend(full_command, command)

        vim.system(full_command, { text = true }, function(object)
            if object.code ~= 0 then
                vim.schedule(function()
                    _on_fail(object)
                end)

                return
            end
        end)
    end

    vim.keymap.set(
        "n",
        "<leader>gac",
        _P.git_add_current_buffer,
        { desc = "Run `git add` for all hunks in the current buffer." }
    )

    vim.keymap.set(
        "n",
        "<leader>gcm",
        _P.git_commit_current_repository,
        { desc = "Run `git commit` for the currently-staged files." }
    )

    vim.keymap.set(
        "n",
        "<leader>grc",
        _P.git_reset_current_buffer,
        { desc = "Run `git reset` for all hunks in the current buffer." }
    )

    vim.keymap.set("n", "<leader>gsp", _P.push_stash_by_name, { desc = "Create a new, named git stash." })
    vim.keymap.set("n", "<leader>gsa", _P.show_git_stashes, { desc = "Show the git stashes that are available." })
    vim.keymap.set(
        "n",
        "<leader>gap",
        _P.run_git_add_p,
        { noremap = true, silent = true, desc = "Create a terminal and run `git add -p` on it." }
    )
end

-- Reference: https://github.com/vim/vim/issues/17187#issuecomment-2820531752
do -- NOTE: Automatically call `:nohlsearch`
    vim.cmd([[
    noremap <expr> <Plug>(StopHL) execute('nohlsearch')[-1]
    noremap! <expr> <Plug>(StopHL) execute('nohlsearch')[-1]

    fu! HlSearch()
        let s:pos = match(getline('.'), @/, col('.') - 1) + 1
        if s:pos != col('.')
         call StopHL()
        endif
    endfu

    fu! StopHL()
        if !v:hlsearch || mode() isnot 'n'
         return
        else
         sil call feedkeys("\<Plug>(StopHL)", 'm')
        endif
    endfu

    augroup SearchHighlight
    au!
        au CursorMoved * call HlSearch()
        au InsertEnter * call StopHL()
    augroup end
    ]])
end

do
    -- grapple.nvim replacement using only native Neovim
    --
    -- Reference:
    --     https://www.reddit.com/r/neovim/comments/1js5bg8/comment/mloidmn/?utm_source=share&utm_medium=web3x&utm_name=web3xcss
    --
    for index = _BOOKMARK_MINIMUM, _BOOKMARK_MAXIMUM do
        local mark = _P.get_vim_mark_from_bookmark_index(index)

        vim.keymap.set("n", "<leader>" .. index, function()
            _P.mark_current_buffer_as_bookmark(mark)
        end, { desc = "Toggle bookmark " .. tostring(index) })
        vim.keymap.set("n", "<leader>bd" .. index, function()
            _P.delete_bookmark(index)
        end, { desc = "[b]ookmark [d]elete " .. tostring(index) })
    end

    vim.keymap.set("n", "<M-S-j>", function()
        _P.go_to_relative_bookmark(1)
    end, { desc = "Cycle to the next bookmark." })
    vim.keymap.set("n", "<M-S-k>", function()
        _P.go_to_relative_bookmark(-1)
    end, { desc = "Cycle to the previous bookmark." })
    vim.keymap.set("n", "<M-S-l>", _P.show_bookmarks, { desc = "List all bookmarks." })
    vim.keymap.set("n", "<M-S-h>", _P.toggle_bookmark_in_current_buffer, { desc = "Delete bookmark." })
end

do -- NOTE: Visualize trailing whitespace
    vim.api.nvim_set_hl(0, "TrailingWhitespace", { link = "Error" })
    -- Apply the highlight using a match pattern
    vim.cmd([[match TrailingWhitespace /\s\+$/]])
end

do -- NOTE: Remove trailing whitespace from modified lines
    -- TODO: In the future this should be modified to work in visual mode, too
    ---@type table<integer, boolean>
    local _MODIFIED_LINES = {}

    vim.api.nvim_create_autocmd("InsertCharPre", {
        callback = function()
            local line = vim.api.nvim_win_get_cursor(0)[1]
            _MODIFIED_LINES[line] = true
        end,
        pattern = "*",
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()

            ---@type integer[]
            local lines = {}

            for line in pairs(_MODIFIED_LINES) do
                table.insert(lines, line)
            end

            table.sort(lines)

            for _, line in ipairs(lines) do
                local content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]

                if content then
                    local cleaned = content:gsub("%s+$", "")
                    vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { cleaned })
                end
            end

            _MODIFIED_LINES = {}
        end,
    })
end

do -- NOTE: The `ii` indentwise text-object
    local function first_non_whitespace_col(line)
        line = vim.fn.getline(line)
        local _, column = string.find(line, "^%s*")

        return column and (column + 1) or 1 -- Lua is 1-indexed
    end

    local function last_non_whitespace_col(line)
        line = vim.fn.getline(line)
        local trimmed = string.match(line, "^(.-)%s*$")
        return #trimmed + 1 -- again, Lua is 1-indexed
    end

    local function select_same_indent(allow_empty_line)
        allow_empty_line = allow_empty_line or false
        local current_line = vim.fn.line(".")
        local indent = vim.fn.indent(current_line)

        local function _needs_stop(line)
            local text = vim.fn.getline(line)

            if vim.fn.indent(line) >= indent then
                return false
            end

            -- TODO: Check for trailing whitespace here
            if text ~= "" then
                return true
            end

            if not allow_empty_line then
                return true
            end

            return false
        end

        local start_line = current_line

        while start_line > 1 do
            if _needs_stop(start_line) then
                break
            end

            start_line = start_line - 1
        end

        local end_line = current_line

        while end_line < vim.fn.line("$") do
            if _needs_stop(end_line) then
                break
            end

            end_line = end_line + 1
        end

        start_line = start_line + 1
        end_line = end_line - 1

        _P.set_text_object_marks(
            start_line,
            first_non_whitespace_col(start_line) - 1,
            end_line,
            last_non_whitespace_col(end_line) - 2
        )
    end

    vim.keymap.set({ "o", "x" }, "ii", function()
        select_same_indent(false)
    end, { desc = "Select block with same indentation, stop at whitespace lines." })
    vim.keymap.set({ "o", "x" }, "iI", function()
        select_same_indent(true)
    end, { desc = "Select block with same indentation, ignore whitespace lines." })
end

do -- NOTE: Statusline definition
    local _SHUTDOWN_STATUSLINE = false
    local _TIMER = vim.uv.new_timer()

    if not _TIMER then
        error("A new timer could not be created.", 0)
    end

    -- NOTE: Update the statusline every 10 ms (0.01 seconds)
    _TIMER:start(
        0,
        10,
        vim.schedule_wrap(function()
            if _SHUTDOWN_STATUSLINE then
                _TIMER:stop()
                _TIMER:close()

                return
            end

            vim.o.statusline = table.concat({
                " ",
                "%#StatusGit# ",
                get_git_branch_safe(),
                "%#StatusGitAfter# ",
                _P.get_grapple_statusline(),
                "%=", -- Spacer
                "%#StatusPosition# Ln %l, Col %c ",
                "%#StatusProgress# [%{v:lua.get_window_line_progress()}] ",
            })
        end)
    )

    vim.api.nvim_set_hl(0, "StatusLine", { bg = "#333333" })
    vim.api.nvim_set_hl(0, "StatusGit", { link = "Special" })
    vim.api.nvim_set_hl(0, "StatusPosition", { link = "Comment" })
    vim.api.nvim_set_hl(0, "StatusProgress", { link = "Comment" })
    vim.api.nvim_set_hl(0, "StatusGrappleInactive", { link = "Comment" })
    vim.api.nvim_set_hl(0, "StatusGrappleActive", { link = "Special" })
end

do -- NOTE: Make text-objects to work with `p`. e.g. `piw`
    --- Change `p` into a text-object-aware operator.
    ---
    ---@param type_ "char" | "line" The type of operator to consider.
    ---
    function _P.operator_paste(type_)
        local register = vim.v.register ~= "" and vim.v.register or '"'

        -- Delete the target text to the black hole register
        if type_ == "char" then
            vim.cmd('normal! `[v`]"_d')
        elseif type_ == "line" then
            vim.cmd('normal! `[V`]"_d')
        else
            vim.notify(
                string.format('Unknown mode "%s" is not supported for paste operator.', type_),
                vim.log.levels.WARN
            )

            return
        end

        vim.cmd(string.format('normal! `["%sP', register))
    end

    --- Change `p` into a text-object-aware operator and revert later.
    ---
    ---@param caller fun(type_: string): nil Some custom operatorfunc behavior.
    ---
    function _P.wrap_operatorfunc(caller)
        return function()
            local original = vim.go.operatorfunc

            function _G.temporary_operator_paste(type_)
                caller(type_)

                vim.go.operatorfunc = original
                _G.temporary_operator_paste = nil
            end

            vim.go.operatorfunc = "v:lua.temporary_operator_paste"

            return "g@"
        end
    end

    vim.keymap.set(
        "n",
        "p",
        _P.wrap_operatorfunc(_P.operator_paste),
        { silent = true, desc = "[p]ut text and replace the [i]nner [w]ord with that text.", expr = true }
    )
    vim.keymap.set("n", "PP", "P", { noremap = true, silent = true, desc = "Paste the text." })
    vim.keymap.set("n", "pp", "p", { noremap = true, silent = true, desc = "Paste the text." })
    vim.keymap.set("n", "P", "<Nop>", { noremap = true, silent = true, desc = "Disable pasting with P." })
end

-- Section Start: quick-scope
-- Reference: https://github.com/unblevable/quick-scope/blob/master/plugin/quick_scope.vim
-- TODO: Finish this
-- Section End: quick-scope

do -- NOTE: Colorscheme
    local _extend = function(table_to_modify, items)
        for key, value in pairs(items) do
            table_to_modify[key] = value
        end
    end

    local _multi_2 = function(first, second)
        local output = {}

        _extend(output, first)
        _extend(output, second)

        return output
    end

    local _multi_3 = function(first, second, third)
        local output = {}

        _extend(output, first)
        _extend(output, second)
        _extend(output, third)

        return output
    end

    vim.cmd("set background=dark")

    -- General Palette. Make sure these colors look good!
    local _BLACK_20 = "#2c323c"
    local _BLACK_30 = "#282a2e"
    local _BLACK_50 = "#1d1f21"

    local _WHITE = "#abb2bf"

    local _GRAY_10 = "#c0c0c0"
    local _GRAY_20 = "#707880"
    local _GRAY_30 = "#6c6c6c"
    local _GRAY_50 = "#373b41"

    -- Used for errors
    local _RED_10 = "#cc6666"
    local _RED_20 = "#5f0000"

    -- Colors that denote "sections"
    local _SECTION_10 = "#de935f"
    local _SECTION_20 = "#DF8239"
    local _SECTION_30 = "#f0c674"
    local _SECTION_40 = "#f0e4c8"
    local _SECTION_50 = "#cccccc"
    local _SECTION_60 = "#ffffff"

    -- "Base" colors, used for "normal" situations
    local _GREEN_10 = "#b5bd68"
    local _GREEN_30 = "#5f875f"

    -- Typically used for "builtin" colors
    local _PURPLE_10 = "#d7d7ff"
    local _PURPLE_30 = "#b294bb"
    local _PURPLE_50 = "#5f005f"
    local _COOL_BLUE_10 = "#81a2be"
    local _COOL_BLUE_20 = "#005f5f"

    -- Special purpose, "don't use these too often" colors
    local _ACCENT_ATTENTION_NORMAL = "#d7ffaf"
    local _ACCENT_BRIGHT_WHITE_10 = "#cccccc"
    local _ACCENT_DEEP_BLUE_10 = "#00005f"
    local _ACCENT_COOL_GRAY = "#5f5f87"
    local _ACCENT_INFO_50 = "DeepSkyBlue2"
    local _ACCENT_ERROR_50 = "#ff2211"
    local _ACCENT_WARNING_50 = "#ffcc00"

    local _ACCENT_CRITICAL_30 = "#FF4400"

    -- Controller Variables - Colors
    local _BLACK_30_BG = { bg = _BLACK_30, ctermbg = 235 }
    local _ACCENT_BLUE_50_BG = { bg = _ACCENT_DEEP_BLUE_10, ctermbg = 17 }
    local _ACCENT_COOL_GRAY_BG = { bg = _ACCENT_COOL_GRAY, ctermbg = 60 }
    local _CYAN_10_BG = { bg = _COOL_BLUE_10, ctermbg = 109 }
    local _CYAN_10_FG = { fg = _COOL_BLUE_10, ctermfg = 109 }
    local _CYAN_30_BG = { bg = _COOL_BLUE_20, ctermbg = 23 }
    local _GRAY_20_FG = { fg = _GRAY_10, ctermfg = 250 }
    local _GRAY_30_BG = { bg = _GRAY_30, ctermbg = 242 }
    local _KHAKI_GREEN = { fg = _GREEN_10, ctermfg = 143 }
    local _PURPLE_20_FG = { fg = _PURPLE_30, ctermfg = 139 }
    local _PURPLE_50_BG = { bg = _PURPLE_50, ctermbg = 53 }
    local _WHITE_BG = { bg = _WHITE, ctermbg = 249 }
    local _WHITE_FG = { fg = _WHITE, ctermfg = 249 }
    local _WHITE_10_FG = { fg = _BLACK_50, ctermfg = 234 }

    -- Controller Variables - Purposes
    local _BG = { bg = _BLACK_50, ctermbg = 234 }
    local _BG_DARKER_20 = { ctermbg = 16, bg = "#111111" } -- Like _BG, but much darker
    local _BG_AS_FG = { fg = _BLACK_50, ctermfg = 234 }
    local _COMMENT = { fg = _GRAY_20, ctermfg = 243 }
    local _CONSTANT_FG = { fg = _RED_10, ctermfg = 167 }
    local _CURSOR_GRAY_FG = { fg = _BLACK_20, ctermfg = 236 }
    local _DIFF_CHANGE_FG = { fg = _PURPLE_10, ctermfg = 189 }
    local _ERROR_50_BG = { bg = _RED_20, ctermbg = 52 }
    local _ERROR_BG = { bg = _RED_10, ctermbg = 167 }
    local _ERROR_FG = { fg = _RED_10, ctermfg = 167 }
    local _KNOWN_VARIABLE = { fg = _PURPLE_30, ctermfg = 216 } -- LightSalmon1
    local _LINE_GRAY_BG = { bg = _GRAY_20, ctermbg = 243 }
    local _NON_TEXT_FG = { fg = _GRAY_50, ctermfg = 237 }
    local _NOTE_10_FG = { fg = _ACCENT_ATTENTION_NORMAL, ctermfg = 193 }
    local _NOTE_DIFF_ADD_10_FG = _NOTE_10_FG
    local _SEARCH_BG = { bg = _BLACK_50, ctermbg = 234 }
    local _SEARCH_FG = { fg = _BLACK_50, ctermfg = 234 }
    local _SPECIAL_GRAY_FG = { fg = _GRAY_50, ctermfg = 238 }
    local _SPECIAL_VARIABLE = { fg = _ACCENT_CRITICAL_30, ctermfg = 96 }
    local _STATEMENT = { fg = _COOL_BLUE_10, ctermfg = 109 }
    local _TITLE_BG = { bg = _SECTION_30, ctermbg = 222 }
    local _TITLE_FG = { fg = _SECTION_30, ctermfg = 222 }
    local _TYPE = { fg = _SECTION_10, ctermfg = 173 }
    local _VERT_SPLIT_FG = { fg = _GRAY_50, ctermfg = 236 }
    local _VISUAL_GRAY_BG = { bg = _GRAY_50, ctermbg = 237 }
    local _VISUAL_GRAY_FG = { fg = _GRAY_50, ctermfg = 237 }

    -- Controller Variables - Miscellaneous
    local _BOLD = { bold = true }
    local _NONE = { cterm = nil, gui = nil } -- Use this to disable highlighting on a group
    local _REVERSE = { reverse = true }
    local _UNDERLINE = { underline = true }

    -- General
    vim.api.nvim_set_hl(0, "Boolean", _CONSTANT_FG)
    vim.api.nvim_set_hl(0, "Character", _CONSTANT_FG)
    vim.api.nvim_set_hl(0, "ColorColumn", _BLACK_30_BG)
    vim.api.nvim_set_hl(0, "Comment", _COMMENT)
    vim.api.nvim_set_hl(0, "Conceal", _multi_2(_GRAY_20_FG, _GRAY_30_BG))
    vim.api.nvim_set_hl(0, "Conditional", _STATEMENT)
    vim.api.nvim_set_hl(0, "Constant", _CONSTANT_FG)
    vim.api.nvim_set_hl(0, "CurSearch", _multi_2(_SEARCH_FG, { bg = _SECTION_40 })) -- Searched, selected text
    vim.api.nvim_set_hl(0, "Cursor", _REVERSE)
    vim.api.nvim_set_hl(0, "Define", _STATEMENT)
    vim.api.nvim_set_hl(0, "DiffAdd", _multi_2(_NOTE_10_FG, { bg = _GREEN_30, ctermbg = 65 }))
    vim.api.nvim_set_hl(0, "DiffChange", _multi_2(_DIFF_CHANGE_FG, _ACCENT_COOL_GRAY_BG))
    vim.api.nvim_set_hl(0, "DiffDelete", _multi_2(_SEARCH_FG, _ERROR_BG))
    vim.api.nvim_set_hl(0, "DiffText", _multi_2(_WHITE_10_FG, _CYAN_10_BG))
    vim.api.nvim_set_hl(0, "Directory", _CYAN_10_FG)
    vim.api.nvim_set_hl(0, "EndOfBuffer", _NON_TEXT_FG)
    vim.api.nvim_set_hl(0, "Error", _multi_2(_ERROR_FG, _ERROR_50_BG))
    vim.api.nvim_set_hl(0, "ErrorMsg", _ERROR_FG)
    vim.api.nvim_set_hl(0, "Exception", _STATEMENT)
    vim.api.nvim_set_hl(0, "Float", _CONSTANT_FG)
    vim.api.nvim_set_hl(0, "FoldColumn", _BG)
    vim.api.nvim_set_hl(0, "Folded", _COMMENT)
    vim.api.nvim_set_hl(0, "Function", _TITLE_FG)
    vim.api.nvim_set_hl(0, "Identifier", _WHITE_FG)
    vim.api.nvim_set_hl(0, "IncSearch", { link = "Search" })
    vim.api.nvim_set_hl(0, "Include", _STATEMENT)
    vim.api.nvim_set_hl(0, "Keyword", _STATEMENT)
    vim.api.nvim_set_hl(0, "Label", _STATEMENT)
    vim.api.nvim_set_hl(0, "LineNr", _CURSOR_GRAY_FG)
    vim.api.nvim_set_hl(0, "Macro", _STATEMENT)
    vim.api.nvim_set_hl(0, "MatchParen", _multi_2(_WHITE_10_FG, _ACCENT_COOL_GRAY_BG))
    vim.api.nvim_set_hl(0, "NonText", _NON_TEXT_FG)
    vim.api.nvim_set_hl(0, "Normal", _multi_2(_BG, _WHITE_FG)) -- BG color
    vim.api.nvim_set_hl(0, "NormalFloat", _BG_DARKER_20) -- Floating BG color
    vim.api.nvim_set_hl(0, "Number", _CONSTANT_FG)
    vim.api.nvim_set_hl(0, "Operator", _STATEMENT)
    vim.api.nvim_set_hl(0, "Pmenu", { link = "NormalFloat" })
    vim.api.nvim_set_hl(0, "PmenuSel", _multi_2(_BG_AS_FG, _WHITE_BG))
    vim.api.nvim_set_hl(0, "PreCondit", _STATEMENT)
    vim.api.nvim_set_hl(0, "PreProc", _STATEMENT)
    vim.api.nvim_set_hl(0, "Question", _NOTE_10_FG)
    vim.api.nvim_set_hl(0, "QuickFixLine", _multi_2(_SEARCH_FG, _SEARCH_BG))
    vim.api.nvim_set_hl(0, "Repeat", _STATEMENT)
    vim.api.nvim_set_hl(0, "Search", _multi_2(_SEARCH_FG, _TITLE_BG)) -- Searched, non-selected text
    vim.api.nvim_set_hl(0, "SignColumn", _BG)
    vim.api.nvim_set_hl(0, "Special", _KHAKI_GREEN)
    vim.api.nvim_set_hl(0, "SpecialComment", _KHAKI_GREEN)
    vim.api.nvim_set_hl(0, "SpecialKey", _SPECIAL_GRAY_FG)
    vim.api.nvim_set_hl(0, "SpellBad", _multi_3(_ERROR_FG, _ERROR_50_BG, _UNDERLINE))
    vim.api.nvim_set_hl(0, "SpellCap", _multi_3(_CYAN_10_FG, _ACCENT_BLUE_50_BG, _UNDERLINE))
    vim.api.nvim_set_hl(0, "SpellLocal", _multi_3(_CYAN_10_FG, _CYAN_30_BG, _UNDERLINE))
    vim.api.nvim_set_hl(0, "SpellRare", _multi_3(_PURPLE_20_FG, _PURPLE_50_BG, _UNDERLINE))
    vim.api.nvim_set_hl(0, "Statement", _STATEMENT)
    vim.api.nvim_set_hl(0, "StatusLineNC", _multi_3(_VERT_SPLIT_FG, _LINE_GRAY_BG, _REVERSE))
    vim.api.nvim_set_hl(0, "StorageClass", _TYPE)
    vim.api.nvim_set_hl(0, "String", _KHAKI_GREEN)
    vim.api.nvim_set_hl(0, "Structure", _STATEMENT)
    vim.api.nvim_set_hl(0, "TabLine", _GRAY_30_BG)
    vim.api.nvim_set_hl(0, "TabLineFill", _REVERSE)
    vim.api.nvim_set_hl(0, "TabLineSel", _BOLD)
    vim.api.nvim_set_hl(0, "TermCursor", _multi_2(_BG_AS_FG, _WHITE_BG))
    vim.api.nvim_set_hl(0, "Title", _TITLE_FG)
    vim.api.nvim_set_hl(0, "Todo", _NOTE_10_FG)
    vim.api.nvim_set_hl(0, "Type", _TYPE)
    vim.api.nvim_set_hl(0, "Typedef", _STATEMENT)
    vim.api.nvim_set_hl(0, "Underlined", _multi_2(_CYAN_10_FG, _UNDERLINE))
    vim.api.nvim_set_hl(0, "VertSplit", { link = "WinSeparator" })
    vim.api.nvim_set_hl(0, "Visual", _VISUAL_GRAY_BG)
    vim.api.nvim_set_hl(0, "VisualNOS", _VISUAL_GRAY_FG)
    vim.api.nvim_set_hl(0, "WinBar", _BOLD)
    vim.api.nvim_set_hl(0, "WinBarNC", { link = "WinBar" })
    vim.api.nvim_set_hl(0, "WinSeparator", _VERT_SPLIT_FG)

    -- Advanced LSP features that seemed to look nice
    vim.api.nvim_set_hl(0, "LspCodeLens", { link = "Normal" })
    vim.api.nvim_set_hl(0, "LspInlayHint", { link = "Comment" })

    -- Disable LSP underlining. I already use virtual text so there's no need for
    -- distracting underlines as well.
    --
    vim.api.nvim_set_hl(0, "DiagnosticUnderlineError", _NONE)
    vim.api.nvim_set_hl(0, "DiagnosticUnderlineInfo", _NONE)
    vim.api.nvim_set_hl(0, "DiagnosticUnderlineHint", _NONE)
    vim.api.nvim_set_hl(0, "DiagnosticUnderlineWarn", _NONE)
    vim.api.nvim_set_hl(0, "DiagnosticUnderlineOk", _NONE)

    -- Adding diagnostic colors (it makes lualine look better)
    vim.api.nvim_set_hl(0, "DiagnosticError", { fg = _ACCENT_ERROR_50 })
    vim.api.nvim_set_hl(0, "DiagnosticWarning", { fg = _ACCENT_WARNING_50 })
    vim.api.nvim_set_hl(0, "DiagnosticHint", { fg = _GRAY_10 })
    vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = _ACCENT_INFO_50 })

    -- Quickfix
    vim.api.nvim_set_hl(0, "qfLineNr", _TITLE_FG)
    vim.api.nvim_set_hl(0, "QuickFixLine", { link = "Search" })
    -- qfFileName
    -- qfLineNr
    -- qfError

    -- nvim-treesitter settings
    --
    -- https://github.com/nvim-treesitter/nvim-treesitter
    --
    vim.api.nvim_set_hl(0, "@attribute", { link = "Function" })
    vim.api.nvim_set_hl(0, "@character.cpp", { link = "String" })
    vim.api.nvim_set_hl(0, "@comment.documentation", { link = "@string.documentation" })
    vim.api.nvim_set_hl(0, "@diff.add.diff", { link = "DiffAdd" })
    vim.api.nvim_set_hl(0, "@diff.delete.diff", { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, "@diff.minus.diff", { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, "@diff.plus.diff", { link = "DiffAdd" })
    vim.api.nvim_set_hl(0, "@function.builtin", _KNOWN_VARIABLE)
    vim.api.nvim_set_hl(0, "@lsp.mod.readonly", { link = "Constant" })
    vim.api.nvim_set_hl(0, "@markup.heading.1", { fg = _SECTION_10 })
    vim.api.nvim_set_hl(0, "@markup.heading.2", { fg = _SECTION_20 })
    vim.api.nvim_set_hl(0, "@markup.heading.3", { fg = _SECTION_30 })
    vim.api.nvim_set_hl(0, "@markup.heading.4", { fg = _SECTION_40 })
    vim.api.nvim_set_hl(0, "@markup.heading.5", { fg = _SECTION_50 })
    vim.api.nvim_set_hl(0, "@markup.heading.6", { fg = _SECTION_60 })
    vim.api.nvim_set_hl(0, "@markup.link", _SPECIAL_VARIABLE)
    vim.api.nvim_set_hl(0, "@markup.link.label", { fg = _ACCENT_BRIGHT_WHITE_10, bold = true })
    vim.api.nvim_set_hl(0, "@markup.raw", _STATEMENT)
    vim.api.nvim_set_hl(0, "@module", _COMMENT)
    vim.api.nvim_set_hl(0, "@punctuation", _WHITE_FG)
    vim.api.nvim_set_hl(0, "@string.documentation", { link = "String" })
    vim.api.nvim_set_hl(0, "@string.special.url", _SPECIAL_VARIABLE)
    vim.api.nvim_set_hl(0, "@text.diff.add.diff", { link = "DiffAdd" })
    vim.api.nvim_set_hl(0, "@text.diff.delete.diff", { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, "@text.uri", { link = "@string.special.url" })
    vim.api.nvim_set_hl(0, "@variable.builtin", _KNOWN_VARIABLE)

    -- LSP Semantic Tokens
    vim.api.nvim_set_hl(0, "@lsp.typemod.function.defaultLibrary", { link = "@function.builtin" })
    -- NOTE: This looks good in Lua. Maybe it'd look good in other languages?
    vim.api.nvim_set_hl(0, "@lsp.typemod.keyword.documentation.lua", { link = "@string.documentation" })

    -- Neovim 0.10+ ships Python queries that break backwards compatibility
    vim.api.nvim_set_hl(0, "@variable", { link = "Identifier" })
    vim.api.nvim_set_hl(0, "@variable.parameter", { fg = _ACCENT_BRIGHT_WHITE_10, bold = true })

    -- Miscellaneous: Highlight non-auto-completed text (make it look like virtual text)
    --
    -- e.g. Ctrl-X + Ctrl-L and then select an entry to view the effect.
    --
    vim.api.nvim_set_hl(0, "ComplMatchIns", { link = "Comment" })

    -- Plugin - https://github.com/airblade/vim-gitgutter
    vim.api.nvim_set_hl(0, "GitGutterAdd", _NOTE_DIFF_ADD_10_FG)
    vim.api.nvim_set_hl(0, "GitGutterChange", _DIFF_CHANGE_FG)
    vim.api.nvim_set_hl(0, "GitGutterDelete", _VERT_SPLIT_FG)
    vim.api.nvim_set_hl(0, "GitGutterAddInvisible", { bg = "Grey", ctermbg = 242 })
    vim.api.nvim_set_hl(0, "GitGutterChangeInvisible", { bg = "Grey", ctermbg = 242 })
    vim.api.nvim_set_hl(0, "GitGutterDeleteInvisible", { bg = "Grey", ctermbg = 242 })

    -- Special: Disable line highlighting of the cursor row BUT highlight the current line as a color
    --
    -- Reference: https://stackoverflow.com/a/26205823
    -- Reference: https://www.reddit.com/r/neovim/comments/16zjizx/comment/k3ey1rt/?utm_source=share&utm_medium=web2x&context=3
    --
    vim.api.nvim_set_hl(0, "CursorLine", { cterm = nil, ctermbg = nil, ctermfg = nil, bg = nil, fg = nil })
    vim.api.nvim_set_hl(0, "CursorColumn", _BLACK_30_BG)
    vim.api.nvim_set_hl(0, "CursorLineNr", _TITLE_FG)
    vim.cmd("set cursorline")

    -- Plugin - https://github.com/machakann/vim-highlightedyank
    vim.api.nvim_set_hl(0, "HighlightedyankRegion", { link = "Search" })

    -- Reference: https://www.reddit.com/r/neovim/comments/12gvms4/this_is_why_your_higlights_look_different_in_90/
    local links = {
        ["@lsp.type.namespace"] = "@namespace",
        ["@lsp.type.type"] = "@type",
        ["@lsp.type.class"] = "@type",
        ["@lsp.type.enum"] = "@type",
        ["@lsp.type.interface"] = "@type",
        ["@lsp.type.struct"] = "@structure",
        ["@lsp.type.parameter"] = "@parameter",
        ["@lsp.type.variable"] = "@variable",
        ["@lsp.type.property"] = "@property",
        ["@lsp.type.enumMember"] = "@constant",
        ["@lsp.type.function"] = "@function",
        ["@lsp.type.method"] = "@method",
        ["@lsp.type.macro"] = "@macro",
        ["@lsp.type.decorator"] = "@function",
    }
    for newgroup, oldgroup in pairs(links) do
        vim.api.nvim_set_hl(0, newgroup, { link = oldgroup, default = true })
    end

    vim.api.nvim_set_hl(0, "@attribute", { link = "Function" })
    vim.api.nvim_set_hl(0, "@character.cpp", { link = "String" })
    vim.api.nvim_set_hl(0, "@comment.documentation", { link = "@string.documentation" })
    vim.api.nvim_set_hl(0, "@diff.add.diff", { link = "DiffAdd" })
    vim.api.nvim_set_hl(0, "@diff.delete.diff", { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, "@diff.minus.diff", { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, "@diff.plus.diff", { link = "DiffAdd" })
    vim.api.nvim_set_hl(0, "@lsp.mod.readonly", { link = "Constant" })
    vim.api.nvim_set_hl(0, "@string.documentation", { link = "String" })
    vim.api.nvim_set_hl(0, "@text.diff.add.diff", { link = "DiffAdd" })
    vim.api.nvim_set_hl(0, "@text.diff.delete.diff", { link = "DiffDelete" })
    vim.api.nvim_set_hl(0, "@text.uri", { link = "@string.special.url" })

    -- LSP Semantic Tokens
    vim.api.nvim_set_hl(0, "@lsp.typemod.function.defaultLibrary", { link = "@function.builtin" })
    vim.api.nvim_set_hl(0, "@lsp.typemod.keyword.documentation.lua", { link = "@string.documentation" })

    -- Neovim 0.10+ ships Python queries that break backwards compatibility
    vim.api.nvim_set_hl(0, "@variable", { link = "Identifier" })
end

do -- NOTE: auto-pairs functionality
    local function _define_close_mapping(character)
        vim.keymap.set("i", character, function()
            local line = vim.api.nvim_get_current_line()
            local column = vim.api.nvim_win_get_cursor(0)[2]
            local next_character = line:sub(column + 1, column + 1)

            if next_character == character then
                return "<Right>"
            end

            return character
        end, { expr = true, desc = "Decide whether to type a closing character or move to the right, instead." })
    end

    local function _define_open_mapping(open, close)
        vim.keymap.set("i", open, function()
            -- NOTE: Assume that `cloes` is only one character.
            return open .. close .. "<Left>"
        end, { expr = true, desc = "Create an open + close pair and move the cursor to the middle." })
    end

    local _PAIRS = {
        ["("] = ")",
        ["["] = "]",
        ["{"] = "}",
        ["'"] = "'",
        ['"'] = '"',
        ["`"] = "`",
    }

    local _CLOSING_PAIRS = {
        ")",
        "]",
        "}",
        "'",
        '"',
        "`",
    }

    for open, close in pairs(_PAIRS) do
        _define_open_mapping(open, close)
    end

    for _, character in ipairs(_CLOSING_PAIRS) do
        _define_close_mapping(character)
    end

    vim.keymap.set("i", "<BS>", function()
        local line = vim.api.nvim_get_current_line()
        local column = vim.api.nvim_win_get_cursor(0)[2]
        local previous_character = line:sub(column, column)
        local next_character = line:sub(column + 1, column + 1)

        for open, close in pairs(_PAIRS) do
            if previous_character == open and next_character == close then
                return "<Del><BS>"
            end
        end

        return "<BS>"
    end, { expr = true, desc = "Delete the open and close pair characters at once." })
end

do -- NOTE: Add [p ]p >p <p >P <P mappings.
    --- Paste to the line above or below, and move text left or right.
    ---
    ---@param direction "above" | "below"
    ---    Put text above or below the current line.
    ---@param indent string?
    ---    If not provided, the pasted text is on the same line as the current line.
    ---    Otherwise >> indents right and << indents left.
    ---
    local function _paste_line(direction, indent)
        local row = vim.fn.line(".")

        if direction == "above" then
            row = row - 1
        end

        local register = vim.v.register ~= "" and vim.v.register or '"'
        local line = vim.fn.getreg(register)
        line = _P.rstrip(line)
        local lines = vim.split(line, "\n")
        vim.api.nvim_buf_set_lines(0, row, row, true, lines)
        local start = row + 1
        local end_ = start + #lines - 1

        vim.cmd(string.format("%s,%snormal! ==", start, end_))

        if indent then
            vim.cmd(string.format("%s,%snormal! %s", start, end_, indent))
        end
    end

    vim.keymap.set("n", "[p", function()
        _paste_line("above")
    end, { desc = "Paste line above" })
    vim.keymap.set("n", "]p", function()
        _paste_line("below")
    end, { desc = "Paste line below" })
    vim.keymap.set("n", ">p", function()
        _paste_line("below", ">>")
    end, { desc = "Paste below + indent" })
    vim.keymap.set("n", "<p", function()
        _paste_line("below", "<<")
    end, { desc = "Paste below + dedent" })
    vim.keymap.set("n", ">P", function()
        _paste_line("above", ">>")
    end, { desc = "Paste above + indent" })
    vim.keymap.set("n", "<P", function()
        _paste_line("above", "<<")
    end, { desc = "Paste above + dedent" })
end

do -- NOTE: If at the edge of the Neovim tab, move to the nearest tmux pane instead.
    --- Move in `direction` if 1. on a Neovim edge tab 2. there is a nearby tmux pane.
    ---
    ---@param direction "h" | "j" | "k" | "l"
    ---    The Neovim or tmux pane to move in.
    ---
    local function _move_to_tmux_pane_if_needed(direction)
        local tmux_directions = { h = "L", j = "D", k = "U", l = "R" }

        local current_window = vim.api.nvim_get_current_win()
        vim.cmd("wincmd " .. direction)

        if vim.api.nvim_get_current_win() ~= current_window then
            return
        end

        vim.fn.system(string.format("tmux select-pane -%s", tmux_directions[direction]))
    end

    local _desc = function(opts, direction)
        return vim.tbl_deep_extend(
            "force",
            opts,
            { desc = string.format('Move the cursor to the "%s" window.', direction) }
        )
    end
    local desc = function(direction)
        _desc({ noremap = true, silent = true }, direction)
    end

    vim.keymap.set("n", "<C-h>", function()
        _move_to_tmux_pane_if_needed("h")
    end, desc("left"))
    vim.keymap.set("n", "<C-j>", function()
        _move_to_tmux_pane_if_needed("j")
    end, desc("down"))
    vim.keymap.set("n", "<C-k>", function()
        _move_to_tmux_pane_if_needed("k")
    end, desc("up"))
    vim.keymap.set("n", "<C-l>", function()
        _move_to_tmux_pane_if_needed("l")
    end, desc("right"))
end

do -- NOTE: Print the current word (It's https://github.com/andrewferrier/debugprint.nvim, basically)
    local _COUNTER = 1

    ---@return string? # Get the visual selection, if it is in visual mode.
    local function _get_selected_word()
        local mode = vim.api.nvim_get_mode().mode

        if not mode:match("[vV]") then
            return nil
        end

        local characters = vim.fn.getregion(vim.fn.getpos("."), vim.fn.getpos("v"), { type = mode })
        local result = vim.fn.join(characters, "")

        if mode:match("V") then
            result = _P.strip_left(result)
        end

        return result
    end

    --- Print the current word to the line above or below.
    ---
    ---@param direction "above" | "below"
    ---    The placement of the inserted print statement.
    ---
    local function _print_word_under_cursor(direction)
        local word = _get_selected_word() or vim.fn.expand("<cword>")
        local row = vim.fn.line(".")
        local file_name = vim.fn.expand("%")
        _COUNTER = _COUNTER + 1
        ---@type string
        local line

        if vim.o.filetype == "lua" then
            line = string.format(
                'print("DEBUGPRINT[%s]: %s:%s: %s=" .. vim.inspect(%s))',
                _COUNTER,
                file_name,
                row,
                word,
                word
            )
        elseif vim.o.filetype == "python" then
            line = string.format('print(f"DEBUGPRINT[%s]: %s:%s: %s={%s}")', _COUNTER, file_name, line, word, word)
        else
            _COUNTER = _COUNTER - 1
            vim.notify(string.format('Type "%s" is not supported yet.', vim.o.filetype), vim.log.levels.ERROR)

            return
        end

        if direction == "below" then
            vim.api.nvim_buf_set_lines(0, row, row, true, { line })
            vim.cmd(string.format("%snormal! ==", row + 1))
        elseif direction == "above" then
            vim.api.nvim_buf_set_lines(0, row - 1, row - 1, true, { line })
            vim.cmd(string.format("%snormal! ==", row))
        end
    end

    vim.keymap.set({ "n", "v" }, "<leader>iv", function()
        _print_word_under_cursor("below")
    end, { noremap = true, desc = "Print the current word below the cursor line." })

    vim.keymap.set({ "n", "v" }, "<leader>iV", function()
        _print_word_under_cursor("above")
    end, { noremap = true, desc = "Print the current word above the cursor line." })
end

do -- NOTE: A lightweight "toggleterminal". Use <space>T to open and close it.
    ---@type table<integer, _my.ToggleTerminal>
    local _TAB_TERMINALS = {}
    ---@type table<integer, _my.ToggleTerminal>
    local _BUFFER_TO_TERMINAL = {}
    local _DARKER_TERMINAL_COLOR = "#111111"

    local _Mode = {
        insert = "insert",
        normal = "normal",
        unknown = "?",
    }
    local _NEXT_NUMBER = 0
    local _STARTING_MODE = _Mode.insert -- NOTE: Start off in insert mode

    --- Check if `buffer` is shown to the user.
    ---
    --- @param buffer number A 0-or-more index pointing to some Vim data.
    --- @return boolean # If at least one window contains `buffer`.
    ---
    local function _is_buffer_visible(buffer)
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == buffer then
                return true
            end
        end

        return false
    end

    --- Find all windows that show `buffer`.
    ---
    --- @param buffer number A 0-or-more index pointing to some Vim data.
    --- @return number[] # All of the windows found, if any.
    ---
    local function _get_buffer_windows(buffer)
        ---@type number[]
        local output = {}

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == buffer then
                table.insert(output, window)
            end
        end

        return output
    end

    --- Get the next UUID so we can use if for terminal buffer names.
    local function _increment_terminal_uuid()
        _NEXT_NUMBER = _NEXT_NUMBER + 1
    end

    --- Suggest a new terminal name, starting with `name`, that is unique.
    ---
    --- @param name string
    ---     Some terminal prefix. i.e. `"term://bash"`.
    --- @return string
    ---     The full buffer path that doesn't already exist. i.e.
    ---     `"term://bash;::toggleterminal::1"`. It's important though to remember
    ---     - This won't be the final, real terminal path name because this name
    ---     doesn't contain a $PWD.
    ---
    local function _suggest_name(name)
        local current = name .. ";::toggleterminal::" .. _NEXT_NUMBER

        while vim.fn.bufexists(current) == 1 do
            _increment_terminal_uuid()
            current = name .. ";::toggleterminal::" .. _NEXT_NUMBER
        end

        -- We add another one so that, if `_suggest_name` is called again, we save
        -- 1 extra call to `vim.fn.bufexists`.
        --
        _increment_terminal_uuid()

        return current
    end

    --- Bootstrap `toggleterminal` logic to an existing terminal `buffer`.
    ---
    --- @param buffer number A 0-or-more index pointing to some Vim data.
    ---
    local function _initialize_terminal_buffer(buffer)
        vim.bo[buffer].bufhidden = "hide"
        vim.b[buffer]._toggle_terminal_buffer = true
    end

    --- Set colors onto `window`.
    ---
    --- @param window number A 1-or-more value of some `toggleterminal` buffer.
    ---
    local function _apply_highlights(window)
        local namespace = "Normal"
        local window_namespace = "ToggleTerminalNormal"
        vim.api.nvim_set_hl(0, window_namespace, { bg = _DARKER_TERMINAL_COLOR })

        vim.api.nvim_set_option_value(
            "winhighlight",
            string.format("%s:%s", namespace, window_namespace),
            { scope = "local", win = window }
        )
    end

    --- @return _my.ToggleTerminal # Create a buffer from scratch.
    local function _create_terminal()
        vim.cmd("edit! " .. _suggest_name("term://bash"))

        local buffer = vim.fn.bufnr()
        _initialize_terminal_buffer(buffer)

        return { buffer = buffer, mode = _STARTING_MODE }
    end

    --- Change `buffer` to insert or normal mode.
    ---
    --- @param buffer number A 1-or-more index pointing to a `toggleterm` buffer.
    ---
    local function _handle_term_enter(buffer)
        local terminal = _BUFFER_TO_TERMINAL[buffer]
        local mode = terminal.mode

        if mode == _Mode.insert then
            vim.cmd.startinsert()
        elseif mode == _Mode.unknown then
            if _STARTING_MODE == _Mode.insert then
                vim.cmd.startinsert()
            end
        elseif mode == _Mode.normal then
            -- TODO: Double-check this part
            return
        end
    end

    --- Keep track of `buffer` mode so we can restore it as needed, later.
    ---
    --- @param buffer number A 1-or-more index pointing to a `toggleterm` buffer.
    ---
    local function _handle_term_leave(buffer)
        local raw_mode = vim.api.nvim_get_mode().mode
        local mode = _Mode.unknown

        if raw_mode:match("nt") then -- nt is normal mode in the terminal
            mode = _Mode.normal
        elseif raw_mode:match("t") then -- t is insert mode in the terminal
            mode = _Mode.insert
        end

        local terminal = _BUFFER_TO_TERMINAL[buffer]

        if terminal and mode then
            terminal.mode = mode
        end
    end

    --- Make a window (non-terminal) so we can assign a terminal into it later.
    local function _prepare_terminal_window()
        vim.cmd("set nosplitbelow")
        vim.cmd("split")
        vim.cmd("set splitbelow&") -- Restore the previous split setting
        vim.cmd.wincmd("J") -- Move the split to the bottom of the tab
        vim.cmd.resize(10)
    end

    local function _save_terminal_state(keys)
        return function()
            _handle_term_leave(vim.fn.bufnr())

            return keys
        end
    end

    --- Open an existing terminal for the current tab or create one if it doesn't exist.
    local function _toggle_terminal()
        local tab = vim.fn.tabpagenr()
        local existing_terminal = _TAB_TERMINALS[tab]

        if not existing_terminal or vim.fn.bufexists(existing_terminal.buffer) == 0 then
            _prepare_terminal_window()

            local terminal = _create_terminal()
            _TAB_TERMINALS[tab] = terminal
            _BUFFER_TO_TERMINAL[terminal.buffer] = _TAB_TERMINALS[tab]

            return
        end

        local terminal = _TAB_TERMINALS[tab]

        if _is_buffer_visible(terminal.buffer) then
            for _, window in ipairs(_get_buffer_windows(terminal.buffer)) do
                vim.api.nvim_win_close(window, false)
            end
        else
            _prepare_terminal_window()
            vim.cmd.buffer(terminal.buffer)
        end
    end

    --- Add Neovim `toggleterminal`-related autocommands.
    function _P.setup_autocommands()
        local group = vim.api.nvim_create_augroup("ToggleTerminalCommands", { clear = true })
        local toggleterm_pattern = { "term://*::toggleterminal::*" }

        vim.api.nvim_create_autocmd("BufEnter", {
            pattern = toggleterm_pattern,
            group = group,
            nested = true, -- This is necessary in case the buffer is the last
            callback = function()
                local buffer = vim.fn.bufnr()
                vim.schedule(function()
                    _handle_term_enter(buffer)
                end)
            end,
        })

        vim.api.nvim_create_autocmd("TermOpen", {
            group = group,
            pattern = toggleterm_pattern,
            callback = function()
                local window = vim.fn.win_getid()

                vim.wo[window].relativenumber = false
                vim.wo[window].number = false
                vim.wo[window].signcolumn = "no"

                vim.schedule(function()
                    _apply_highlights(window)
                end)
            end,
        })
    end

    --- Add command(s) for interacting with the terminals.
    function _P.setup_commands()
        vim.api.nvim_create_user_command(
            "ToggleTerminal",
            _toggle_terminal,
            { desc = "Open / Close a terminal at the bottom of the tab", nargs = 0 }
        )
    end

    _P.setup_autocommands()
    vim.keymap.set("n", "<space>T", _toggle_terminal)

    -- NOTE: Allow quick and easy movement out of a terminal buffer using just <C-hjkl>
    vim.keymap.set({ "n", "t" }, "<C-h>", _save_terminal_state("<C-\\><C-n><C-w>h"), {
        desc = "Move to the left of the terminal buffer.",
        expr = true,
        silent = true,
    })
    vim.keymap.set({ "n", "t" }, "<C-j>", _save_terminal_state("<C-\\><C-n><C-w>j"), {
        desc = "Move down to the buffer below the terminal buffer.",
        expr = true,
        silent = true,
    })
    vim.keymap.set({ "n", "t" }, "<C-k>", _save_terminal_state("<C-\\><C-n><C-w>k"), {
        desc = "Move up to the buffer above the terminal buffer.",
        expr = true,
        silent = true,
    })
    vim.keymap.set({ "n", "t" }, "<C-l>", _save_terminal_state("<C-\\><C-n><C-w>l"), {
        desc = "Move to the right of the terminal buffer.",
        expr = true,
        silent = true,
    })
end
