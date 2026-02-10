-- init.lua — Neovim entry point (LazyVim bootstrap)
-- Clones lazy.nvim if missing, then loads config/lazy.lua

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load options before plugins (LazyVim convention)
require("config.options")

-- Load lazy.nvim plugin manager
require("config.lazy")
