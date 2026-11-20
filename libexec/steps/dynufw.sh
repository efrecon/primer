#!/usr/bin/env sh

# Static rules to add
PRIMER_STEP_DYNUFW_STATIC=${PRIMER_STEP_DYNUFW_STATIC:-}

# Location of dynamic rules files to install
PRIMER_STEP_DYNUFW_RULES=${PRIMER_STEP_DYNUFW_RULES:-}

# Version of dynufw to download. Can be set from the outside, defaults to
# master, which is probably always what you want anyway...
PRIMER_STEP_DYNUFW_BRANCH=${PRIMER_STEP_DYNUFW_BRANCH:-master}

# Commit of dynufw to install, verified by git: the tip of master when this
# version of primer was released. Empty to install the tip of the branch,
# unverified, and update it on every installation.
PRIMER_STEP_DYNUFW_COMMIT=${PRIMER_STEP_DYNUFW_COMMIT-90ac5c50aae2e8173bd695a03470a1168fa73453}

# DNS server to use, empty for host default
PRIMER_STEP_DYNUFW_DNS=${PRIMER_STEP_DYNUFW_DNS:-}

PRIMER_STEP_DYNUFW_SCHEDULE=${PRIMER_STEP_DYNUFW_SCHEDULE:-'* * * * *'}

# Repo for dynufw scripts
PRIMER_STEP_DYNUFW_REPO=${PRIMER_STEP_DYNUFW_REPO:-https://github.com/efrecon/dynufw.git}

# Location of the dynamic rules configuration file, this matches the default for
# the dynufw project.
PRIMER_STEP_DYNUFW_DYNPATH=${PRIMER_STEP_DYNUFW_DYNPATH:-/etc/ufw-dynamic-hosts.allow}

# Regular expression for static openings: host.tld:port/proto/d, where host.tld
# (or an IP address, with ~ instead of / for CIDR notations), proto and /d are
# optional, and port can be a range, e.g. 8080-8090.
# Comment of the static rules added by this step. It is how they are recognised
# when cleaning, so that other rules are left untouched.
PRIMER_STEP_DYNUFW_COMMENT=${PRIMER_STEP_DYNUFW_COMMENT:-"primer dynufw"}

PRIMER_STEP_DYNUFW_STATIC_RX='^(([0-9a-zA-Z.~-]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$'

primer_step_dynufw() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--static --rules --dns --commit"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --static)
                        PRIMER_STEP_DYNUFW_STATIC="$PRIMER_STEP_DYNUFW_STATIC $2"; shift 2;;
                    --rules)
                        PRIMER_STEP_DYNUFW_RULES=$2; shift 2;;
                    --dns)
                        PRIMER_STEP_DYNUFW_DNS=$2; shift 2;;
                    --commit)
                        PRIMER_STEP_DYNUFW_COMMIT=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            _primer_step_dynufw_install_ufw
            _primer_step_dynufw_install_dynufw || return 1
            if [ -n "$PRIMER_STEP_DYNUFW_RULES" ]; then
                yush_info "Installing dynamic rules from $PRIMER_STEP_DYNUFW_RULES"
                $PRIMER_OS_SUDO cp -f "$PRIMER_STEP_DYNUFW_RULES" "$PRIMER_STEP_DYNUFW_DYNPATH"
            else
                $PRIMER_OS_SUDO touch "$PRIMER_STEP_DYNUFW_DYNPATH"
            fi
            _primer_step_dynufw_install_static
            # Run once to open all ports
            _primer_step_dynufw_update
            _primer_step_dynufw_install_cron
            # Start firewall, unless this would lock out SSH connections.
            if ! _primer_step_dynufw_ssh_allowed; then
                yush_error "No rule allows SSH connections on port $_ssh_port, enabling the firewall would lock them out. Add one, e.g. --dynufw:static $_ssh_port, the firewall is left disabled"
                return 1
            fi
            yush_notice "Enabling firewall forcefully"
            $PRIMER_OS_SUDO ufw --force enable
            ;;
        "clean")
            _primer_step_dynufw_clean_cron
            # Only remove the rules of dynufw, the firewall stays as it is,
            # i.e. enabled, with all other rules.
            if primer_utils_syscmd_exists ufw; then
                _primer_step_dynufw_clean_rules
            fi
            if [ -f "$PRIMER_STEP_DYNUFW_DYNPATH" ]; then
                $PRIMER_OS_SUDO rm -f "$PRIMER_STEP_DYNUFW_DYNPATH"
            fi
            for _script in ufw-clean ufw-dynamic-host-update; do
                if [ -L "${PRIMER_BINDIR%%/}/${_script}.sh" ]; then
                    $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/${_script}.sh"
                fi
            done
            if [ -d "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH" ]; then
                yush_info "Removing dynufw from ${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH"
                $PRIMER_OS_SUDO rm -rf "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH"
                $PRIMER_OS_SUDO rmdir "${PRIMER_OPTDIR%%/}/dynufw" 2>/dev/null || true
            fi
            ;;
    esac
}


