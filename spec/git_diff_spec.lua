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
end)
