" ============================================================================
"  .vimrc — Kali Linux Enhanced Config
"  Background: Pure Black (untouched)
" ============================================================================

" --- Core Behavior ---
set nocompatible
set encoding=utf-8
set fileencoding=utf-8
set fileformats=unix,dos,mac
set backspace=indent,eol,start
set hidden                          " Allow switching buffers without saving
set autoread                        " Reload files changed outside vim
set clipboard=unnamedplus           " Use system clipboard
set mouse=a                         " Enable mouse in all modes
set updatetime=300                  " Faster CursorHold events
set timeoutlen=500                  " Mapping timeout
set ttimeoutlen=10                  " Key code timeout (snappy ESC)

" --- Display & UI ---
syntax on
set termguicolors
set background=dark
set number                          " Line numbers
set relativenumber                  " Relative line numbers (great for jumps)
set cursorline                      " Highlight current line
set signcolumn=yes                  " Always show sign column
set showmatch                       " Highlight matching brackets
set matchtime=2
set scrolloff=8                     " Keep 8 lines visible above/below cursor
set sidescrolloff=8
set laststatus=2                    " Always show status line
set showcmd                         " Show partial commands
set noshowmode                      " Mode shown in statusline instead
set cmdheight=1
set shortmess+=c                    " Don't pass messages to ins-completion
set splitbelow                      " Horizontal splits below
set splitright                      " Vertical splits to the right
set nowrap                          " No line wrapping by default
set linebreak                       " Wrap at word boundaries when wrap is on
set list                            " Show invisible characters
set listchars=tab:›\ ,trail:·,extends:»,precedes:«,nbsp:␣

" --- Colorscheme Overrides (preserve pure black background) ---
autocmd ColorScheme * highlight Normal       ctermbg=NONE guibg=NONE
autocmd ColorScheme * highlight NonText      ctermbg=NONE guibg=NONE
autocmd ColorScheme * highlight LineNr       ctermbg=NONE guibg=NONE
autocmd ColorScheme * highlight SignColumn   ctermbg=NONE guibg=NONE
autocmd ColorScheme * highlight EndOfBuffer  ctermbg=NONE guibg=NONE
autocmd ColorScheme * highlight CursorLineNr ctermbg=NONE guibg=NONE ctermfg=Green guifg=#50fa7b
autocmd ColorScheme * highlight CursorLine   ctermbg=235  guibg=#1a1a1a cterm=NONE gui=NONE
autocmd ColorScheme * highlight StatusLine   ctermbg=235  guibg=#1a1a1a ctermfg=Green guifg=#50fa7b
autocmd ColorScheme * highlight StatusLineNC ctermbg=234  guibg=#111111 ctermfg=244  guifg=#666666
autocmd ColorScheme * highlight VertSplit     ctermbg=NONE guibg=NONE ctermfg=238 guifg=#333333
autocmd ColorScheme * highlight Pmenu        ctermbg=235  guibg=#1a1a1a ctermfg=250  guifg=#bcbcbc
autocmd ColorScheme * highlight PmenuSel     ctermbg=22   guibg=#005f00 ctermfg=White guifg=#ffffff
autocmd ColorScheme * highlight Search       ctermbg=214  guibg=#ffaf00 ctermfg=Black guifg=#000000
autocmd ColorScheme * highlight Visual       ctermbg=238  guibg=#444444

" Apply a dark colorscheme (falls back gracefully)
silent! colorscheme desert

" --- Indentation ---
set autoindent
set smartindent
set expandtab                       " Spaces over tabs
set tabstop=4
set shiftwidth=4
set softtabstop=4
set shiftround                      " Round indent to multiple of shiftwidth

" Language-specific overrides
augroup FileTypeIndent
    autocmd!
    autocmd FileType html,css,javascript,json,yaml,yml setlocal ts=2 sw=2 sts=2
    autocmd FileType python setlocal ts=4 sw=4 sts=4
    autocmd FileType go setlocal noexpandtab ts=4 sw=4
    autocmd FileType sh,bash,zsh setlocal ts=2 sw=2 sts=2
augroup END

" --- Search ---
set incsearch                       " Incremental search
set hlsearch                        " Highlight matches
set ignorecase                      " Case-insensitive search...
set smartcase                       " ...unless uppercase is used

" --- Completion ---
set wildmenu                        " Enhanced command-line completion
set wildmode=longest:full,full
set wildignore+=*.o,*.obj,*.pyc,*.pyo,__pycache__
set wildignore+=*.swp,*.bak,*~
set wildignore+=*.jpg,*.png,*.gif,*.pdf
set completeopt=menuone,noinsert,noselect

" --- Performance ---
set lazyredraw                      " Don't redraw during macros
set ttyfast
set synmaxcol=300                   " Limit syntax highlighting on long lines

" --- Backup / Swap / Undo ---
set nobackup
set nowritebackup
set noswapfile
if has('persistent_undo')
    set undofile
    set undodir=~/.vim/undodir
    if !isdirectory(expand('~/.vim/undodir'))
        call mkdir(expand('~/.vim/undodir'), 'p', 0700)
    endif
endif
set undolevels=1000
set undoreload=10000

" --- Folding ---
set foldmethod=indent
set foldlevelstart=99               " Start with all folds open
set foldnestmax=5

" ============================================================================
"  KEY MAPPINGS
" ============================================================================

" Leader key
let mapleader = "\<Space>"
let maplocalleader = ","

" Quick save / quit
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>

" Clear search highlight
nnoremap <leader><Space> :nohlsearch<CR>

" Buffer navigation
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>
nnoremap <leader>bd :bdelete<CR>
nnoremap <leader>bl :ls<CR>

