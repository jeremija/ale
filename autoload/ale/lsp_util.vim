" Author: Jerko Steiner <jerko.steiner@gmail.com>
" Description: Contains boilerplate when handling LSP requests
"
let s:request_map = {}

" Used to get the lsp_helper map in tests.
function! ale#lsp_util#GetMap() abort
    return deepcopy(s:lsp_helper_map)
endfunction

" Used to set the lsp_helper map in tests.
function! ale#lsp_util#SetMap(map) abort
    let s:lsp_helper_map = a:map
endfunction

function! ale#lsp_util#ClearLSPData() abort
    let s:lsp_helper_map = {}
endfunction

function! s:message(message) abort
    call ale#util#Execute('echom ' . string(a:message))
endfunction

function! ale#lsp_util#HandleTSServerResponse(conn_id, response) abort
    if !has_key(a:response, 'request_seq')
        return
    endif

    if !has_key(s:request_map, a:response.request_seq)
        return
    endif

    let l:params = remove(s:request_map, a:response.request_seq)

    if get(a:response, 'success', v:false) is v:false
        let l:message = get(a:response, 'message', 'unknown')
        call s:message(
        \ 'Error executing ' . l:params.command . 'Details: ' . l:message)

        return
    endif

    call l:params.tsserver.HandleResponse(l:params, a:response)
endfunction

function! ale#lsp_util#HandleLSPResponse(conn_id, response) abort
    if !has_key(a:response, 'id')
        return
    endif

    if !has_key(s:request_map, a:response.id)
        return
    endif

    let l:params = remove(s:request_map, a:response.request_seq)

    call l:params.lsp.HandleResponse(l:params, a:response)
endfunction

function! s:OnReady(params, linter, lsp_details) abort
    let l:id = a:lsp_details.connection_id

    if !ale#lsp#HasCapability(l:id, a:params.command)
        return
    endif

    let l:buffer = a:lsp_details.buffer

    let l:Callback = a:linter.lsp is# 'tsserver'
    \   ? function('ale#lsp_util#HandleTSServerResponse')
    \   : function('ale#lsp_util#HandleLSPResponse')

    call ale#lsp#RegisterCallback(l:id, l:Callback)

    let l:message = {}

    if a:linter.lsp is# 'tsserver'
        if has_key(a:params, 'tsserver')
            let l:message = a:params.tsserver.GetMessage(a:params)
        endif
    else
        if has_key(a:params, 'lsp')
            let l:message = a:params.lsp.GetMessage(a:params)
        endif
    endif

    if !empty(l:message)
        let l:request_id = ale#lsp#Send(l:id, l:message)
        let s:request_map[l:request_id] = a:params
    endif
endfunction

function! s:Execute(linter, params) abort
    let l:Callback = function('s:OnReady', [a:params])
    call ale#lsp_linter#StartLSP(a:params.buffer, a:linter, l:Callback)
endfunction

" Params should contain the following keys:
"  - command
"  - [GetOptions]
"  - [lsp]
"    - GetMessage(params)
"    - HandleRequest(params)
"  - [tsserver]
"    - GetMessage(params)
"    - HandleRequest(params)
function! ale#lsp_util#Send(params) abort
    let l:lsp_linters = []

    for l:linter in ale#linter#Get(&filetype)
        if !empty(l:linter.lsp)
            call add(l:lsp_linters, l:linter)
        endif
    endfor

    if empty(l:lsp_linters)
        call s:message('No active LSPs')

        return
    endif

    let l:buffer = bufnr('')
    let [l:line, l:column] = getpos('.')[1:2]
    let l:column = min([l:column, len(getline(l:line))])

    try
        let l:options = has_key(a:params, 'GetOptions')
        \ ? a:params.GetOptions() : {}
    catch
        call s:message(v:exception)

        return
    endtry

    let l:params = {
    \ 'command': a:params.command,
    \ 'buffer': bufnr(''),
    \ 'line': l:line,
    \ 'column': l:column,
    \ 'options': l:options,
    \}

    if !has_key(a:params, 'lsp') && !has_key(a:params, 'tsserver')
        throw 'Neither lsp nor tsserver params were provided'
    endif

    if has_key(a:params, 'lsp')
        let l:params.lsp = a:params.lsp
    endif

    if has_key(a:params, 'tsserver')
        let l:params.tsserver = a:params.tsserver
    endif

    for l:lsp_linter in l:lsp_linters
        call s:Execute(l:lsp_linter, l:params)
    endfor
endfunction
