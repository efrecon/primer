#!/usr/bin/env sh

# List regular users, or system users with -a or --all
primer_auth_user_list() {
    if [ "$#" -gt "0" ] && { [ "$1" = "-a" ] || [ "$1" = "--all" ]; }; then
        getent passwd | cut -d ":" -f "1"
    elif [ -f "/etc/login.defs" ]; then
        # Only regular users
        _min=$(grep -E ^UID_MIN /etc/login.defs | awk '{print $2}')
        _max=$(grep -E ^UID_MAX /etc/login.defs | awk '{print $2}')
        _primer_auth_getent_passwd "$_min" "$_max"
    else
        yush_debug "No /etc/login.defs, using defaults"
        _primer_auth_getent_passwd "1000" "60000"
    fi
}

# This reimplements getent passwd {min..max} as it does not exists on Alpine.
_primer_auth_getent_passwd() {
    getent passwd | while IFS= read -r line; do
        _uid=$(printf %s\\n "$line" | cut -d ":" -f 3)
        if [ "$_uid" -ge "$1" ] && [ "$_uid" -le "$2" ]; then
            printf %s\\n "$line" | cut -d ":" -f 1
        fi
    done 
}

# Create user group passed as parameter if it does not exist.
primer_auth_group_add() {
    if [ "$#" -gt "0" ] && [ -n "$1" ]; then
        if ! getent group | grep -q "^$1:"; then
            yush_info "Creating group: $1"
            if primer_utils_syscmd_exists addgroup; then
                $PRIMER_OS_SUDO addgroup "$1"
            elif primer_utils_syscmd_exists groupadd; then
                $PRIMER_OS_SUDO groupadd "$1"
            fi
        else
            yush_debug "Group $1 already exists"
        fi
    fi
}

# Add user $1 to group $2
primer_auth_group_membership() {
    if [ "$#" -gt "1" ] && [ -n "$1" ] && [ -n "$2" ]; then
        if id -Gn "$1" | tr ' ' '\n' | grep -qx "$2"; then
            yush_debug "$1 already in group $2"
        else
            yush_info "Adding $1 to group $2"
            if primer_utils_syscmd_exists usermod; then
                $PRIMER_OS_SUDO usermod -a -G "$2" "$1"
            elif primer_utils_syscmd_exists addgroup; then
                $PRIMER_OS_SUDO addgroup "$1" "$2"
            fi
        fi
    fi
}

# Return success when the shell passed as an argument is a valid login shell.
_primer_auth_valid_shell() {
    [ -f /etc/shells ] && grep -qxF "$1" /etc/shells
}

# Create user $1. Options are:
# --group     Main group of the user, created if necessary (default: the name
#             of the user)
# --shell     Login shell (default: the shell of the caller, or /bin/sh)
# --gecos     GECOS details, also --details or --comment
# --password  Password of the user, no password when empty (the default)
primer_auth_user_add() {
    if [ "$#" -gt "0" ]; then
        _username="$1"
        shift
        _group=
        _caller=$(id -un)
        _shell=$(getent passwd "$_caller" | cut -d ":" -f 7)
        [ -z "$_shell" ] && _shell=/bin/sh
        _gecos=""
        _password=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --group)
                    _group=$2; shift 2;;
                --shell)
                    _shell=$2; shift 2;;
                --gecos | --details | --comment)
                    _gecos=$2; shift 2;;
                --pass*)
                    _password=$2; shift 2;;
                -*)
                    yush_warn "Unknown option: $1 !"; shift 2;;
                *)
                    break;;
            esac
        done
        [ -z "$_group" ] && _group=$_username

        # Validate shell
        if ! _primer_auth_valid_shell "$_shell"; then
            yush_warn "$_shell is not a valid login shell!"
            return 1
        fi

        # Create group for user if it does not exist.
        if ! getent group | grep -q "^$_group:"; then
            primer_auth_group_add "$_group"
        fi

        # Create the user, without password, coping with the nightmare of the
        # various adduser and useradd and their varying options...
        if primer_utils_syscmd_exists useradd; then
            $PRIMER_OS_SUDO useradd \
                            --create-home \
                            --gid "$_group" \
                            --comment "$_gecos" \
                            --shell "$_shell" \
                        "$_username"
        elif primer_utils_syscmd_exists adduser; then
            if adduser -h 2>&1 | grep -iq busybox; then
                $PRIMER_OS_SUDO adduser \
                                -G "$_group" \
                                -g "$_gecos" \
                                -s "$_shell" \
                                -D \
                            "$_username"
            else
                $PRIMER_OS_SUDO adduser \
                                --ingroup "$_group" \
                                --gecos "$_gecos" \
                                --shell "$_shell" \
                                --disabled-password \
                            "$_username"
            fi
        else
            yush_error "Neither useradd nor adduser available, cannot create $_username"
            return 1
        fi

        # Set the password, if any.
        if [ -n "$_password" ]; then
            primer_auth_user_password "$_username" "$_password"
        fi
    fi
}

