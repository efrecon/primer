#!/usr/bin/env sh

# Path to disk creation/mounting specification. The file contains colon
# separated lines with good default values. Fields are #1 dev name (sans /dev/)
# #2 filesystem type, e.g. ext4, #3 mount point, #4 colon separated mount
# options, #5 user, #6 group #7 permissions for mount point 
PRIMER_STEP_DISK_DB=${PRIMER_STEP_DISK_DB:-}

# Default format when none specified
PRIMER_STEP_DISK_FORMAT=${PRIMER_STEP_DISK_FORMAT:-ext4}

# Should we reformat (with specified filesystem type) when device is already
# formatted?
PRIMER_STEP_DISK_OVERWRITE=${PRIMER_STEP_DISK_OVERWRITE:-0}

# ext4 formatting options. This variable will automatically be looked up using
# the name of the filesystem to be used, converted to upper case.
PRIMER_STEP_DISK_EXT4=${PRIMER_STEP_DISK_EXT4:-"-m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard"}

primer_step_disk() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--db --ext4 --overwrite"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --db)
                        PRIMER_STEP_DISK_DB=$2; shift 2;;
                    --ext4)
                        PRIMER_STEP_DISK_EXT4=$2; shift 2;;
                    --overwrite)
                        PRIMER_STEP_DISK_OVERWRITE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -n "$PRIMER_STEP_DISK_DB" ] && [ -f "$PRIMER_STEP_DISK_DB" ]; then
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "${line}" ]; then
                        # Parse lines and find out good defaults.
                        _primer_step_disk_linespec "$line"

                        # Resolve symlinks, as we can use udev disk/by-label
                        # categorisation, but only the real target will be
                        # reported by mount
                        if [ -L "/dev/${dev}" ]; then
                            _dev=$(readlink -f "/dev/${dev}")
                            yush_debug "Resolved /dev/${dev} to $_dev"
                        else
                            _dev="/dev/${dev}"
                        fi

                        if ls -1 "$_dev" >/dev/null 2>&1; then
                            # Make sure we can format at that filesystem
                            mkfs=mkfs.$fmt
                            if command -v "$mkfs" >/dev/null; then
                                # Check if device is already formatted.
                                current=$($PRIMER_OS_SUDO blkid "$_dev" | _primer_step_disk_blkid_val "TYPE")
                                format=0
                                if [ -z "$current" ]; then
                                    format=1
                                elif yush_is_true "$PRIMER_STEP_DISK_OVERWRITE"; then
                                    format=1
                                    yush_warn "/dev/$dev already formatted as $current, overwriting with $fmt filesystem"
                                else
                                    yush_notice "/dev/$dev already formatted as $current, keeping it"
                                fi

                                # Format
                                if [ "$format" = "1" ]; then
                                    # Figure out filesystem specific mkfs
                                    # options.
                                    fstype=$(printf "%s" "$fmt" | tr '[:lower:]' '[:upper:]')
                                    varname=PRIMER_STEP_DISK_$fstype
                                    mkfs_opts=
                                    if primer_utils_var_exists "$varname"; then
                                        mkfs_opts=$(primer_utils_var_value "$varname")
                                    fi

                                    # Format with requested filesystem
                                    yush_notice "Formatting /dev/$dev as $fmt with options: $opts"
                                    $PRIMER_OS_SUDO "mkfs.${PRIMER_STEP_DISK_FORMAT}" $mkfs_opts "$_dev"
                                fi

                                # Create mount point
                                yush_debug "Creating mount point"
                                $PRIMER_OS_SUDO mkdir -p "$mnt"

                                # Persist mount over reboots through using the
                                # UUID of the device.
                                yush_debug "Getting UUID for /dev/$dev"
                                # We parse the output, even though it would be
                                # tempting to use eval as whatever comes after
                                # the colon sign is well-formatted shell vars
                                uuid=$($PRIMER_OS_SUDO blkid "$_dev" | _primer_step_disk_blkid_val "UUID")
                                if [ -n "$uuid" ]; then
                                    if mount | grep -qE "^$_dev"; then
                                        yush_warn "$_dev already mounted, skipping $mnt mountpoint!"
                                    else
                                        yush_notice "Mounting $uuid onto $mnt at boot with options: $opts"
                                        printf "UUID=%s %s %s %s 0 2\n" "$uuid" "$mnt" "$fmt" "$opts" |
                                            $PRIMER_OS_SUDO tee -a /etc/fstab > /dev/null
                                        $PRIMER_OS_SUDO mount "$mnt"
                                        $PRIMER_OS_SUDO chown "${user}:${group}" "$mnt"
                                        $PRIMER_OS_SUDO chmod "$perms" "$mnt"
                                    fi
                                fi
                            else
                                yush_warn "$fmt is an unknown filesystem type!"
                            fi
                        else
                            yush_warn "$dev is not an existing device!"
                        fi
                    fi
                done < "${PRIMER_STEP_DISK_DB}"
            else
                yush_warn "No user disk specification provided, or cannot access."
            fi
            ;;
        "clean")
            if [ -n "$PRIMER_STEP_DISK_DB" ] && [ -f "$PRIMER_STEP_DISK_DB" ]; then
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "${line}" ]; then
                        # Parse lines and find out good defaults.
                        _primer_step_disk_linespec "$line"

                        # Resolve symlinks, as we can use udev disk/by-label
                        # categorisation, but only the real target will be
                        # reported by mount
                        if [ -L "/dev/${dev}" ]; then
                            _dev=$(readlink -f "/dev/${dev}")
                            yush_debug "Resolved /dev/${dev} to $_dev"
                        else
                            _dev="/dev/${dev}"
                        fi

                        if mount | grep -qE "^$_dev on $mnt"; then
                            yush_notice "Unmounting $mnt"
                            $PRIMER_OS_SUDO umount "$mnt"
                        fi

                        if $PRIMER_OS_SUDO grep -q "$mnt $fmt" /etc/fstab; then
                            yush_notice "Removing $dev from boottime mount as $mnt"
                            _tmp=$(mktemp)
                            $PRIMER_OS_SUDO grep -v "$mnt $fmt" /etc/fstab > "$_tmp"
                            primer_utils_path_ownership "$_tmp" --user root
                            $PRIMER_OS_SUDO mv "$_tmp" /etc/fstab
                        fi

                        [ -d "$mnt" ] && $PRIMER_OS_SUDO rmdir "$mnt"
                    fi
                done < "${PRIMER_STEP_DISK_DB}"
            else
                yush_warn "No user disk specification provided, or cannot access."
            fi
            ;;
    esac
}

