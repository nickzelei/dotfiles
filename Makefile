# Maintenance commands for this zsh config. Run `make` (or `make help`) to list
# them. Targets are self-documenting via the `## ` comments below.

.DEFAULT_GOAL := help
.PHONY: help bench bench-install profile install install-work stow update-plugins update-tools

help: ## List available commands
	@echo "Usage: make <target>\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

bench: ## Benchmark zsh init time (appends a row to bench/results.md)
	@./bench/bench.zsh

bench-install: ## Benchmark a COLD install.sh in a sandbox (the devbox bootstrap path)
	@./bench/install-bench.sh

profile: ## Show a per-component init profile (what's slow)
	@ZSH_PROFILE=1 zsh -i -c exit

install: ## Install brew deps (if brew is present), symlink and wire zsh, then install mise tools
	@if command -v brew >/dev/null 2>&1; then brew bundle; \
	else echo "brew not found — get git, stow and mise from your distro's package manager"; fi
	./install.sh

stow: ## Symlink the config into $HOME and wire zsh startup files (no brew deps)
	./install.sh

install-work: ## Symlink config incl. the work overlay (DOTFILES_ENABLE=work)
	DOTFILES_ENABLE=work ./install.sh

update-tools: ## Refresh mise.lock (pinned tool versions, URLs and checksums)
	@tmp="$$(mktemp -d)"; mkdir -p "$$tmp/conf.d"; \
	cp packages/mise/.config/mise/conf.d/10-dotfiles.toml "$$tmp/conf.d/"; \
	GITHUB_TOKEN="$${GITHUB_TOKEN:-$$(gh auth token 2>/dev/null)}" \
	  MISE_CONFIG_DIR="$$tmp" MISE_CACHE_DIR="$$tmp/cache" \
	  MISE_DATA_DIR="$$tmp/data" MISE_STATE_DIR="$$tmp/state" \
	  mise lock --global || exit 1; \
	cp "$$tmp/mise.lock" mise.lock; chmod 644 mise.lock; rm -rf "$$tmp"
	@git diff --stat -- mise.lock || true

update-plugins: ## Bump the zsh plugin submodules to their upstream tips
	git submodule update --remote --merge -- packages/zsh/.config/zsh/plugins
	@git diff --quiet -- packages/zsh/.config/zsh/plugins \
		&& echo "plugins already up to date" \
		|| git status --short -- packages/zsh/.config/zsh/plugins
