" FIXME:
"
" Implement caching taking inspiration from:
"
"     https://github.com/google/vim-searchindex/blob/master/plugin/searchindex.vim

" FIXME:
" Sometimes, the blinking doesn't work. Need to restart Vim.

" blink "{{{

fu! search#blink(times, delay) abort
    let s:blink = {
                  \ 'ticks': 2 * a:times,
                  \ 'delay': a:delay,
                  \ }

    fu! s:blink.tick(_) abort
        let self.ticks -= 1

        " FIXME:
        " Why       `self == s:blink`?
        " Maybe the purpose is to check whether `s:blink.tick()` has been
        " called since `s:blink` has been (re-)initialized? To be verified.
        "
        " BTW, we can't move the initialization of `s:blink` outside `search#blink()`.
        " Because it must be re-initialized EACH time `search#blink()` is called.
        " We can't move `s:blink.tick()` and `s:blink.clear()` outside `search#blink()` either,
        " because the dictionary to which it refers must exist when they are defined.
        "
        " Could we initialize `s:blink.tick()` and `s:blink.clear()` outside
        " `search#blink()` if we also initialized `s:blink` outside `search#blink()`?
        " (while also keeping an initialization of `s:blink` inside `search#blink()`)
        let active = self == s:blink && self.ticks > 0

        " FIXME:
        " Don't understand this line:
        if !self.clear() && &hlsearch && active
        " `!self.clear()` is true iff `w:blink_id` doesn't exist.

            " '\v%%%dl%%>%dc%%<%dc'
            "    |    |     |
            "    |    |     +-- '%<'.(col('.')+2).'c'      →    before    column    `col('.')+2`
            "    |    +-- '%<'.max([0, col('.')-2]).'c'    →    after     column    `max(0, col('.')-2)`
            "    +-- '%'.line('.').'l'                     →    on        line      `line('.')`

            let w:blink_id = matchadd('IncSearch',
                           \          printf(
                           \                 '\v%%%dl%%>%dc%%<%dc',
                           \                  line('.'),
                           \                  max([0, col('.')-2]),
                           \                  col('.')+2
                           \                )
                           \         )
        endif

        " if `self == s:blink` and `self.ticks > 0`
        if active
            " `self` is `s:blink`, so the next line calls `s:blink.tick()`
            " (current function) after `s:blink.delay` ms
            call timer_start(self.delay, self.tick)
        endif
    endfu

    fu! s:blink.clear() abort
        if exists('w:blink_id')
            call matchdelete(w:blink_id)
            unlet w:blink_id
            return 1
        endif

        " In `s:blink.tick()`, we test the output of this function to decide
        " whether we should create a match.
        "
        " We could write `return 0` at the end, but we don't do it, because
        " that's what Vim does by default.
        " Try this:
        "
        "   fu! Myfunc()
        "   endfu
        "
        "   :echo Myfunc()
    endfu

    call s:blink.clear()
    call s:blink.tick(0)
    return ''
endfu

"}}}
" escape "{{{

fu! search#escape(backward) abort
    return '\V'.substitute(escape(@", '\' . (a:backward ? '?' : '/')), "\n", '\\n', 'g')
endfu

"}}}
" immobile "{{{

fu! search#immobile(seq) abort
    let search#winline = winline()
    return a:seq."\<plug>(my_search_prev)"
endfu

"}}}

" `nohl_and_blink()` does 4 things:
"
"     1. install a fire-once autocmd to disable 'hlsearch' as soon as we move the cursor
"     2. open possible folds
"     3. restore the position of the window
"     4. make the cursor blink

" nohl_and_blink "{{{

fu! search#nohl_and_blink() abort
    augroup my_search
        au!
        au CursorMoved,CursorMovedI * set nohlsearch | au! my_search | aug! my_search
    augroup END

    let seq = foldclosed('.') != -1 ? 'zMzv' : ''

    " What are `s:winline` and `s:windiff`? "{{{
    "
    " `s:winline` exists only if we hit `*`, `#` (visual/normal), `g*` or `g#`.
    "
    " NOTE:
    "
    " The goal of `s:windiff` is to restore the state of the window after we
    " search with `*` and similar normal commands (`#`, `g*`, `g#`).
    "
    " When we hit `*`, the `{rhs}` of the `*` mapping is evaluated as an
    " expression. During the evaluation, `search#immobile()` is called, which set
    " the variable `s:winline`. The result of the evaluation is:
    "
    "     <plug>(my_search_nohl_and_blink)*<plug>(my_search_prev)
    "
    " … which is equivalent to:
    "
    "     :call <sid>nohl_and_blink_on_leave()<CR>*<C-o>
    "
    " What's important to understand here, is that `nohl_and_blink()` is
    " called AFTER `search#immobile()`. Therefore, `s:winline` is not necessarily
    " the same as the current output of `winline()`, and we can use:
    "
    "     winline() - s:winline
    "
    " … to compute the number of times we have to hit `C-e` or `C-y` to
    " position the current line in the window, so that the state of the window
    " is restored as it was before we hit `*`.

"}}}

    if exists('s:winline')
        let windiff = winline() - s:winline
        unlet s:winline

        " If `windiff` is positive, it means the current line is further away
        " from the top line of the window, than it was originally.
        " We have to move the window down to restore the original distance
        " between current line and top line.
        " Thus, we use `C-e`. Otherwise, we use `C-y`.

        let seq .= windiff > 0
                 \   ? windiff."\<c-e>"
                 \   : windiff < 0
                 \     ? -windiff."\<c-y>"
                 \     : ''
    endif

    return seq."\<plug>(my_search_blink)"
endfu

"}}}
" nohl_and_blink_on_leave "{{{

fu! search#nohl_and_blink_on_leave()
    augroup my_search
        au!
        au InsertLeave * call search#nohl_and_blink() | au! my_search | aug! my_search
    augroup END
    return ''
endfu

"}}}
" `wrap()` enables 'hlsearch' then calls `nohl_and_blink()`
" wrap "{{{

fu! s:snr()
    return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfu

fu! s:reset_more(...)
    set more
endfu

fu! search#wrap(seq) abort
    let [ l:line, l:mode, l:type ] = [ getcmdline(), mode(), getcmdtype() ]

    if l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>" && l:line =~# '#\s*$'
        " If we're on the Ex command line, it ends with a number sign, and we
        " hit Enter, return the Enter key, and add a colon at the end of it.
        "
        " Why?
        " Because `:#` is a command used to print lines with their addresses:
        "     :g/pattern/#
        "
        " And, when it's executed, we probably want to jump to one of them, by
        " typing its address on the command line:
        "     https://gist.github.com/romainl/047aca21e338df7ccf771f96858edb86

        return "\<cr>:"

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*%(ls|buffers|files)\s*$'

        return "\<cr>:b "

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*%(d|i)l%[ist]\s+'

        return "\<cr>:".matchstr(l:line, '\S').'j '

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*%(c|l)li%[st]\s*$'

        " allow Vim's pager to display the full contents of any command,
        " even if it takes more than one screen; don't stop after the first
        " screen to display the message:    -- More --
        set nomore

        " reset 'more' after the keys have been typed
        call timer_start(10, s:snr().'reset_more')

        return "\<cr>:".repeat(matchstr(l:line, '\S'), 2).' '

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*%(c|l)hi%[story]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:sil ".matchstr(l:line, '\S').'older '

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*old%[files]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:e #<"

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*changes\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        " We don't return the keys directly, because S-left could be remapped
        " to something else, leading to spurious bugs.
        " We need to tell Vim to not remap it. We can't do that with `:return`.
        " But we can do it with `feedkeys()` and the `n` flag.
        call feedkeys("\<cr>:norm! g;\<s-left>", 'in')
        return ''

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*ju%[mps]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        call feedkeys("\<cr>:norm! \<c-o>\<s-left>", 'in')
"                                                      │
"                                                      └─ don't remap C-o and S-left
        return ''

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*marks\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:norm! `"

    elseif l:mode ==# 'c' && l:type ==# ':' && a:seq ==# "\<cr>"
                \ && l:line =~# '\v\C^\s*undol%[ist]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:u "

    elseif l:mode ==# 'c' && l:type !~# '[/?]'
        " if we're not on the search command line, just return the key sequence
        " without any modification
        return a:seq
    endif

    " we store the key inside `s:seq` so that `echo_msg()` knows whether it must
    " echo a msg or not
    let s:seq = a:seq

    " FIXME:
    " how to get `n` `N` to move consistently no matter the direction of the
    " search `/`, or `?` ?
    " If we change the value of `s:seq` (`n` to `N` or `N` to `n`), when we perform
    " a backward search we have an error:
    "
    "         too recursive mapping
    "
    " Why?

    if a:seq ==? 'n'
        " toggle the value of `n`, `N`
        let s:seq = (a:seq ==# 'n' ? 'Nn' : 'nN')[v:searchforward]
        " " convert it into a non-recursive mapping to avoid error "too recursive mapping"
        " " Pb: when we use non-recursive mapping, we don't see the message anymore
        " " Maybe because the non-recursive mapping is expanded after the
        " " message has been displayed ?
        "
        " let s:seq = (s:seq ==# 'n' ? "\<plug>(my_search_n)" : "\<plug>(my_search_N)")
        "
        " Move mappings outside function:
        " nno <plug>(my_search_n) n
        " nno <plug>(my_search_N) N
    else
        let s:seq = a:seq
    endif

    sil! au! my_search | aug! my_search
    set hlsearch

    return s:seq."\<plug>(my_search_nohl_and_blink)\<plug>(my_search_echo_msg)"
endfu

"}}}
" echo_msg "{{{

fu! search#echo_msg() abort
    if s:seq ==? 'n'

        let winview     = winsaveview()
        let [line, col] = [winview.lnum, winview.col]

        call cursor(1, 1)
        let [idx, total]          = [1, 0]
        let [matchline, matchcol] = searchpos(@/, 'cW')
        while matchline && total <= 999
            let total += 1
            if matchline < line || (matchline == line && matchcol <= col)
                let idx += 1
            endif
            let [matchline, matchcol] = searchpos(@/, 'W')
        endwhile

        echo @/.'('.idx.'/'.total.')'
    endif

    return ''
endfu

"}}}
