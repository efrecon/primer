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

_primer_exists() {
    eval "[ ! -z \${$1:-} ]"
    return $?  # Pedantic.
}

_primer_value() { eval printf %s\\n "\$$1"; }

primer_load() {
    _varname=PRIMER_STEP_$(printf %s "$1" | tr '[:lower:]' '[:upper:]' | tr -C '[:alnum:]' '_')_PATH
    if _primer_exists "$_varname"; then
        yush_debug "$1 already loaded from $(_primer_value "$_varname")"
    else
        _impl=$(primer_locate "$1" || true)
        if [ -n "$_impl" ]; then
            yush_info "Loading $1 implementation from $_impl"
            # shellcheck disable=SC1090
            . "$_impl"
            _varname=PRIMER_STEP_$(printf %s "$1" | tr '[:lower:]' '[:upper:]' | tr -C '[:alnum:]' '_')_PATH
            export "${_varname}=${_impl}"
        fi
    fi
}

# If two files are passed arrange for the rights on the first to be applied to
# the first file. Otherwise fix ownership of file passed as argument so that:
# - It is owned by root
# - It is readable and writable by root
# - It is readable (only) by all others
primer_root_ownership() {
    if [ "$#" -gt "1" ]; then
        _ownership=$(stat -c "%U" "$2"):$(stat -c "%G" "$2")
    else
        _ownership="root:root"
    fi
    $PRIMER_SUDO chown $_ownership "$1"

    if [ "$#" -gt "1" ]; then
        _access=$(stat -c "%A" "$2")
    else
        _access="u+rw,go+r,go-w"
    fi
    $PRIMER_SUDO chmod "$_access" "$1"
}
