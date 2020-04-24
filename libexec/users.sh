#!/usr/bin/env sh

# List regular users, or system users with -a or --all
primer_users() {
    if [ "$#" -gt "0" ] && ( [ "$1" = "-a" ] || [ "$1" = "--all" ] ); then
        getent passwd | cut -d ":" -f "1"
    elif [ -f "/etc/login.defs" ]; then
        # Only regular users
        _min=$(grep -E ^UID_MIN /etc/login.defs | awk '{print $2}')
        _max=$(grep -E ^UID_MAX /etc/login.defs | awk '{print $2}')
        _primer_users "$_min" "$_max"
    else
        yush_debug "No /etc/login.defs, using defaults"
        _primer_users "1000" "60000"
    fi
}

# This reimplements getent passwd {min..max} as it does not exists on Alpine.
_primer_users() {
    getent passwd | while IFS= read -r line; do
        _uid=$(printf %s\\n "$line" | cut -d ":" -f 3)
        if [ "$_uid" -ge "$1" ] && [ "$_uid" -le "$2" ]; then
            printf %s\\n "$line" | cut -d ":" -f 1
        fi
    done 
}

# Create user group passed as parameter if it does not exist.
primer_group_create() {
    if [ "$#" -gt "0" ] && [ -n "$1" ]; then
        if ! getent group | grep -q "^$1:"; then
            yush_info "Creating group: $1"
            if [ -x "$(command -v "addgroup")" ]; then
                $PRIMER_SUDO addgroup "$1"
            elif [ -x "$(command -v "groupadd")" ]; then
                $PRIMER_SUDO groupadd "$1"
            fi
        else
            yush_debug "Group $1 already exists"
        fi
    fi
}

# Add user $1 to group $2
primer_group_membership() {
    if [ "$#" -gt "1" ] && [ -n "$1" ] && [ -n "$2" ]; then
        if id -Gn "$1" | grep -q "$2"; then
            yush_debug "$1 already in group $2"
        else
            yush_info "Adding $1 to group $2"
            if [ -x "$(command -v "adduser")" ]; then
                $PRIMER_SUDO addgroup "$1" "$2"
            elif [ -x "$(command -v "usermod")" ]; then
                $PRIMER_SUDO usermod -a -G "$2" "$1"
            fi
        fi
    fi
}