_primer_step_disk_linespec() {
    dev=$(printf %s\\n "$1" | cut -d ":" -f "1")
    fmt=$(printf %s\\n "$1" | cut -d ":" -f "2")
    if [ -z "$fmt" ]; then
        fmt=$PRIMER_STEP_DISK_FORMAT
        yush_debug "Defaulting to $PRIMER_STEP_DISK_FORMAT filesystem"
    fi
    mnt=$(printf %s\\n "$1" | cut -d ":" -f "3")
    if [ -z "$mnt" ]; then
        mnt=/mnt/disks/$dev
        yush_debug "Mounting to $mnt (default)"
    fi
    opts=$(printf %s\\n "$1" | cut -d ":" -f "4")
    if [ -z "$opts" ]; then
        opts=defaults,nofail
        yush_debug "Using default mount options: $opts"
    fi
    user=$(printf %s\\n "$1" | cut -d ":" -f "5")
    if [ -z "$user" ]; then
        user=root
        yush_debug "$mnt will be owned by user: $user"
    fi
    group=$(printf %s\\n "$1" | cut -d ":" -f "6")
    if [ -z "$group" ]; then
        group=root
        yush_debug "$mnt will be owned by group: $group"
    fi
    perms=$(printf %s\\n "$1" | cut -d ":" -f "7")
    if [ -z "$perms" ]; then
        perms=a+w
        yush_debug "Permissions for $mnt will be: $perms"
    fi
}

_primer_step_disk_blkid_val() {
    grep -Eo "\s+${1}=\"[[:alnum:]-]+\"" | sed -E "s/\s+${1}=\"([[:alnum:]-]+)\"/\1/"
}