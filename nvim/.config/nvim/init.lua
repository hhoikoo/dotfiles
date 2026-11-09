-- Neovim config (kickstart.nvim-based, managed with vim.pack). Requires Neovim 0.12+.

-- ============================================================
-- SECTION 1: OPTIONS
-- ============================================================
do
  vim.loader.enable()

  -- Disable netrw (nvim-tree replaces it); must happen before anything loads it
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

  -- Leader must be set before any mappings are defined
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  vim.g.have_nerd_font = true

  vim.o.number = true
  vim.o.relativenumber = true
  vim.o.mouse = 'a'
  vim.o.showmode = false -- mode is shown in the statusline

  -- Locally sync with the OS clipboard; over SSH leave it unset so Nvim's automatic OSC 52 provider kicks in (:h clipboard-osc52)
  if not vim.env.SSH_TTY then vim.schedule(function() vim.o.clipboard = 'unnamedplus' end) end

  vim.o.breakindent = true
  vim.o.undofile = true
  vim.o.ignorecase = true -- case-insensitive search unless \C or a capital letter is used
  vim.o.smartcase = true
  vim.o.signcolumn = 'yes'
  vim.o.updatetime = 250
  vim.o.timeoutlen = 300
  vim.o.splitright = true
  vim.o.splitbelow = true
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
  vim.o.inccommand = 'split' -- live preview of :substitute
  vim.o.cursorline = true
  vim.o.scrolloff = 10
  vim.o.confirm = true -- ask to save instead of failing on :q with unsaved changes
end

-- ============================================================
-- SECTION 2: KEYMAPS & AUTOCMDS
-- ============================================================
do
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })

  vim.diagnostic.config {
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = { min = vim.diagnostic.severity.WARN } },
    virtual_text = true,
    virtual_lines = false,
    -- Open the diagnostic float after jumping with [d / ]d
    jump = {
      on_jump = function(_, bufnr) vim.diagnostic.open_float { bufnr = bufnr, scope = 'cursor', focus = false } end,
    },
  }
  vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Diagnostic [Q]uickfix list' })

  vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

  -- One persistent terminal per instance: open at the bottom, hide if visible, reopen if hidden
  local term_buf
  vim.keymap.set('n', '<leader>tt', function()
    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
      local win = vim.fn.win_findbuf(term_buf)[1]
      if win and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
        if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_hide(win) end
        return
      end
      vim.cmd('botright sbuffer ' .. term_buf)
    else
      vim.cmd 'botright new'
      vim.cmd.terminal()
      term_buf = vim.api.nvim_get_current_buf()
    end
    vim.cmd.resize(math.max(15, math.floor(vim.o.lines * 0.3)))
    vim.cmd.startinsert()
  end, { desc = '[T]oggle [T]erminal' })

  -- Window navigation
  vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
  vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
  vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
  vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

  -- Built-in undotree (opt package, loaded on first use)
  vim.keymap.set('n', '<leader>u', function()
    vim.cmd.packadd 'nvim.undotree'
    require('undotree').open()
  end, { desc = '[U]ndotree' })

  vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking text',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function() vim.hl.on_yank() end,
  })
end

-- ============================================================
-- SECTION 3: PLUGIN MANAGER HOOKS
-- Update:  :lua vim.pack.update()
-- Status:  :lua vim.pack.update(nil, { offline = true })
-- ============================================================
do
  -- Build hooks; defined before the first vim.pack.add so they also run when bootstrapping from the lockfile
  vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
      local name, kind = ev.data.spec.name, ev.data.kind
      if name == 'nvim-treesitter' and (kind == 'install' or kind == 'update') then
        if not ev.data.active then vim.cmd.packadd 'nvim-treesitter' end
        vim.cmd 'TSUpdate'
      end
    end,
  })
end

---@param repo string
---@return string
local function gh(repo) return 'https://github.com/' .. repo end

