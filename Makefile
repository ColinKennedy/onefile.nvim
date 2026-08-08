.PHONY: api-documentation check-stylua download-dependencies lint llscheck luacheck privata stylua test

# Git will error if the repository already exists. We ignore the error.
# NOTE: We still print out that we did the clone to the user so that they know.
#
ifeq ($(OS),Windows_NT)
    IGNORE_EXISTING =
else
    IGNORE_EXISTING = 2> /dev/null || true
endif

CONFIGURATION = .luarc.json
ARGUMENTS ?=

# Where the privata checkout lives. Override on the command line to point at a
# different working copy: make privata PRIVATA=/path/to/privata
PRIVATA ?= $(HOME)/repositories/privata

download-dependencies:
	git clone git@github.com:Bilal2453/luvit-meta.git .dependencies/luvit-meta $(IGNORE_EXISTING)
	git clone git@github.com:LuaCATS/busted.git .dependencies/busted $(IGNORE_EXISTING)
	git clone git@github.com:LuaCATS/luassert.git .dependencies/luassert $(IGNORE_EXISTING)

lint: stylua luacheck privata llscheck

llscheck: download-dependencies
	VIMRUNTIME="`nvim --clean --headless --cmd 'lua io.write(os.getenv("VIMRUNTIME"))' --cmd 'quit'`" llscheck --configpath $(CONFIGURATION) .

luacheck:
	luacheck $(ARGUMENTS) init.lua lua spec

check-stylua:
	stylua init.lua lua spec --color always --check

privata:
	LUA_PATH="$(PRIVATA)/lua/?.lua;$(PRIVATA)/lua/?/init.lua;;" lua "$(PRIVATA)/bin/privata.lua" . $(ARGUMENTS)

stylua:
	stylua init.lua lua spec

test:
	busted .
