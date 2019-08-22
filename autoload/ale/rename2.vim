" Author: Jerko Steiner <jerko.steiner@gmail.com>
" Description: Rename symbol support for LSP / tsserver

let g:ale_rename_tsserver_find_in_comments = get(g:, 'ale_rename_tsserver_find_in_comments')
let g:ale_rename_tsserver_find_in_strings = get(g:, 'ale_rename_tsserver_find_in_strings')

function! s:message(message) abort
    call ale#util#Execute('echom ' . string(a:message))
endfunction

function! ale#rename2#HandleTSServerResponse(params, response) abort
    let l:old_name = a:params.options.old_name
    let l:new_name = a:params.options.new_name

    let l:changes = []

    for l:response_item in a:response.body.locs
        let l:filename = l:response_item.file
        let l:text_changes = []

        for l:loc in l:response_item.locs
            call add(l:text_changes, {
            \ 'start': {
            \   'line': l:loc.start.line,
            \   'offset': l:loc.start.offset,
            \ },
            \ 'end': {
            \   'line': l:loc.end.line,
            \   'offset': l:loc.end.offset,
            \ },
            \ 'newText': l:new_name,
            \})
        endfor

        call add(l:changes, {
        \   'fileName': l:filename,
        \   'textChanges': l:text_changes,
        \})
    endfor

    if empty(l:changes)
        call s:message('Error renaming "' . l:old_name . '" to: "' . l:new_name . '"')

        return
    endif

    call ale#code_action#HandleCodeAction({
    \ 'description': 'rename',
    \ 'changes': l:changes,
    \})
endfunction

function! ale#rename2#HandleLSPResponse(params, response) abort
    let l:workspace_edit = a:response.result

    if !has_key(l:workspace_edit, 'changes') || empty(l:workspace_edit.changes)
        call s:message('No changes received from server')

        return
    endif

    let l:changes = []

    for l:file_name in keys(l:workspace_edit.changes)
        let l:text_edits = l:workspace_edit.changes[l:file_name]
        let l:text_changes = []

        for l:edit in l:text_edits
            let l:range = l:edit.range
            let l:new_text = l:edit.newText

            call add(l:text_changes, {
            \ 'start': {
            \   'line': l:range.start.line + 1,
            \   'offset': l:range.start.character + 1,
            \ },
            \ 'end': {
            \   'line': l:range.end.line + 1,
            \   'offset': l:range.end.character + 1,
            \ },
            \ 'newText': l:new_text,
            \})
        endfor

        call add(l:changes, {
        \   'fileName': l:file_name,
        \   'textChanges': l:text_changes,
        \})
    endfor

    call ale#code_action#HandleCodeAction({
    \   'description': 'rename',
    \   'changes': l:changes,
    \})
endfunction

function! s:GetOptions() abort
    let l:old_name = expand('<cword>')
    let l:new_name = ale#util#Input('New name: ', l:old_name)

    if empty(l:new_name)
        throw 'New name cannot be empty!'
    endif

    return {
    \ 'old_name': l:old_name,
    \ 'new_name': l:new_name,
    \}
endfunction

function! ale#rename2#Execute() abort
    call ale#lsp_util#Send({
    \   'command': 'rename',
    \   'GetOptions': function('s:GetOptions'),
    \   'tsserver': {
    \       'GetMessage': {params -> ale#lsp#tsserver_message#Rename(
    \            params.buffer,
    \            params.line,
    \            params.column,
    \            g:ale_rename_tsserver_find_in_comments,
    \            g:ale_rename_tsserver_find_in_strings,
    \       )},
    \       'HandleResponse': function('ale#rename2#HandleTSServerResponse'),
    \   },
    \   'lsp': {
    \       'GetMessage': {params -> ale#lsp#tsserver_message#Rename(
    \           params.buffer,
    \           params.line,
    \           params.column,
    \           params.options.new_name,
    \       )},
    \       'HandleResponse': function('ale#rename2#HandleLSPResponse'),
    \   },
    \ })
endfunction
