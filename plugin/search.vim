if exists('g:loaded_search')
    finish
endif
let g:loaded_search = 1

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

" Autocmds {{{1

augroup my_hls_after_slash
    au!
    " If 'hls'  and 'is' are  set, then ALL  matches are highlighted  when we're
    " writing a regex.  Not just the next match. See `:h 'is`.
    " So, we make sure 'hls' is set when we enter a search command line.
    au CmdlineEnter /,\? call search#toggle_hls('save')
    "               └──┤
    "                  └ we could also write this:     [/\?]
    "                    but it doesn't work on Windows:
    "                    https://github.com/vim/vim/pull/2198#issuecomment-341131934
    "
    "                    Also, why escape the question mark? {{{
    "                    Because, in the pattern of an autocmd, it has a special meaning:
    "
    "                            any character (:h file-pattern)
    "
    "                    We want the literal meaning, to only match a backward search command line.
    "                    Not all the others (:h cmdwin-char).
    "
    "                    Inside a collection, it seems `?` doesn't work (no meaning).
    "                    To make some tests, use this snippet:
    "
    "                            augroup test_pattern
    "                                au!
    "                                "         ✔
    "                                               ┌─ it probably works because the pattern
    "                                               │  is supposed to be a single character,
    "                                               │  so Vim interprets `?` literally, when it's alone
    "                                               │
    "                                au CmdWinEnter ?     nno <buffer> cd :echo 'hello'<cr>
    "                                au CmdWinEnter \?    nno <buffer> cd :echo 'hello'<cr>
    "                                au CmdWinEnter /,\?  nno <buffer> cd :echo 'hello'<cr>
    "                                au CmdWinEnter [/\?] nno <buffer> cd :echo 'hello'<cr>

    "                                "         ✘ (match any command line)
    "                                au CmdWinEnter /,?   nno <buffer> cd :echo 'hello'<cr>
    "                                "         ✘ (only / is affected)
    "                                au CmdWinEnter [/?]  nno <buffer> cd :echo 'hello'<cr>
    "                            augroup END
"}}}

    " Restore the state of 'hls', then invoke `after_slash()`.
    " And if the search has just failed, invoke `nohls()` to disable 'hls'.
    au CmdlineLeave /,\? call search#toggle_hls('restore')
                     \ | if getcmdline() isnot# '' && search#after_slash_status() ==# 1
                     \ |     call search#after_slash()
                     \ |     call timer_start(0, {-> v:errmsg[:4] is# 'E486:' ? search#nohls() : ''})
                     \ | endif

    " Why `search#after_slash_status()`?{{{
    "
    " To disable this part of the autocmd when we do `/ up cr c-o`.
    "}}}
    " Why `v:errmsg…` ?{{{
    "
    " Open 2 windows with 2 buffers A and B.
    " In A, search for a pattern which has a match in B but not in A.
    " Move the cursor: the highlighting should be disabled in B, but it's not.
    " This is because Vim stops processing a mapping as soon as an error occurs:
    "
    "         https://github.com/junegunn/vim-slash/issues/5
    "         :h map-error
"}}}
    " Why the timer?{{{
    "
    " Because we haven't performed the search yet.
    " CmdlineLeave is fired just before.
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
               \ |     nmap  <buffer><nowait>  <cr>  <cr><plug>(ms_index)
               \ | endif
augroup END

" I don't think `<silent>` is needed here, but we use it to stay consistent,
" and who knows, it may be useful to sometimes avoid a brief message
nmap  <expr><silent><unique>  gd  search#wrap_gd(1)
nmap  <expr><silent><unique>  gD  search#wrap_gd(0)

" `<silent>` is important: it prevents `n` and `N` to display their own message
"
" without `<silent>`, when our message (`pattern [12/34]`) is displayed,
" it erases the previous one, and makes look like the command line is “flashing“
nmap  <expr><silent><unique>  n  search#wrap_n(1)
nmap  <expr><silent><unique>  N  search#wrap_n(0)

" Star &friends {{{2

" By default, you can search automatically for the word under the cursor with
" * or #. But you can't do the same for the text visually selected.
" The following mappings work in normal mode, but also in visual mode, to fill
" that gap.
"
" `<silent>` is useful to avoid `/ pattern cr` to display a brief message on
" the command line.
nmap  <expr><silent><unique>  *  search#wrap_star('*')
"                                │
"                                └─ * c-o
"                                   / up cr c-o
"                                   <plug>(ms_nohls)
"                                   <plug>(ms_view)  ⇔  <number> c-e / c-y
"                                   <plug>(ms_blink)
"                                   <plug>(ms_index)

nmap  <expr><silent><unique>  #   search#wrap_star('#')
nmap  <expr><silent><unique>  g*  search#wrap_star('g*')
nmap  <expr><silent><unique>  g#  search#wrap_star('g#')
" Why don't we implement `g*` and `g#` mappings?{{{
" If we search a visual selection, we probably don't want to add the anchors:
"         \< \>
"
" So our implementation of `v_*` and `v_#` don't add them.
"}}}

"                        ┌ just append keys at the end to add some fancy features
"                        │
"                        │                 ┌─ copy visual selection
"                        │                 │┌─ search for
"                        │                 ││      ┌ insert an expression
"                        │                 ││┌─────┤
xmap  <expr><unique>  *  search#wrap_star("y/\<c-r>=search#escape(1)\<plug>(ms_cr)\<plug>(ms_cr)")
"                                                   └──────────────┤│             │
"                                                                  ││             └─ validate search
"                                                                  │└─ validate expression
"                                                                  └ escape unnamed register

xmap  <expr><unique>  #  search#wrap_star("y?\<c-r>=search#escape(0)\<plug>(ms_cr)\<plug>(ms_cr)")
"                                                                 │
"                                                                 └─ direction of the search
"                                                                    necessary to know which character among [/?]
"                                                                    is special, and needs to be escaped

" Customizations (blink, index, …) {{{2

" This mapping  is used in `search#wrap_star()` to reenable  our autocmd after a
" search via star &friends.
nno  <expr>          <plug>(ms_re-enable_after_slash)  search#after_slash_status('delete')

nno  <expr><silent>  <plug>(ms_view)   search#view()

nno  <expr><silent>  <plug>(ms_blink)  search#blink()
nno  <expr><silent>  <plug>(ms_nohls)  search#nohls()
nno        <silent>  <plug>(ms_index)  :<c-u>call search#index()<cr>
" We  can't use  <expr> to  invoke `search#index()`,  because in  the latter  we
" perform a substitution, which is forbidden when the text is locked.

" Regroup all customizations behind `<plug>(ms_custom)`
"                                         ┌─ install a fire-once autocmd to disable 'hls' when we move
"                                         │               ┌─ unfold if needed, restore the view after `*` &friends
"                                         │               │
nmap  <silent>  <plug>(ms_custom)  <plug>(ms_nohls)<plug>(ms_view)<plug>(ms_blink)<plug>(ms_index)
"                                                                         │               │
"                                            make the current match blink ┘               │
"                                                         print `[12/34]` kind of message ┘


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
ino  <silent>  <plug>(ms_nohls)  <c-r>=search#nohls_on_leave()<cr>
ino  <silent>  <plug>(ms_index)  <nop>
ino  <silent>  <plug>(ms_blink)  <nop>
ino  <silent>  <plug>(ms_view)   <nop>

" Options {{{1

" ignore the case when searching for a pattern, containing only lowercase
" characters
set ignorecase

" but don't ignore the case if it contains an uppercase character
set smartcase

" Incremental search
set incsearch
