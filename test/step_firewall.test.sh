#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in the containers.
# shellcheck disable=SC2016

# Tests of the firewall step. ufw and firewalld can register rules while
# inactive, so they are tested for real in regular containers. iptables,
# nftables and awall change the netfilter rules of the container, so they need
# privileged containers. Detection and command lines are tested in library
# mode, with mocks.

test_firewall_ufw_inactive() {
    in_container "$IMG_TRIXIE" '
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null 2>&1
        primer_run -s firewall --firewall:ports "8080 443/tcp" install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "Using firewall ufw" "$PRIMER_ERR"
        added=$(ufw show added)
        assert_contains "ufw allow 8080/tcp" "$added"
        assert_contains "ufw allow 8080/udp" "$added"
        assert_contains "ufw allow 443/tcp" "$added"
        assert_not_contains "443/udp" "$added"
        primer_run -s firewall --firewall:ports "8080 443/tcp" clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_not_contains "allow" "$(ufw show added)"'
}

test_firewall_firewalld_offline() {
    in_container "$IMG_TRIXIE" '
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq firewalld >/dev/null 2>&1
        primer_run -s firewall --firewall:type firewalld --firewall:ports "8080 53/udp" install
        assert_equal 0 "$PRIMER_RC" "install status"
        ports=$(firewall-offline-cmd --list-ports)
        assert_contains "8080/tcp" "$ports"
        assert_contains "8080/udp" "$ports"
        assert_contains "53/udp" "$ports"
        primer_run -s firewall --firewall:type firewalld --firewall:ports "8080 53/udp" clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_equal "" "$(firewall-offline-cmd --list-ports)"'
}

test_firewall_iptables() {
    require_privileged
    in_container -P "$IMG_TRIXIE" '
        primer_run -s firewall --firewall:ports "8080/tcp 5353/udp" install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "Using firewall iptables" "$PRIMER_ERR"
        assert_contains "not persistent" "$PRIMER_ERR"
        assert_true iptables -C INPUT -p tcp --dport 8080 -j ACCEPT
        assert_true iptables -C INPUT -p udp --dport 5353 -j ACCEPT
        primer_run -s firewall --firewall:ports "8080/tcp 5353/udp" install
        assert_equal 0 "$PRIMER_RC" "second install status"
        assert_equal 1 "$(iptables -S INPUT | grep -c "dport 8080")" "rules after two installs"
        primer_run -s firewall --firewall:ports "8080/tcp 5353/udp" clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_false iptables -C INPUT -p tcp --dport 8080 -j ACCEPT
        assert_false iptables -C INPUT -p udp --dport 5353 -j ACCEPT'
}

test_firewall_nftables() {
    require_privileged
    in_container -P "$IMG_ALPINE" '
        apk add -q nftables >/dev/null
        nft add table inet filter
        nft add chain inet filter input "{ type filter hook input priority 0; policy accept; }"
        primer_run -s firewall --firewall:type nftables --firewall:ports 8080 install
        assert_equal 0 "$PRIMER_RC" "install status"
        rules=$(nft list chain inet filter input)
        assert_contains "tcp dport 8080 accept comment \"primer\"" "$rules"
        assert_contains "udp dport 8080 accept comment \"primer\"" "$rules"
        primer_run -s firewall --firewall:type nftables --firewall:ports 8080 install
        assert_equal 2 "$(nft list chain inet filter input | grep -c "dport 8080")" "rules after two installs"
        # A rule not created by primer is left alone when cleaning
        nft add rule inet filter input tcp dport 8080 accept
        primer_run -s firewall --firewall:type nftables --firewall:ports 8080 clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        rules=$(nft list chain inet filter input)
        assert_not_contains "comment \"primer\"" "$rules"
        assert_contains "tcp dport 8080 accept" "$rules"'
}

test_firewall_awall() {
    require_privileged
    in_container -P "$IMG_ALPINE" '
        apk add -q awall iptables ip6tables >/dev/null
        mkdir -p /etc/awall/optional
        echo "{ \"description\": \"Base policy\" }" > /etc/awall/optional/base.json
        awall enable base
        primer_run -s firewall --firewall:ports 8080/tcp install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "Using firewall awall" "$PRIMER_ERR"
        assert_true [ -f /etc/awall/optional/primer-8080-tcp.json ]
        assert_match "^primer-8080-tcp +enabled" "$(awall list)"
        assert_match "dport 8080 .*ACCEPT" "$(iptables -S)"
        primer_run -s firewall --firewall:ports 8080/tcp clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_false [ -f /etc/awall/optional/primer-8080-tcp.json ]
        assert_not_contains "primer-8080-tcp" "$(awall list)"
        assert_not_contains "dport 8080" "$(iptables -S)"'
}

