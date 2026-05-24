local command_line_completion = require("modules.features.command_line_completion")

describe("modules.features.command_line_completion", function()
    local original_wildmenumode
    local original_wildcharm

    before_each(function()
        original_wildmenumode = vim.fn.wildmenumode
        original_wildcharm = vim.o.wildcharm
    end)

    after_each(function()
        vim.fn.wildmenumode = original_wildmenumode
        vim.o.wildcharm = original_wildcharm
    end)

    it("sets wildcharm so mappings can open command-line completion", function()
        vim.o.wildcharm = 0

        command_line_completion._P.ensure_wildcharm()

        assert.equal(vim.fn.char2nr(command_line_completion._P.keycode("<C-z>")), vim.o.wildcharm)
    end)

    it("opens completion with Tab when selecting next and the menu is closed", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.wildmenumode = function()
            return 0
        end

        assert.equal(
            vim.fn.nr2char(vim.o.wildcharm),
            command_line_completion._P.get_command_line_completion_key("next")
        )
    end)

    it("opens completion with Tab when selecting previous and the menu is closed", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.wildmenumode = function()
            return 0
        end

        assert.equal(
            vim.fn.nr2char(vim.o.wildcharm),
            command_line_completion._P.get_command_line_completion_key("previous")
        )
    end)

    it("selects the next item when the menu is open", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.wildmenumode = function()
            return 1
        end

        assert.equal(
            command_line_completion._P.keycode("<C-n>"),
            command_line_completion._P.get_command_line_completion_key("next")
        )
    end)

    it("selects the previous item when the menu is open", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.wildmenumode = function()
            return 1
        end

        assert.equal(
            command_line_completion._P.keycode("<C-p>"),
            command_line_completion._P.get_command_line_completion_key("previous")
        )
    end)
end)
