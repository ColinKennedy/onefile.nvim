local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
--- Add mksession support.
-- This integrates well with [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
--
-- Important:
--     This code assumes that you tend to start Neovim from the root of
--     a VCS repository (e.g. git). If you don't do that then things may
--     still work but likely aren't going to work 100% as expected.
--
-- It's recommended to add this to your ~/.bash_aliases:
--
-- ```sh
-- alias es='cp $PWD/${NEOVIM_SESSIONS_DIRECTORY_NAME:-.sessions}/`git branch --show-current`/Session.vim . 2>/dev/null; NVIM_APPNAME=noplugins nvim -S'
-- ```
--
-- How it works:
-- - Use `es` to load Neovim
-- - Just before loading neovim, the current branch's Session.vim is copied over.
--     - This is also the same command that tmux-resurrect uses
-- - Just work as you normally do now.
-- - On-close, Neovim will save the current layout + git branch to a unique Session.vim file.
--
-- TODO: This doesn't 100% work with tmux-resurrect. We need to make
-- tmux-resurrect use the alias, somehow. Add instructions on how to do
-- that later.
--

--- Find the location on-disk where we should save a Sesssion.vim file.
---
---@param reference_path string The path on-disk to search for a git / VCS root.
---@return string? # The recommended Session.vim save location, if any.
---
function _P.get_session_branch_path(reference_path)
    local root = _P.get_nearest_project_root(reference_path)

    if not root then
        vim.notify(
            string.format('Skipped saving "%s" session. Not git root was found.', reference_path),
            vim.log.levels.ERROR
        )

        return nil
    end

    local branch = _P.get_git_branch_safe()

    if not branch then
        vim.notify(string.format('Cannot save "%s" project. No branch was found.', root), vim.log.levels.ERROR)

        return nil
    end

    return vim.fs.joinpath(root, _SESSIONS_DIRECTORY_NAME, branch, _VIM_SESSION_FILE_NAME)
end

--- Keep track of the current Vim Session.vim, if there is one.
---
---@param session string
---    The path on-disk to write a session file. We will
---    also make a VCS-root session file too, if needed.
---
function _P.save_session(session)
    vim.cmd("mksession! " .. session)

    local path = _P.get_session_branch_path(session)

    if not path then
        vim.notify(
            string.format('Cannot save a branch session for "%s" session. no VCS root was found.', session),
            vim.log.levels.ERROR
        )

        return
    end

    vim.uv.fs_mkdir(vim.fs.dirname(path), 448) -- NOTE: 448 = 0700
    vim.uv.fs_copyfile(session, path)
end

vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        local session = vim.v.this_session

        if session == "" then
            return
        end

        _P.save_session(session)
    end,
})

vim.api.nvim_create_user_command("SessionWrite", function()
    local directory = vim.fn.getcwd()
    local root = _P.get_nearest_project_root(directory)

    if not root then
        vim.notify(
            string.format('Cannot save a session for "%s" directory. No VCS root was found.', directory),
            vim.log.levels.ERROR
        )

        return
    end

    local path = _P.get_session_branch_path(directory)

    if not path then
        vim.notify(
            string.format('Cannot save a session for "%s" directory for some reason.', directory),
            vim.log.levels.ERROR
        )

        return
    end

    local session = vim.fs.joinpath(directory, _VIM_SESSION_FILE_NAME)
    _P.save_session(session)
    vim.uv.fs_mkdir(vim.fs.dirname(path), 448) -- NOTE: 448 = 0700
    vim.uv.fs_copyfile(session, path)
end, {
    nargs = 0,
    desc = "Write a session to the current git repository's branch.",
})
end)
