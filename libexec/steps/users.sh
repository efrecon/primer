#!/usr/bin/env sh

# Path to users database, a file modelled after the /etc/password file, 5
# colon-separated fields. When the password is the letter x, one will be
# generated. The file must end with an empty line. See
# spec/support/data/users.db for an example file with more details on the
# format.
PRIMER_STEP_USERS_DB=${PRIMER_STEP_USERS_DB:-}

# Additional groups the users should be part of, including the user calling this
# script!
PRIMER_STEP_USERS_GROUPS=${PRIMER_STEP_USERS_GROUPS:-}

# Save the generated passwords in file along side the main DB file, with the
# extension below instead?
PRIMER_STEP_USERS_PWSAVE=${PRIMER_STEP_USERS_PWSAVE:-0}

# Extension of the file containing (generated) cleartext passwords
PRIMER_STEP_USERS_PWEXT=${PRIMER_STEP_USERS_PWEXT:-".pwd"}

# Length of generated passwords
PRIMER_STEP_USERS_PWLEN=${PRIMER_STEP_USERS_PWLEN:-12}

# URL to GitHub API
PRIMER_STEP_USERS_GHAPI=${PRIMER_STEP_USERS_GHAPI:-"https://api.github.com/"}

primer_step_users() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--db --save --ext"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --db)
                        PRIMER_STEP_USERS_DB=$2; shift 2;;
                    --save)
                        PRIMER_STEP_USERS_PWSAVE=$2; shift 2;;
                    --ext)
                        PRIMER_STEP_USERS_PWSAVE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -n "$PRIMER_STEP_USERS_DB" ] && [ -f "$PRIMER_STEP_USERS_DB" ]; then
                # Create groups
                _primer_step_users_groups | _primer_step_users_groups_create
                yush_split "$PRIMER_STEP_USERS_GROUPS" "," | _primer_step_users_groups_create

                # Now remove/create users. When the password is the letter x, generate a
                # password and encrypt it using mkpasswd. Note that mkpasswd comes from the
                # whois package, which should have been installed previously.
                yush_info "Users setup using DB at $(yush_green "$PRIMER_STEP_USERS_DB")..."
                if yush_is_true "$PRIMER_STEP_USERS_PWSAVE"; then
                    _pwstore=${PRIMER_STEP_USERS_DB%.*}.${PRIMER_STEP_USERS_PWEXT#.*}
                    yush_notice "Will store cleartext passwords in $_pwstore"
                fi
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "${line}" ]; then
                        username=$(printf %s::::::\\n "$line" | cut -d ":" -f "1")
                        password=$(printf %s::::::\\n "$line" | cut -d ":" -f "2")
                        groups=$(printf %s::::::\\n "$line" | cut -d ":" -f "3")
                        group=$(yush_split "$groups" "," | head -n 1); # Primary group is first
                        details=$(printf %s::::::\\n "$line" | cut -d ":" -f "4")
                        shell=$(printf %s::::::\\n "$line" | cut -d ":" -f "5")
                        ghusers=$(printf %s::::::\\n "$line" | cut -d ":" -f "6")
                        _caller=$(id -un)
                        [ -z "$shell" ] && shell=$(getent passwd | grep -q "^$_caller:" | cut -d ":" -f 7)

                        if [ -z "$(getent passwd "$username")" ]; then
                            if [ "$password" = "x" ]; then
                                password=$(yush_password "$PRIMER_STEP_USERS_PWLEN")
                                if yush_is_true "$PRIMER_STEP_USERS_PWSAVE"; then
                                    yush_notice "Creating user $username, adding password to store at $(yush_yellow "$_pwstore"), clean away once initialisation finished!"
                                    echo "${username}:${password}:${group}:${details}:${shell}" >> "$_pwstore"
                                else
                                    yush_info "Creating user $username with password $password Copy password, cannot be recovered!"
                                fi
                            else
                                yush_notice "Creating user $username with password from $USERS, this is insecure!"
                            fi
                            primer_auth_user_add "$username" \
                                                    --group "$group" \
                                                    --gecos "$details" \
                                                    --shell "$shell" \
                                                    --password "$password"
                            # Make user member of all other groups as of file,
                            # and as of general settings.
                            for g in $(yush_split "$groups" "," | tail -n +2); do
                                primer_auth_group_membership "$username" "$g"
                            done
                            _primer_step_users_groups_membership "$username"
                        else
                            yush_debug "User $username already exists, modifying except password"
                            primer_auth_user_mod "$username" \
                                                    --group "$group" \
                                                    --gecos "$details" \
                                                    --shell "$shell"
                            if yush_is_true "$PRIMER_STEP_USERS_PWSAVE"; then
                                if [ -f "$_pwstore" ] && grep -Eq "^${username}:" "$_pwstore"; then
                                    password=$(grep -E "^${username}:" "$_pwstore" | head -n 1 | cut -d ":" -f "2")
                                    sed -Ei "/^${username}:.*/d" "$_pwstore"
                                    echo "${username}:${password}:${group}:${details}:${shell}" >> "$_pwstore"
                                fi
                            fi
                        fi

                        # Add GitHub user access
                        if [ -n "$ghusers" ]; then
                            for ghuser in $(yush_split "$ghusers" ","); do
                                _primer_step_users_github_access "$username" "$group" "$ghuser"
                            done
                        fi
                    fi
                done < "${PRIMER_STEP_USERS_DB}"

                # Restrict access to clear text password
                if yush_is_true "$PRIMER_STEP_USERS_PWSAVE" && [ -f "$_pwstore" ]; then
                    chmod go-rwx "$_pwstore"
                fi

                if [ -n "$PRIMER_STEP_USERS_GROUPS" ]; then
                    REALUSER=$(id -un)
                    yush_info "Give $(yush_green "$REALUSER") access to groups $PRIMER_STEP_USERS_GROUPS"
                    _primer_step_users_groups_membership "$REALUSER"
                fi
            else
                yush_warn "No user database provided, or cannot access."
            fi
            ;;
        "clean")
            if [ -n "$PRIMER_STEP_USERS_DB" ] && [ -f "$PRIMER_STEP_USERS_DB" ]; then
                _pwstore=${PRIMER_STEP_USERS_DB%.*}.${PRIMER_STEP_USERS_PWEXT#.*}
                if yush_is_true "$PRIMER_STEP_USERS_PWSAVE" && [ -f "$_pwstore" ]; then
                    yush_notice "Removing existing password storage at $(yush_green "$_pwstore")"
                    rm -f "$_pwstore"
                fi
                REALUSER=$(id -un)
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
                    if [ -n "${line}" ]; then
                        username=$(printf %s\\n "$line" | cut -d ":" -f "1")
                        if [ -n "$(getent passwd "$username")" ] && [ "$username" != "$REALUSER" ]; then
                            yush_debug "Removing user $username"
                            $PRIMER_OS_SUDO deluser "$username"
                        fi
                    fi
                done < "${PRIMER_STEP_USERS_DB}"
            else
                yush_warn "No user database provided, or cannot access."
            fi
            ;;
    esac
}

