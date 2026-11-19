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

# Print the default login shell for new (human) users on this platform, i.e.
# the shell the main user creation tool of the distribution gives them:
# - Debian derivatives: the DSHELL setting of adduser, /bin/bash when unset.
#   This is the default of adduser and of the installer, while the low-level
#   useradd defaults to /bin/sh.
# - Alpine: /bin/sh, as busybox adduser and root, even when shadow is installed
#   (its useradd defaults to /bin/ash, the same busybox shell).
# - Other distributions with useradd: its default, e.g. /bin/bash on Fedora.
# - Otherwise /bin/sh.
# The shell must exist and be a valid login shell, /bin/sh is used otherwise.
_primer_auth_default_shell() {
    _def_shell=
    case "$(primer_os_distribution)" in
        *buntu|*bian)
            if [ -f /etc/adduser.conf ]; then
                _def_shell=$(sed -nE 's/^[[:space:]]*DSHELL[[:space:]]*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' /etc/adduser.conf | tail -n 1)
            fi
            [ -z "$_def_shell" ] && _def_shell=/bin/bash
            ;;
        alpine*)
            _def_shell=/bin/sh
            ;;
        *)
            if primer_utils_syscmd_exists useradd; then
                _def_shell=$(useradd -D 2>/dev/null | sed -n 's/^SHELL=//p' | head -n 1)
            fi
            ;;
    esac
    if [ -n "$_def_shell" ] && [ -x "$_def_shell" ] && _primer_auth_valid_shell "$_def_shell"; then
        printf %s\\n "$_def_shell"
    else
        printf %s\\n /bin/sh
    fi
}

# Return success when the GECOS details passed as an argument can be stored in
# /etc/passwd, i.e. contain neither colons nor newlines: removing them must not
# change the details.
_primer_auth_valid_gecos() {
    [ "$(printf %s "$1" | tr -d ':\n')" = "$1" ]
}

# Create user $1. Options are:
# --group     Main group of the user, created if necessary (default: the name
#             of the user)
# --shell     Login shell, empty for the default login shell of the platform
#             (the default, see _primer_auth_default_shell)
# --gecos     GECOS details, also --details or --comment
# --password  Password of the user, no password when empty (the default)
primer_auth_user_add() {
    if [ "$#" -gt "0" ]; then
        _username="$1"
        shift
        _group=
        _shell=
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
        [ -z "$_shell" ] && _shell=$(_primer_auth_default_shell)

        # Validate shell
        if ! _primer_auth_valid_shell "$_shell"; then
            yush_warn "$_shell is not a valid login shell!"
            return 1
        fi
        if ! _primer_auth_valid_gecos "$_gecos"; then
            yush_warn "GECOS details for $_username cannot contain colons or newlines!"
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
# their defaults are the current settings of the user. Empty values (group,
# shell, GECOS) keep the current settings.
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
                    if [ -n "$2" ]; then _group=$2; fi
                    shift 2;;
                --shell)
                    if [ -n "$2" ]; then _shell=$2; fi
                    shift 2;;
                --gecos | --details | --comment)
                    if [ -n "$2" ]; then _gecos=$2; fi
                    shift 2;;
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
        if ! _primer_auth_valid_gecos "$_gecos"; then
            yush_warn "GECOS details for $_username cannot contain colons or newlines!"
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
            # /etc/passwd. Values are passed through the environment, as awk
            # would interpret backslashes in -v assignments. The file is
            # replaced atomically, and only when the new content looks sane.
            _gid=$(getent group "$_group" | cut -d ":" -f 3)
            _passwd=$(mktemp)
            if PRIMER_AUTH_U=$_username PRIMER_AUTH_G=$_gid \
                PRIMER_AUTH_C=$_gecos PRIMER_AUTH_S=$_shell \
                    awk -F ":" -v OFS=":" '
                        $1 == ENVIRON["PRIMER_AUTH_U"] {
                            $4 = ENVIRON["PRIMER_AUTH_G"]
                            $5 = ENVIRON["PRIMER_AUTH_C"]
                            $7 = ENVIRON["PRIMER_AUTH_S"]
                        }
                        { print }' /etc/passwd > "$_passwd" \
                    && [ -n "$_gid" ] \
                    && grep -q "^${_username}:" "$_passwd"; then
                primer_utils_sysfile_replace /etc/passwd < "$_passwd"
                rm -f "$_passwd"
            else
                rm -f "$_passwd"
                yush_error "Could not modify $_username in /etc/passwd"
                return 1
            fi
        fi
        if [ -n "$_password" ]; then
            primer_auth_user_password "$_username" "$_password"
        fi
    fi
}
