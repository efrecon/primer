#!/usr/bin/env sh

# Space separated list of port definitions to open in the firewall. Each
# definition is a port number, e.g. 8080, or a port number and a protocol, e.g.
# 8080/tcp. Protocol-less definitions open both TCP and UDP.
PRIMER_STEP_FIREWALL_PORTS=${PRIMER_STEP_FIREWALL_PORTS:-}

# Firewall to operate on, one of ufw, firewalld, awall, nftables or iptables.
# When empty, the default, the firewall is detected automatically.
PRIMER_STEP_FIREWALL_TYPE=${PRIMER_STEP_FIREWALL_TYPE:-}

# Marker for the rules created by this step, so they can be found and removed
# when cleaning: only rules with the marker are ever removed. This is the
# comment of nftables and iptables rules, the start of the comment of ufw rules,
# the name of the firewalld service holding the ports, and the prefix of the
# names of awall policies. Only letters, digits and dashes are kept, as in awall
# policy names.
PRIMER_STEP_FIREWALL_MARKER=${PRIMER_STEP_FIREWALL_MARKER:-"primer"}

# Directory where to place the awall policies created by this step. This must be
# one of the directories where awall looks for optional policies.
PRIMER_STEP_FIREWALL_AWALL_DIR=${PRIMER_STEP_FIREWALL_AWALL_DIR:-"/etc/awall/optional"}

primer_step_firewall() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--port --ports --type"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --port)
                        PRIMER_STEP_FIREWALL_PORTS="$PRIMER_STEP_FIREWALL_PORTS $2"; shift 2;;
                    --ports)
                        PRIMER_STEP_FIREWALL_PORTS=$2; shift 2;;
                    --type)
                        PRIMER_STEP_FIREWALL_TYPE=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install"|"clean")
            if [ -z "$PRIMER_STEP_FIREWALL_PORTS" ]; then
                yush_warn "No firewall ports specified."
                return
            fi
            # The marker ends up in nftables rules and awall policy (file)
            # names, keep the characters accepted by awall only.
            _marker=$(printf %s "$PRIMER_STEP_FIREWALL_MARKER" | LC_ALL=C tr -cd '0-9a-zA-Z-')
            [ -z "$_marker" ] && _marker=primer
            if [ "$_marker" != "$PRIMER_STEP_FIREWALL_MARKER" ]; then
                yush_warn "Firewall marker '$PRIMER_STEP_FIREWALL_MARKER' contains unsafe characters, using '$_marker'"
                PRIMER_STEP_FIREWALL_MARKER=$_marker
            fi
            _fw=$(_primer_step_firewall_detect)
            case "$_fw" in
                ufw|firewalld|awall|nftables|iptables) ;;
                *)
                    yush_warn "Firewall $_fw is not supported"
                    return 1;;
            esac
            if [ "$1" = "install" ]; then
                _action=open
            else
                _action=close
            fi
            yush_info "Using firewall $_fw to $_action ports: $PRIMER_STEP_FIREWALL_PORTS"
            # Expand port definitions to (port, protocol) pairs and call the
            # implementation of the action for the detected firewall.
            _primer_step_firewall_rules | while read -r _port _proto; do
                "_primer_step_firewall_${_fw}_${_action}" "$_port" "$_proto" < /dev/null
            done
            if [ "$_fw" = "iptables" ]; then
                if _primer_step_firewall_iptables_persistent; then
                    _primer_step_firewall_iptables_save "$_action"
                else
                    yush_warn "iptables rules are not persistent; save them with your distribution's mechanism"
                fi
            fi
            ;;
    esac
}

