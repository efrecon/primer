#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the announce step. Daemons are not started in containers, so
# service and firewall handling are tested with mocks.

test_announce_mdns_alpine() {
    in_container "$IMG_ALPINE" '
        primer_run -s announce --announce:methods mDNS install
        assert_equal 0 "$PRIMER_RC"
        assert_true apk info -e avahi
        assert_true [ -x /usr/sbin/avahi-daemon ]
        assert_contains "not relevant in a container" "$PRIMER_ERR"
        primer_run -s announce --announce:methods mDNS clean
        assert_equal 0 "$PRIMER_RC"
        # Packages are kept: they might have been installed before primer.
        assert_true apk info -e avahi'
}

test_announce_mdns_debian() {
    in_container "$IMG_TRIXIE" '
        primer_run -s announce --announce:methods mDNS install
        assert_equal 0 "$PRIMER_RC"
        assert_equal "install ok installed" "$(dpkg-query -W -f "\${Status}" avahi-daemon)"
        assert_true [ -x /usr/sbin/avahi-daemon ]
        primer_run -s announce --announce:methods mDNS clean
        assert_equal 0 "$PRIMER_RC"
        assert_true [ -x /usr/sbin/avahi-daemon ]'
}

test_announce_netbios_alpine() {
    in_container "$IMG_ALPINE" '
        primer_run -s announce --announce:methods NetBIOS install
        assert_equal 0 "$PRIMER_RC"
        assert_true apk info -e samba-server
        assert_true [ -x /usr/sbin/nmbd ]
        primer_run -s announce --announce:methods NetBIOS clean
        assert_equal 0 "$PRIMER_RC"
        assert_true apk info -e samba-server'
}

test_announce_no_methods() {
    primer_in "$IMG_ALPINE" -v warn -s announce --announce:methods "" install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No DNS announce methods specified" "$PRIMER_ERR"'
}

test_announce_unknown_method() {
    primer_in "$IMG_ALPINE" -v warn -s announce --announce:methods "carrier-pigeon" install -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "carrier-pigeon is not supported" "$PRIMER_ERR"'
}

# The first --method replaces the defaults, then methods accumulate, without
# duplicates.
test_announce_method_option() {
    unit "$IMG_ALPINE" '
        unit_step announce
        assert_equal "mDNS NetBIOS" "$PRIMER_STEP_ANNOUNCE_METHODS"
        primer_step_announce option --method mDNS
        assert_equal "mDNS" "$PRIMER_STEP_ANNOUNCE_METHODS"
        primer_step_announce option --method mdns
        assert_equal "mDNS" "$PRIMER_STEP_ANNOUNCE_METHODS"
        primer_step_announce option --method NetBIOS
        assert_equal "mDNS NetBIOS" "$PRIMER_STEP_ANNOUNCE_METHODS"
        primer_step_announce option --methods NetBIOS
        assert_equal "NetBIOS" "$PRIMER_STEP_ANNOUNCE_METHODS"
        primer_step_announce option --method mDNS
        assert_equal "NetBIOS mDNS" "$PRIMER_STEP_ANNOUNCE_METHODS"'
}

# Outside containers, daemons are started and enabled (OpenRC on Alpine), and
# ports are opened when a firewall is active, with the marker of the step.
# Clean stops and disables the daemons, closes the ports it opened, and keeps
# the packages and the rules of the administrator.
test_announce_services_and_firewall_alpine() {
    unit "$IMG_ALPINE" '
        mock primer_os_dependency
        mock -o ufw primer_net_active_firewall
        mock -r 1 primer_os_in_container
        mock avahi-daemon nmbd rc-service rc-update
        # Stateful ufw: rules as printed by ufw show added, with one rule of the
        # administrator.
        printf "ufw allow 137/udp\n" > /tmp/added
        ufw() {
            if [ "$1" = show ]; then cat /tmp/added; return; fi
            mock_log ufw "$@"
            case "$1" in
                allow) printf "ufw allow %s comment '"'"'%s'"'"'\n" "$2" "$4" >> /tmp/added;;
                delete) grep -vxF "ufw allow $3 comment '"'"'$5'"'"'" /tmp/added > /tmp/added.n || true
                        mv /tmp/added.n /tmp/added;;
            esac
        }
        unit_step announce
        primer_step_announce install
        calls=$(mock_calls)
        assert_contains "primer_os_dependency avahi-daemon avahi" "$calls"
        assert_contains "rc-service avahi-daemon start" "$calls"
        assert_contains "rc-update add avahi-daemon" "$calls"
        assert_contains "ufw allow 5353/udp comment primer-announce firewall" "$calls"
        assert_contains "primer_os_dependency nmbd samba-server" "$calls"
        assert_contains "rc-service nmbd start" "$calls"
        assert_contains "rc-update add nmbd" "$calls"
        assert_contains "ufw allow 138/udp comment primer-announce firewall" "$calls"
        assert_not_contains "ufw allow 137/udp" "$calls"
        mock_reset
        mock primer_os_packages
        primer_step_announce clean
        calls=$(mock_calls)
        assert_contains "rc-service avahi-daemon stop" "$calls"
        assert_contains "rc-update del avahi-daemon" "$calls"
        assert_contains "rc-service nmbd stop" "$calls"
        assert_not_contains "primer_os_packages del" "$calls"
        assert_equal "ufw allow 137/udp" "$(cat /tmp/added)" "rules after clean"'
}

# Same with systemd on Debian, and no firewall: no port is opened. NetBIOS
# comes from the samba package.
test_announce_services_debian() {
    unit "$IMG_TRIXIE" '
        mock primer_os_dependency
        mock primer_net_active_firewall
        mock -r 1 primer_os_in_container
        mock systemctl avahi-daemon nmbd ufw
        unit_step announce
        primer_step_announce install
        calls=$(mock_calls)
        assert_contains "primer_os_dependency avahi-daemon avahi-daemon" "$calls"
        assert_contains "systemctl start avahi-daemon" "$calls"
        assert_contains "systemctl unmask avahi-daemon" "$calls"
        assert_contains "systemctl enable avahi-daemon" "$calls"
        assert_contains "primer_os_dependency nmbd samba" "$calls"
        assert_contains "systemctl enable nmbd" "$calls"
        assert_not_contains "ufw" "$calls"
        mock_reset
        primer_step_announce clean
        calls=$(mock_calls)
        assert_contains "systemctl disable nmbd" "$calls"
        assert_not_contains "ufw" "$calls"'
}
