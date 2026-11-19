#!/usr/bin/env sh

# Static rules to add
PRIMER_STEP_DYNUFW_STATIC=${PRIMER_STEP_DYNUFW_STATIC:-}

# Location of dynamic rules files to install
PRIMER_STEP_DYNUFW_RULES=${PRIMER_STEP_DYNUFW_RULES:-}

# Version of dynufw to download. Can be set from the outside, defaults to
# master, which is probably always what you want anyway...
PRIMER_STEP_DYNUFW_BRANCH=${PRIMER_STEP_DYNUFW_BRANCH:-master}

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
PRIMER_STEP_DYNUFW_STATIC_RX='^(([0-9a-zA-Z.~-]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$'

primer_step_dynufw() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--static --rules --dns"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --static)
                        PRIMER_STEP_DYNUFW_STATIC="$PRIMER_STEP_DYNUFW_STATIC $2"; shift 2;;
                    --rules)
                        PRIMER_STEP_DYNUFW_RULES=$2; shift 2;;
                    --dns)
                        PRIMER_STEP_DYNUFW_DNS=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            _primer_step_dynufw_install_ufw
            _primer_step_dynufw_install_dynufw
            if [ -n "$PRIMER_STEP_DYNUFW_RULES" ]; then
                yush_info "Installing dynamic rules from $PRIMER_STEP_DYNUFW_RULES"
                $PRIMER_OS_SUDO cp -f "$PRIMER_STEP_DYNUFW_RULES" "$PRIMER_STEP_DYNUFW_DYNPATH"
            else
                $PRIMER_OS_SUDO touch "$PRIMER_STEP_DYNUFW_DYNPATH"
            fi
            _primer_step_dynufw_static allow
            # Run once to open all ports
            _primer_step_dynufw_update
            _primer_step_dynufw_install_cron
            # Start firewall, if everything was wrong with the rules, you might
            # be kicked out!
            yush_notice "Enabling firewall forcefully"
            $PRIMER_OS_SUDO ufw --force enable
            ;;
        "clean")
            _primer_step_dynufw_clean_cron
            if primer_utils_syscmd_exists ufw; then
                _primer_step_dynufw_static delete
                if [ -f "$PRIMER_STEP_DYNUFW_DYNPATH" ]; then
                    _primer_step_dynufw_clean_dynamic
                    $PRIMER_OS_SUDO rm -f "$PRIMER_STEP_DYNUFW_DYNPATH"
                fi
                yush_notice "Disabling firewall"
                $PRIMER_OS_SUDO ufw --force disable
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
        $PRIMER_OS_SUDO sed -E -i.bak \
            's/#?[[:space:]]*IPV6=[[:space:]]*[[:alnum:]]*[[:space:]]*$/IPV6=no/g' \
            /etc/default/ufw
    fi
}

# Install the dynufw package directly out of its git repository. We will need
# the two main scripts. However, the installation script is re-implemented
# (better) within this step.
_primer_step_dynufw_install_dynufw() {
    primer_os_dependency git
    yush_info "Installing dynufw from $PRIMER_STEP_DYNUFW_REPO (branch: $PRIMER_STEP_DYNUFW_BRANCH)"
    if [ -d "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH/.git" ]; then
        $PRIMER_OS_SUDO git -C "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH" pull -q
    else
        $PRIMER_OS_SUDO mkdir -p "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH"
        $PRIMER_OS_SUDO git clone "$PRIMER_STEP_DYNUFW_REPO" \
                        --recurse \
                        --branch "$PRIMER_STEP_DYNUFW_BRANCH" \
                        --depth 1 \
                        "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH"
    fi
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

# Remove the ufw rules created for the dynamic rules file, i.e. the rules for
# the port and protocol of each line, commented with the name of the host.
_primer_step_dynufw_clean_dynamic() {
    yush_info "Removing dynamic rules from $PRIMER_STEP_DYNUFW_DYNPATH"
    sed -E -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$PRIMER_STEP_DYNUFW_DYNPATH" |
        while IFS=: read -r _proto _port _host; do
            _port=$(printf %s\\n "$_port" | sed 's/-/:/g')
            for _ip in $($PRIMER_OS_SUDO ufw status |
                            grep -F "# $_host" |
                            grep -F "${_port}/${_proto}" |
                            awk '{print $3}'); do
                yush_debug "Removing rule for $_host on ${_port}/${_proto} from $_ip"
                $PRIMER_OS_SUDO ufw delete allow proto "$_proto" from "$_ip" to any port "$_port" < /dev/null
            done
        done
}

# Add (when $1 is allow) or remove (when $1 is delete) static rules. This is for
# opening the firewall for hostnames that will never change. rules are
# yourhost.tld:22/tcp/d (where the port can be a range instead, e.g.
# 8080-8090) tcp is default, when d is present, an extra entry will be added to
# the dynamic rules files when allowing. This makes it easier to express the
# rules without a rules configuration files when you only have a few rules.
_primer_step_dynufw_static() {
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
            # Convert dash separated port range to colon separated (which is
            # the format supported by UFW)
            port=$(printf %s\\n "$port" | sed 's/-/:/g')
            if [ -z "$host" ]; then
                yush_notice "Firewall rule for all incoming traffic on port ${port}/${proto}: $1"
                if [ "$1" = "allow" ]; then
                    $PRIMER_OS_SUDO ufw allow "${port}/${proto}"
                else
                    $PRIMER_OS_SUDO ufw delete allow "${port}/${proto}"
                fi
            elif [ -n "$dyn" ]; then
                # Add an entry to the main dynamic rules file. Removal happens
                # with the file.
                if [ "$1" = "allow" ]; then
                    port=$(printf %s\\n "$port" | sed 's/:/-/g')
                    if ! grep -qxF "${proto}:${port}:${host}" "$PRIMER_STEP_DYNUFW_DYNPATH"; then
                        yush_notice "Opening firewall for incoming traffic on port ${port}/${proto} from ${host} (dynamic)"
                        printf '\n# Rule automatically added by primer\n%s:%s:%s\n' "$proto" "$port" "$host" |
                            primer_utils_sysfile_append "$PRIMER_STEP_DYNUFW_DYNPATH"
                    else
                        yush_debug "Skipping adding existing rule on port ${port}/${proto} from ${host}!"
                    fi
                fi
            else
                # Convert ~ sign to / for CIDR notation support.
                host=$(printf %s\\n "$host" | sed 's/~/\//g')
                if printf %s\\n "$host" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$'; then
                    ip=${host}
                else
                    ip=$(yush_resolv_v4 "$host" || true)
                fi
                if [ -n "$ip" ]; then
                    yush_debug "One time resolution of $host led to $ip"
                    yush_notice "Firewall rule for incoming traffic on port ${port}/${proto} from ${ip}: $1"
                    if [ "$1" = "allow" ]; then
                        $PRIMER_OS_SUDO ufw allow proto "$proto" from "$ip" to any port "$port"
                    else
                        $PRIMER_OS_SUDO ufw delete allow proto "$proto" from "$ip" to any port "$port"
                    fi
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