# Succeed when enabling the firewall keeps SSH connections possible: when it is
# already active, when there is no SSH server and primer does not run over SSH,
# or when a rule allows (or limits) connections to the SSH port, which is set
# in _ssh_port: the one of the current connection, 22 otherwise.
_primer_step_dynufw_ssh_allowed() {
    _ssh_port=22
    if [ -n "${SSH_CONNECTION:-}" ]; then
        _ssh_port=$(printf %s\\n "$SSH_CONNECTION" | awk '{ print $4 }')
    elif ! primer_utils_syscmd_exists sshd; then
        return 0
    fi
    if $PRIMER_OS_SUDO ufw status 2>/dev/null | grep -q '^Status: active'; then
        return 0
    fi
    $PRIMER_OS_SUDO ufw show added |
        grep -E '^ufw (allow|limit) ' |
        grep -qE "( ${_ssh_port}(/tcp)?( |\$)| (OpenSSH|ssh)( |\$))"
}

# Install ufw, with additional necessary extra packages. We treat containers a
# little bit different (which is mostly usefull for testing)
_primer_step_dynufw_install_ufw() {
    if ! primer_utils_syscmd_exists ufw; then
        primer_os_packages add ufw
    fi

    # In containers, we turn off IPv6 as a work around for the "can't initialize
    # ip6tables table `filter': Table does not exist (do you need to insmod?)"
    # message when enabling ufw.
    if primer_os_in_container && [ -f "/etc/default/ufw" ]; then
        yush_debug "Turning off IPv6 in containers"
        # Replaced atomically, keeping owner and permissions, with no backup
        # left behind.
        $PRIMER_OS_SUDO sed -E \
            's/#?[[:space:]]*IPV6=[[:space:]]*[[:alnum:]]*[[:space:]]*$/IPV6=no/g' \
            /etc/default/ufw | primer_utils_sysfile_replace /etc/default/ufw
    fi
}

# Install the dynufw package directly out of its git repository. We will need
# the two main scripts. However, the installation script is re-implemented
# (better) within this step.
_primer_step_dynufw_install_dynufw() {
    yush_info "Installing dynufw from $PRIMER_STEP_DYNUFW_REPO (branch: $PRIMER_STEP_DYNUFW_BRANCH, commit: ${PRIMER_STEP_DYNUFW_COMMIT:-none})"
    primer_net_git_clone "$PRIMER_STEP_DYNUFW_REPO" "$PRIMER_STEP_DYNUFW_BRANCH" \
        "$PRIMER_STEP_DYNUFW_COMMIT" "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH" update || return 1
    yush_debug "Installing as ${PRIMER_BINDIR%%/}/dynufw"
    for _script in ufw-clean ufw-dynamic-host-update; do
        $PRIMER_OS_SUDO chmod a+x "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH/${_script}.sh"
        $PRIMER_OS_SUDO ln -sf "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH/${_script}.sh" "${PRIMER_BINDIR%%/}/${_script}.sh"
    done
}