# Print the name of the firewall to operate on. This is the one forced through
# PRIMER_STEP_FIREWALL_TYPE, the currently active one, awall when it manages
# the firewall on Alpine, the default firewall of the distribution when it is
# installed but inactive, or iptables as a last resort.
_primer_step_firewall_detect() {
    if [ -n "$PRIMER_STEP_FIREWALL_TYPE" ]; then
        printf '%s\n' "$PRIMER_STEP_FIREWALL_TYPE" | tr '[:upper:]' '[:lower:]'
        return
    fi

    _active=$(primer_net_active_firewall)
    if [ -n "$_active" ]; then
        printf '%s\n' "$_active"
        return
    fi

    # Both ufw and firewalld (through firewall-offline-cmd) can register rules
    # while inactive. These will be applied once the firewall is enabled.
    case "$(primer_os_distribution)" in
        *buntu|*bian)
            if primer_utils_syscmd_exists ufw; then
                printf '%s\n' ufw
                return
            fi
            ;;
        fedora*|centos*|rhel*|rocky*|almalinux*)
            if primer_utils_syscmd_exists firewall-offline-cmd; then
                printf '%s\n' firewalld
                return
            fi
            ;;
        alpine*)
            # awall generates the iptables rules from its policies, so it
            # manages the firewall as soon as one policy is enabled.
            if primer_utils_syscmd_exists awall &&
                    $PRIMER_OS_SUDO awall list 2>/dev/null |
                        awk '$2 == "enabled" { found=1 } END { exit !found }'; then
                printf '%s\n' awall
                return
            fi
            ;;
    esac

    printf '%s\n' iptables
}

# Print one line per port and protocol pair described by the port definitions
# in PRIMER_STEP_FIREWALL_PORTS. Protocol-less definitions are expanded to both
# TCP and UDP, invalid definitions are skipped with a warning.
_primer_step_firewall_rules() {
    for _def in $PRIMER_STEP_FIREWALL_PORTS; do
        _port=${_def%%/*}
        _proto=${_def#*/}
        [ "$_port" = "$_proto" ] && _proto=
        if ! printf '%s\n' "$_port" | grep -Eq '^[0-9]+$' ||
                [ "$_port" -lt 1 ] || [ "$_port" -gt 65535 ]; then
            yush_warn "Invalid port definition: $_def"
            continue
        fi
        _proto=$(printf '%s\n' "$_proto" | tr '[:upper:]' '[:lower:]')
        case "$_proto" in
            "")
                printf '%s tcp\n%s udp\n' "$_port" "$_port";;
            tcp|udp)
                printf '%s %s\n' "$_port" "$_proto";;
            *)
                yush_warn "Invalid protocol in port definition: $_def";;
        esac
    done
}

# Print the comment of the ufw rules created by this step.
_primer_step_firewall_ufw_comment() {
    printf '%s firewall\n' "$PRIMER_STEP_FIREWALL_MARKER"
}

# Open port $1 for protocol $2 using ufw, with a rule marked by its comment.
# Nothing is done when a rule for the same traffic exists, whatever its action
# or comment: adding the rule would change the comment of the existing rule,
# making it look like one of ours.
_primer_step_firewall_ufw_open() {
    if $PRIMER_OS_SUDO ufw show added |
            grep -Eq "^ufw (allow|deny|reject|limit)( in)? ${1}(/${2})?( |\$)"; then
        yush_info "A ufw rule for port $1/$2 already exists, leaving it alone"
        return
    fi
    yush_info "Opening port $1/$2 in ufw"
    $PRIMER_OS_SUDO ufw allow "${1}/${2}" comment "$(_primer_step_firewall_ufw_comment)"
}

# Close port $1 for protocol $2 using ufw, i.e. remove the rule created when
# opening, and only that one: ufw matches the comment when deleting.
_primer_step_firewall_ufw_close() {
    _comment=$(_primer_step_firewall_ufw_comment)
    if $PRIMER_OS_SUDO ufw show added | grep -qxF "ufw allow ${1}/${2} comment '${_comment}'"; then
        yush_info "Closing port $1/$2 in ufw"
        $PRIMER_OS_SUDO ufw delete allow "${1}/${2}" comment "$_comment"
    fi
}

# Run firewalld configuration commands on the permanent configuration: through
# firewall-cmd when the daemon is running, firewall-offline-cmd otherwise.
_primer_step_firewall_firewalld_cmd() {
    if $PRIMER_OS_SUDO firewall-cmd --state 2>/dev/null | grep -qx running; then
        $PRIMER_OS_SUDO firewall-cmd --permanent "$@"
    else
        $PRIMER_OS_SUDO firewall-offline-cmd "$@"
    fi
}

# Apply the permanent configuration when the daemon is running.
_primer_step_firewall_firewalld_reload() {
    if $PRIMER_OS_SUDO firewall-cmd --state 2>/dev/null | grep -qx running; then
        $PRIMER_OS_SUDO firewall-cmd --reload
    fi
}

