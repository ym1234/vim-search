" FIXME:
" Search highlight is not cleared when there is no match
" https://github.com/junegunn/vim-slash/issues/5

" NOTE:
" Why doesn't our `n` mapping raise the error “too recursive mapping“?
" From `:h recursive_mapping`:
"
"     If the {rhs} starts with {lhs}, the first character is not mapped again
"     (this is Vi compatible). For example:
"
"          :map ab abcd
"
"     … will execute the "a" command and insert "bcd" in the text.  The "ab" in
"     the {rhs} will not be mapped again.
"
" Is it neovim compatible? Maybe it's the reason of our crash.
" We should probably get rid of this, and make sure `n` is non recursive.
" If it prevents the number of matches to be displayed, use a timer to
" slightly differ the display.


" n →    wrap('n')
"
"   →    remove autocmd (!)
"        set hlsearch
"        n <plug>(ms_nohl_and_blink)
"
"   →    n search#nohl_and_blink()
"
"   →    autocmd `set nohls` when cursor moves
"        n <plug>(ms_blink)
"
"   →    n search#blink()

" (!) Why do we remove the autocmd even though we re-install it right after?
" When we perform a search:
"
"     /pattern
"
" … we hit `CR` which has been remapped to the output of `search#wrap()`.
" At the end of the evaluation of this function, an autocmd is installed to
" remove the hl as soon as the cursor moves.
" If we don't remove the autocmd, then, when we'll hit `n`, the cursor will
" move and the hl will be removed.

" map = `nvo`
map  <expr> n    search#wrap('n')
map  <expr> N    search#wrap('N')
map  <expr> gd   search#wrap('gd')
map  <expr> gD   search#wrap('gD')
cmap <expr> <cr> search#wrap("\<cr>")

" NOTE:
"
" Without the next mapping, we face this issue:
"
"     https://github.com/junegunn/vim-slash/issues/4
"
"     c/pattern
"
" … inserts `<Plug>(ms_nohl_and_blink)`

imap <expr>   <plug>(ms_nohl_and_blink)   search#nohl_and_blink_on_leave()

" FIXME:
" When disabling `<plug>(ms_prev)` is necessary?

ino           <plug>(ms_prev)      <nop>

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
"                  │         │
"                  │         └─ *<plug>(ms_prev)
"                  └─ <plug>(ms_nohl_and_blink)*<plug>(ms_prev)

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

xmap <expr> *    search#wrap(search#immobile("y/\<c-r>=search#escape(0)\<plug>(ms_cr)\<plug>(ms_cr)"))
xmap <expr> #    search#wrap(search#immobile("y?\<c-r>=search#escape(1)\<plug>(ms_cr)\<plug>(ms_cr)"))

" Breaking down:
"
"     y / c-r = s:escape(0) CR CR
"     │ │ │   │ │           │  │
"     │ │ │   │ │           │  └─ validate search
"     │ │ │   │ │           └─ validate expression
"     │ │ │   │ └─ escape the unnamed register
"     │ │ │   └─ expression register
"     │ │ └─ insert register
"     │ └─ search for
"     └─ copy visual selection


map     <expr>    <plug>(ms_nohl_and_blink)    search#nohl_and_blink()
cno               <plug>(ms_cr)                <cr>
" noremap = `nvo`
noremap           <plug>(ms_prev)              <c-o>
noremap <expr>    <plug>(ms_blink)             search#blink()

nno    <expr>     <plug>(ms_echo_msg)          search#echo_msg()
