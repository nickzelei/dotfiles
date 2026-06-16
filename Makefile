# Maintenance commands for this zsh config. Run `make` (or `make help`) to list
# them. Targets are self-documenting via the `## ` comments below.

.DEFAULT_GOAL := help
.PHONY: help bench profile install stow update

help: ## List available commands
	@echo "Usage: make <target>\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

bench: ## Benchmark zsh init time (appends a row to bench/results.md)
	@./bench/bench.zsh

profile: ## Show a per-component init profile (what's slow)
	@ZSH_PROFILE=1 zsh -i -c exit

install: ## Install brew deps, then symlink the config and wire up zsh startup files
	brew bundle
	./install.sh

stow: ## Symlink the config into $HOME and wire zsh startup files (no brew deps)
	./install.sh

update: ## Update plugin submodules to their latest upstream
	git submodule update --remote --merge
