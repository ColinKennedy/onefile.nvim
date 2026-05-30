--- Run a Git command inside `root`.
---
---@param root string The Git repository root.
---@param arguments string[] The Git arguments to run after `-C root`.
---@return string # The command's standard output.
local function run_git(root, arguments)
    vim.wait(120)

    ---@type string[]
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

--- Write exact text to `path`.
---
---@param path string The path to write.
---@param text string The text contents to write.
local function write_text(path, text)
    local file = assert(vim.uv.fs_open(path, "w", 438))
    assert(vim.uv.fs_write(file, text, 0))
    vim.uv.fs_close(file)
end

--- Create a temporary Git repository for integration tests.
---
---@return string # The temporary repository root.
local function make_repo()
    local root = vim.fn.tempname()
    assert.equal(1, vim.fn.mkdir(root, "p"))

    local result = vim.system({ "git", "-C", root, "init" }, { text = true }):wait()
    assert.equal(0, result.code, result.stderr)

    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    return root
end

--- Remove a temporary test directory after leaving its buffer.
---
---@param path string The directory to remove.
local function remove_tree(path)
    vim.cmd("enew!")
    vim.wait(20)
    vim.fn.delete(path, "rf")
end

--- Edit `path` in the current Neovim session and replace its lines.
---
---@param path string The file path to edit.
---@param lines string[] The buffer lines to set.
local function edit_file(path, lines)
    vim.cmd("silent edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.endofline = true
end

--- Press normal-mode keys and execute their mapping.
---
---@param keys string The key sequence to press.
local function press_normal_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    vim.wait(250)
end

--- Capture notifications while `callback` runs and replay them only on failure.
---
---@param callback fun(): nil The test body to run quietly.
local function with_captured_notifications(callback)
    local notify = vim.notify
    ---@type string[]
    local messages = {}

    rawset(vim, "notify", function(message, _level, _options)
        table.insert(messages, tostring(message))

        return nil
    end)

    local ok, err = pcall(callback)
    rawset(vim, "notify", notify)

    if not ok then
        for _, message in ipairs(messages) do
            notify(message)
        end
    end

    assert(ok, err)
end

--- Get the currently placed git-gutter sign lines.
---
---@return integer[] # The sorted sign line numbers.
local function get_gutter_lines()
    vim.wait(250)

    local placed = vim.fn.sign_getplaced(vim.api.nvim_get_current_buf(), { group = "my.git_gutter" })
    local signs = placed[1] and placed[1].signs or {}
    ---@type string[]
    local lines = {}

    for _, sign in ipairs(signs) do
        table.insert(lines, sign.lnum)
    end

    table.sort(lines)

    return lines
end

describe("git visual hunk selection commands", function()
    it("stages selected unsaved buffer lines into the index", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "three", "FOUR" })
            vim.cmd("2,2GitStageSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.matches("-two\n+TWO", cached, 1, true)
            assert.is_nil(cached:find("-four\n+FOUR", 1, true))
            assert.equal("one\nTWO\nthree\nFOUR", buffer_text)
        end)

        remove_tree(root)
    end)

    it("resets selected staged lines while preserving the working tree", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "one\nTWO\nthree\nFOUR\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "one", "TWO", "three", "FOUR" })
            vim.cmd("2,2GitResetSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local worktree = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.is_nil(cached:find("-two\n+TWO", 1, true))
            assert.matches("-four\n+FOUR", cached, 1, true)
            assert.equal("one\nTWO\nthree\nFOUR", worktree)
        end)

        remove_tree(root)
    end)

    it("stages deleted lines from the visible deletion sign line", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "four" })
            vim.cmd("2,2GitStageSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.matches("-two\n-three", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("stages deleted lines from the line above the deletion", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "four" })
            vim.cmd("1,1GitStageSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.matches("-two\n-three", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("resets staged deleted lines from the visible deletion sign line", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "one\nfour\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "one", "four" })
            vim.cmd("2,2GitResetSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.equal("", cached)
        end)

        remove_tree(root)
    end)

    it("stages multiple selected hunks from one visual range", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\nfive\nsix\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "three", "four", "FIVE", "six" })
            vim.cmd("2,5GitStageSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.matches("-two\n+TWO", cached, 1, true)
            assert.matches("-five\n+FIVE", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("checks out selected unstaged buffer lines from the index", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "THREE", "four" })
            vim.cmd("2,2GitCheckoutSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.equal("", cached)
            assert.equal("one\ntwo\nTHREE\nfour", buffer_text)
        end)

        remove_tree(root)
    end)

    it("does not check out already-staged selected lines", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "one\nTWO\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "one", "TWO", "THREE", "four" })
            vim.cmd("2,3GitCheckoutSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.matches("-two\n+TWO", cached, 1, true)
            assert.equal("one\nTWO\nthree\nfour", buffer_text)
        end)

        remove_tree(root)
    end)

    it("checks out selected deleted lines from the visible deletion sign line", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "four" })
            vim.cmd("2,2GitCheckoutSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.equal("", cached)
            assert.equal("one\ntwo\nthree\nfour", buffer_text)
        end)

        remove_tree(root)
    end)

    it("checks out multiple selected hunks from one visual range", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\nfive\nsix\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "three", "four", "FIVE", "six" })
            vim.cmd("2,5GitCheckoutSelection")
            vim.wait(250)

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.equal("", cached)
            assert.equal("one\ntwo\nthree\nfour\nfive\nsix", buffer_text)
        end)

        remove_tree(root)
    end)

    it("stages the closest hunk from normal mode", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\nfive\nsix\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "three", "four", "FIVE", "six" })
            vim.api.nvim_win_set_cursor(0, { 4, 0 })
            press_normal_keys(",gah")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.is_nil(cached:find("-two\n+TWO", 1, true))
            assert.matches("-five\n+FIVE", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("resets the closest hunk from normal mode", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\nfive\nsix\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "one\nTWO\nthree\nfour\nFIVE\nsix\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "one", "TWO", "three", "four", "FIVE", "six" })
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            press_normal_keys(",grh")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.is_nil(cached:find("-two\n+TWO", 1, true))
            assert.matches("-five\n+FIVE", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("checks out the closest hunk from normal mode", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\nfive\nsix\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "one\nTWO\nthree\nfour\nfive\nsix\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "one", "TWO", "three", "four", "FIVE", "six" })
            vim.api.nvim_win_set_cursor(0, { 4, 0 })
            press_normal_keys(",gch")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.matches("-two\n+TWO", cached, 1, true)
            assert.equal("one\nTWO\nthree\nfour\nfive\nsix", buffer_text)
        end)

        remove_tree(root)
    end)

    it("stages the closest deleted hunk from normal mode", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "four" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            press_normal_keys(",gah")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.matches("-two\n-three", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("refreshes gutter signs after staging selected unsaved lines", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "three", "FOUR" })
            require("modules.features.git_gutter").update(0)

            assert.are.same({ 2, 4 }, get_gutter_lines())

            vim.cmd("2,2GitStageSelection")
            vim.wait(250)

            assert.are.same({ 4 }, get_gutter_lines())
        end)

        remove_tree(root)
    end)

    it("refreshes gutter signs after resetting selected staged lines", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "one\nTWO\nthree\nFOUR\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "one", "TWO", "three", "FOUR" })
            require("modules.features.git_gutter").update(0)

            assert.are.same({}, get_gutter_lines())

            vim.cmd("2,2GitResetSelection")
            vim.wait(250)

            assert.are.same({ 2 }, get_gutter_lines())
        end)

        remove_tree(root)
    end)

    it("stages the entire unsaved current buffer", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "ONE", "two", "THREE" })
            press_normal_keys(",gac")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.matches("-one\n+ONE", cached, 1, true)
            assert.matches("-three\n+THREE", cached, 1, true)
        end)

        remove_tree(root)
    end)

    it("stages a resolved conflicted current buffer", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "README.md")
            write_text(path, "title\nshared\n")
            run_git(root, { "add", "README.md" })
            run_git(root, { "commit", "-m", "init" })
            run_git(root, { "branch", "feature" })

            write_text(path, "title\nmain change\n")
            run_git(root, { "add", "README.md" })
            run_git(root, { "commit", "-m", "main change" })
            run_git(root, { "checkout", "feature" })
            write_text(path, "title\nfeature change\n")
            run_git(root, { "add", "README.md" })
            run_git(root, { "commit", "-m", "feature change" })

            local merge = vim.system({ "git", "-C", root, "merge", "master" }, { text = true }):wait()
            assert.is_true(merge.code ~= 0)
            assert.matches("README.md", run_git(root, { "diff", "--name-only", "--diff-filter=U" }), 1, true)

            edit_file(path, { "title", "resolved change" })
            press_normal_keys(",gac")

            assert.equal("", run_git(root, { "ls-files", "-u", "--", "README.md" }))
            assert.equal("title\nresolved change\n", run_git(root, { "show", ":README.md" }))
        end)

        remove_tree(root)
    end)

    it("resets the entire current file from the index", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(path, "ONE\ntwo\nTHREE\n")
            run_git(root, { "add", "file.txt" })
            edit_file(path, { "ONE", "two", "THREE" })
            press_normal_keys(",grc")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })
            local buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            assert.equal("", cached)
            assert.equal("ONE\ntwo\nTHREE", buffer_text)
        end)

        remove_tree(root)
    end)
end)
