local function run_git(root, arguments)
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

local function write_text(path, text)
    local file = assert(vim.uv.fs_open(path, "w", 438))
    assert(vim.uv.fs_write(file, text, 0))
    vim.uv.fs_close(file)
end

local function make_repo()
    local root = vim.fn.tempname()
    assert.equal(1, vim.fn.mkdir(root, "p"))

    local result = vim.system({ "git", "-C", root, "init" }, { text = true }):wait()
    assert.equal(0, result.code, result.stderr)

    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    return root
end

local function remove_tree(path)
    vim.cmd("enew!")
    vim.wait(20)
    vim.fn.delete(path, "rf")
end

local function edit_file(path, lines)
    vim.cmd("silent edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.endofline = true
end

local function with_captured_notifications(callback)
    local notify = vim.notify
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

local function get_gutter_lines()
    local placed = vim.fn.sign_getplaced(vim.api.nvim_get_current_buf(), { group = "my.git_gutter" })
    local signs = placed[1] and placed[1].signs or {}
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

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", "file.txt" })

            assert.matches("-two\n+TWO", cached, 1, true)
            assert.matches("-five\n+FIVE", cached, 1, true)
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

            assert.are.same({ 2 }, get_gutter_lines())
        end)

        remove_tree(root)
    end)
end)
