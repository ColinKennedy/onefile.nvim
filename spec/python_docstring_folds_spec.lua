local python_docstring_folds = require("modules.features.python_docstring_folds")

---@param ranges _my.python_docstring_folds.Range[]
---@return integer[][]
local function simplify(ranges)
    local result = {}

    for _, range in ipairs(ranges) do
        table.insert(result, { range.first, range.last })
    end

    return result
end

describe("python docstring folds", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("finds strict module, class, function, and async function docstrings without tree-sitter", function()
        local ranges = python_docstring_folds.get_fallback_docstring_ranges({
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
        local ranges = python_docstring_folds.get_fallback_docstring_ranges({
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
        local ranges = python_docstring_folds.get_fallback_docstring_ranges({
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

        python_docstring_folds.refresh(buffer)

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

        assert.equal("Docstring starts several lines down.", python_docstring_folds.get_summary(buffer, 2, 6))
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

        python_docstring_folds.refresh(buffer)
        vim.wo.foldmethod = "expr"
        vim.wo.foldexpr = "v:lua.require'modules.features.python_docstring_folds'.foldexpr(v:lnum)"
        vim.wo.foldtext = "v:lua.require'modules.features.python_docstring_folds'.foldtext()"

        vim.v.foldstart = 2
        vim.v.foldend = 6

        assert.equal("    <ASDASDSDADS.....................................................[5 lines]>", python_docstring_folds.foldtext())
    end)
end)
