" Enable syntax highlighting
syntax on

" Show line numbers
set number

" Set relative numbers elsewhere
set relativenumber

" Highlight the current line
" set cursorline

" Use spaces instead of tabs
set expandtab

" Set the number of spaces for a tab
set tabstop=4

" Set the number of spaces for auto-indentation
set shiftwidth=4

" Enable smart indentation
set smartindent

" Show matching parentheses
set showmatch

" Ignore case in searches (unless a capital letter is used
set ignorecase
set smartcase

" Display a status line at the bottom
" set laststatus=2

" Highlight search matches
set hlsearch

" Allow backspace to work properly in Insert mode
set backspace=indent,eol,start

" Enable persistent undo
set undofile
set undodir=~/.vim/undo/
" Vim won't create undodir itself; make it on first launch so writes don't fail
if !isdirectory(&undodir)
  call mkdir(&undodir, 'p')
endif

" Use a nice color scheme
" colorscheme desert

