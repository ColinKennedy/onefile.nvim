package.path = "lua/?.lua;" .. package.path

local git_diff = require("modules.utilities.git_diff")

describe("modules.utilities.git_diff", function()
    it("reports add, change, and delete hunks", function()
        local hunks = git_diff.compute_hunks({ "one", "two", "three", "four" }, {
            "one",
            "TWO",
            "three",
            "added",
            "four",
        })

        assert.are.same({
            {
                line = 2,
                new_count = 1,
                new_start = 2,
                old_count = 1,
                old_start = 2,
                type = "change",
            },
            {
                line = 4,
                new_count = 1,
                new_start = 4,
                old_count = 0,
                old_start = 4,
                type = "add",
            },
        }, hunks)
    end)

    it("anchors delete hunks on the following buffer line", function()
        local hunks = git_diff.compute_hunks({ "one", "deleted", "two" }, { "one", "two" })

        assert.are.same({
            {
                line = 2,
                new_count = 0,
                new_start = 2,
                old_count = 1,
                old_start = 2,
                type = "delete",
            },
        }, hunks)
    end)

    it("does not report hunks for trailing carriage-return-only differences", function()
        local hunks = git_diff.compute_hunks({
            "foo_bar_baz    -> civquux -> foo_quux_baz",
            "QUUX_SPAM      -> civLOTS_OF -> LOTS_OF_SPAM",
        }, {
            "foo_bar_baz    -> civquux -> foo_quux_baz\r",
            "QUUX_SPAM      -> civLOTS_OF -> LOTS_OF_SPAM\r",
        })

        assert.are.same({}, hunks)
    end)

    it("builds a selected target for the middle of a larger hunk", function()
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

        local partial, count = git_diff.build_selection_target(base, target, diff, 3, 3)

        assert.equal(1, count)
        assert.equal("one\ntwo\nTHREE\nfour\n", partial)
    end)

    it("builds a selected target for one changed line near another change", function()
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

        local partial, count = git_diff.build_selection_target(base, target, diff, 2, 2)

        assert.equal(1, count)
        assert.equal("one\nTWO\nthree\nfour\n", partial)
    end)

    it("builds a selected target for added lines", function()
        local base = "one\nfour\n"
        local target = "one\ntwo\nthree\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -1,0 +2,2 @@
+two
+three
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 3, 3)

        assert.equal(1, count)
        assert.equal("one\nthree\nfour\n", partial)
    end)

    it("uses the gutter-style anchor for deleted lines", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +1,0 @@
-two
-three
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 1, 1)

        assert.equal(2, count)
        assert.equal("one\nfour\n", partial)
    end)

    it("selects deleted lines from the visible sign line", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +1,0 @@
-two
-three
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 2, 2)

        assert.equal(2, count)
        assert.equal("one\nfour\n", partial)
    end)

    it("selects deleted lines from a range spanning the deleted hunk", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +1,0 @@
-two
-three
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 1, 2)

        assert.equal(2, count)
        assert.equal("one\nfour\n", partial)
    end)

    it("selects changed lines across multiple hunks", function()
        local base = "one\ntwo\nthree\nfour\nfive\nsix\n"
        local target = "one\nTWO\nthree\nfour\nFIVE\nsix\n"
        local diff = [[
diff --git a/file b/file
@@ -2 +2 @@
-two
+TWO
@@ -5 +5 @@
-five
+FIVE
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 2, 5)

        assert.equal(2, count)
        assert.equal("one\nTWO\nthree\nfour\nFIVE\nsix\n", partial)
    end)

    it("selects partial hunks across a visual range", function()
        local base = "one\ntwo\nthree\nfour\nfive\n"
        local target = "one\nTWO\nTHREE\nfour\nFIVE\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +2,2 @@
-two
-three
+TWO
+THREE
@@ -5 +5 @@
-five
+FIVE
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 3, 5)

        assert.equal(2, count)
        assert.equal("one\ntwo\nTHREE\nfour\nFIVE\n", partial)
    end)

    it("keeps unselected removed lines in replacement hunks", function()
        local base = "one\ntwo\nthree\nfour\n"
        local target = "one\nTWO\nfour\n"
        local diff = [[
diff --git a/file b/file
@@ -2,2 +2 @@
-two
-three
+TWO
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 2, 2)

        assert.equal(1, count)
        assert.equal("one\nTWO\nthree\nfour\n", partial)
    end)

    it("counts no changes when the selection misses the hunk", function()
        local base = "one\ntwo\n"
        local target = "one\nTWO\n"
        local diff = [[
diff --git a/file b/file
@@ -2 +2 @@
-two
+TWO
]]

        local partial, count = git_diff.build_selection_target(base, target, diff, 1, 1)

        assert.equal(0, count)
        assert.equal("one\ntwo\n", partial)
    end)

    it("coalesces and caches file-detail lookups until the buffer is renamed", function()
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buffer, "/tmp/git-details-cache-" .. buffer .. ".txt")

        local original_run_git = git_diff.run_git
        local calls = {}
        ---@type _my.git_diff.FileDetails[]
        local received = {}

        rawset(git_diff, "run_git", function(arguments, directory, stdin, callback)
            table.insert(calls, { arguments = arguments, callback = callback, directory = directory, stdin = stdin })
        end)

        local ok, err = pcall(function()
            git_diff.get_file_details(buffer, function(details)
                details = assert(details)
                table.insert(received, details)
            end)
            git_diff.get_file_details(buffer, function(details)
                details = assert(details)
                table.insert(received, details)
            end)

            assert.equal(1, #calls)
            calls[1].callback({ code = 0, stderr = "", stdout = "/tmp/repository\n" })
            assert.equal(2, #calls)
            calls[2].callback({ code = 0, stderr = "", stdout = "file.txt\n" })

            assert.equal(2, #received)
            assert.equal("file.txt", received[1].relative_path)

            git_diff.get_file_details(buffer, function(details)
                details = assert(details)
                table.insert(received, details)
            end)
            assert.equal(2, #calls)
            assert.equal(3, #received)

            git_diff.invalidate_file_details(buffer)
            git_diff.get_file_details(buffer, function() end)
            assert.equal(3, #calls)
        end)

        rawset(git_diff, "run_git", original_run_git)
        vim.api.nvim_buf_delete(buffer, { force = true })

        if not ok then
            error(err)
        end
    end)

    it("caches current-buffer file details by the resolved buffer handle", function()
        local first = vim.api.nvim_create_buf(false, true)
        local second = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(first, "/tmp/git-current-buffer-cache-first.txt")
        vim.api.nvim_buf_set_name(second, "/tmp/git-current-buffer-cache-second.txt")

        local original_run_git = git_diff.run_git
        local calls = 0
        rawset(git_diff, "run_git", function(arguments, _, _, callback)
            calls = calls + 1

            if arguments[4] == "rev-parse" then
                callback({ code = 0, stderr = "", stdout = "/tmp/repository\n" })

                return
            end

            callback({
                code = 0,
                stderr = "",
                stdout = vim.fs.basename(arguments[#arguments]) .. "\n",
            })
        end)

        local ok, err = pcall(function()
            vim.api.nvim_set_current_buf(first)
            local first_details
            git_diff.get_file_details(0, function(details)
                first_details = details
            end)

            vim.api.nvim_set_current_buf(second)
            local second_details
            git_diff.get_file_details(0, function(details)
                second_details = details
            end)

            assert.equal("git-current-buffer-cache-first.txt", assert(first_details).relative_path)
            assert.equal("git-current-buffer-cache-second.txt", assert(second_details).relative_path)
            assert.equal(4, calls)

            vim.api.nvim_set_current_buf(first)
            git_diff.get_file_details(0, function() end)
            assert.equal(4, calls)
        end)

        rawset(git_diff, "run_git", original_run_git)
        vim.cmd("silent enew!")
        vim.api.nvim_buf_delete(first, { force = true })
        vim.api.nvim_buf_delete(second, { force = true })

        if not ok then
            error(err)
        end
    end)

    it("coalesces index reads and fetches again after an index mutation", function()
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buffer, "/tmp/git-index-cache-" .. buffer .. ".txt")

        local original_run_git = git_diff.run_git
        ---@type _my.git_diff.FileDetails?
        local details

        rawset(git_diff, "run_git", function(arguments, _, _, callback)
            local stdout = arguments[4] == "rev-parse" and "/tmp/repository\n" or "file.txt\n"
            callback({ code = 0, stderr = "", stdout = stdout })
        end)
        git_diff.get_file_details(buffer, function(found)
            details = found
        end)
        details = assert(details)

        local calls = {}
        local received = {}
        rawset(git_diff, "run_git", function(arguments, directory, stdin, callback)
            table.insert(calls, { arguments = arguments, callback = callback, directory = directory, stdin = stdin })
        end)

        local ok, err = pcall(function()
            git_diff.get_index_lines(details, function(lines)
                table.insert(received, lines)
            end)
            git_diff.get_index_lines(details, function(lines)
                table.insert(received, lines)
            end)

            assert.equal(1, #calls)
            calls[1].callback({ code = 0, stderr = "", stdout = "one\ntwo\n" })
            assert.are.same({ { "one", "two" }, { "one", "two" } }, received)

            git_diff.get_index_lines(details, function(lines)
                table.insert(received, lines)
            end)
            assert.equal(1, #calls)
            assert.equal(3, #received)

            git_diff.invalidate_index_lines(buffer)
            git_diff.get_index_lines(details, function() end)
            assert.equal(2, #calls)
        end)

        rawset(git_diff, "run_git", original_run_git)
        vim.api.nvim_buf_delete(buffer, { force = true })

        if not ok then
            error(err)
        end
    end)

    it("applies a cached patch with one mutating Git command", function()
        local original_run_git = git_diff.run_git
        local calls = {}
        local success

        rawset(git_diff, "run_git", function(arguments, directory, stdin, callback)
            table.insert(calls, { arguments = arguments, directory = directory, stdin = stdin })
            callback({ code = 0, stderr = "", stdout = "" })
        end)

        local ok, err = pcall(function()
            git_diff.apply_cached_patch(
                {
                    absolute_path = "/tmp/repository/file.txt",
                    relative_path = "file.txt",
                    repository = "/tmp/repository",
                },
                "patch text",
                function(applied)
                    success = applied
                end
            )

            assert.is_true(success)
            assert.equal(1, #calls)
            assert.are.same({ "-C", "/tmp/repository", "apply", "--cached" }, vim.list_slice(calls[1].arguments, 1, 4))
        end)

        rawset(git_diff, "run_git", original_run_git)

        if not ok then
            error(err)
        end
    end)
end)