# Open port $1 for protocol $2 using firewalld. Ports are added to a dedicated
# service, named after the marker, enabled in the default zone. Ports opened
# otherwise are never touched.
_primer_step_firewall_firewalld_open() {
    yush_info "Opening port $1/$2 in firewalld service $PRIMER_STEP_FIREWALL_MARKER"
    if ! _primer_step_firewall_firewalld_cmd --get-services | tr ' ' '\n' | grep -qxF "$PRIMER_STEP_FIREWALL_MARKER"; then
        _primer_step_firewall_firewalld_cmd --new-service="$PRIMER_STEP_FIREWALL_MARKER"
    fi
    _primer_step_firewall_firewalld_cmd --service="$PRIMER_STEP_FIREWALL_MARKER" --add-port="${1}/${2}"
    if ! _primer_step_firewall_firewalld_cmd --list-services | tr ' ' '\n' | grep -qxF "$PRIMER_STEP_FIREWALL_MARKER"; then
        _primer_step_firewall_firewalld_cmd --add-service="$PRIMER_STEP_FIREWALL_MARKER"
    fi
    _primer_step_firewall_firewalld_reload
}

# Close port $1 for protocol $2 using firewalld, i.e. remove it from the
# dedicated service. The service is removed with its last port.
_primer_step_firewall_firewalld_close() {
    if ! _primer_step_firewall_firewalld_cmd --get-services | tr ' ' '\n' | grep -qxF "$PRIMER_STEP_FIREWALL_MARKER"; then
        return
    fi
    yush_info "Closing port $1/$2 in firewalld service $PRIMER_STEP_FIREWALL_MARKER"
    _primer_step_firewall_firewalld_cmd --service="$PRIMER_STEP_FIREWALL_MARKER" --remove-port="${1}/${2}"
    if [ -z "$(_primer_step_firewall_firewalld_cmd --service="$PRIMER_STEP_FIREWALL_MARKER" --get-ports)" ]; then
        yush_info "Removing firewalld service $PRIMER_STEP_FIREWALL_MARKER"
        if _primer_step_firewall_firewalld_cmd --list-services | tr ' ' '\n' | grep -qxF "$PRIMER_STEP_FIREWALL_MARKER"; then
            _primer_step_firewall_firewalld_cmd --remove-service="$PRIMER_STEP_FIREWALL_MARKER"
        fi
        _primer_step_firewall_firewalld_cmd --delete-service="$PRIMER_STEP_FIREWALL_MARKER"
    fi
    _primer_step_firewall_firewalld_reload
}

# Print the name of the awall policy for port $1 and protocol $2.
_primer_step_firewall_awall_policy() {
    printf '%s-%s-%s\n' "$PRIMER_STEP_FIREWALL_MARKER" "$1" "$2"
}

# Open port $1 for protocol $2 using awall, through a dedicated policy accepting
# incoming traffic to the host from all zones. Activating the policies also
# saves the resulting rules, so they are restored at boot.
_primer_step_firewall_awall_open() {
    _policy=$(_primer_step_firewall_awall_policy "$1" "$2")
    yush_info "Opening port $1/$2 in awall with policy $_policy"
    $PRIMER_OS_SUDO mkdir -p "$PRIMER_STEP_FIREWALL_AWALL_DIR"
    $PRIMER_OS_SUDO tee "${PRIMER_STEP_FIREWALL_AWALL_DIR%/}/${_policy}.json" > /dev/null <<EOF
{
  "description": "Port $1/$2 opened by primer",
  "service": { "$_policy": { "proto": "$2", "port": $1 } },
  "filter": [ { "out": "_fw", "service": "$_policy", "action": "accept" } ]
}
EOF
    $PRIMER_OS_SUDO awall enable "$_policy"
    $PRIMER_OS_SUDO awall activate -f
}

# Close port $1 for protocol $2 using awall, i.e. disable and remove the policy
# created when opening, then activate the remaining policies.
_primer_step_firewall_awall_close() {
    _policy=$(_primer_step_firewall_awall_policy "$1" "$2")
    yush_info "Closing port $1/$2 in awall, removing policy $_policy"
    if [ -f "${PRIMER_STEP_FIREWALL_AWALL_DIR%/}/${_policy}.json" ]; then
        $PRIMER_OS_SUDO awall disable "$_policy"
        $PRIMER_OS_SUDO rm -f "${PRIMER_STEP_FIREWALL_AWALL_DIR%/}/${_policy}.json"
        $PRIMER_OS_SUDO awall activate -f
    fi
}