-- ============================================================
-- SECTION 4: UI / CORE UX PLUGINS
-- ============================================================
do
  vim.pack.add { gh 'WTFox/jellybeans.nvim' }
  vim.cmd.colorscheme 'jellybeans-hc'

  vim.pack.add { gh 'nvim-mini/mini.nvim' }

  -- Icons; also stands in for nvim-web-devicons (used by nvim-tree)
  require('mini.icons').setup()
  MiniIcons.mock_nvim_web_devicons()

  -- Notifications (replaces vim.notify) and LSP progress
  require('mini.notify').setup()

  -- Around/inside textobjects (aa/ii avoid clashing with 0.12's built-in incremental selection)
  require('mini.ai').setup {
    mappings = { around_next = 'aa', inside_next = 'ii' },
    n_lines = 500,
  }

  -- Surround: sa (add), sd (delete), sr (replace)
  require('mini.surround').setup()

  require('mini.pairs').setup()

  local statusline = require 'mini.statusline'
  statusline.setup { use_icons = vim.g.have_nerd_font }
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_location = function() return '%2l:%-2v' end

  -- File visit tracking with labels (pickers go through vim.ui.select -> fzf-lua)
  require('mini.visits').setup()
  vim.keymap.set('n', '<leader>va', function() MiniVisits.add_label() end, { desc = '[V]isits [A]dd label' })
  vim.keymap.set('n', '<leader>vd', function() MiniVisits.remove_label() end, { desc = '[V]isits [D]elete label' })
  vim.keymap.set('n', '<leader>vv', function() MiniVisits.select_label('', nil) end, { desc = '[V]isits labelled files (cwd)' })
  vim.keymap.set('n', '<leader>vr', function() MiniVisits.select_path() end, { desc = '[V]isits [R]ecent (cwd)' })

  -- Pending-keymap hints
  local miniclue = require 'mini.clue'
  miniclue.setup {
    triggers = {
      { mode = 'n', keys = '<Leader>' },
      { mode = 'x', keys = '<Leader>' },
      { mode = 'n', keys = 'g' },
      { mode = 'x', keys = 'g' },
      { mode = 'n', keys = 'z' },
      { mode = 'x', keys = 'z' },
      { mode = 'n', keys = '<C-w>' },
      { mode = 'n', keys = "'" },
      { mode = 'n', keys = '`' },
      { mode = 'x', keys = "'" },
      { mode = 'x', keys = '`' },
      { mode = 'n', keys = '"' },
      { mode = 'x', keys = '"' },
      { mode = 'i', keys = '<C-r>' },
      { mode = 'c', keys = '<C-r>' },
      { mode = 'i', keys = '<C-x>' },
    },
    clues = {
      { mode = 'n', keys = '<Leader>s', desc = '+[S]earch' },
      { mode = 'x', keys = '<Leader>s', desc = '+[S]earch' },
      { mode = 'n', keys = '<Leader>h', desc = '+Git [H]unk' },
      { mode = 'x', keys = '<Leader>h', desc = '+Git [H]unk' },
      { mode = 'n', keys = '<Leader>t', desc = '+[T]oggle' },
      { mode = 'n', keys = '<Leader>v', desc = '+[V]isits' },
      { mode = 'n', keys = 'gr', desc = '+LSP' },
      miniclue.gen_clues.builtin_completion(),
      miniclue.gen_clues.g(),
      miniclue.gen_clues.marks(),
      miniclue.gen_clues.registers(),
      miniclue.gen_clues.windows(),
      miniclue.gen_clues.z(),
    },
    window = { delay = 300 },
  }

  vim.pack.add { gh 'NMAC427/guess-indent.nvim' }
  require('guess-indent').setup {}

  vim.pack.add { gh 'lewis6991/gitsigns.nvim' }
  local gitsigns = require 'gitsigns'
  gitsigns.setup {
    signs = {
      add = { text = '+' }, ---@diagnostic disable-line: missing-fields
      change = { text = '~' }, ---@diagnostic disable-line: missing-fields
      delete = { text = '_' }, ---@diagnostic disable-line: missing-fields
      topdelete = { text = '‾' }, ---@diagnostic disable-line: missing-fields
      changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
    },
    on_attach = function(bufnr)
      local function map(mode, l, r, desc) vim.keymap.set(mode, l, r, { buf = bufnr, desc = desc }) end
      map('n', ']c', function()
        if vim.wo.diff then
          vim.cmd.normal { ']c', bang = true }
        else
          gitsigns.nav_hunk 'next'
        end
      end, 'Next git [c]hange')
      map('n', '[c', function()
        if vim.wo.diff then
          vim.cmd.normal { '[c', bang = true }
        else
          gitsigns.nav_hunk 'prev'
        end
      end, 'Previous git [c]hange')
      map('v', '<leader>hs', function() gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' } end, 'git [s]tage hunk')
      map('v', '<leader>hr', function() gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' } end, 'git [r]eset hunk')
      map('n', '<leader>hs', gitsigns.stage_hunk, 'git [s]tage hunk')
      map('n', '<leader>hr', gitsigns.reset_hunk, 'git [r]eset hunk')
      map('n', '<leader>hS', gitsigns.stage_buffer, 'git [S]tage buffer')
      map('n', '<leader>hR', gitsigns.reset_buffer, 'git [R]eset buffer')
      map('n', '<leader>hp', gitsigns.preview_hunk, 'git [p]review hunk')
      map('n', '<leader>hi', gitsigns.preview_hunk_inline, 'git preview hunk [i]nline')
      map('n', '<leader>hb', function() gitsigns.blame_line { full = true } end, 'git [b]lame line')
      map('n', '<leader>hd', gitsigns.diffthis, 'git [d]iff against index')
      map('n', '<leader>hD', function() gitsigns.diffthis '~' end, 'git [D]iff against last commit')
      map('n', '<leader>hQ', function() gitsigns.setqflist 'all' end, 'git hunk [Q]uickfix list (repo)')
      map('n', '<leader>hq', gitsigns.setqflist, 'git hunk [q]uickfix list (file)')
      map('n', '<leader>tb', gitsigns.toggle_current_line_blame, '[T]oggle git [b]lame line')
      map('n', '<leader>tw', gitsigns.toggle_word_diff, '[T]oggle git [w]ord diff')
      map({ 'o', 'x' }, 'ih', gitsigns.select_hunk, '[i]nside git [h]unk')
    end,
  }

  -- File tree sidebar
  vim.pack.add { gh 'nvim-tree/nvim-tree.lua' }
  require('nvim-tree').setup {}
  vim.keymap.set('n', '<leader>e', '<cmd>NvimTreeToggle<CR>', { desc = 'File [E]xplorer' })

  -- Rendered markdown in normal mode (picks up mini.icons automatically)
  vim.pack.add { gh 'MeanderingProgrammer/render-markdown.nvim' }
  require('render-markdown').setup {}
end

-- ============================================================
-- SECTION 5: SEARCH & NAVIGATION (fzf-lua)
-- ============================================================
do
  vim.pack.add { gh 'ibhagwan/fzf-lua' }
  local fzf = require 'fzf-lua'
  fzf.setup {}
  fzf.register_ui_select() -- vim.ui.select (code actions, mini.visits, ...) uses fzf-lua

  vim.keymap.set('n', '<leader>sh', fzf.helptags, { desc = '[S]earch [H]elp' })
  vim.keymap.set('n', '<leader>sk', fzf.keymaps, { desc = '[S]earch [K]eymaps' })
  vim.keymap.set('n', '<leader>sf', fzf.files, { desc = '[S]earch [F]iles' })
  vim.keymap.set('n', '<leader>ss', fzf.builtin, { desc = '[S]earch [S]elect picker' })
  vim.keymap.set('n', '<leader>sw', fzf.grep_cword, { desc = '[S]earch current [W]ord' })
  vim.keymap.set('x', '<leader>sw', fzf.grep_visual, { desc = '[S]earch selection' })
  vim.keymap.set('n', '<leader>sg', fzf.live_grep, { desc = '[S]earch by [G]rep' })
  vim.keymap.set('n', '<leader>sd', fzf.diagnostics_workspace, { desc = '[S]earch [D]iagnostics' })
  vim.keymap.set('n', '<leader>sr', fzf.resume, { desc = '[S]earch [R]esume' })
  vim.keymap.set('n', '<leader>s.', fzf.oldfiles, { desc = '[S]earch recent files' })
  vim.keymap.set('n', '<leader>sc', fzf.commands, { desc = '[S]earch [C]ommands' })
  vim.keymap.set('n', '<leader><leader>', fzf.buffers, { desc = '[ ] Find existing buffers' })
  vim.keymap.set('n', '<leader>/', fzf.blines, { desc = '[/] Search in current buffer' })
  vim.keymap.set('n', '<leader>s/', fzf.lines, { desc = '[S]earch [/] in open buffers' })
  vim.keymap.set('n', '<leader>sn', function() fzf.files { cwd = vim.fn.stdpath 'config' } end, { desc = '[S]earch [N]eovim config' })

  -- fzf-lua LSP pickers (override the built-in grr/gri/grt/gO with fuzzy pickers)
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('fzf-lsp-attach', { clear = true }),
    callback = function(event)
      local function map(keys, func, desc) vim.keymap.set('n', keys, func, { buf = event.buf, desc = 'LSP: ' .. desc }) end
      map('grr', fzf.lsp_references, '[G]oto [R]eferences')
      map('gri', fzf.lsp_implementations, '[G]oto [I]mplementation')
      map('grd', fzf.lsp_definitions, '[G]oto [D]efinition')
      map('grt', fzf.lsp_typedefs, '[G]oto [T]ype definition')
      map('gO', fzf.lsp_document_symbols, 'Document symbols')
      map('gW', fzf.lsp_live_workspace_symbols, 'Workspace symbols')
    end,
  })
end

-- ============================================================
-- SECTION 6: LSP
-- Built-in defaults: grn rename, gra code action, grr refs, gri impl, gO symbols, K hover
-- ============================================================
do
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
    callback = function(event)
      local function map(keys, func, desc) vim.keymap.set('n', keys, func, { buf = event.buf, desc = 'LSP: ' .. desc }) end
      map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

      local client = vim.lsp.get_client_by_id(event.data.client_id)

      -- Highlight references of the word under the cursor while it rests
      if client and client:supports_method('textDocument/documentHighlight', event.buf) then
        local group = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, { buffer = event.buf, group = group, callback = vim.lsp.buf.document_highlight })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, { buffer = event.buf, group = group, callback = vim.lsp.buf.clear_references })
        vim.api.nvim_create_autocmd('LspDetach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
          callback = function(event2)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
          end,
        })
      end

      if client and client:supports_method('textDocument/inlayHint', event.buf) then
        map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle inlay [H]ints')
      end
    end,
  })

  -- Language servers (nvim-lspconfig defaults plus these overrides)
  ---@type table<string, vim.lsp.Config>
  local servers = {
    lua_ls = {
      settings = {
        Lua = {
          runtime = { version = 'LuaJIT' },
          workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
          format = { enable = false }, -- stylua formats via conform
        },
      },
    },
    basedpyright = {},
    ruff = {},
    vtsls = {},
    bashls = {},
    jsonls = {},
    yamlls = {},
    marksman = {},
    dockerls = {},
  }

  -- Formatters used by conform (section 7)
  local tools = { 'stylua', 'prettierd', 'prettier', 'shfmt', 'taplo' }

  vim.pack.add {
    gh 'neovim/nvim-lspconfig',
    gh 'mason-org/mason.nvim',
    gh 'mason-org/mason-lspconfig.nvim',
    gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  }

  require('mason').setup {}
  -- Only used for lspconfig <-> mason name mapping; servers are enabled explicitly below
  require('mason-lspconfig').setup { automatic_enable = false }
  require('mason-tool-installer').setup { ensure_installed = vim.list_extend(vim.tbl_keys(servers), tools) }

  for name, server in pairs(servers) do
    vim.lsp.config(name, server)
    vim.lsp.enable(name)
  end
