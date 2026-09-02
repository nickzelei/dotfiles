# Only what mise can't provide. Everything else (fzf, fd, ripgrep, bat, zoxide,
# gh, lazygit, hyperfine, neovim) lives in packages/mise/.config/mise/conf.d/
# so the Linux boxes, which have no brew, get it too.

brew "git"
brew "stow" # symlink farm manager; install.sh uses it to link configs into $HOME
brew "mise" # bootstraps itself; installs the rest of the toolchain

brew "luarocks" # not in the mise registry; some nvim plugins need it

# zsh plugins are shell scripts, not binaries, so mise can't ship them. apt has
# all three on Linux; setup.zsh's _source_plugin finds either prefix.
brew "fzf-tab" # replaces zsh tab-completion menu with an fzf picker
brew "zsh-autosuggestions" # inline suggestions from history
brew "zsh-syntax-highlighting" # colorizes the command line as you type

cask "ghostty"
cask "music-decoy" # https://lowtechguys.com/musicdecoy/
cask "font-jetbrains-mono-nerd-font" # nerd font for nvim/terminal glyphs