# Run the dynamic rules update script once, if installed.
_primer_step_dynufw_update() {
    if [ -x "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh" ]; then
        yush_info "Updating dynamic rules"
        if [ -n "$PRIMER_STEP_DYNUFW_DNS" ]; then
            $PRIMER_OS_SUDO "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh" -q -s "$PRIMER_STEP_DYNUFW_DNS"
        else
            $PRIMER_OS_SUDO "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh" -q
        fi
    fi
}

# Remove the ufw rules that belong to dynufw: the static rules, recognised by
# their comment, and the rules created by the update script for the lines of
# the dynamic rules file, recognised by their comment (the host), port and
# protocol, which must all match exactly. The added rules are listed in the
# syntax of the ufw command, independently of the status of the firewall.
_primer_step_dynufw_clean_rules() {
    # Dynamic rules as "proto port host" lines, with ranges in ufw format, i.e.
    # 8080:8090 instead of 8080-8090.
    _dynamic=
    if [ -f "$PRIMER_STEP_DYNUFW_DYNPATH" ]; then
        _dynamic=$(sed -E -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$PRIMER_STEP_DYNUFW_DYNPATH" |
            while IFS=: read -r _proto _port _host; do
                [ -n "$_host" ] || continue
                case "$_port" in
                    *-*) _port=${_port%%-*}:${_port#*-};;
                esac
                printf '%s %s %s\n' "$_proto" "$_port" "$_host"
            done)
    fi
    _rules=$(_primer_step_dynufw_rules | while IFS='|' read -r _action _rule _comment; do
        if [ -z "$_comment" ]; then
            continue
        fi
        if [ "$_comment" = "$PRIMER_STEP_DYNUFW_COMMENT" ] \
                || _primer_step_dynufw_is_dynamic "$_rule" "$_comment" "$_dynamic"; then
            printf '%s %s\n' "$_action" "$_rule"
        fi
    done)
    if [ -n "$_rules" ]; then
        yush_info "Removing dynufw rules from firewall"
        printf %s\\n "$_rules" | while IFS= read -r _rule; do
            yush_debug "Removing rule: $_rule"
            # shellcheck disable=SC2086 # The rule is made of several words.
            $PRIMER_OS_SUDO ufw delete $_rule < /dev/null
        done
    fi
}

# Is the ufw rule $1, commented $2, one created by the update script for a line
# of the dynamic rules $3 (as "proto port host" lines)? Its protocol, port and
# host (the comment) must all match exactly.
_primer_step_dynufw_is_dynamic() {
    _dyn_comment=$2
    _dyn_list=$3
    _dyn_proto=
    _dyn_port=
    # Split the rule into words, without expanding globs, and pick the values
    # after the proto and port keywords.
    set -f
    # shellcheck disable=SC2086
    set -- $1
    set +f
    while [ "$#" -gt 1 ]; do
        case "$1" in
            proto) _dyn_proto=$2;;
            port) _dyn_port=$2;;
        esac
        shift
    done
    [ -n "$_dyn_list" ] \
        && printf '%s\n' "$_dyn_list" | grep -qxF "$_dyn_proto $_dyn_port $_dyn_comment"
}

