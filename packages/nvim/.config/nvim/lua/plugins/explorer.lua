-- Show dotfiles by default in neo-tree (LazyVim's <leader>e explorer).
-- `visible = true` sets the initial state to reveal filtered items. Leaving
-- hide_dotfiles/hide_gitignored at their defaults keeps them filterable, so
-- `H` (toggle_hidden) still flips visibility on and off.
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      filtered_items = {
        visible = true,
      },
    },
  },
}
