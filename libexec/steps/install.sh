#!/usr/bin/env sh

# Path to file/dir installation specification. The file contains colon separated
# lines with good default values. Fields are #1 source, #2 destination, #3
# owner, #4 group, #5 permissions
PRIMER_STEP_INSTALL_BUNDLE=${PRIMER_STEP_INSTALL_BUNDLE:-}

# Same as above, but a space separated of such-formatted specifications
PRIMER_STEP_INSTALL_TARGETS=${PRIMER_STEP_INSTALL_TARGETS:-}

# Overwrite file/dirs even when they exists (this is on by default as this step
# is about installing new files)
PRIMER_STEP_INSTALL_OVERWRITE=${PRIMER_STEP_INSTALL_OVERWRITE:-1}

primer_step_install() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--bundle --target --targets"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --bundle)
                        PRIMER_STEP_INSTALL_BUNDLE=$2; shift 2;;
                    --target)
                        PRIMER_STEP_INSTALL_TARGETS="$PRIMER_STEP_INSTALL_TARGETS $2"; shift 2;;
                    --targets)
                        PRIMER_STEP_INSTALL_TARGETS=$2; shift 2;;
                    --overwrite)
                        PRIMER_STEP_INSTALL_OVERWRITE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install" | "clean")
            if [ -n "$PRIMER_STEP_INSTALL_BUNDLE" ]; then
                if [ -f "$PRIMER_STEP_INSTALL_BUNDLE" ]; then
                    while IFS= read -r line || [ -n "$line" ]; do
                        line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                        if [ -n "${line}" ]; then
                            _primer_step_install "$1" "$line"
                        fi
                    done < "${PRIMER_STEP_INSTALL_BUNDLE}"
                else
                    yush_warn "Cannot access file at $PRIMER_STEP_INSTALL_BUNDLE"
                fi
            fi
            for spec in $PRIMER_STEP_INSTALL_TARGETS; do
                _primer_step_install "$1" "$spec"
            done
            ;;
    esac
}

_primer_step_install() {
    src=$(_primer_step_install_field "$2" 1 | primer_net_urldec)
    tgt=$(_primer_step_install_field "$2" 2 | primer_net_urldec)
    if [ -z "$tgt" ]; then
        yush_warn "No destination in installation specification $2, skipping"
        return 0
    fi
    user=$(_primer_step_install_field "$2" 3)
    if [ -z "$user" ]; then
        user=$(id -un)
        yush_debug "$tgt will be owned by user: $user"
    fi
    group=$(_primer_step_install_field "$2" 4)
    if [ -z "$group" ]; then
        group=$(id -gn)
        yush_debug "$tgt will be owned by group: $group"
    fi
    perms=$(_primer_step_install_field "$2" 5)
    if [ -z "$perms" ]; then
        perms=u+rw,g+r,g-w,o-rw
        yush_debug "Permissions for $tgt will be: $perms"
    fi

    case "$1" in
        "install")
            # The default is to change the permissions of the destination.
            # However, when overwrite is set to disabled, we will only change
            # the permissions when the destination didn't already exist. In
            # other words, when overwrite is disabled, we are being conservative
            # and don't change anything.
            do_perms=1

            # Copy remote locations, directories or files. Arrange to check for
            # existence before copies occurs so as to respect
            # PRIMER_STEP_INSTALL_OVERWRITE
            if printf %s\\n "$src" | grep -Eq '^https?://'; then
                if [ -d "$tgt" ]; then
                    tgt=${tgt%/}/$(yush_basename "$src")
                fi

                if [ -f "$tgt" ] && ! yush_is_true "$PRIMER_STEP_INSTALL_OVERWRITE"; then
                    yush_debug "Target $tgt already exists!"
                    do_perms=0
                else
                    # Download to a temporary file first, so a failed download
                    # never truncates an existing target.
                    yush_info "Downloading $src into $tgt"
                    _download=$(mktemp)
                    if primer_net_curl "$src" > "$_download"; then
                        primer_utils_sysfile_replace "$tgt" < "$_download"
                    else
                        yush_warn "Could not download $src, $tgt left untouched"
                        do_perms=0
                    fi
                    rm -f "$_download"
                fi
            elif [ -z "$src" ]; then
                # When the source is empty, we have a special case and simply
                # ensure the target directory or file exists. Directories should
                # end with a slash.
                if yush_glob '*/' "$tgt"; then
                    if [ -d "$tgt" ]; then
                        yush_debug "Directory at $tgt already exists!"
                        if ! yush_is_true "$PRIMER_STEP_INSTALL_OVERWRITE"; then
                            do_perms=0
                        fi
                    else
                        yush_info "Creating directory $tgt"
                        mkdir -p "$tgt"
                    fi
                else
                    if [ -f "$tgt" ]; then
                        yush_debug "File at $tgt already exists!"
                        if ! yush_is_true "$PRIMER_STEP_INSTALL_OVERWRITE"; then
                            do_perms=0
                        fi
                    else
                        yush_info "Creating empty file $tgt, including containing directory"
                        mkdir -p "$(yush_dirname "$tgt")"
                        touch "$tgt"
                    fi
                fi
            else
                # When here, the source is neither empty, nor a remote resource,
                # so we consider it a local file or directory. When the target
                # is an existing directory, or ends with a slash, the source is
                # copied into it. The effective target is then the copy, so
                # that permissions only apply to what was installed. A target
                # directory (without a slash) that only contains files from
                # the source directory is the copy made by an earlier
                # installation: it is refreshed rather than copied into.
                if [ -d "$src" ] && ! yush_glob '*/' "$tgt" \
                        && _primer_step_install_within "$src" "$tgt"; then
                    yush_debug "$tgt is a copy of $src"
                elif [ -d "$tgt" ] || yush_glob '*/' "$tgt"; then
                    [ -d "$tgt" ] || $PRIMER_OS_SUDO mkdir -p "$tgt"
                    tgt=${tgt%/}/$(yush_basename "${src%/}")
                fi
                if { [ -e "$tgt" ] || [ -L "$tgt" ]; } && ! yush_is_true "$PRIMER_STEP_INSTALL_OVERWRITE"; then
                    yush_debug "Target $tgt already exists!"
                    do_perms=0
                elif [ -d "$src" ]; then
                    yush_info "Recursively copying $src to $tgt"
                    if [ -d "$tgt" ]; then
                        $PRIMER_OS_SUDO cp -R "${src%/}/." "$tgt"
                    else
                        $PRIMER_OS_SUDO cp -R "$src" "$tgt"
                    fi
                else
                    yush_info "Copying $src to $tgt"
                    $PRIMER_OS_SUDO cp "$src" "$tgt"
                fi
            fi

            if [ "$do_perms" = "1" ]; then
                yush_debug "$tgt will be owned by user: ${user}:${group} and with permissions: $perms"
                primer_utils_path_ownership "$tgt" \
                                                --user "$user" \
                                                --group "$group" \
                                                --perms "$perms"
            fi
            ;;
        "clean")
            if [ -z "$src" ] && yush_glob '*/' "$tgt"; then
                # Directories created from an empty source are only removed
                # when empty, they might have been populated since.
                if [ -d "$tgt" ]; then
                    if [ -z "$(ls -A "$tgt")" ]; then
                        yush_info "Removing directory $tgt"
                        $PRIMER_OS_SUDO rmdir "$tgt"
                    else
                        yush_warn "Directory $tgt is not empty, keeping it"
                    fi
                fi
            elif printf %s\\n "$src" | grep -Eq '^https?://'; then
                # Downloads are placed into target directories.
                if [ -d "$tgt" ]; then
                    tgt=${tgt%/}/$(yush_basename "$src")
                fi
                _primer_step_install_rm_file "$tgt"
            elif [ -d "$src" ]; then
                # Directories are copied into existing target directories, or
                # become the target. As nothing records which one happened,
                # only remove directories that are (still) a copy of the
                # source: the copy inside the target first, then the target
                # itself, unless it ends with a slash, i.e. was meant as a
                # parent directory. This never removes a directory that
                # existed before installation, even when cleaning twice.
                _into=${tgt%/}/$(yush_basename "${src%/}")
                if _primer_step_install_is_copy "$src" "$_into"; then
                    yush_info "Recursively removing $_into"
                    $PRIMER_OS_SUDO rm -rf "$_into"
                elif ! yush_glob '*/' "$tgt" && _primer_step_install_is_copy "$src" "$tgt"; then
                    yush_info "Recursively removing $tgt"
                    $PRIMER_OS_SUDO rm -rf "$tgt"
                elif [ -e "$_into" ]; then
                    yush_warn "$_into is not a copy of $src (anymore), not removing it"
                elif [ -e "$tgt" ] && ! yush_glob '*/' "$tgt"; then
                    yush_notice "$tgt is not a copy of $src, not removing it"
                fi
            else
                # Files are copied into target directories, or become the
                # target.
                if [ -n "$src" ] && { yush_glob '*/' "$tgt" || [ -d "$tgt" ]; }; then
                    tgt=${tgt%/}/$(yush_basename "$src")
                fi
                _primer_step_install_rm_file "$tgt"
            fi
            ;;
    esac
}

