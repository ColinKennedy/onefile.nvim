local build_target = _G._onefile_build_git_selection_target

local function run_git(root, args)
    local command = { "git", "-C", root }
    vim.list_extend(command, args)

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
    vim.fn.delete(path, "rf")
end

local function edit_file(path, lines)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.endofline = true
end

describe("git selection target builder", function()
    it("selects only the middle of a larger hunk", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nTWO\nTHREE\nFOUR\n"
        local diff = [[
diff --git a/file b/file
@@ -2,3 +2,3 @@
-two
-three
-four
+TWO
+THREE
+FOUR
]]

        local partial, count = build_target(base, target, diff, 3, 3)

        assert.equal(1, count)
        assert.equal("one\ntwo\nTHREE\nfour\n", partial)
    end)

    it("selects one changed line while leaving nearby changes unstaged", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nTWO\nthree\nFOUR\n"
        local diff = [[
diff --git a/file b/file
@@ -2 +2 @@
-two
+TWO
@@ -4 +4 @@
-four
+FOUR
]]

        local partial, count = build_target(base, target, diff, 2, 2)

        assert.equal(1, count)
        assert.equal("one\nTWO\nthree\nfour\n", partial)
    end)

    it("selects added lines", function()
        local base = "one\nfour\n"
        local target = "one\ntwo\nthree\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -1,0 +2,2 @@
+two
+three
]]

        local partial, count = build_target(base, target, diff, 3, 3)

        assert.equal(1, count)
        assert.equal("one\nthree\nfour\n", partial)
    end)

    it("uses the gutter-style anchor for deletions", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +1,0 @@
-two
-three
]]

        local partial, count = build_target(base, target, diff, 1, 1)

        assert.equal(2, count)
        assert.equal("one\nfour\n", partial)
    end)

    it("keeps unselected extra removed lines in replacement hunks", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nTWO\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +2 @@
-two
-three
+TWO
]]

        local partial, count = build_target(base, target, diff, 2, 2)

        assert.equal(1, count)
        assert.equal("one\nTWO\nthree\nfour\n", partial)
    end)
end)

describe("git visual hunk selection commands", function()
    it("stages selected unsaved buffer lines into the index", function()
        local root = make_repo()

        local ok, err = pcall(function()
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
        assert(ok, err)
    end)

    it("resets selected staged lines while preserving the working tree", function()
        local root = make_repo()

        local ok, err = pcall(function()
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
        assert(ok, err)
    end)

    it("stages selected lines for paths containing spaces", function()
        local root = make_repo()

        local ok, err = pcall(function()
            local directory = vim.fs.joinpath(root, "dir with space")
            assert.equal(1, vim.fn.mkdir(directory, "p"))

            local relative = "dir with space/file name.txt"
            local path = vim.fs.joinpath(root, "dir with space", "file name.txt")
            write_text(path, "one\ntwo\nthree\nfour\n")
            run_git(root, { "add", relative })
            run_git(root, { "commit", "-m", "init" })

            edit_file(path, { "one", "TWO", "three", "FOUR" })
            vim.cmd("2,2GitStageSelection")

            local cached = run_git(root, { "diff", "--cached", "--unified=0", "--", relative })

            assert.matches("-two\n+TWO", cached, 1, true)
            assert.is_nil(cached:find("-four\n+FOUR", 1, true))
        end)

        remove_tree(root)
        assert(ok, err)
    end)
end)