end

-- ============================================================
-- SECTION 7: FORMATTING
-- conform.nvim honours project configs (.prettierrc, pyproject.toml, stylua.toml, ...)
-- ============================================================
do
  vim.pack.add { gh 'stevearc/conform.nvim' }

  local prettier = { 'prettierd', 'prettier', stop_after_first = true }
  require('conform').setup {
    notify_on_error = false,
    format_on_save = function(bufnr)
      -- No format-on-save for languages without a widely agreed style
      local disable_filetypes = { c = true, cpp = true }
      if disable_filetypes[vim.bo[bufnr].filetype] then return nil end
      return { timeout_ms = 500, lsp_format = 'fallback' }
    end,
    default_format_opts = { lsp_format = 'fallback' },
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff_organize_imports', 'ruff_format' },
      javascript = prettier,
      javascriptreact = prettier,
      typescript = prettier,
      typescriptreact = prettier,
      json = prettier,
      jsonc = prettier,
      yaml = prettier,
      markdown = prettier,
      css = prettier,
      html = prettier,
      sh = { 'shfmt' },
      bash = { 'shfmt' },
      toml = { 'taplo' },
    },
  }

  vim.keymap.set({ 'n', 'v' }, '<leader>f', function() require('conform').format { async = true } end, { desc = '[F]ormat buffer' })
