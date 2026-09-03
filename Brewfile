# Only what mise can't provide. Everything else (fzf, fd, ripgrep, bat, zoxide,
# gh, lazygit, hyperfine, neovim) lives in packages/mise/.config/mise/conf.d/
# so the Linux boxes, which have no brew, get it too. The zsh plugins aren't
# here either — they're git submodules under packages/zsh/.config/zsh/plugins/,
# since apt doesn't package fzf-tab at all.

brew "git"
brew "stow" # symlink farm manager; install.sh uses it to link configs into $HOME
brew "mise" # bootstraps itself; installs the rest of the toolchain

cask "ghostty"
cask "music-decoy" # https://lowtechguys.com/musicdecoy/
cask "font-jetbrains-mono-nerd-font" # nerd font for nvim/terminal glyphs