test_firewall_detection() {
    unit "$IMG_ALPINE" '
        unit_step firewall
        _detect() { PRIMER_OS_DISTRO=$1; _primer_step_firewall_detect; }
        primer_net_active_firewall() { :; }

        PRIMER_STEP_FIREWALL_TYPE=UFW
        assert_equal ufw "$(_detect alpine)" "forced type"
        PRIMER_STEP_FIREWALL_TYPE=

        primer_net_active_firewall() { echo firewalld; }
        assert_equal firewalld "$(_detect debian)" "active firewall first"
        primer_net_active_firewall() { :; }

        assert_equal iptables "$(_detect debian)" "debian without ufw"
        mock ufw
        assert_equal ufw "$(_detect debian)" "debian with ufw"
        assert_equal ufw "$(_detect ubuntu)" "ubuntu with ufw"
        assert_equal iptables "$(_detect fedora)" "fedora without firewalld"
        mock firewall-offline-cmd
        assert_equal firewalld "$(_detect fedora)" "fedora with firewalld"
        assert_equal firewalld "$(_detect rocky)" "rocky with firewalld"

        assert_equal iptables "$(_detect alpine)" "alpine without awall"
        mock -o "base  disabled  Base policy" awall
        assert_equal iptables "$(_detect alpine)" "alpine without enabled awall policy"
        mock -o "base  enabled  Base policy" awall
        assert_equal awall "$(_detect alpine)" "alpine with enabled awall policy"'
}

test_firewall_port_parsing() {
    unit "$IMG_ALPINE" '
        unit_step firewall
        PRIMER_STEP_FIREWALL_PORTS="80 abc 70000 0 53/sctp 8080/TCP"
        run _primer_step_firewall_rules
        assert_equal 0 "$RUN_RC"
        assert_equal "$(printf "80 tcp\n80 udp\n8080 tcp")" "$RUN_OUT"
        assert_contains "Invalid port definition: abc" "$RUN_ERR"
        assert_contains "Invalid port definition: 70000" "$RUN_ERR"
        assert_contains "Invalid port definition: 0" "$RUN_ERR"
        assert_contains "Invalid protocol in port definition: 53/sctp" "$RUN_ERR"

        primer_step_firewall option --ports 22 --port 80/udp
        assert_equal "22 80/udp" "$PRIMER_STEP_FIREWALL_PORTS" "options"'
}

test_firewall_commands() {
    unit "$IMG_ALPINE" '
        unit_step firewall
        PRIMER_STEP_FIREWALL_PORTS="80 443/tcp"

        PRIMER_STEP_FIREWALL_TYPE=ufw
        mock ufw
        primer_step_firewall install
        primer_step_firewall clean
        assert_equal "$(printf "%s\n" "ufw allow 80/tcp" "ufw allow 80/udp" "ufw allow 443/tcp" \
            "ufw delete allow 80/tcp" "ufw delete allow 80/udp" "ufw delete allow 443/tcp")" "$(mock_calls)" "ufw"

        mock_reset
        PRIMER_STEP_FIREWALL_TYPE=firewalld
        mock -o running firewall-cmd
        PRIMER_STEP_FIREWALL_PORTS=443/tcp
        primer_step_firewall install
        calls=$(mock_calls)
        assert_contains "firewall-cmd --permanent --add-port=443/tcp" "$calls"
        assert_contains "firewall-cmd --add-port=443/tcp" "$calls"

        mock_reset
        mock -o stopped firewall-cmd
        mock firewall-offline-cmd
        primer_step_firewall clean
        assert_contains "firewall-offline-cmd --remove-port=443/tcp" "$(mock_calls)"
        assert_not_contains "firewall-cmd --permanent" "$(mock_calls)"'
}

test_firewall_marker() {
    unit "$IMG_ALPINE" '
        unit_step firewall
        PRIMER_STEP_FIREWALL_TYPE=nftables
        PRIMER_STEP_FIREWALL_PORTS=22/tcp
        PRIMER_STEP_FIREWALL_MARKER="my marker!"
        mock nft
        run primer_step_firewall install
        assert_equal 0 "$RUN_RC"
        assert_contains "using '"'"'mymarker'"'"'" "$RUN_ERR"
        assert_contains "nft add rule inet filter input tcp dport 22 accept comment \"mymarker\"" "$(mock_calls)"'
}

test_firewall_unknown_type_and_no_ports() {
    primer_in "$IMG_ALPINE" -s firewall --firewall:type foo --firewall:ports 22 install -- '
        assert_false [ "$PRIMER_RC" = 0 ]
        assert_contains "Firewall foo is not supported" "$PRIMER_ERR"
        primer_run -s firewall install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No firewall ports specified" "$PRIMER_ERR"'
}