_primer_step_users_github_access() {
    yush_notice "Collecting SSH public keys from GitHub user $3 for user $1"
    _homedir=$(getent passwd "$1"|cut -d ":" -f 6)
    # .ssh directory is private, so need to become root to discover if it
    # exists. When it does not, create it and make it privately accessible to
    # the user only.
    if ! $PRIMER_OS_SUDO  test -d "${_homedir}/.ssh"; then
        yush_debug "Creating SSH directory ${_homedir}/.ssh for user $1"
        $PRIMER_OS_SUDO mkdir "${_homedir}/.ssh"
        primer_utils_path_ownership "${_homedir}/.ssh" \
            --user "$1" \
            --group "$2" \
            --perms "u+rwx,go-rwx"
    fi
    # Request the SSH public keys registered for the GitHub user. GitHub returns
    # well formated JSON, so remove cruft so we keep just the meaningfull lines.
    # Extract key id and key content in turns and add them to the
    # authorized_keys file.
    _id=
    _key=
    while IFS= read -r line || [ -n "$line" ]; do
        if printf %s\\n "$line" | grep -qE '\s*"id"\s*:'; then
            _id=$(printf %s\\n "$line" | sed -E 's/\s*"id"\s*:\s*([0-9]+).*/\1/')
        fi
        if printf %s\\n "$line" | grep -qE '\s*"key"\s*:'; then
            _key=$(printf %s\\n "$line" | sed -E 's/\s*"key"\s*:\s*"([^"]+)".*/\1/')
        fi
        if [ -n "$_id" ] && [ -n "$_key" ]; then
            # Add the key to the authorized_keys file if we haven't done it at a
            # prior run. We use the title of the SSH key to reflect the name of
            # the GitHub user, the origin (github itself) and the identifier of
            # the key. This generates a unique identifier, which is also
            # human-readable if necessary.
            if ! grep -qF "${3}@github/${_id}" "${_homedir}/.ssh/authorized_keys" 2>/dev/null; then
                yush_trace "Adding key #$_id to ${_homedir}/.ssh/authorized_keys"
                printf '%s %s\n' "$_key" "${3}@github/${_id}" | $PRIMER_OS_SUDO tee -a "${_homedir}/.ssh/authorized_keys" > /dev/null
            fi
            _id=
            _key=
        fi
    done <<EOF
$(primer_net_curl "${PRIMER_STEP_USERS_GHAPI%/}/users/${3}/keys" | grep -vF -e '[' -e ']' -e '{' -e '}')
EOF
    # Arrange for the authorize_keys file to be private for the user only.
    if $PRIMER_OS_SUDO test -f "${_homedir}/.ssh/authorized_keys"; then
        primer_utils_path_ownership "${_homedir}/.ssh/authorized_keys" \
            --user "$1" \
            --group "$2"
    fi
}

_primer_step_users_groups() {
    yush_debug "Collecting groups from DB at $(yush_green "$PRIMER_STEP_USERS_DB")..."
    # Collect groups
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf %s\\n "$line" | sed '/^[[:space:]]*$/d' | sed '/^[[:space:]]*#/d')
        if [ -n "${line}" ]; then
            yush_split "$(printf %s\\n "$line" | cut -d ":" -f 3)" ","
        fi
    done < "${PRIMER_STEP_USERS_DB}" | sort -u
}

_primer_step_users_groups_create() {
    while IFS= read -r grp; do
        primer_auth_group_add "$grp"
    done
}

_primer_step_users_groups_membership() {
    for g in $(yush_split "$PRIMER_STEP_USERS_GROUPS" ","); do
        primer_auth_group_membership "$1" "$g"
    done
}
