local _P = {}
local core_editor_setup = require("modules.features.core_editor_setup")
local core_helpers = require("modules.utilities.core_helpers")

--- Search Neovim's :help, quickly and easily
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
            found_language = core_helpers._ENGLISH_LANGUAGE
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
            assert(not error_open, error_open)

            if not handler then
                error(string.format('Path "%s" could be opened.', path), 0)
            end

            vim.uv.fs_fstat(handler, function(error_stat, stat)
                assert(not error_stat, error_stat)

                if not stat then
                    error(string.format('Path "%s" could not be stat.', path), 0)
                end

                vim.uv.fs_read(handler, stat.size, 0, function(error_read, data)
                    assert(not error_read, error_read)

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

    local search_paths = core_helpers.get_helptag_search_paths()
    local tag_paths = _P.get_tag_files(search_paths)

    ---@type string[]
    local options = {}

    for _, path in ipairs(tag_paths[core_helpers._ENGLISH_LANGUAGE]) do
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

    core_editor_setup.select_from_options(options, {
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
