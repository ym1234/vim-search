" FIXME:
" Search highlight is not cleared when there is no match
" https://github.com/junegunn/vim-slash/issues/5

" FIXME:
" Why do we remove the autocmd, if we re-install right after?
"
" n → wrap('n')
"
"   →    n <plug>(my_search_nohl_and_blink)
"          + remove autocmd  (why remove if we're going to reinstall right after ?)
"          + set hlsearch
"
"   →    n search#nohl_and_blink()
"
"   →    n<plug>(my_search_blink)
"          + autocmd `set nohls` when cursor moves
"
"   →    n search#blink(2, 50)

cmap <expr> <cr> search#wrap("\<cr>")
map  <expr> n    search#wrap('n')
map  <expr> N    search#wrap('N')
map  <expr> gd   search#wrap('gd')
map  <expr> gD   search#wrap('gD')

" NOTE:
"
" Without the next mapping, we face this issue:
"
"     https://github.com/junegunn/vim-slash/issues/4
"
"     c/pattern
"
" … inserts `<Plug>(my_search_nohl_and_blink)`

imap <expr>   <plug>(my_search_nohl_and_blink)   search#nohl_and_blink_on_leave()

" FIXME:
" When disabling `<plug>(my_search_prev)` is necessary?

ino           <plug>(my_search_prev)      <nop>

" NOTE:
"
" `search#immobile('<key>')` can be read as:
"
"     <key><c-o>
"
" … + it saves `winline()` in `s:winline`.
"
" `winline()` returns the position of the current line from the top line of
" the window. The position / index of the latter is 1.

map  <expr> *    search#wrap(search#immobile('*'))
"                  |         |
"                  |         +-- *<plug>(my_search_prev)
"                  +-- <plug>(my_search_nohl_and_blink)*<plug>(my_search_prev)

map  <expr> #    search#wrap(search#immobile('#'))
map  <expr> g*   search#wrap(search#immobile('g*'))
map  <expr> g#   search#wrap(search#immobile('g#'))


" NOTE:
"
" If we want to search a visual selection, we probably don't need to add the
" anchors. So our implementation of `v_*` and `v_#` don't add them.
" And thus, we don't need to implement `g*` and `g#` mappings.
"
" `escape()` escapes special characters that may be present inside the search
" register. But it needs to know in which direction we're searching.
" Because if we search forward, then `/` is special. But if we search
" backward, then `/` is not special, but `?` is.
" That's why we pass a numerical argument to it (0 or 1). It stands for the direction.

xmap <expr> *    search#wrap(search#immobile("y/\<c-r>=search#escape(0)\<plug>(my_search_cr)\<plug>(my_search_cr)"))
xmap <expr> #    search#wrap(search#immobile("y?\<c-r>=search#escape(1)\<plug>(my_search_cr)\<plug>(my_search_cr)"))

" Breaking down:
"
"     y / c-r = s:escape(0) CR CR
"     | | |   | |           |  |
"     | | |   | |           |  +-- validate search
"     | | |   | |           +-- validate expression
"     | | |   | +-- escape the unnamed register
"     | | |   +-- expression register
"     | | +-- insert register
"     | +-- search for
"     +-- copy visual selection

map     <expr>    <plug>(my_search_nohl_and_blink)    search#nohl_and_blink()
cno               <plug>(my_search_cr)                <cr>
noremap           <plug>(my_search_prev)              <c-o>
noremap <expr>    <plug>(my_search_blink)             search#blink(2, 50)

nno    <expr>     <plug>(my_search_echo_msg)          search#echo_msg()
