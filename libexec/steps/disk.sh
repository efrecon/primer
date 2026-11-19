#!/usr/bin/env sh

# Path to disk creation/mounting specification. The file contains colon
# separated lines with good default values. Fields are #1 dev name (sans /dev/)
# #2 filesystem type, e.g. ext4, #3 mount point, #4 comma separated mount
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
                        _primer_step_disk_install "$line" < /dev/null
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
                        _primer_step_disk_clean "$line" < /dev/null
                    fi
                done < "${PRIMER_STEP_DISK_DB}"
            else
                yush_warn "No user disk specification provided, or cannot access."
            fi
            ;;
    esac
}

# Format (when necessary) and mount the disk described by the specification
# line passed as an argument, and arrange for it to be mounted at boot.
_primer_step_disk_install() {
    # Parse line and find out good defaults.
    _primer_step_disk_linespec "$1"

    if ! ls -1 "$_dev" >/dev/null 2>&1; then
        yush_warn "$dev is not an existing device!"
        return 0
    fi

    # Never touch a device that is already mounted.
    if _primer_step_disk_mounted "$_dev"; then
        yush_warn "$_dev already mounted, skipping $mnt mountpoint!"
        return 0
    fi

    # Check if device is already formatted.
    current=$($PRIMER_OS_SUDO blkid "$_dev" | _primer_step_disk_blkid_val "TYPE" || true)
    format=0
    if [ -z "$current" ]; then
        format=1
    elif yush_is_true "$PRIMER_STEP_DISK_OVERWRITE"; then
        format=1
        yush_warn "/dev/$dev already formatted as $current, overwriting with $fmt filesystem"
    else
        if [ "$current" != "$fmt" ]; then
            yush_notice "/dev/$dev already formatted as $current, keeping it (and not $fmt)"
            fmt=$current
        else
            yush_notice "/dev/$dev already formatted as $current, keeping it"
        fi
    fi

    # Format
    if [ "$format" = "1" ]; then
        # Make sure we can format at that filesystem
        if ! primer_utils_syscmd_exists "mkfs.$fmt"; then
            yush_warn "$fmt is an unknown filesystem type!"
            return 0
        fi

        # Figure out filesystem specific mkfs options.
        fstype=$(printf "%s" "$fmt" | tr '[:lower:]' '[:upper:]')
        varname=PRIMER_STEP_DISK_$fstype
        mkfs_opts=
        if primer_utils_var_exists "$varname"; then
            mkfs_opts=$(primer_utils_var_value "$varname")
        fi
        # Force creation, as we have decided to (re)format: this also avoids
        # questions when the device is not a partition (whole disks, image
        # files). Mounted devices are still protected, see above.
        case "$fmt" in
            ext*) mkfs_opts="-F $mkfs_opts";;
            xfs|btrfs) mkfs_opts="-f $mkfs_opts";;
        esac

        # Format with requested filesystem
        yush_notice "Formatting /dev/$dev as $fmt with options: $mkfs_opts"
        # shellcheck disable=SC2086
        $PRIMER_OS_SUDO "mkfs.$fmt" $mkfs_opts "$_dev"
    fi

    # Persist mount over reboots through using the UUID of the device. We
    # parse the output, even though it would be tempting to use eval as
    # whatever comes after the colon sign is well-formatted shell vars
    yush_debug "Getting UUID for /dev/$dev"
    uuid=$($PRIMER_OS_SUDO blkid "$_dev" | _primer_step_disk_blkid_val "UUID" || true)
    if [ -z "$uuid" ]; then
        yush_warn "Cannot find UUID of $_dev, will not mount it"
        return 0
    fi

    yush_debug "Creating mount point"
    $PRIMER_OS_SUDO mkdir -p "$mnt"

    # Replace any previous entry for the mount point, e.g. from an earlier
    # installation or a disk that has been reformatted since.
    yush_notice "Mounting $uuid onto $mnt at boot with options: $opts"
    _primer_step_disk_fstab_remove "$mnt"
    printf "UUID=%s %s %s %s 0 2\n" "$uuid" "$mnt" "$fmt" "$opts" |
        $PRIMER_OS_SUDO tee -a /etc/fstab > /dev/null
    $PRIMER_OS_SUDO mount "$mnt"
    $PRIMER_OS_SUDO chown "${user}:${group}" "$mnt"
    $PRIMER_OS_SUDO chmod "$perms" "$mnt"
}

