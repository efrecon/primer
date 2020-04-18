#!/usr/bin/env sh

primer_abort() {
    yush_error "$1"
    exit 1
}

primer_locate() {
    yush_debug "Locating $1 in $PRIMER_PATH"
    for _dir in $(yush_split "$PRIMER_PATH" ":"); do
        for _ext in $PRIMER_EXTS; do
            _fpath="${_dir%%/}/${1}.${_ext##*.}"
            if [ -f "$_fpath" ]; then
                printf %s\\n "$_fpath"
                return 0;
            fi
        done
    done
    return 1;
}
