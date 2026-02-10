-- lazy.lua — LazyVim plugin manager setup

require("lazy").setup({
  spec = {
    -- LazyVim core + defaults
    {
      "LazyVim/LazyVim",
      import = "lazyvim.plugins",
    },
    -- Local plugin overrides
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  install = {
    colorscheme = { "tokyonight" },
  },
  checker = {
    enabled = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
