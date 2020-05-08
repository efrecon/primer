#!/usr/bin/env sh

# Static rules to add
PRIMER_STEP_DYNUFW_STATIC=${PRIMER_STEP_DYNUFW_STATIC:-}

# Location of dynamic rules files to install
PRIMER_STEP_DYNUFW_RULES=${PRIMER_STEP_DYNUFW_RULES:-}

# Version of dynufw to download. Can be set from the outside, defaults to
# amster, which is probably alway what you want anyway...
PRIMER_STEP_DYNUFW_BRANCH=${PRIMER_STEP_DYNUFW_BRANCH:-master}

# DNS server to use, empty for host default
PRIMER_STEP_DYNUFW_DNS=${PRIMER_STEP_DYNUFW_DNS:-}

PRIMER_STEP_DYNUFW_SCHEDULE=${PRIMER_STEP_DYNUFW_SCHEDULE:-"* * * * *"}

# Repo for dynufw scripts
PRIMER_STEP_DYNUFW_REPO=https://github.com/efrecon/dynufw.git

# Location of the dynamic rules configuration file, this matches the default for
# the dynufw project.
PRIMER_STEP_DYNUFW_DYNPATH=/etc/ufw-dynamic-hosts.allow

primer_step_dynufw() {
    case "$1" in
        "option")
            shift;
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
                touch "$PRIMER_STEP_DYNUFW_DYNPATH"
            fi
            _primer_step_dynufw_install_static
            # Run once to open all ports
            if [ -x "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh" ]; then
                yush_info "Initialising dynamic rules"
                "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh"
            fi
            _primer_step_dynufw_install_cron
            # Start firewall, if everything was wrong with the rules, you might
            # be kicked out!
            yush_notice "Enabling firewall forcefully"
            $PRIMER_OS_SUDO ufw --force enable
            ;;
        "clean")
            ;;
    esac
}


# Install ufw, with additional necessary extra packages. We treat containers a
# little bit different (which is mostly usefull for testing)
_primer_step_dynufw_install_ufw() {
    if [ -z "$(command -v ufw)" ]; then
        lsb_dist=$(primer_os_distribution)
        case "$lsb_dist" in
            alpine)
                # This only works if testing exists on the system.
                primer_os_packages add ip6tables ufw@testing
                ;;
            *)
                primer_os_packages add ufw
                ;;
        esac
    fi

    # In containers, we turn off IPv6 as a work around for the "can't initialize
    # ip6tables table `filter': Table does not exist (do you need to insmod?)"
    # message when enabling ufw.
    if primer_os_in_container && [ -f "/etc/default/ufw" ]; then
        yush_debug "Turning off IPv6 in containers"
        sed -E -i.bak \
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
    if [ -d "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH" ]; then
        ( cd "${PRIMER_OPTDIR%%/}/dynufw/$PRIMER_STEP_DYNUFW_BRANCH" && git pull )
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

# Install static rules. This is for opening the firewall for hostnames that will
# never change. rules are yourhost.tld:22/tcp/d (where the port can be a range
# instead, e.g. 8080-8090) tcp is default, when d is present, an extra entry
# will be added to the dynamic rules files. This makes it easier to express the
# rules without a rules configuration files when you only have a few rules.
_primer_step_dynufw_install_static() {
    for opening in $PRIMER_STEP_DYNUFW_STATIC; do
        # Opening are in the form host.tld:80/tcp (where host.tld and tcp can be
        # omitted)
        if echo "$opening" | grep -Eqo '^(([0-9a-zA-Z\.\-~]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$'; then
            host=$(echo "$opening" | sed -E 's;^(([0-9a-zA-Z\.\-~]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$;\2;g')
            port=$(echo "$opening" | sed -E 's;^(([0-9a-zA-Z\.\-~]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$;\3;g')
            proto=$(echo "$opening" | sed -E 's;^(([0-9a-zA-Z\.\-~]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$;\6;g')
            dyn=$(echo "$opening" | sed -E 's;^(([0-9a-zA-Z\.\-~]+):)?([0-9]+(-[0-9]+)?)(/(udp|tcp)(/d)?)?$;\7;g')
            if [ -z "$proto" ]; then
                proto="tcp";
            fi
            if [ -z "$host" ]; then
                # Convert dash separated port range to colon separated (which is
                # the format supported by UFW)
                port=$(printf %s\\n "$port" | sed 's/-/:/g')
                yush_notice "Opening firewall for all incoming traffic on port ${port}/${proto}"
                $PRIMER_OS_SUDO ufw allow "${port}/${proto}"
            else
                if [ -n "$dyn" ]; then
                    # Add an entry to the main dynamic rules file.
                    if [ -x "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh" ]; then
                        if ! grep -q "${proto}:${port}:${host}" "$PRIMER_STEP_DYNUFW_DYNPATH"; then
                            yush_notice "Opening firewall for incoming traffic on port ${port}/${proto} from ${host} (dynamic)"
                            {
                                echo "";
                                echo "# Rule automatically added by ${0##*/}";
                                echo "${proto}:${port}:${host}";
                            }  >> "$PRIMER_STEP_DYNUFW_DYNPATH"
                        else
                            yush_debug "Skipping adding existing rule on port ${port}/${proto} from ${host}!"
                        fi
                    fi
                else
                    # Convert dash separated port range to colon separated
                    # (which is the format supported by UFW) and & sign to / for
                    # CIDR notation support.
                    port=$(printf %s\\n "$port" | sed 's/-/:/g')
                    host=$(printf %s\\n "$host" | sed 's/~/\//g')
                    if printf %s\\n "$host" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then
                        ip=${host}
                    else
                        ip=$(yush_resolv_v4 "$host")
                    fi
                    if [ -n "$ip" ]; then
                        yush_notice "Opening firewall for incoming traffic on port ${port}/${proto} from ${ip}"
                        $PRIMER_OS_SUDO ufw allow proto "$proto" from "$ip" to any port "$port"
                    else
                        yush_warn "Could not resolve $host, skipping rule!"
                    fi
                fi
            fi
        else
            yush_warn "$opening is not a valid port opening specification!"
        fi
    done
}

# Install a cron rule
_primer_step_dynufw_install_cron() {
    # install cron, for the time being. We might move to systemd timer soon?
    primer_os_packages add cron
    # Schedule to run this often via crontab.
    if ! crontab -l | grep -q "${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh"; then
        yush_info "Arranging for ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh to keep port openings at regular intervals"
        if [ -n "$PRIMER_STEP_DYNUFW_DNS" ]; then
            line="${PRIMER_STEP_DYNUFW_SCHEDULE} ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh -q -s $PRIMER_STEP_DYNUFW_DNS"
        else
            line="${PRIMER_STEP_DYNUFW_SCHEDULE} ${PRIMER_BINDIR%%/}/ufw-dynamic-host-update.sh -q"
        fi
        # echo the extra line after the current crontab and give it back to
        # crontab. This is to make sure we can properly make use of sudo.
        ($PRIMER_OS_SUDO crontab -l || true; echo "$line") | $PRIMER_OS_SUDO crontab -
    fi
}