# Print the handles of the rules matching port $1 and protocol $2 that were
# created by this step in the input chain of the inet filter table.
_primer_step_firewall_nftables_handles() {
    $PRIMER_OS_SUDO nft -a list chain inet filter input 2>/dev/null |
        grep -F "$2 dport $1 accept comment \"$PRIMER_STEP_FIREWALL_MARKER\"" |
        sed -E 's/.*#[[:space:]]*handle[[:space:]]+([0-9]+).*/\1/'
}

# Open port $1 for protocol $2 using nftables, unless already open.
_primer_step_firewall_nftables_open() {
    if [ -n "$(_primer_step_firewall_nftables_handles "$1" "$2")" ]; then
        yush_debug "Port $1/$2 already open in nftables"
        return
    fi
    yush_info "Opening port $1/$2 in nftables"
    $PRIMER_OS_SUDO nft add rule inet filter input "$2" dport "$1" accept comment "\"$PRIMER_STEP_FIREWALL_MARKER\""
}

# Close port $1 for protocol $2 using nftables, i.e. remove all rules created by
# this step for that port.
_primer_step_firewall_nftables_close() {
    yush_info "Closing port $1/$2 in nftables"
    for _handle in $(_primer_step_firewall_nftables_handles "$1" "$2"); do
        $PRIMER_OS_SUDO nft delete rule inet filter input handle "$_handle"
    done
}

# Print the iptables binaries available, i.e. IPv4 and IPv6 when present.
_primer_step_firewall_iptables_bins() {
    for _bin in iptables ip6tables; do
        primer_utils_syscmd_exists "$_bin" && printf '%s\n' "$_bin"
    done
}

# Open port $1 for protocol $2 using iptables (and ip6tables), unless already
# open by this step. Rules are marked with a comment, and inserted first in the
# INPUT chain to take precedence.
_primer_step_firewall_iptables_open() {
    primer_os_dependency iptables iptables
    yush_info "Opening port $1/$2 in iptables"
    for _bin in $(_primer_step_firewall_iptables_bins); do
        if ! $PRIMER_OS_SUDO "$_bin" -C INPUT -p "$2" --dport "$1" -m comment --comment "$PRIMER_STEP_FIREWALL_MARKER" -j ACCEPT 2>/dev/null; then
            $PRIMER_OS_SUDO "$_bin" -I INPUT -p "$2" --dport "$1" -m comment --comment "$PRIMER_STEP_FIREWALL_MARKER" -j ACCEPT
        fi
    done
}

# Close port $1 for protocol $2 using iptables (and ip6tables), removing all
# matching rules created by this step, i.e. marked with its comment.
_primer_step_firewall_iptables_close() {
    yush_info "Closing port $1/$2 in iptables"
    for _bin in $(_primer_step_firewall_iptables_bins); do
        while $PRIMER_OS_SUDO "$_bin" -C INPUT -p "$2" --dport "$1" -m comment --comment "$PRIMER_STEP_FIREWALL_MARKER" -j ACCEPT 2>/dev/null; do
            $PRIMER_OS_SUDO "$_bin" -D INPUT -p "$2" --dport "$1" -m comment --comment "$PRIMER_STEP_FIREWALL_MARKER" -j ACCEPT || break
        done
    done
}

# Can iptables rules be saved and restored at boot? This is the case when the
# OpenRC service for iptables is installed, as on Alpine.
_primer_step_firewall_iptables_persistent() {
    primer_utils_syscmd_exists rc-service && [ -x /etc/init.d/iptables ]
}

# Save the current iptables (and ip6tables) rules through their OpenRC
# services. When $1 is open, also enable the services so the saved rules are
# restored at boot.
_primer_step_firewall_iptables_save() {
    for _bin in $(_primer_step_firewall_iptables_bins); do
        if [ -x "/etc/init.d/$_bin" ]; then
            yush_info "Saving $_bin rules"
            $PRIMER_OS_SUDO rc-service "$_bin" save
            if [ "$1" = "open" ]; then
                primer_os_service enable "$_bin"
            fi
        fi
    done
}
