if exists('g:loaded_mysearch')
    finish
endif
let g:loaded_mysearch = 1

" Links {{{1

" Ideas for other implementations.
"
" Interesting:
" https://github.com/neovim/neovim/issues/5581

" CACHING
"
" To improve efficiency, we cache results of last counting. This makes 'n'
" super fast. We only cache linewise counts, and in-line part is always
" recalculated. This prevents counting error from building up after multiple
" searches if in-line count was imprecise (which happens with regex searches).
"
" Source:
" https://github.com/google/vim-searchindex/blob/master/plugin/searchindex.vim

" Autocmd {{{1

augroup my_hls_after_slash
    au!
    au CmdLineEnter * if expand('<afile>') =~# '[/?]' | let b:my_errmsg_save = v:errmsg | endif

    "                    autocmd disabled when we do  / up cr c-o ┐
    "                                                             │
    au CmdLineLeave * if expand('<afile>') =~# '[/?]' && get(b:, 'my_hls_after_slash_enabled', 1) == 1
                   \|     call search#after_slash()
                   \|     call timer_start(0, {-> execute('if v:errmsg[:4] ==# "E486:"
                   \|                                          call feedkeys("\<plug>(ms_nohls)", "i")
                   \|                                          let v:errmsg = b:my_errmsg_save
                   \|                                          unlet! b:my_errmsg_save
                   \|                                      endif')})
                   \| endif

    " Why the timer?{{{
    "
    " Open 2 windows with 2 buffers A and B.
    " In A, search for a pattern which has a match in B but not in A.
    " Move the cursor: the highlighting should be disabled in B, but it's not.
    " This is because Vim stops processing a mapping as soon as an error occurs:
    "
    "         https://github.com/junegunn/vim-slash/issues/5
    "         :h map-error
"}}}
augroup END

" Mappings {{{1
" Disable unwanted recursivity {{{2

" We remap the following keys RECURSIVELY:
"
"     cr
"     n N
"     * #
"     g* g#
"     gd gD
"
" Each time, we use a wrapper in the rhs.
"
" Any key returned by a wrapper will be remapped.
" We want this remapping, but only for `<plug>(…)` keys.
" For anything else, remapping should be forbidden.
" So, we install non-recursive mappings for various keys we may return in our wrappers.

cno  <plug>(ms_cr)      <cr>
cno  <plug>(ms_up)      <up>
nno  <plug>(ms_slash)   /
nno  <plug>(ms_n)       n
nno  <plug>(ms_N)       N
nno  <plug>(ms_prev)    <c-o>

" cr  gd  n {{{2

" NOTE:
" Don't add `<silent>` to the next mapping.
" When we search for a pattern which has no match in the current buffer,
" the combination of `set shm+=s` and `<silent>`, would make Vim display the
" search command, which would cause 2 messages to be displayed + a prompt:
"
"     /garbage
"     E486: Pattern not found: garbage
"     Press ENTER or type command to continue
"
" Without `<silent>`, Vim behaves as expected:
"     E486: Pattern not found: garbage

augroup ms_cmdwin
  au!
  au CmdWinEnter * if getcmdwintype() =~ '[/?]'
                \|     nmap <buffer> <nowait> <cr> <cr><plug>(ms_index)
                \| endif
augroup END

" I don't think `<silent>` is needed here, but we use it to stay consistent,
" and who knows, it may be useful to sometimes avoid a brief message
nmap  <silent> <expr>  gd   search#wrap_gd(0)
nmap  <silent> <expr>  gD   search#wrap_gd(1)

" `<silent>` is important: it prevents `n` and `N` to display their own message
"
" without `<silent>`, when our message (`pattern [12/34]`) is displayed,
" it erases the previous one, and makes look like the command line is “flashing“
nmap  <silent> <expr>  n    search#wrap_n(0)
nmap  <silent> <expr>  N    search#wrap_n(1)

" Star &friends {{{2

" By default, you can search automatically for the word under the cursor with
" * or #. But you can't do the same for the text visually selected.
" The following mappings work in normal mode, but also in visual mode, to fill
" that gap.
"
" `<silent>` is useful to avoid `/ pattern cr` to display a brief message on
" the command line.
"
" FIXME:
" If the next occurrence of the word under the cursor is not visible on the
" screen (or its distance from the last line of the screen is < &scrolloff),
" the latter will “flash“. That's because the cursor moves back and forth
" between the current and the next word. It would be hard to get rid of it,
" because we need to perform a search with `/` to be sure that 'smartcase'
" is taken into account.
nmap <silent>  <expr>       *    search#wrap_star('*')
"                                │
"                                └─ * c-o
"                                   / up cr c-o
"                                   <plug>(ms_nohls)
"                                   <plug>(ms_view)  ⇔  <number> c-e / c-y
"                                   <plug>(ms_blink)
"                                   <plug>(ms_index)

nmap <silent> <expr>  #    search#wrap_star('#')
nmap <silent> <expr>  g*   search#wrap_star('g*')
nmap <silent> <expr>  g#   search#wrap_star('g#')

" NOTE:
"
" If we search a visual selection, we probably don't want to add the anchors:
"         \< \>
"
" So our implementation of `v_*` and `v_#` don't add them.
" And thus, we don't need to implement `g*` and `g#` mappings.

" NOTE:
"
" `search#escape()` escapes special characters that may be present inside the
" search register. But it needs to know in which direction we're searching.
" Because if we search forward, then `/` is special. But if we search
" backward, it's `?` which is special, not `/`.
" That's why we pass a numerical argument to it (0 or 1).
" It stands for the direction.

"              ┌ just append keys at the end to add some fancy features
"              │
"              │                 ┌─ copy visual selection
"              │                 │┌─ search for
"              │                 ││      ┌ insert an expression
"              │                 ││┌─────┤
xmap <expr> *  search#wrap_star("y/\<c-r>=search#escape(0)\<plug>(ms_cr)\<plug>(ms_cr)")
"                                         └──────────────┤│             │
"                                                        ││             └─ validate search
"                                                        │└─ validate expression
"                                                        └ escape unnamed register

xmap <expr> #  search#wrap_star("y?\<c-r>=search#escape(1)\<plug>(ms_cr)\<plug>(ms_cr)")

" Customizations (blink, index, …) {{{2

" This mapping  is used in `search#wrap_star()` to reenable  our autocmd after a
" search via star &friends.
nno  <expr> <plug>(ms_reenable_autocmd) execute('unlet! b:my_hls_after_slash_enabled')

nno  <expr> <silent> <plug>(ms_view)    search#view()

nno  <silent>  <plug>(ms_blink)   :<c-u>call search#blink()<cr>
nno  <silent>  <plug>(ms_index)   :<c-u>call search#index()<cr>
nno  <silent>  <plug>(ms_nohls)   :<c-u>call search#nohls()<cr>

" Regroup all customizations behind `<plug>(ms_custom)`
"                                       ┌─ install a fire-once autocmd to disable 'hls' when we move
"                                       │               ┌─ unfold if needed, restore the view after `*` &friends
"                                       │               │
nmap <silent> <plug>(ms_custom)  <plug>(ms_nohls)<plug>(ms_view)<plug>(ms_blink)<plug>(ms_index)
"                                                                       │               │
"                                          make the current match blink ┘               │
"                                                       print `[12/34]` kind of message ┘


" Without the next mappings, we face this issue:
"     https://github.com/junegunn/vim-slash/issues/4
"
"     c /pattern cr
"
" … inserts a succession of literal <plug>(…) strings in the buffer, in front
" of `pattern`.
" The problem comes from the wrong assumption that after a `/` search, we are
" in normal mode. We could also be in insert mode.

" Why don't we disable `<plug>(ms_nohls)`?
" Because, the search in `c /pattern cr` has enabled 'hls', so we need
" to disable it.
ino <silent>  <plug>(ms_nohls)  <c-r>=search#nohls_on_leave()<cr>
ino <silent>  <plug>(ms_index)  <nop>
ino <silent>  <plug>(ms_blink)  <nop>
ino <silent>  <plug>(ms_view)   <nop>
