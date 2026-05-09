local tmux_navigation = require("modules.features.tmux_navigation")

describe("tmux navigation", function()
    describe("SendTmux", function()
        it("builds a tmux send-keys command for adjacent panes", function()
            assert.are.same(
                { "tmux", "send-keys", "-t", "{left-of}", "tttt" },
                tmux_navigation.get_send_text_arguments("left", "tttt")
            )
            assert.are.same(
                { "tmux", "send-keys", "-t", "{right-of}", "tttt" },
                tmux_navigation.get_send_text_arguments("right", "tttt")
            )
        end)

        it("converts literal CR markers into enter keys", function()
            assert.are.same(
                { "tmux", "send-keys", "-t", "{left-of}", "tttt", "Enter" },
                tmux_navigation.get_send_text_arguments("left", "tttt<CR>")
            )
            assert.are.same(
                { "tmux", "send-keys", "-t", "{left-of}", "foo", "Enter", "bar" },
                tmux_navigation.get_send_text_arguments("left", "foo<CR>bar")
            )
        end)

        it("completes only the direction argument", function()
            assert.are.same({ "left" }, tmux_navigation.complete_send_text("le", "SendTmux le"))
            assert.are.same({}, tmux_navigation.complete_send_text("tttt", "SendTmux left tttt"))
        end)
    end)
end)
