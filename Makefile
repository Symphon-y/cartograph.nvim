.PHONY: test deps

NVIM ?= nvim
DEPS_DIR := .deps
PLENARY_DIR := $(DEPS_DIR)/plenary.nvim

# Clone plenary on first run; it provides the busted-style test harness.
deps:
	@mkdir -p $(DEPS_DIR)
	@test -d $(PLENARY_DIR) || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)

# Run the pure-Lua engine specs headlessly.
test: deps
	@$(NVIM) --headless --noplugin \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
