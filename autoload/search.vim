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
    "
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

fu! search#wrap(seq) abort
    if mode() ==# 'c' && getcmdtype() !~# '[/?]'
        return a:seq
    endif

    sil! au! my_search | aug! my_search
    set hlsearch
    return a:seq."\<plug>(my_search_nohl_and_blink)"
endfu

"}}}
