#!/usr/bin/env sh

primer_utils_find() {
    yush_debug "Finding $1 in $PRIMER_PATH"
    for _dir in $(yush_split "$PRIMER_PATH" ":"); do
        for _ext in $PRIMER_EXTS; do
            find "${_dir%%/}" -mindepth 1 -maxdepth 1 -type f -name "${1}.${_ext##*.}"
        done
    done
}

primer_utils_locate() {
    _fpath=$(primer_utils_find "$1" | head -n 1)
    [ -z "$_fpath" ] && return 1
    printf %s\\n "$_fpath"
}

primer_utils_var_exists() {
    eval "[ ! -z \"\${$1:-}\" ]"
    return $?  # Pedantic.
}

primer_utils_var_value() { eval printf %s "\"\$$1\""; }

primer_utils_load() {
    _varname=PRIMER_STEP__$(printf %s "$1" | tr '[:lower:]' '[:upper:]' | tr -C '[:alnum:]' '_')_PATH
    if primer_utils_var_exists "$_varname"; then
        yush_debug "$1 already loaded from $(primer_utils_var_value "$_varname")"
    else
        _impl=$(primer_utils_locate "$1" || true)
        if [ -n "$_impl" ]; then
            yush_info "Loading $1 implementation from $_impl"
            # shellcheck disable=SC1090
            . "$_impl"
            _varname=PRIMER_STEP__$(printf %s "$1" | tr '[:lower:]' '[:upper:]' | tr -C '[:alnum:]' '_')_PATH
            export "${_varname}=${_impl}"
        fi
    fi
}

primer_utils_origin() {
    _varname=PRIMER_STEP__$(printf %s "$1" | tr '[:lower:]' '[:upper:]' | tr -C '[:alnum:]' '_')_PATH
    if primer_utils_var_exists "$_varname"; then
        primer_utils_var_value "$_varname"
    elif _primer_utils_is_function "primer_step_$1"; then
        if grep -oEq "^primer_step_${1}\s*\(\)" "$0"; then
            printf %s\\n "$0"
        fi
    fi
}

_primer_utils_is_function() {
    LC_ALL=C type "$1" | head -n 1 | grep -q "function"
}

primer_utils_loadif() {
    if ! _primer_utils_is_function "primer_step_$1"; then
        primer_utils_load "$1"
        if ! _primer_utils_is_function "primer_step_$1"; then
            primer_abort "primer_step_$1 not implemented !"
        fi
    fi
}

# Append what comes in from stdin to a system file
primer_utils_sysfile_append() {
    $PRIMER_OS_SUDO tee -a "$1" > /dev/null
}

# Remove all lines matching $2 from (not only system) file at $1
primer_utils_sysfile_clip() {
    _tmp=$(mktemp)
    grep -v "$2" "$1" > $_tmp
    primer_utils_path_ownership "$_tmp" --as "$1"
    $PRIMER_OS_SUDO mv -f "$_tmp" "$1"
}


# Somewhat restrictive recursive file ownership changes. The default is to
# arrange for the tree passed as first argument to be owned by the caller and
# only readable and writable by that user. Options are as follows:
# --user   Transfer ownership to that user (and his/her group)
# --group  Specific group for ownership
# --perm   chmod compatible access rights
# --as     Take ownership and access rights from this file/dir instead
primer_utils_path_ownership() {
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

    $PRIMER_OS_SUDO chown -R "${_username}:${_group}" "$_path"
    $PRIMER_OS_SUDO chmod -R "$_perms" "$_path"
}