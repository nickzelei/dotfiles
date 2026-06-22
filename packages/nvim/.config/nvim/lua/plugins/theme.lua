-- Follow the macOS system appearance (Auto/Light/Dark).
-- Neovim can't read the system setting itself, so this plugin watches it
-- and flips `background`, which tokyonight live-swaps between its dark and
-- day variants.
return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      update_interval = 1000,
      set_dark_mode = function()
        vim.o.background = "dark"
      end,
      set_light_mode = function()
        vim.o.background = "light"
      end,
    },
  },
}
