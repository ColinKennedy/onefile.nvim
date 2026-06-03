local core_helpers = require("modules.utilities.core_helpers")
local file_tree = require("modules.plugins.file_tree")

local function run_git(root, arguments)
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

local function write_text(path, text)
    assert.equal(1, vim.fn.mkdir(vim.fs.dirname(path), "p"))

    local file = assert(vim.uv.fs_open(path, "w", 438))
    assert(vim.uv.fs_write(file, text, 0))
    assert(vim.uv.fs_close(file))
end

local function make_repository()
    local root = vim.fn.tempname()

    assert.equal(1, vim.fn.mkdir(root, "p"))
    run_git(root, { "init" })
    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    write_text(vim.fs.joinpath(root, ".gitignore"), "*.log\n")
    write_text(vim.fs.joinpath(root, "src", "main.py"), "print('hello')\n")
    write_text(vim.fs.joinpath(root, "notes.md"), "# Notes\n")
    write_text(vim.fs.joinpath(root, "ignored.log"), "ignored\n")
    run_git(root, { "add", ".gitignore", "src/main.py" })

    return root
end

local function names(rows)
    local output = {}

    for _, row in ipairs(rows) do
        table.insert(output, row.name)
    end

    return output
end

local function close_file_tree_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if vim.bo[buffer].filetype == "filetree" then
            vim.api.nvim_win_close(window, true)
        end
    end
end

describe("file tree", function()
    local original_nerdfont_allowed

    before_each(function()
        original_nerdfont_allowed = core_helpers.IS_NERDFONT_ALLOWED
        close_file_tree_windows()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        core_helpers.IS_NERDFONT_ALLOWED = original_nerdfont_allowed
        close_file_tree_windows()
        vim.cmd.enew({ bang = true })
    end)

    it("shows Git-visible files by default", function()
        local root = make_repository()
        local rows = file_tree._P.build_rows(root, false, { [vim.fs.normalize(root)] = true })

        assert.are.same({ "src", ".gitignore", "notes.md" }, names(rows))
        vim.fn.delete(root, "rf")
    end)

    it("can show ignored files when show-all is enabled", function()
        local root = make_repository()
        local rows = file_tree._P.build_rows(root, true, { [vim.fs.normalize(root)] = true })

        assert.are.same({ "src", ".gitignore", "ignored.log", "notes.md" }, names(rows))
        vim.fn.delete(root, "rf")
    end)

    it("expands and collapses directories", function()
        local root = make_repository()
        local expanded = { [vim.fs.normalize(root)] = true }
        local collapsed_rows = file_tree._P.build_rows(root, false, expanded)

        assert.are.same({ "src", ".gitignore", "notes.md" }, names(collapsed_rows))

        expanded[vim.fs.normalize(vim.fs.joinpath(root, "src"))] = true

        local expanded_rows = file_tree._P.build_rows(root, false, expanded)

        assert.are.same({ "src", "main.py", ".gitignore", "notes.md" }, names(expanded_rows))
        vim.fn.delete(root, "rf")
    end)

    it("uses ASCII icons when Nerd Font icons are disabled", function()
        local root = make_repository()

        core_helpers.IS_NERDFONT_ALLOWED = false

        assert.equal("D", file_tree._P.get_icon(vim.fs.joinpath(root, "src")))
        assert.equal("F", file_tree._P.get_icon(vim.fs.joinpath(root, "src", "main.py")))
        vim.fn.delete(root, "rf")
    end)

    it("uses a Python file icon when Nerd Font icons are enabled", function()
        local root = make_repository()

        core_helpers.IS_NERDFONT_ALLOWED = true

        assert.is_false(file_tree._P.get_icon(vim.fs.joinpath(root, "src", "main.py")) == "F")
        vim.fn.delete(root, "rf")
    end)

    it("opens selected files in the source window", function()
        local root = make_repository()
        local source_window = vim.api.nvim_get_current_win()

        file_tree.open(root)

        local tree_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(tree_window, { 1, 0 })
        file_tree.expand()
        vim.api.nvim_win_set_cursor(tree_window, { 2, 0 })
        core_helpers.with_file_messages_suppressed(function()
            file_tree.open_entry()
        end)

        assert.equal(source_window, vim.api.nvim_get_current_win())
        assert.equal(
            vim.fs.normalize(vim.fs.joinpath(root, "src", "main.py")),
            vim.fs.normalize(vim.api.nvim_buf_get_name(0))
        )
        vim.fn.delete(root, "rf")
    end)

    it("expands and collapses all directories under the current row", function()
        local root = make_repository()
        write_text(vim.fs.joinpath(root, "src", "package", "util.py"), "print('util')\n")
        run_git(root, { "add", "src/package/util.py" })

        file_tree.open(root)

        file_tree.expand_all()

        assert.is_not_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("util%.py"))

        file_tree.collapse_all()

        assert.is_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("main%.py"))
        assert.is_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("util%.py"))
        vim.fn.delete(root, "rf")
    end)

    it("sets winfixbuf on the file tree window", function()
        local root = make_repository()

        file_tree.open(root)

        assert.True(vim.wo[vim.api.nvim_get_current_win()].winfixbuf)
        vim.fn.delete(root, "rf")
    end)

    it("opens selected files in the most recent non-tree window", function()
        local root = make_repository()
        local first_window = vim.api.nvim_get_current_win()

        file_tree.open(root)
        vim.api.nvim_set_current_win(first_window)
        vim.cmd.vsplit()

        local second_window = vim.api.nvim_get_current_win()

        file_tree.toggle()

        local tree_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(tree_window, { 1, 0 })
        file_tree.expand()
        vim.api.nvim_win_set_cursor(tree_window, { 2, 0 })
        core_helpers.with_file_messages_suppressed(function()
            file_tree.open_entry()
        end)

        assert.equal(second_window, vim.api.nvim_get_current_win())
        assert.equal(
            vim.fs.normalize(vim.fs.joinpath(root, "src", "main.py")),
            vim.fs.normalize(vim.api.nvim_buf_get_name(0))
        )
        vim.fn.delete(root, "rf")
    end)

    it("registers buffer-local navigation and show-all mappings", function()
        local root = make_repository()

        file_tree.open(root)

        for _, key in ipairs({ "h", "l", "H", "L", "<CR>", "<leader>sa" }) do
            local mapping = vim.fn.maparg(key, "n", false, true)

            assert.is_function(mapping.callback)
        end

        vim.fn.delete(root, "rf")
    end)

    it("toggles showing ignored files from the tree buffer", function()
        local root = make_repository()

        file_tree.open(root)

        assert.is_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("ignored%.log"))

        local mapping = vim.fn.maparg("<leader>sa", "n", false, true)
        mapping.callback()

        assert.is_not_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("ignored%.log"))
        vim.fn.delete(root, "rf")
    end)

    it("registers a toggle mapping", function()
        local mapping = vim.fn.maparg("<Space>F", "n", false, true)

        assert.is_function(mapping.callback)
        assert.equal("Toggle/Show the [f]ile tree.", mapping.desc)
    end)
end)
