describe("git gutter diff parser", function()
    local parse = _G._onefile_parse_git_gutter_diff

    it("finds added lines", function()
        assert.same(
            {
                { kind = "add", line = 2 },
                { kind = "add", line = 3 },
            },
            parse([[
diff --git a/file b/file
@@ -1,0 +2,2 @@
+new
+more
]])
        )
    end)

    it("finds changed lines", function()
        assert.same(
            {
                { kind = "change", line = 2 },
            },
            parse([[
diff --git a/file b/file
@@ -2 +2 @@
-old
+new
]])
        )
    end)

    it("anchors middle deletions to the previous line", function()
        assert.same(
            {
                { kind = "delete", line = 2 },
            },
            parse([[
diff --git a/file b/file
@@ -3 +2,0 @@
-gone
]])
        )
    end)

    it("anchors top-of-file deletions to line 1", function()
        assert.same(
            {
                { kind = "delete", line = 1 },
            },
            parse([[
diff --git a/file b/file
@@ -1 +0,0 @@
-gone
]])
        )
    end)

    it("anchors end-of-file deletions to the previous line", function()
        assert.same(
            {
                { kind = "delete", line = 3 },
            },
            parse([[
diff --git a/file b/file
@@ -4 +3,0 @@
-gone
]])
        )
    end)

    it("marks replacement hunks as changed plus added lines", function()
        assert.same(
            {
                { kind = "change", line = 4 },
                { kind = "change", line = 5 },
                { kind = "add", line = 6 },
            },
            parse([[
diff --git a/file b/file
@@ -4,2 +4,3 @@
-old
-text
+new
+text
+extra
]])
        )
    end)

    it("keeps a delete sign for replacement hunks with extra removed lines", function()
        assert.same(
            {
                { kind = "change", line = 4 },
                { kind = "delete", line = 4 },
            },
            parse([[
diff --git a/file b/file
@@ -4,3 +4 @@
-old
-text
-more
+new
]])
        )
    end)

    it("returns no signs for an empty diff", function()
        assert.same({}, parse(""))
    end)
end)
