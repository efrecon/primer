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

# Is the command $1 available? Regular users have no sbin directories in their
# PATH, so look them up explicitly to also find system daemons and tools.
primer_utils_syscmd_exists() {
    PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin" command -v "$1" >/dev/null 2>&1
}

primer_utils_var_exists() {
    eval "[ ! -z \"\${$1:-}\" ]"
    return $?  # Pedantic.
}

# Print the value of the variable which name is passed as an argument, empty
# when unset (also under set -u).
primer_utils_var_value() { eval printf %s "\"\${$1:-}\""; }

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
    LC_ALL=C type "$1" 2>/dev/null | head -n 1 | grep -q "function"
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

# Replace the content of the (not only system) file at $1 with what comes in
# from stdin, keeping the owner and access rights of the file (a new file is
# made readable by all). The content is first written to a temporary file in
# the same directory, which is then moved in place: the file is replaced
# atomically and never left truncated or half-written. When $1 is a symbolic
# link, the file it points to is replaced, and the link kept.
primer_utils_sysfile_replace() {
    _rpl_path=$1
    if [ -L "$_rpl_path" ]; then
        _rpl_path=$($PRIMER_OS_SUDO readlink -f "$1")
    fi
    _rpl_tmp=$($PRIMER_OS_SUDO mktemp "$(dirname "$_rpl_path")/.$(basename "$_rpl_path").XXXXXX")
    if $PRIMER_OS_SUDO tee "$_rpl_tmp" > /dev/null; then
        if [ -e "$_rpl_path" ]; then
            primer_utils_path_ownership "$_rpl_tmp" --as "$_rpl_path"
        else
            $PRIMER_OS_SUDO chmod 644 "$_rpl_tmp"
        fi
        $PRIMER_OS_SUDO mv -f "$_rpl_tmp" "$_rpl_path"
    else
        $PRIMER_OS_SUDO rm -f "$_rpl_tmp"
        return 1
    fi
}

# Install the executable file $1 as $2, or into $2 when it is a directory, and
# remove $1. The installed file is a copy made with sudo, so it is owned by
# root rather than by the owner of $1, e.g. the user running primer or the uid
# recorded in a tar archive. It is executable by all, and moved in place
# atomically.
primer_utils_install_bin() {
    _ib_dst=$2
    [ -d "$_ib_dst" ] && _ib_dst="${_ib_dst%/}/$(basename "$1")"
    _ib_tmp=$($PRIMER_OS_SUDO mktemp "$(dirname "$_ib_dst")/.$(basename "$_ib_dst").XXXXXX")
    if $PRIMER_OS_SUDO cp "$1" "$_ib_tmp" && $PRIMER_OS_SUDO chmod 755 "$_ib_tmp"; then
        $PRIMER_OS_SUDO mv -f "$_ib_tmp" "$_ib_dst"
        rm -f "$1"
    else
        $PRIMER_OS_SUDO rm -f "$_ib_tmp"
        return 1
    fi
}

# Remove the binary at $1 when it is at the version $2, the one that primer
# installs, as reported by the command $3 called with $1 (primer_version_current
# by default). Leading v are ignored. Binaries at other versions, or when the
# version is unknown, might not have been installed by primer: they are kept,
# with a warning.
primer_utils_remove_at_version() {
    [ -e "$1" ] || return 0
    _rv_have=$("${3:-primer_version_current}" "$1" 2>/dev/null || true)
    if [ -n "$2" ] && [ "${_rv_have#v}" = "${2#v}" ]; then
        yush_info "Removing $1 at version $_rv_have"
        $PRIMER_OS_SUDO rm -f "$1"
    else
        yush_warn "Keeping $1, at version ${_rv_have:-unknown}, not installed by primer (version ${2:-unknown})"
    fi
}

# Remove all lines matching the basic regular expression $2 from (not only
# system) file at $1. The file is read with sudo, as only root might be able to.
primer_utils_sysfile_clip() {
    _clip_tmp=$(mktemp)
    # grep returns 1 when all lines are removed, which is not an error, but 2
    # on errors, e.g. a missing file.
    if $PRIMER_OS_SUDO grep -v -e "$2" "$1" > "$_clip_tmp" || [ "$?" = "1" ]; then
        primer_utils_sysfile_replace "$1" < "$_clip_tmp"
        rm -f "$_clip_tmp"
    else
        rm -f "$_clip_tmp"
        return 1
    fi
}


# Somewhat restrictive recursive file ownership changes. The default is to
# arrange for the tree passed as first argument to be owned by the caller and
# only readable and writable by that user. Options are as follows:
# --user   Transfer ownership to that user (and his/her group)
# --group  Specific group for ownership
# --perm   chmod compatible access rights
# --as     Take ownership and access rights from this file/dir instead
primer_utils_path_ownership() {
    # Variables are prefixed, as callers might use the same names (shell
    # variables are global).
    _po_path="$1"
    shift
    _po_user=$(id -un)
    _po_group=$(id -gn)
    _po_perms="u+rw,go-rw"
    while [ $# -gt 0 ]; do
        case "$1" in
            --user*)
                _po_user=$2; _po_group=$(id -gn "$2");  shift 2;;
            --group*)
                _po_group=$2;  shift 2;;
            --perm*)
                _po_perms=$2; shift 2;;
            --as*)
                # Numeric ids, as the reference might be owned by ids without
                # names.
                _po_user=$(stat -c "%u" "$2")
                _po_group=$(stat -c "%g" "$2")
                _po_perms=$(stat -c "%a" "$2")
                shift 2
                ;;
            -*)
                yush_warn "Unknown option: $1 !"; shift 2;;
            *)
                break;;
        esac
    done

    $PRIMER_OS_SUDO chown -R "${_po_user}:${_po_group}" "$_po_path"
    $PRIMER_OS_SUDO chmod -R "$_po_perms" "$_po_path"
}