# Print the rules added to ufw, one per line, as action|rule|comment, where
# rule is in the syntax used by "ufw show added", e.g. 22/tcp or "from
# 10.0.0.0/8 to any port 22 proto tcp", and comment is empty when the rule has
# none.
_primer_step_dynufw_rules() {
    $PRIMER_OS_SUDO ufw show added | while IFS= read -r _line; do
        case "$_line" in
            "ufw "*) ;;
            *) continue;;
        esac
        _rule=${_line#ufw }
        _action=${_rule%% *}
        _rule=${_rule#* }
        _comment=
        case "$_rule" in
            *" comment '"*)
                _comment=${_rule#* comment \'}
                _comment=${_comment%\'}
                _rule=${_rule%% comment \'*}
                ;;
        esac
        printf '%s|%s|%s\n' "$_action" "$_rule" "$_comment"
    done
}

# Allow the traffic described by the arguments (as for ufw allow) and mark the
# rule as belonging to dynufw, with a comment, unless a rule for the same
# traffic already exists. $1 is that rule as listed by "ufw show added", e.g.
# "from 10.0.0.0/8 to any port 22 proto tcp" for "proto tcp from 10.0.0.0/8 to
# any port 22". Existing rules are never modified: ufw would otherwise replace
# their action (e.g. limit) or comment, and cleaning would remove them, e.g. a
# rule for SSH added by hand.
_primer_step_dynufw_allow() {
    _dyn_tuple=$1
    shift
    _dyn_existing=$(_primer_step_dynufw_rules | while IFS='|' read -r _action _rule _comment; do
        if [ "$_rule" = "$_dyn_tuple" ]; then
            printf '%s|%s\n' "$_action" "$_comment"
        fi
    done)
    if [ -z "$_dyn_existing" ]; then
        $PRIMER_OS_SUDO ufw allow "$@" comment "$PRIMER_STEP_DYNUFW_COMMENT"
        # Verify that the rule is listed as expected, i.e. that the check for
        # existing rules above works with this version of ufw.
        if ! _primer_step_dynufw_rules | grep -qxF "allow|${_dyn_tuple}|${PRIMER_STEP_DYNUFW_COMMENT}"; then
            yush_warn "Rule for $_dyn_tuple is not listed as expected by ufw, check it is not one of yours before cleaning"
        fi
    elif [ "$_dyn_existing" = "allow|$PRIMER_STEP_DYNUFW_COMMENT" ]; then
        yush_debug "Rule for $_dyn_tuple already present"
    else
        yush_notice "A rule for $_dyn_tuple already exists (${_dyn_existing%%|*}), keeping it as is: it is yours and will not be removed when cleaning"
    fi
}

# Install static rules. This is for opening the firewall for hostnames that
# will never change. rules are yourhost.tld:22/tcp/d (where the port can be a
# range instead, e.g. 8080-8090) tcp is default, when d is present, an extra
# entry will be added to the dynamic rules files. This makes it easier to
# express the rules without a rules configuration files when you only have a
# few rules. Rules are commented, so they can be recognised when cleaning.
_primer_step_dynufw_install_static() {
    for opening in $PRIMER_STEP_DYNUFW_STATIC; do
        # Opening are in the form host.tld:80/tcp (where host.tld and tcp can be
        # omitted)
        if printf %s\\n "$opening" | grep -Eq "$PRIMER_STEP_DYNUFW_STATIC_RX"; then
            host=$(printf %s\\n "$opening" | sed -E "s;${PRIMER_STEP_DYNUFW_STATIC_RX};\\2;")
            port=$(printf %s\\n "$opening" | sed -E "s;${PRIMER_STEP_DYNUFW_STATIC_RX};\\3;")
            proto=$(printf %s\\n "$opening" | sed -E "s;${PRIMER_STEP_DYNUFW_STATIC_RX};\\6;")
            dyn=$(printf %s\\n "$opening" | sed -E "s;${PRIMER_STEP_DYNUFW_STATIC_RX};\\7;")
            if [ -z "$proto" ]; then
                proto="tcp";
            fi
            if [ -z "$host" ]; then
                # Convert dash separated port range to colon separated (which
                # is the format supported by UFW)
                port=$(printf %s\\n "$port" | sed 's/-/:/g')
                yush_notice "Opening firewall for all incoming traffic on port ${port}/${proto}"
                _primer_step_dynufw_allow "${port}/${proto}" "${port}/${proto}"
            elif [ -n "$dyn" ]; then
                # Add an entry to the main dynamic rules file, the update
                # script creates the rule. Removal happens with the file.
                if ! grep -qxF "${proto}:${port}:${host}" "$PRIMER_STEP_DYNUFW_DYNPATH"; then
                    yush_notice "Opening firewall for incoming traffic on port ${port}/${proto} from ${host} (dynamic)"
                    printf '\n# Rule automatically added by primer\n%s:%s:%s\n' "$proto" "$port" "$host" |
                        primer_utils_sysfile_append "$PRIMER_STEP_DYNUFW_DYNPATH"
                else
                    yush_debug "Skipping adding existing rule on port ${port}/${proto} from ${host}!"
                fi
            else
                # Convert dash separated port range to colon separated, and ~
                # sign to / for CIDR notation support.
                port=$(printf %s\\n "$port" | sed 's/-/:/g')
                host=$(printf %s\\n "$host" | sed 's/~/\//g')
                if printf %s\\n "$host" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$'; then
                    ip=${host}
                else
                    ip=$(yush_resolv_v4 "$host" || true)
                fi
                if [ -n "$ip" ]; then
                    yush_debug "One time resolution of $host led to $ip"
                    yush_notice "Opening firewall for incoming traffic on port ${port}/${proto} from ${ip}"
                    _primer_step_dynufw_allow "from $ip to any port $port proto $proto" \
                        proto "$proto" from "$ip" to any port "$port"
                else
                    yush_warn "Could not resolve $host, skipping rule!"
                fi
            fi
        else
            yush_warn "$opening is not a valid port opening specification!"
        fi
    done
}

# Name of the cron package and service on the current distribution, as
# "package service". The package is empty when cron is part of the base
# system.
_primer_step_dynufw_cron() {
    case "$(primer_os_distribution)" in
        alpine*)
            # busybox crond and crontab
            echo " crond";;
        fedora*|centos*|rhel*|rocky*|almalinux*)
            echo "cronie crond";;
        *)
            echo "cron cron";;
    esac
}

