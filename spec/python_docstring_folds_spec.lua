local python_docstring_folds = require("modules.features.python_docstring_folds")

local _ORIGINAL_REFRESH = python_docstring_folds._refresh
local _ORIGINAL_SCHEDULE_REFRESH = python_docstring_folds._schedule_refresh
---@param ranges _my.python_docstring_folds.Range[]
---@return integer[][]
local function simplify(ranges)
    ---@type integer[][]
    local result = {}

    for _, range in ipairs(ranges) do
        table.insert(result, { range.first, range.last })
    end

    return result
end

---@param filetype string
---@return integer
local function prepare_buffer(filetype)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.bo[buffer].filetype = filetype

    return buffer
end

---@param event string
---@param buffer integer
local function execute_buffer_autocmd(event, buffer)
    vim.api.nvim_exec_autocmds(event, { buffer = buffer })
end

describe("python docstring folds", function()
    after_each(function()
        python_docstring_folds._refresh = _ORIGINAL_REFRESH
        python_docstring_folds._schedule_refresh = _ORIGINAL_SCHEDULE_REFRESH
        vim.cmd.enew({ bang = true })
        vim.wo.foldmethod = "manual"
        vim.wo.foldexpr = "0"
        vim.wo.foldtext = "foldtext()"
    end)
    it("refreshes immediately after Neovim reloads an externally changed Python file", function()
        local buffer = prepare_buffer("python")
        local refreshed = 0

        ---@diagnostic disable-next-line: duplicate-set-field
        python_docstring_folds._refresh = function(refreshed_buffer)
            refreshed = refreshed + 1
            assert.equal(buffer, refreshed_buffer)
        end

        execute_buffer_autocmd("FileChangedShellPost", buffer)

        assert.equal(1, refreshed)
    end)

    it("does not refresh docstring folds for external changes in non-Python buffers", function()
        local buffer = prepare_buffer("lua")
        local refreshed = 0

        ---@diagnostic disable-next-line: duplicate-set-field
        python_docstring_folds._refresh = function()
            refreshed = refreshed + 1
        end

        execute_buffer_autocmd("FileChangedShellPost", buffer)

        assert.equal(0, refreshed)
    end)

    it("finds strict module, class, function, and async function docstrings without tree-sitter", function()
        local ranges = python_docstring_folds._get_fallback_docstring_ranges({
            '"""',
            "Module docs.",
            '"""',
            "",
            "class Thing:",
            "    '''",
            "    Class docs.",
            "    '''",
            "",
            "    def method(self):",
            '        r"""',
            "        Method docs.",
            '        """',
            "        return 1",
            "",
            "async def run():",
            '    f"""',
            "    Async docs.",
            '    """',
            "    return 2",
        })

        assert.are.same({ { 1, 3 }, { 6, 8 }, { 11, 13 }, { 17, 19 } }, simplify(ranges))
    end)

    it("ignores non-first-statement triple strings in the fallback scanner", function()
        local ranges = python_docstring_folds._get_fallback_docstring_ranges({
            "VALUE = 1",
            '"""not a module docstring"""',
            "",
            "def function():",
            "    value = 2",
            '    """not a function docstring"""',
            "    return value",
        })

        assert.are.same({}, simplify(ranges))
    end)

    it("does not create folds for one-line docstrings", function()
        local ranges = python_docstring_folds._get_fallback_docstring_ranges({
            '"""module docs"""',
            "",
            "def function():",
            '    """function docs"""',
            "    return 1",
        })

        assert.are.same({}, simplify(ranges))
    end)

    it("uses cached fold levels in the fold expression", function()
        local buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            '"""',
            "Module docs.",
            '"""',
            "",
            "value = 1",
        })
        vim.api.nvim_set_current_buf(buffer)
        vim.bo[buffer].filetype = "python"

        python_docstring_folds._refresh(buffer)

        assert.equal(1, python_docstring_folds.foldexpr(1))
        assert.equal(1, python_docstring_folds.foldexpr(2))
        assert.equal(1, python_docstring_folds.foldexpr(3))
        assert.equal(0, python_docstring_folds.foldexpr(4))
    end)

    it("uses the first non-empty docstring content line as the fold summary", function()
        local buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            "def foo():",
            '    """',
            "",
            "    Docstring starts several lines down.",
            "",
            '    """',
            "    pass",
        })

        assert.equal("Docstring starts several lines down.", python_docstring_folds._get_summary(buffer, 2, 6))
    end)

    it("renders compact docstring fold text", function()
        local buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            "def another():",
            '    """',
            "    ASDASDSDADS.",
            "",
            "    More details.",
            '    """',
            "    pass",
        })
        vim.api.nvim_set_current_buf(buffer)
        vim.bo[buffer].filetype = "python"

        python_docstring_folds._refresh(buffer)
        vim.wo.foldmethod = "expr"
        vim.wo.foldexpr = "v:lua.require'modules.features.python_docstring_folds'.foldexpr(v:lnum)"
        vim.wo.foldtext = "v:lua.require'modules.features.python_docstring_folds'.foldtext()"

        vim.v.foldstart = 2
        vim.v.foldend = 6

        assert.equal(
            "    <ASDASDSDADS.·····················································[5 lines]>",
            python_docstring_folds.foldtext()
        )
    end)

    it("does not install foldexpr or foldtext for Lua buffers", function()
        local buffer = prepare_buffer("lua")

        vim.wo.foldmethod = "manual"
        vim.wo.foldexpr = "0"
        vim.wo.foldtext = "foldtext()"

        execute_buffer_autocmd("FileType", buffer)

        assert.equal("manual", vim.wo.foldmethod)
        assert.is_false(vim.wo.foldexpr == "v:lua.require'modules.features.python_docstring_folds'.foldexpr(v:lnum)")
        assert.is_false(vim.wo.foldtext == "v:lua.require'modules.features.python_docstring_folds'.foldtext()")
    end)

    it("removes its foldexpr and foldtext after switching from Python to a non-Python buffer", function()
        local python_buffer = prepare_buffer("python")

        execute_buffer_autocmd("FileType", python_buffer)
        assert.equal("expr", vim.wo.foldmethod)
        assert.equal("v:lua.require'modules.features.python_docstring_folds'.foldexpr(v:lnum)", vim.wo.foldexpr)
        assert.equal("v:lua.require'modules.features.python_docstring_folds'.foldtext()", vim.wo.foldtext)

        local busted_buffer = prepare_buffer("lua")

        vim.api.nvim_buf_set_name(busted_buffer, vim.fn.tempname() .. "/.busted")
        execute_buffer_autocmd("BufEnter", busted_buffer)

        assert.equal("manual", vim.wo.foldmethod)
        assert.equal("0", vim.wo.foldexpr)
        assert.equal("foldtext()", vim.wo.foldtext)
        assert.False(vim.wo.foldenable)
        assert.equal(0, python_docstring_folds.foldexpr(1))
    end)

    it("debounces repeated Python text-change refreshes", function()
        local buffer = prepare_buffer("python")
        local refreshed = 0

        ---@diagnostic disable-next-line: duplicate-set-field
        python_docstring_folds._refresh = function(refreshed_buffer)
            refreshed = refreshed + 1
            assert.equal(buffer, refreshed_buffer)
        end

        python_docstring_folds._schedule_refresh(buffer, 20)
        python_docstring_folds._schedule_refresh(buffer, 20)
        python_docstring_folds._schedule_refresh(buffer, 20)

        vim.wait(100)

        assert.equal(1, refreshed)
    end)

    it("updates cached fold levels after an externally changed Python buffer is reloaded", function()
        local buffer = prepare_buffer("python")

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            '"""',
            "Module docs.",
            '"""',
            "",
            "value = 1",
        })

        python_docstring_folds._refresh(buffer)

        assert.equal(1, python_docstring_folds.foldexpr(1))

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            "value = 1",
        })

        execute_buffer_autocmd("FileChangedShellPost", buffer)

        assert.equal(0, python_docstring_folds.foldexpr(1))
    end)

    it("does not move the cursor while refreshing during insert mode", function()
        local get_mode = vim.api.nvim_get_mode
        local buffer = prepare_buffer("python")

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            "value = {",
            '    "A": "A",',
            "}",
        })
        vim.api.nvim_win_set_cursor(0, { 2, 4 })

        ---@diagnostic disable-next-line: duplicate-set-field
        rawset(vim.api, "nvim_get_mode", function()
            return { mode = "i", blocking = false }
        end)

        local ok, message = pcall(function()
            python_docstring_folds._refresh(buffer)
        end)

        rawset(vim.api, "nvim_get_mode", get_mode)

        assert(ok, message)
        assert.are.same({ 2, 4 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("schedules debounced refreshes only for Python text changes", function()
        local python_buffer = prepare_buffer("python")
        local lua_buffer = prepare_buffer("lua")
        ---@type {buffer: integer, delay: integer}[]
        local scheduled = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        python_docstring_folds._schedule_refresh = function(buffer, delay)
            table.insert(scheduled, { buffer = buffer, delay = delay })
        end

        execute_buffer_autocmd("TextChanged", lua_buffer)
        execute_buffer_autocmd("TextChangedI", lua_buffer)
        execute_buffer_autocmd("InsertLeave", lua_buffer)
        execute_buffer_autocmd("BufWritePost", lua_buffer)
        execute_buffer_autocmd("TextChanged", python_buffer)
        execute_buffer_autocmd("TextChangedI", python_buffer)
        execute_buffer_autocmd("InsertLeave", python_buffer)
        execute_buffer_autocmd("BufWritePost", python_buffer)

        assert.are.same({
            { buffer = python_buffer, delay = 500 },
            { buffer = python_buffer, delay = 500 },
            { buffer = python_buffer, delay = 500 },
            { buffer = python_buffer, delay = 500 },
        }, scheduled)
    end)
end)
