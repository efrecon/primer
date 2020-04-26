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
            if [ -x "$(command -v "addgroup")" ]; then
                $PRIMER_OS_SUDO addgroup "$1"
            elif [ -x "$(command -v "groupadd")" ]; then
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
        if id -Gn "$1" | grep -q "$2"; then
            yush_debug "$1 already in group $2"
        else
            yush_info "Adding $1 to group $2"
            if [ -x "$(command -v "adduser")" ]; then
                $PRIMER_OS_SUDO addgroup "$1" "$2"
            elif [ -x "$(command -v "usermod")" ]; then
                $PRIMER_OS_SUDO usermod -a -G "$2" "$1"
            fi
        fi
    fi
}

primer_auth_user_add() {
    if [ "$#" -gt "0" ]; then
        _username="$1"
        shift
        _group="$1"
        _caller=$(id -un)
        _shell=$(getent passwd | grep -q "^$_caller:" | cut -d ":" -f 7)
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

        # Validate shell
        if ! grep -q "$_shell" /etc/shells; then
            yush_warn "$_shell is not a valid login shell!"
            return 1
        fi

        # Create group for user if it does not exist.
        if ! getent group | grep -q "^$_group:"; then
            primer_auth_group_add "$_group"
        fi

        # Create the user, coping with the nightmare of the varioud adduser and
        # useradd and their varying options...
        if [ -x "$(command -v "adduser")" ]; then
            if adduser -h 2>&1 | grep -iq busybox; then
                if [ -z "$_password" ]; then
                    $PRIMER_OS_SUDO adduser \
                                    -G "$_group" \
                                    -g "$_gecos" \
                                    -s "$_shell" \
                                    -D \
                                "$_username"
                else
                    printf %s\\n%s\\n "$_password" "$_password" |
                        $PRIMER_OS_SUDO adduser \
                                    -G "$_group" \
                                    -g "$_gecos" \
                                    -s "$_shell" \
                                "$_username"
                fi
            else
                if [ -z "$_password" ]; then
                    $PRIMER_OS_SUDO adduser \
                                    --ingroup "$_group" \
                                    --gecos "$_gecos" \
                                    --shell "$_shell" \
                                    --disabled-password \
                                "$_username"
                else
                    printf %s\\n%s\\n "$_password" "$_password" |
                        $PRIMER_OS_SUDO adduser \
                                    --ingroup "$_group" \
                                    --gecos "$_gecos" \
                                    --shell "$_shell" \
                                "$_username"
                fi
            fi
        elif [ -x "$(command -v "useradd")" ]; then
            $PRIMER_OS_SUDO useradd \
                            --gid "$_group" \
                            --comment "$_gecos" \
                            --shell "$_shell" \
                        "$_username"
            if [ -n "$_password" ]; then
                primer_auth_user_password "$_username" "$_password"
            fi
        fi
    fi
}


primer_auth_user_password() {
    if [ -n "$_password" ]; then
        printf %s\\n%s\\n "$2" "$2" | $PRIMER_OS_SUDO passwd "$1"
    fi
}

primer_auth_user_mod() {
    if [ "$#" -gt "0" ]; then
        _username="$1"
        shift
        _group=$(id -Gn "$_username")
        _entry=$(getent passwd | grep "^$_username:")
        _uid=$(printf %s\\n "$_entry" | cut -d ":" -f 3)
        _gid=$(printf %s\\n "$_entry" | cut -d ":" -f 4)
        _gecos=$(printf %s\\n "$_entry" | cut -d ":" -f 5)
        _home=$(printf %s\\n "$_entry" | cut -d ":" -f 6)
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
        if ! grep -q "$_shell" /etc/shells; then
            yush_warn "$_shell is not a valid login shell!"
            return 1
        fi

        # Create group for user if it does not exist.
        if ! getent group | grep -q "^$_group:"; then
            primer_auth_group_add "$_group"
        fi

        if [ -x "$(command -v "usermod")" ]; then
            $PRIMER_OS_SUDO usermod \
                            --gid "$_group" \
                            --comment "$_gecos" \
                            --shell "$_shell" \
                        "$_username"
        else
            yush_error "Modifying /etc/passwd does not work!"
            return 1
            _tmp=$(mktemp)
            while IFS= read -r line; do
                echo "<< $line"
                if grep -qE "^${_username}:"; then
                    printf %s:x:%d:%d:%s:%s:%s\\n "$_username" "$_uid" "$_gid" "$_gecos" "$_home" "$_shell" >> "$_tmp"
                else
                    printf %s\\n "$line" >> "$_tmp"
                fi
            done </etc/passwd
            primer_utils_path_ownership "$_tmp" --as /etc/passwd
            $PRIMER_OS_SUDO mv -f "$_tmp" /etc/passwd
        fi
        if [ -n "$_password" ]; then
            primer_auth_user_password "$_username" "$_password"
        fi
    fi
}