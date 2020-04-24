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

_primer_value() { eval printf %s "\$$1"; }

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


# Somewhat restrictive recursive file ownership changes. The default is to
# arrange for the tree passed as first argument to be owned by the caller and
# only readable and writable by that user. Options are as follows:
# --user   Transfer ownership to that user (and his/her group)
# --group  Specific group for ownership
# --perm   chmod compatible access rights
# --as     Take ownership and access rights from this file/dir instead
primer_ownership() {
    _path="$1"
    shift
    _username=$(id -un)
    _group=$(id -gn)
    _perms="u+rw,go-rw"
    while [ $# -gt 0 ]; do
        case "$1" in
            --user*)
                _username=$2; _group=$(id -gn "$2");  shift 2;;
            --group*)
                _group=$2;  shift 2;;
            --perm*)
                _perms=$2; shift 2;;
            --as*)
                _username=$(stat -c "%U" "$2")
                _group=$(stat -c "%G" "$2")
                _perms=$(stat -c "%A" "$2")
                shift 2
                ;;
            -*)
                yush_warn "Unknown option: $1 !"; shift 2;;
            *)
                break;;
        esac
    done

    $PRIMER_SUDO chown -R "${_username}:${_group}" "$_path"
    $PRIMER_SUDO chmod -R "$_perms" "$_path"
}