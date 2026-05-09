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

    it("builds selected lines for a partial changed hunk", function()
        local lines = git_diff.make_selected_lines({ "one", "two", "three" }, { "one", "TWO", "THREE" }, 2, 2)

        assert.are.same({ "one", "TWO", "three" }, lines)
    end)

    it("builds an empty patch when the selection has no changes", function()
        local patch = git_diff.build_selected_patch({ "one", "two" }, { "one", "TWO" }, "example.txt", 1, 1, false)

        assert.equal("", patch)
    end)
end)
