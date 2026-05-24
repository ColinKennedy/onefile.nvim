local core_helpers = require("modules.utilities.core_helpers")
local core_editor_setup = require("modules.features.core_editor_setup")
local git_status = require("modules.utilities.git_status")

require("modules.features.statusline")

--- Check if a string contains literal text.
---
---@param text string The text to search.
---@param pattern string The literal text to find.
---@return boolean # If the pattern is found, return true.
local function contains(text, pattern)
    return text:find(pattern, 1, true) ~= nil
end

describe("modules.features.statusline", function()
    local original_get_statusline

    before_each(function()
        original_get_statusline = git_status.get_statusline
        core_helpers.delete_all_bookmarks()
    end)

    after_each(function()
        git_status.get_statusline = original_get_statusline
        core_helpers.delete_all_bookmarks()
    end)

    it("does not render git-detail or grapple separators when both are empty", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        git_status.get_statusline = function()
            return ""
        end

        local text = _G.get_git_and_grapple_statusline()

        assert.is_true(contains(text, "%#StatusLightArrow#"))
        assert.is_false(contains(text, ""))
        assert.is_false(contains(text, ">>"))
        assert.is_false(contains(text, "%#StatusGrapple"))
    end)

    it("renders the branch/details separator only when git details exist", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        git_status.get_statusline = function()
            return " %#StatusGitModified#*1"
        end

        local text = _G.get_git_and_grapple_statusline()

        assert.is_true(contains(text, "%#StatusGit#"))
        assert.is_true(contains(text, "StatusGitModified"))
        assert.is_true(contains(text, "%#StatusLightArrow#"))
    end)

    it("elides long hyphenated ticket branch names", function()
        local branch = core_editor_setup.elide_git_branch_name("ASC-1234-some_really_long_description_here_003")

        assert.equal("ASC-1234-..._here_003", branch)
    end)

    it("elides long underscored ticket branch names", function()
        local branch = core_editor_setup.elide_git_branch_name("ABC-1234_some_really_long_description_here_003")

        assert.equal("ABC-1234_..._here_003", branch)
    end)

    it("keeps long non-ticket branch names unchanged", function()
        local branch = core_editor_setup.elide_git_branch_name("some_really_long_description_here_003")

        assert.equal("some_really_long_description_here_003", branch)
    end)

    it("keeps short ticket branch names unchanged", function()
        local branch = core_editor_setup.elide_git_branch_name("ASC-1234-short")

        assert.equal("ASC-1234-short", branch)
    end)
end)