# Set the password of user $1 to $2, does nothing when $2 is empty.
primer_auth_user_password() {
    if [ -n "${2:-}" ]; then
        if primer_utils_syscmd_exists chpasswd; then
            printf '%s:%s\n' "$1" "$2" | $PRIMER_OS_SUDO chpasswd
        else
            printf %s\\n%s\\n "$2" "$2" | $PRIMER_OS_SUDO passwd "$1"
        fi
    fi
}

# Modify existing user $1. Options are the same as for primer_auth_user_add,
# their defaults are the current settings of the user.
primer_auth_user_mod() {
    if [ "$#" -gt "0" ]; then
        _username="$1"
        shift
        _entry=$(getent passwd "$_username" || true)
        if [ -z "$_entry" ]; then
            yush_warn "User $_username does not exist!"
            return 1
        fi
        _group=$(id -gn "$_username")
        _gecos=$(printf %s\\n "$_entry" | cut -d ":" -f 5)
        _shell=$(printf %s\\n "$_entry" | cut -d ":" -f 7)
        _password=
        while [ $# -gt 0 ]; do
            case "$1" in
                --group)
                    _group=$2; shift 2;;
                --shell)
                    _shell=$2; shift 2;;
                --gecos | --details | --comment)
                    _gecos=$2; shift 2;;
                --pass*)
                    _password=$2; shift 2;;
                -*)
                    yush_warn "Unknown option: $1 !"; shift 2;;
                *)
                    break;;
            esac
        done

        # Validate shell
        if ! _primer_auth_valid_shell "$_shell"; then
            yush_warn "$_shell is not a valid login shell!"
            return 1
        fi

        # Create group for user if it does not exist.
        if ! getent group | grep -q "^$_group:"; then
            primer_auth_group_add "$_group"
        fi

        if primer_utils_syscmd_exists usermod; then
            $PRIMER_OS_SUDO usermod \
                            --gid "$_group" \
                            --comment "$_gecos" \
                            --shell "$_shell" \
                        "$_username"
        else
            # No usermod (e.g. busybox): rewrite the entry of the user in
            # /etc/passwd. Writing through tee keeps the owner and mode of the
            # file (busybox cp would copy the mode of the temporary file).
            _gid=$(getent group "$_group" | cut -d ":" -f 3)
            _tmp=$(mktemp)
            awk -F ":" -v OFS=":" \
                -v u="$_username" -v g="$_gid" -v c="$_gecos" -v s="$_shell" \
                '$1 == u { $4 = g; $5 = c; $7 = s } { print }' /etc/passwd > "$_tmp"
            $PRIMER_OS_SUDO tee /etc/passwd < "$_tmp" > /dev/null
            rm -f "$_tmp"
        fi
        if [ -n "$_password" ]; then
            primer_auth_user_password "$_username" "$_password"
        fi
    fi
}
