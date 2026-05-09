local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- This is a "poor man's https://github.com/folke/todo-comments.nvim".
    ---
    --- It highlights tagged inline comments with a unique color.

    ---@enum _my.ColorType A custom color alias (used to compute real colors later).
    _ColorType = {
        default = "default",
        error = "error",
        hint = "hint",
        info = "info",
        warning = "warning",
    }

    ---@class _my.comment.ColorOptions
    ---    A description of "what text to look for in inline-comments"
    ---    + details about how to style any matching comments.
    ---@field highlight_prefix string
    ---    A Vim-internal name used to make a color highlight group.
    ---@field match_texts string[]
    ---    All matching candidates. This could be a word or phrase.
    ---@field color _my.ColorType
    ---    A description of the color to display for any matching text.

    ---@class _my.comment.HighlightGroup
    ---    A Vim-internal highlight name for some `_my.comment.ColorOptions`.
    ---    This meant to be a minor "performance optimization"-related struct.
    ---@field match_highlight_name string
    ---    The Vim highlight group that controls the main inline comment tag.
    ---@field match_conceal_highlight_name string
    ---    An extension of `match_highlight_name` that obscures the `":"` character.
    ---@field text_highlight_name string
    ---    The rest of the inline comment is colored using this Vim highlight group.

    ---@type table<string, {links: string[], fallback: string}>
    _COLOR_TYPES = {
        default = { links = { "Identifier" }, fallback = "#7C3AED" },
        error = { links = { "DiagnosticError", "ErrorMsg" }, fallback = "#DC2626" },
        hint = { links = { "DiagnosticHint" }, fallback = "#10B981" },
        info = { links = { "DiagnosticInfo" }, fallback = "#2563EB" },
        warning = { links = { "DiagnosticWarn", "WarningMsg" }, fallback = "#FBBF24" },
    }

    _COMMENT_HIGHLIGHT = vim.api.nvim_create_namespace("my.comment.highlighter")

    ---@type _my.comment.ColorOptions[]
    _COMMENT_TYPES = {
        {
            highlight_prefix = "Fix",
            match_texts = { "FIX", "FIXME", "BUG", "IMPORTANT", "ISSUE" },
            color = _ColorType.error,
        },
        {
            highlight_prefix = "Note",
            match_texts = { "NOTE", "HINT", "INFO" },
            color = _ColorType.hint,
        },
        {
            highlight_prefix = "Perf",
            match_texts = { "PERF", "PERFORMANCE", "OPTIIM", "OPTIMIZE" },
            color = _ColorType.default,
        },
        {
            highlight_prefix = "Todo",
            match_texts = { "TODO" },
            color = _ColorType.info,
        },
        {
            highlight_prefix = "Warning",
            match_texts = { "WARNING", "WARN", "XXX" },
            color = _ColorType.warning,
        },
    }

    --- Parse `text` using `template`.
    ---
    ---@param text string Some inline comment text to check. e.g. `"# TODO: Foo bar."`.
    ---@param template string Some `vim.bo.commentstring` to match against. e.g. `"# %s"`.
    ---@return string? # The parsed text, if any.
    ---
    function _P.get_comment_from_template(text, template)
        local pattern = template:gsub("%%s", "(.+)")
        local matched = text:match(pattern)

        if matched then
            return matched
        end

        -- TODO: logging?
        -- error(string.format('Got "%s" text that we expected to mach "%s" template.', text, template))
        return nil
    end

    -- TODO: We could memoize the arg + result here.
    function _P.get_match_color(color)
        local color_details = _P.get_text_color(color)
        -- TODO: Check this highlight group later
        local background_details = vim.api.nvim_get_hl(0, { name = "Normal" })

        return { bg = color_details.fg, bold = true, fg = background_details.fg }
    end

    -- TODO: We could memoize the arg + result here.
    function _P.get_text_color(color)
        local data = _COLOR_TYPES[color] or _COLOR_TYPES.default

        for _, link in ipairs(data.links) do
            local status, result = pcall(vim.api.nvim_get_hl, 0, { name = link })

            if status then
                if result.bg then
                    return { fg = result.bg, bold = false }
                else
                    return { fg = result.fg, bold = false }
                end
            end
        end

        return { fg = data.fallback, bold = true }
    end

    --- Get the Vim highlighter that will be used for the comment prefix tag.
    ---
    ---@param text string The prefix name. e.g. "Todo".
    ---@return string # The full highlighter name. e.g. `"MyTodoHighlightMatch"`.
    ---
    function _P.get_match_foreground_highlight_name(text)
        return string.format("My%sHighlightMatch", text)
    end

    --- Get the Vim highlighter that will be used for the user's actual comment text.
    ---
    ---@param text string The prefix name. e.g. "Todo".
    ---@return string # The full highlighter name. e.g. `"MyTodoHighlightText"`.
    ---
    function _P.get_text_foreground_highlight_name(text)
        return string.format("My%sHighlightText", text)
    end

    ---@type table<string, _my.comment.HighlightGroup>
    _COMMENT_MATCHES = {}

    for _, group in ipairs(_COMMENT_TYPES) do
        local text_highlight_name = _P.get_text_foreground_highlight_name(group.highlight_prefix)
        local match_highlight_name = _P.get_match_foreground_highlight_name(group.highlight_prefix)
        local match_conceal_highlight_name = match_highlight_name .. "Conceal"

        local match_color = _P.get_match_color(group.color)
        local match_conceal_color = { bg = match_color.bg, fg = match_color.bg, bold = true }

        vim.api.nvim_set_hl(0, text_highlight_name, _P.get_text_color(group.color))
        vim.api.nvim_set_hl(0, match_highlight_name, match_color)
        vim.api.nvim_set_hl(0, match_conceal_highlight_name, match_conceal_color)

        -- NOTE: We precompute the table just to make future lookups faster
        for _, text in ipairs(group.match_texts) do
            _COMMENT_MATCHES[text] = {
                match_highlight_name = match_highlight_name,
                match_conceal_highlight_name = match_conceal_highlight_name,
                text_highlight_name = text_highlight_name,
            }
        end
    end

    --- Check for the last inline comment line, of `lines`, starting from `start`.
    ---
    ---@param start integer The first line to check from, inclusive.
    ---@param lines string[] The source code lines to check for more comments.
    ---@return integer # The last comment line. If none are found, `start` is returned.
    ---
    function _P.get_end_line(start, lines)
        -- TODO: Add support for this later
        return start
    end

    --- Highlight the line that matched a "tagged" inline comment.
    ---
    ---@param buffer integer
    ---    The Vim buffer to highlight.
    ---@param highlight_groups _my.comment.HighlightGroup
    ---    A Vim highlight groups to apply to each text region.
    ---@param line integer
    ---    The text row to highlight (0-or-more number).
    ---@param columns _my.comment._TagColumns
    ---    The colume range data that we need to highlight the tag properly.
    ---
    function _P.highlight_matching_line(buffer, highlight_groups, line, columns)
        local priority = 200
        local match_end_column = columns.tag_text.last - 1

        -- "NOTE: This highlights the tag prefix.
        vim.api.nvim_buf_set_extmark(buffer, _COMMENT_HIGHLIGHT, line, columns.tag_text.first, {
            end_col = match_end_column,
            hl_group = highlight_groups.match_highlight_name,
            priority = priority,
        })

        -- NOTE: This conceals any language-related syntax surrounding the tag prefix.
        -- vim.api.nvim_buf_set_extmark(buffer, _COMMENT_HIGHLIGHT, line, columns.tag_text.first, {
        --     end_col = columns.tag_text.last,
        --     hl_group = highlight_groups.match_conceal_highlight_name,
        --     priority = priority,
        -- })
        vim.api.nvim_buf_set_extmark(buffer, _COMMENT_HIGHLIGHT, line, match_end_column, {
            end_col = columns.tag_text.last,
            hl_group = highlight_groups.match_conceal_highlight_name,
            priority = priority,
        })

        -- NOTE: This highlights the actual comment (the text that comes after the tag).
        vim.api.nvim_buf_set_extmark(buffer, _COMMENT_HIGHLIGHT, line, columns.tag_text.first, {
            end_col = columns.tag_text.last,
            hl_group = highlight_groups.text_highlight_name,
            priority = priority,
        })
    end

    -- TODO: Add support for this later
    function _P.highlight_other_lines(buffer, highlight_name, start_line, end_line, lines)
        local current = start_line

        while current < end_line do
        end
    end

    -- TODO: Remove this later?
    -- function _P.iter_comment_lines(buffer)
    --     local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    --     local commentstring = vim.bo.commentstring
    --     local index = 0
    --     local count = #lines
    --
    --     return function()  -- Iterator function
    --         while index < count do
    --         end
    --             index = index + 1
    --             local raw_line = lines[index]
    --             local line = _P.get_comment_from_template(raw_line, commentstring)
    --
    --             if not line
    --
    --             -- Create and return a _LineMatch object with raw_line, line, and index
    --             local line_match = {_LineMatch}
    --             line_match.raw_line = raw_line
    --             line_match.line = line
    --             line_match.index = index
    --
    --             return line_match
    --         end
    --     end
    -- end

    --- Use standard Lua regex to find and highlight all inline comments.
    ---
    ---@param buffer integer A Vim buffer to highlight.
    ---
    function _P.highlight_using_vim_commentstring_regex(buffer)
        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        local commentstring = vim.bo.commentstring
        local index = 0
        local count = #lines

        while index < count do
            index = index + 1
            local raw_line = lines[index]
            local line = _P.get_comment_from_template(raw_line, commentstring) or ""

            for match_text, highlight_groups in pairs(_COMMENT_MATCHES) do
                local start_match, end_match = string.find(line, vim.pesc(match_text) .. "%s*:")

                if start_match then
                    local start_column = start_match - 1
                    local match_end_column = start_column + (end_match - start_match) + 2
                    local end_line = _P.get_end_line(index, lines)

                    _P.highlight_matching_line(buffer, highlight_groups, index - 1, {
                        tag_text = { first = start_column, last = match_end_column },
                        tag_bounds = { first = start_column, last = match_end_column },
                        comment_text = { first = match_end_column, last = #lines[end_line] },
                    })

                    _P.highlight_other_lines(buffer, highlight_groups.text_highlight_name, index + 1, end_line, lines)

                    index = end_line

                    break
                end
            end
        end
    end

    --- Use tree-sitter to find and highlight all inline comments.
    ---
    ---@param buffer integer A Vim buffer to highlight.
    ---@param tree TSTree The parsed tree-sitter graph.
    ---
    function _highlight_using_neovim_treesitter(buffer, tree)
        error("TODO: add support for _highlight_using_neovim_treesitter later")
    end

    --- Highlight all inline comments that start with some known tag. e.g. `"NOTE"`.
    ---
    --- We use tree-sitter to find the comments if we can. And use regex if we can't.
    ---
    function _highlight_comments()
        local buffer = vim.api.nvim_get_current_buf()
        local status, parser = pcall(function()
            vim.treesitter.get_parser(buffer)
        end)

        vim.api.nvim_buf_clear_namespace(0, _COMMENT_HIGHLIGHT, 0, -1)
        local buffer = vim.api.nvim_get_current_buf()

        if not status or not parser then
            _P.highlight_using_vim_commentstring_regex(buffer)

            return
        end

        _highlight_using_neovim_treesitter(buffer, parser:parse()[1])
    end

    --- Only highlight a buffer's text if needed.
    function _highlight_comments_if_needed()
        if vim.bo.buftype == "terminal" then
            -- NOTE: terminals don't need these kind of highlights, ever.
            return
        end

        _highlight_comments()
    end

    -- TODO: This code doesn't work. Fix it later.
    -- vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufWritePost", "TextChanged", "TextChangedI" }, {
    --     -- TODO: Fix this later. It's broken. The colors are often wrong and don't apply correctly
    --     callback = _P.debounce_trailing(_highlight_comments_if_needed, 300),
    -- })
    --
    -- vim.schedule(_highlight_comments_if_needed)
end)