" Split navigation (Alt+hjkl)
nnoremap <A-h> <C-w>h
nnoremap <A-j> <C-w>j
nnoremap <A-k> <C-w>k
nnoremap <A-l> <C-w>l

" Resize splits
nnoremap <C-Up>    :resize +3<CR>
nnoremap <C-Down>  :resize -3<CR>
nnoremap <C-Left>  :vertical resize -3<CR>
nnoremap <C-Right> :vertical resize +3<CR>

" Move lines up/down in visual mode
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Keep cursor centered on jumps
nnoremap n nzzzv
nnoremap N Nzzzv
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz

" Indent and stay in visual mode
vnoremap < <gv
vnoremap > >gv

" Quick terminal (horizontal split)
nnoremap <leader>t :below terminal<CR>

" Yank to end of line (consistent with D and C)
nnoremap Y y$

" Select all
nnoremap <leader>a ggVG

" ============================================================================
"  STATUSLINE (lightweight, no plugins needed)
" ============================================================================

function! GitBranch()
    let l:branch = systemlist('git -C ' . expand('%:p:h') . ' rev-parse --abbrev-ref HEAD 2>/dev/null')
    return len(l:branch) > 0 ? '  ' . l:branch[0] . ' ' : ''
endfunction

function! ReadOnly()
    return &readonly ? ' [RO]' : ''
endfunction

set statusline=
set statusline+=%#StatusLine#
set statusline+=\ %{toupper(mode())}                " Mode
set statusline+=\ │                                  " Separator
set statusline+=%{GitBranch()}                       " Git branch
set statusline+=\ │
set statusline+=\ %f                                 " File path
set statusline+=%m                                   " Modified flag
set statusline+=%{ReadOnly()}                        " Read-only flag
set statusline+=%=                                   " Right align
set statusline+=\ %{&filetype!=''?&filetype:'none'}  " Filetype
set statusline+=\ │
set statusline+=\ %{&fileencoding?&fileencoding:&encoding}
set statusline+=\ │
set statusline+=\ %l:%c                              " Line:Column
set statusline+=\ │
set statusline+=\ %p%%\                              " Percentage

" ============================================================================
"  PENTEST / SECURITY WORKFLOW HELPERS
" ============================================================================

" Quick comment toggle (works for most languages)
augroup CommentToggle
    autocmd!
    autocmd FileType python,sh,bash,zsh,yaml,conf,ruby
        \ nnoremap <buffer> <leader>/ :s/^\(\s*\)/\1# /<CR>:nohlsearch<CR>|
        \ vnoremap <buffer> <leader>/ :s/^\(\s*\)/\1# /<CR>:nohlsearch<CR>
    autocmd FileType c,cpp,java,javascript,go,php
        \ nnoremap <buffer> <leader>/ :s/^\(\s*\)/\1\/\/ /<CR>:nohlsearch<CR>|
        \ vnoremap <buffer> <leader>/ :s/^\(\s*\)/\1\/\/ /<CR>:nohlsearch<CR>
    autocmd FileType vim
        \ nnoremap <buffer> <leader>/ :s/^\(\s*\)/\1" /<CR>:nohlsearch<CR>
augroup END

" Recognize common pentest file types
augroup PentestFiletypes
    autocmd!
    autocmd BufNewFile,BufRead *.nse             setfiletype lua
    autocmd BufNewFile,BufRead *.rules           setfiletype conf
    autocmd BufNewFile,BufRead *.nmap            setfiletype nmap
    autocmd BufNewFile,BufRead /etc/hosts        setfiletype conf
    autocmd BufNewFile,BufRead *.scope           setfiletype conf
    autocmd BufNewFile,BufRead Pipfile           setfiletype toml
    autocmd BufNewFile,BufRead *.service         setfiletype systemd
augroup END

" Quick timestamp insert (useful for pentest notes)
nnoremap <leader>d :put =strftime('## %Y-%m-%d %H:%M:%S')<CR>

" Insert common pentest headers
nnoremap <leader>nh :put =['# ' . expand('%:t:r'), '', '## Target: ', '## IP: ', '## Date: ' . strftime('%Y-%m-%d'), '', '---', '', '## Enumeration', '', '## Exploitation', '', '## Post-Exploitation', '', '## Flags', '']<CR>gg

" Highlight trailing whitespace (red)
highlight TrailingWhitespace ctermbg=red guibg=#ff5555
autocmd ColorScheme * highlight TrailingWhitespace ctermbg=red guibg=#ff5555
match TrailingWhitespace /\s\+$/

" Strip trailing whitespace on save
autocmd BufWritePre * :%s/\s\+$//e

" Return to last edit position when reopening files
autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif

" ============================================================================
"  NETRW (built-in file explorer, no plugin needed)
" ============================================================================

let g:netrw_banner = 0              " Hide banner
let g:netrw_liststyle = 3           " Tree view
let g:netrw_browse_split = 4        " Open in previous window
let g:netrw_altv = 1                " Split to the right
let g:netrw_winsize = 22            " Width percentage

nnoremap <leader>e :Lexplore<CR>

" ============================================================================
"  MISC QUALITY OF LIFE
" ============================================================================

" Disable annoying sounds
set belloff=all

" Faster keyword completion
set complete-=i

" Auto-create parent directories on save
autocmd BufWritePre * call mkdir(expand('<afile>:p:h'), 'p')

" Highlight yanked text briefly (Vim 8.2+)
if exists('##TextYankPost')
    autocmd TextYankPost * silent! lua vim.highlight.on_yank({timeout=200})
endif

" Open help in a vertical split
autocmd FileType help wincmd L

" ============================================================================
"  END
" ============================================================================