# Unmount the disk described by the specification line passed as an argument,
# and remove it from the disks mounted at boot.
_primer_step_disk_clean() {
    # Parse line and find out good defaults.
    _primer_step_disk_linespec "$1"

    if mount | grep -qE "^$_dev on $mnt "; then
        yush_notice "Unmounting $mnt"
        $PRIMER_OS_SUDO umount "$mnt"
    fi

    if _primer_step_disk_fstab_has "$mnt"; then
        yush_notice "Removing $dev from boottime mount as $mnt"
        _primer_step_disk_fstab_remove "$mnt"
    fi

    if [ -d "$mnt" ]; then
        $PRIMER_OS_SUDO rmdir "$mnt" || yush_warn "Could not remove mount point $mnt"
    fi
}

# Is the device passed as an argument mounted?
_primer_step_disk_mounted() {
    mount | grep -qE "^$1[[:space:]]"
}

# Is there an entry for the mount point passed as an argument in /etc/fstab?
_primer_step_disk_fstab_has() {
    [ -f /etc/fstab ] && awk -v m="$1" '$2 == m { found=1 } END { exit !found }' /etc/fstab
}

# Remove all entries for the mount point passed as an argument from
# /etc/fstab. The file is written back in place, so it keeps its owner and
# permissions.
_primer_step_disk_fstab_remove() {
    if _primer_step_disk_fstab_has "$1"; then
        _tmp=$(mktemp)
        awk -v m="$1" '$2 != m' /etc/fstab > "$_tmp"
        $PRIMER_OS_SUDO tee /etc/fstab < "$_tmp" > /dev/null
        rm -f "$_tmp"
    fi
}

_primer_step_disk_linespec() {
    dev=$(_primer_step_disk_field 1 "$1")
    fmt=$(_primer_step_disk_field 2 "$1")
    if [ -z "$fmt" ]; then
        fmt=$PRIMER_STEP_DISK_FORMAT
        yush_debug "Defaulting to $PRIMER_STEP_DISK_FORMAT filesystem"
    fi
    mnt=$(_primer_step_disk_field 3 "$1")
    if [ -z "$mnt" ]; then
        mnt=/mnt/disks/$dev
        yush_debug "Mounting to $mnt (default)"
    fi
    opts=$(_primer_step_disk_field 4 "$1")
    if [ -z "$opts" ]; then
        opts=defaults,nofail
        yush_debug "Using default mount options: $opts"
    fi
    user=$(_primer_step_disk_field 5 "$1")
    if [ -z "$user" ]; then
        user=root
        yush_debug "$mnt will be owned by user: $user"
    fi
    group=$(_primer_step_disk_field 6 "$1")
    if [ -z "$group" ]; then
        group=root
        yush_debug "$mnt will be owned by group: $group"
    fi
    perms=$(_primer_step_disk_field 7 "$1")
    if [ -z "$perms" ]; then
        perms=a+w
        yush_debug "Permissions for $mnt will be: $perms"
    fi

    # Resolve symlinks, as we can use udev disk/by-label categorisation, but
    # only the real target will be reported by mount
    if [ -L "/dev/${dev}" ]; then
        _dev=$(readlink -f "/dev/${dev}")
        yush_debug "Resolved /dev/${dev} to $_dev"
    else
        _dev="/dev/${dev}"
    fi
}

# Print field $1 of the colon separated specification line $2, empty when the
# line has fewer fields (unlike cut, which prints lines without separators).
_primer_step_disk_field() {
    printf %s\\n "$2" | awk -F: -v f="$1" '{ print $f }'
}

_primer_step_disk_blkid_val() {
    grep -Eo "[[:space:]]${1}=\"[[:alnum:]-]+\"" | sed -E "s/[[:space:]]${1}=\"([[:alnum:]-]+)\"/\1/"
}