# Maintenance commands for this zsh config. Run `make` (or `make help`) to list
# them. Targets are self-documenting via the `## ` comments below.

.DEFAULT_GOAL := help
.PHONY: help bench profile install install-work stow

help: ## List available commands
	@echo "Usage: make <target>\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

bench: ## Benchmark zsh init time (appends a row to bench/results.md)
	@./bench/bench.zsh

profile: ## Show a per-component init profile (what's slow)
	@ZSH_PROFILE=1 zsh -i -c exit

install: ## Install brew deps (if brew is present), symlink and wire zsh, then install mise tools
	@if command -v brew >/dev/null 2>&1; then brew bundle; \
	else echo "brew not found — get git, stow and the zsh plugins from your distro's package manager"; fi
	./install.sh

stow: ## Symlink the config into $HOME and wire zsh startup files (no brew deps)
	./install.sh

install-work: ## Symlink config incl. the work overlay (DOTFILES_ENABLE=work)
	DOTFILES_ENABLE=work ./install.sh
