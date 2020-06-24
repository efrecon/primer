#!/usr/bin/env sh

# Path to file/dir installation specification. The file contains colon separated
# lines with good default values. Fields are #1 source, #2 destination, #3
# owner, #4 group, #5 permissions
PRIMER_STEP_INSTALL_BUNDLE=${PRIMER_STEP_INSTALL_BUNDLE:-}

# Same as above, but a space separated of such-formatted specifications
PRIMER_STEP_INSTALL_TARGETS=${PRIMER_STEP_INSTALL_TARGETS:-}

primer_step_install() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--bundle --target"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --bundle)
                        PRIMER_STEP_INSTALL_BUNDLE=$2; shift 2;;
                    --target)
                        PRIMER_STEP_INSTALL_TARGETS="$PRIMER_STEP_INSTALL_TARGETS $2"; shift 2;;
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
    src=$(printf %s\\n "$2" | cut -d ":" -f "1" | primer_net_urldec)
    tgt=$(printf %s\\n "$2" | cut -d ":" -f "2" | primer_net_urldec)
    user=$(printf %s\\n "$2" | cut -d ":" -f "3")
    if [ -z "$user" ]; then
        user=$(id -un)
        yush_debug "$tgt will be owned by user: $user"
    fi
    group=$(printf %s\\n "$2" | cut -d ":" -f "4")
    if [ -z "$group" ]; then
        group=$(id -gn)
        yush_debug "$tgt will be owned by group: $group"
    fi
    perms=$(printf %s\\n "$2" | cut -d ":" -f "5")
    if [ -z "$perms" ]; then
        perms=u+rw,g+r,g-w,o-rw
        yush_debug "Permissions for $tgt will be: $perms"
    fi

    case "$1" in
        "install")
            if printf %s\\n "$src" | grep -Eq '^https?://'; then
                if [ -d "$tgt" ]; then
                    tgt=${tgt%/}/$(yush_basename "$src")
                fi
                yush_info "Downloading $src into $tgt"
                # shellcheck disable=SC2086
                primer_net_curl "$src" | $PRIMER_OS_SUDO tee "$tgt" > /dev/null
            else
                if [ -d "$tgt" ]; then
                    yush_info "Recursively copying $src into $tgt"
                    $PRIMER_OS_SUDO cp -R "$src" "$tgt"
                else
                    yush_info "Copying $src into $tgt"
                    $PRIMER_OS_SUDO cp "$src" "$tgt"
                fi
            fi

            primer_utils_path_ownership "$tgt" \
                                            --user "$user" \
                                            --group "$group" \
                                            --perms "$perms"
            ;;
        "clean")
            if printf %s\\n "$src" | grep -Eq '^https?://'; then
                if [ -d "$tgt" ]; then
                    tgt=${tgt%/}/$(yush_basename "$src")
                fi
            fi
            if [ -d "$tgt" ]; then
                # If the source was a directory, remove the entire directory
                # destination. Otherwise, only remove the file that it created.
                if [ -d "$src" ]; then
                    yush_info "Recursively removing $tgt"
                    $PRIMER_OS_SUDO rm -rf "$tgt"
                else
                    tgt=${tgt%/}/$(yush_basename "$src")
                    yush_info "Removing $tgt"
                    $PRIMER_OS_SUDO rm -f "$tgt"
                fi
            else
                yush_info "Removing $tgt"
                $PRIMER_OS_SUDO rm -f "$tgt"
            fi
            ;;
    esac
}
