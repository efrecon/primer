#!/usr/bin/env sh

# Path to users database, a file modelled after the /etc/password file, 5
# colon-separated fields. When the password is the letter x, one will be
# generated. The file must end with an empty line. See
# spec/support/data/users.db for an example file with more details on the
# format.
USERS_DB=${USERS_DB:-}

# Additional groups the users should be part of, including the user calling this
# script!
USERS_GROUPS=${USERS_GROUPS:-docker,sudo}

# Save the generated passwords in file along side the main DB file, with the
# extension below instead?
USERS_PWSAVE=${USERS_PWSAVE:-0}

# Extension of the file containing (generated) cleartext passwords
USERS_PWEXT=${USERS_PWEXT:-".pwd"}

# Length of generated passwords
USERS_PWLEN=${USERS_PWLEN:-12}

users() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --db)
                        USERS_DB=$2; shift 2;;
                    --save)
                        USERS_PWSAVE=$2; shift 2;;
                    --ext)
                        USERS_PWSAVE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            # Create groups
            _users_groups | _users_groups_create
            yush_split "$USERS_GROUPS" "," | _users_groups_create

            # Now remove/create users. When the password is the letter x, generate a
            # password and encrypt it using mkpasswd. Note that mkpasswd comes from the
            # whois package, which should have been installed previously.
            yush_info "Users setup using DB at $(yush_green "$USERS_DB")..."
            if yush_is_true "$USERS_PWSAVE"; then
                _pwstore=${USERS_DB%.*}.${USERS_PWEXT#.*}
                yush_notice "Will store cleartext passwords in $_pwstore"
            fi
            if yush_is_true "$USERS_PWSAVE" && [ -f "$_pwstore" ]; then
                yush_notice "Removing existing password storage at $(yush_green "$_pwstore")"
                rm -f "$_pwstore"
            fi
            while IFS= read -r line; do
                line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                if [ -n "${line}" ]; then
                    username=$(printf %s\\n "$line" | cut -d ":" -f "1")
                    password=$(printf %s\\n "$line" | cut -d ":" -f "2")
                    group=$(printf %s\\n "$line" | cut -d ":" -f "3")
                    details=$(printf %s\\n "$line" | cut -d ":" -f "4")
                    shell=$(printf %s\\n "$line" | cut -d ":" -f "5")

                    if [ -z "$(getent passwd "$username")" ]; then
                        if [ "$password" = "x" ]; then
                            password=$(yush_password "$USERS_PWLEN")
                            if yush_is_true "$USERS_PWSAVE"; then
                                yush_notice "Creating user $username, adding password to store at $(yush_yellow "$_pwstore"), clean away once initialisation finished!"
                                echo "${username}:${password}:${group}:${details}:${shell}" >> "$_pwstore"
                            else
                                yush_info "Creating user $username with password $password Copy password, cannot be recovered!"
                            fi
                        else
                            yush_notice "Creating user $username with password from $USERS, this is insecure!"
                        fi
                        _users_useradd "$username" "$group" "$details" "$shell" "$password"
                        _users_groups_membership "$username"
                    else
                        yush_debug "User $username already exists, modifying except password"
                        _users_usermod "$username" "$group" "$details" "$shell"
                    fi
                fi
            done < "${USERS_DB}"

            # Restrict access to clear text password
            if yush_is_true "$USERS_PWSAVE" && [ -f "$_pwstore" ]; then
                chmod go-rwx "$_pwstore"
            fi

            REALUSER=$(id -un)
            yush_info "Give $(yush_green "$REALUSER") access to groups $USERS_GROUPS"
            _users_groups_membership "$REALUSER"
            ;;
        "clean")
            _pwstore=${USERS_DB%.*}.${USERS_PWEXT#.*}
            if yush_is_true "$USERS_PWSAVE" && [ -f "$_pwstore" ]; then
                yush_notice "Removing existing password storage at $(yush_green "$_pwstore")"
                rm -f "$_pwstore"
            fi
            REALUSER=$(id -un)
            while IFS= read -r line; do
                line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                if [ -n "${line}" ]; then
                    username=$(printf %s\\n "$line" | cut -d ":" -f "1")
                    if [ -n "$(getent passwd "$username")" ] && [ "$username" != "$REALUSER" ]; then
                        yush_debug "Removing user $username"
                        $PRIMER_SUDO deluser "$username"
                    fi
                fi
            done < "${USERS_DB}"
            ;;
    esac
}

_users_groups() {
    yush_debug "Collecting groups from DB at $(yush_green "$USERS_DB")..."
    # Collect groups
    while IFS= read -r line; do
        line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
        if [ -n "${line}" ]; then
            printf %s\\n "$line" | cut -d ":" -f 3
        fi
    done < "${USERS_DB}" | sort -u
}

_users_groups_create() {
    while IFS= read -r grp; do
        if ! getent group | grep -q "^${grp}:"; then
            yush_info "Creating group: $grp"
            if [ -x "$(command -v "addgroup")" ]; then
                $PRIMER_SUDO addgroup "$grp"
            elif [ -x "$(command -v "groupadd")" ]; then
                $PRIMER_SUDO groupadd "$grp"
            fi
        else
            yush_debug "Group $grp already exists"
        fi
    done
}

_users_groups_membership() {
    for g in $(yush_split "$USERS_GROUPS" ","); do
        if id -Gn "$1" | grep -q "$g"; then
            yush_debug "$1 already in group $g"
        else
            yush_info "Adding $1 to group $g"
            if [ -x "$(command -v "adduser")" ]; then
                $PRIMER_SUDO addgroup "$1" "$g"
            elif [ -x "$(command -v "usermod")" ]; then
                $PRIMER_SUDO usermod -a -G "$g" "$1"
            fi
        fi
    done
}

_users_useradd() {
    _username=$1
    _group=$2
    _details=$3
    _shell=$4
    _password=$5

    if [ -x "$(command -v "adduser")" ]; then
        if adduser -h 2>&1 | grep -iq busybox; then
            if [ -z "$_password" ]; then
                $PRIMER_SUDO adduser \
                                -G "$_group" \
                                -g "$_details" \
                                -s "$_shell" \
                                -D \
                            "$_username"
            else
                printf %s\\n%s\\n "$_password" "$_password" |
                    $PRIMER_SUDO adduser \
                                -G "$_group" \
                                -g "$_details" \
                                -s "$_shell" \
                            "$_username"
            fi
        else
            if [ -z "$_password" ]; then
                $PRIMER_SUDO adduser \
                                --ingroup "$_group" \
                                --gecos "$_details" \
                                --shell "$_shell" \
                                --disabled-password \
                            "$_username"
            else
                printf %s\\n%s\\n "$_password" "$_password" |
                    $PRIMER_SUDO adduser \
                                --ingroup "$_group" \
                                --gecos "$_details" \
                                --shell "$_shell" \
                            "$_username"
            fi
        fi
    elif [ -x "$(command -v "useradd")" ]; then
        $PRIMER_SUDO useradd \
                        --gid "$_group" \
                        --comment "$_details" \
                        --shell "$_shell" \
                    "$_username"
        if [ -n "$_password" ]; then
            printf %s\\n%s\\n "$_password" "$_password" | $PRIMER_SUDO passwd "$_username"
        fi
    fi
}

_users_usermod() {
    _username=$1
    _group=$2
    _details=$3
    _shell=$4

    if [ -x "$(command -v "usermod")" ]; then
        $PRIMER_SUDO usermod \
                        --gid "$_group" \
                        --comment "$_details" \
                        --shell "$_shell" \
                    "$_username"
    else
        yush_warn "Cannot modify user $_username on this system"
    fi
}