# Print field number $2 of the colon-separated specification $1, empty when the
# specification has less fields (cut would print the whole line when there is
# no colon at all).
_primer_step_install_field() {
    printf %s\\n "$1" | awk -F: -v n="$2" '{print $n}'
}

# Remove the file (or link) at $1, never a directory.
_primer_step_install_rm_file() {
    if [ -d "$1" ] && ! [ -L "$1" ]; then
        yush_warn "Not removing directory $1"
    elif [ -e "$1" ] || [ -L "$1" ]; then
        yush_info "Removing $1"
        $PRIMER_OS_SUDO rm -f "$1"
    fi
}

# Print the paths of all files and directories under directory $1, relative
# to $1, sorted.
_primer_step_install_tree() {
    _root=${1%/}
    $PRIMER_OS_SUDO find "$_root/" -mindepth 1 | cut -c "$(( ${#_root} + 2 ))-" | sort
}

# Does the non-empty directory at $2 only contain paths that also exist in the
# (source) directory at $1? This is the case for a copy of $1, even when files
# have been added to $1 since. Links to directories are never copies.
_primer_step_install_within() {
    if [ -d "$2" ] && ! [ -L "$2" ] && [ -d "$1" ]; then
        _within_src=$(mktemp)
        _primer_step_install_tree "$1" > "$_within_src"
        _within_tgt=$(_primer_step_install_tree "$2")
        _within_extra=$(printf %s\\n "$_within_tgt" | grep -vxF -f "$_within_src" || true)
        rm -f "$_within_src"
        [ -n "$_within_tgt" ] && [ -z "$_within_extra" ]
    else
        return 1
    fi
}

# Is the directory at $2 a copy of the (source) directory at $1, i.e. do they
# contain the same, non-empty, set of paths? Links to directories are never
# copies.
_primer_step_install_is_copy() {
    if [ -d "$2" ] && ! [ -L "$2" ] && [ -d "$1" ]; then
        _src_tree=$(_primer_step_install_tree "$1")
        [ -n "$_src_tree" ] && [ "$_src_tree" = "$(_primer_step_install_tree "$2")" ]
    else
        return 1
    fi
}
