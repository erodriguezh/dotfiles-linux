-- options.lua — Neovim options (loaded before plugins)

local opt = vim.opt

-- General
opt.clipboard = "unnamedplus"
opt.mouse = "a"
opt.undofile = true
opt.swapfile = false

-- UI
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.showmode = false
opt.laststatus = 3
opt.scrolloff = 8

-- Indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Splits
opt.splitbelow = true
opt.splitright = true

-- Completion
opt.completeopt = "menu,menuone,noselect"

-- Performance
opt.updatetime = 250
opt.timeoutlen = 300