end

-- ============================================================
-- SECTION 8: AUTOCOMPLETE
-- blink.cmp; snippets expand through the built-in vim.snippet
-- ============================================================
do
  vim.pack.add { { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' } }
  require('blink.cmp').setup {
    -- <C-y> accept, <C-space> menu/docs, <C-n>/<C-p> select, <C-e> hide, <C-k> signature, <Tab>/<S-Tab> snippet jump
    keymap = { preset = 'default' },
    appearance = { nerd_font_variant = 'mono' },
    completion = { documentation = { auto_show = false, auto_show_delay_ms = 500 } },
    sources = { default = { 'lsp', 'path', 'snippets' } },
    snippets = { preset = 'default' },
    fuzzy = { implementation = 'lua' },
    signature = { enabled = true },
  }
end

-- ============================================================
-- SECTION 9: TREESITTER (main branch; needs the tree-sitter CLI and a C compiler)
-- ============================================================
do
  vim.pack.add { { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' } }

  local parsers = {
    'bash', 'c', 'diff', 'html', 'javascript', 'typescript', 'tsx', 'json', 'lua', 'luadoc', 'markdown',
    'markdown_inline', 'python', 'query', 'toml', 'vim', 'vimdoc', 'yaml', 'dockerfile', 'go', 'rust',
  }
  require('nvim-treesitter').install(parsers) -- async; no-op for parsers already installed

  -- Highlighting and indentation for any filetype with an installed parser
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('kickstart-treesitter', { clear = true }),
    callback = function(args)
      if not pcall(vim.treesitter.start, args.buf) then return end
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  })
end

-- vim: ts=2 sts=2 sw=2 et