# Install a cron rule
_primer_step_dynufw_install_cron() {
    # install cron, for the time being. We might move to systemd timer soon?
    _cron=$(_primer_step_dynufw_cron)
    _pkg=${_cron% *}
    _svc=${_cron#* }
    if [ -n "$_pkg" ]; then
        primer_os_packages add "$_pkg"
    fi
    primer_os_service enable "$_svc"
    primer_os_service start "$_svc"
    # Schedule to run this often via crontab.
    if ! { $PRIMER_OS_SUDO crontab -l 2>/dev/null || true; } | grep -qF "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh"; then
        yush_info "Arranging for ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh to keep port openings at regular intervals"
        if [ -n "$PRIMER_STEP_DYNUFW_DNS" ]; then
            line="${PRIMER_STEP_DYNUFW_SCHEDULE} ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh -q -s $PRIMER_STEP_DYNUFW_DNS"
        else
            line="${PRIMER_STEP_DYNUFW_SCHEDULE} ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh -q"
        fi
        # echo the extra line after the current crontab and give it back to
        # crontab. This is to make sure we can properly make use of sudo.
        { $PRIMER_OS_SUDO crontab -l 2>/dev/null || true; echo "$line"; } | $PRIMER_OS_SUDO crontab -
    fi
}

# Remove the cron rule, if present.
_primer_step_dynufw_clean_cron() {
    if primer_utils_syscmd_exists crontab \
            && { $PRIMER_OS_SUDO crontab -l 2>/dev/null || true; } | grep -qF "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh"; then
        yush_info "Removing ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh from crontab"
        { $PRIMER_OS_SUDO crontab -l 2>/dev/null || true; } |
            { grep -vF "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh" || true; } |
            $PRIMER_OS_SUDO crontab -
    fi
}
