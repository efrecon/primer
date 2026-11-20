#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in the containers.
# shellcheck disable=SC2016

# Tests of the wifi step. Containers have no wifi interface, so ip, iwlist,
# ifup and ifdown are replaced by stubs (see test/data/wifi/setup.sh), while
# wpa_passphrase is the real one, installed by the step.

# PSK for SSID IEEE and passphrase "password", test vector from IEEE 802.11i.
WIFI_IEEE_PSK=f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e

# Install with a passphrase, check the block, the configuration file, the
# original content and the commands used to bring the interface up. $1 is the
# image, $2 the line of the block pointing to the configuration file.
_wifi_install_psk() {
    in_container "$1" '
        conf_line="'"$2"'"
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC" "install status"
        ifs=$(cat /etc/network/interfaces)
        assert_contains "$(cat test/data/wifi/interfaces)" "$ifs" "original content kept"
        block=$(sed -n "/^# primer autoadd wifi settings: wlan0$/,/^# primer endof wifi settings: wlan0$/p" /etc/network/interfaces)
        assert_contains "auto wlan0" "$block"
        assert_contains "allow-hotplug wlan0" "$block"
        assert_contains "iface wlan0 inet dhcp" "$block"
        assert_contains "$conf_line /etc/wpa_supplicant/primer-wlan0.conf" "$block"
        assert_not_contains "IEEE" "$ifs" "no network in the interfaces"
        assert_not_contains "'"$WIFI_IEEE_PSK"'" "$ifs" "no key in the interfaces"
        conf=/etc/wpa_supplicant/primer-wlan0.conf
        assert_equal "600 root" "$(stat -c "%a %U" "$conf")" "configuration only for root"
        assert_contains "ssid=\"IEEE\"" "$(cat "$conf")"
        assert_contains "psk='"$WIFI_IEEE_PSK"'" "$(cat "$conf")"
        assert_not_contains "password" "$(cat "$conf")" "no cleartext passphrase"
        calls=$(mock_calls)
        assert_contains "ip link set wlan0 up" "$calls"
        assert_contains "iwlist wlan0 scan" "$calls"
        assert_contains "ip link set wlan0 down" "$calls"
        assert_contains "ifdown wlan0" "$calls"
        assert_contains "ifup wlan0" "$calls"
        assert_contains "IEEE is in range" "$PRIMER_ERR"

        # Second run does not add another block
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC" "second install status"
        assert_equal 1 "$(grep -c "^# primer autoadd wifi settings: wlan0$" /etc/network/interfaces)" "blocks"'
}

test_wifi_install_psk_alpine() {
    _wifi_install_psk "$IMG_ALPINE" "    wifi-config-path"
}

test_wifi_install_psk_debian() {
    _wifi_install_psk "$IMG_TRIXIE" "    wpa-conf"
}

test_wifi_install_open_network() {
    in_container "$IMG_ALPINE" '
        WIFI_INRANGE=Other
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:interface wlan0 --wifi:ssid "Open Cafe" install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Open Cafe seems not in range" "$PRIMER_ERR"
        conf=$(cat /etc/wpa_supplicant/primer-wlan0.conf)
        assert_contains "ssid=\"Open Cafe\"" "$conf"
        assert_contains "key_mgmt=NONE" "$conf"
        assert_not_contains "psk=" "$conf"'
}

test_wifi_detects_wlx_interface() {
    in_container "$IMG_ALPINE" '
        WIFI_IF=wlx00c0cab0beef
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:essid IEEE install
        assert_equal 0 "$PRIMER_RC"
        assert_true grep -qxF "iface wlx00c0cab0beef inet dhcp" /etc/network/interfaces
        assert_contains "ifup wlx00c0cab0beef" "$(mock_calls)"'
}

test_wifi_already_connected() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        touch /tmp/wifi.connected
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC"
        assert_equal "$(cat test/data/wifi/interfaces)" "$(cat /etc/network/interfaces)" "interfaces unchanged"
        assert_not_contains "ifup" "$(mock_calls)"'
}

# Changing network or passphrase replaces the block, keeping the rest.
test_wifi_install_replaces_changed_settings() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        chmod 640 /etc/network/interfaces
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC" "first install"
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_not_contains "Replacing wifi" "$PRIMER_ERR" "unchanged settings"
        primer_run -s wifi --wifi:essid Other --wifi:psk "another secret" install
        assert_equal 0 "$PRIMER_RC" "second install"
        assert_contains "Replacing wifi network for wlan0" "$PRIMER_ERR"
        ifs=$(cat /etc/network/interfaces)
        assert_equal 1 "$(grep -c "^# primer autoadd wifi settings: wlan0$" /etc/network/interfaces)" "blocks"
        conf=$(cat /etc/wpa_supplicant/primer-wlan0.conf)
        assert_contains "ssid=\"Other\"" "$conf"
        assert_not_contains "IEEE" "$conf"
        assert_not_contains "'"$WIFI_IEEE_PSK"'" "$conf"
        assert_equal 600 "$(stat -c %a /etc/wpa_supplicant/primer-wlan0.conf)"
        assert_contains "$(cat test/data/wifi/interfaces)" "$ifs" "original content kept"
        assert_equal 640 "$(stat -c %a /etc/network/interfaces)" "mode kept"'
}

# A block without its end marker (e.g. edited by hand) is never removed, as
# that would remove everything after it: the file is left untouched.
test_wifi_damaged_block() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        printf "\n# primer autoadd wifi settings: wlan0\nauto wlan0\n\nauto eth1\niface eth1 inet dhcp\n" >> /etc/network/interfaces
        cp /etc/network/interfaces /tmp/before
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "have no end marker, leaving the file untouched" "$PRIMER_ERR"
        assert_equal "$(cat /tmp/before)" "$(cat /etc/network/interfaces)" "after install"
        primer_run -s wifi clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_contains "have no end marker, leaving the file untouched" "$PRIMER_ERR"
        assert_equal "$(cat /tmp/before)" "$(cat /etc/network/interfaces)" "after clean"'
}

test_wifi_clean_keeps_other_content() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        # Another (manual) wifi block, for an interface sharing the prefix.
        printf "\n# primer autoadd wifi settings: wlan01\nauto wlan01\n# primer endof wifi settings: wlan01\n" >> /etc/network/interfaces
        cp /etc/network/interfaces /tmp/before
        chmod 640 /etc/network/interfaces
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_true grep -qxF "auto wlan0" /etc/network/interfaces
        assert_true test -f /etc/wpa_supplicant/primer-wlan0.conf
        echo "# not from primer" > /etc/wpa_supplicant/primer-wlan01.conf
        primer_run -s wifi clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_equal "$(cat /tmp/before)" "$(cat /etc/network/interfaces)" "content after clean"
        assert_false test -e /etc/wpa_supplicant/primer-wlan0.conf
        assert_true test -f /etc/wpa_supplicant/primer-wlan01.conf
        assert_equal 640 "$(stat -c %a /etc/network/interfaces)" "mode after clean"'
}

test_wifi_clean_connected() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        touch /tmp/wifi.connected
        primer_run -s wifi clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "ifdown --force -v wlan0" "$(mock_calls)"
        assert_equal "$(cat test/data/wifi/interfaces)" "$(cat /etc/network/interfaces)"'
}

test_wifi_no_interface() {
    in_container "$IMG_ALPINE" '
        WIFI_IF=
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:essid IEEE install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "No wifi interface found" "$PRIMER_ERR"
        primer_run -s wifi clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_equal "$(cat test/data/wifi/interfaces)" "$(cat /etc/network/interfaces)"'
}

test_wifi_no_network() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        primer_run -s wifi install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No wifi network specified" "$PRIMER_ERR"
        assert_not_contains "ip link set" "$(mock_calls)"'
}

# Invalid input fails the step and changes nothing: passphrases that
# wpa_passphrase rejects (outside 8..63 characters), network names with double
# quotes.
test_wifi_invalid_input() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        for psk in short "$(printf "%064d" 0)" ""; do
            if [ -n "$psk" ]; then
                primer_run -s wifi --wifi:essid IEEE --wifi:psk "$psk" install
            else
                primer_run -s wifi --wifi:essid "IE\"EE" --wifi:psk longenough install
            fi
            assert_equal 1 "$PRIMER_RC" "status for [$psk]"
            assert_false grep -q "wpa_supplicant" /etc/network/interfaces
            assert_false test -e /etc/wpa_supplicant/primer-wlan0.conf
            assert_equal "$(cat test/data/wifi/interfaces)" "$(cat /etc/network/interfaces)"
            assert_not_contains "ifup" "$(mock_calls)"
        done'
}

# The network name is matched as a fixed string in the scan.
test_wifi_in_range_fixed_string() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:essid "I.EE" install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "I.EE seems not in range" "$PRIMER_ERR"
        primer_run -s wifi --wifi:essid IEEE install
        assert_contains "IEEE is in range" "$PRIMER_ERR"'
}

# Older versions of the step kept the network and its key in the interfaces
# file: the block is replaced by one pointing to the configuration file.
test_wifi_upgrade_old_block() {
    in_container "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        printf "\n# primer autoadd wifi settings: wlan0\nauto wlan0\niface wlan0 inet dhcp\n    wpa-ssid \"IEEE\"\n    wpa-psk '"$WIFI_IEEE_PSK"'\n# primer endof wifi settings: wlan0\n" >> /etc/network/interfaces
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC"
        assert_not_contains "'"$WIFI_IEEE_PSK"'" "$(cat /etc/network/interfaces)"
        assert_contains "wifi-config-path" "$(cat /etc/network/interfaces)"
        assert_contains "'"$WIFI_IEEE_PSK"'" "$(cat /etc/wpa_supplicant/primer-wlan0.conf)"'
}

# The passphrase is given to wpa_passphrase on stdin, never on its command
# line, which all users can see.
test_wifi_passphrase_not_in_arguments() {
    unit "$IMG_ALPINE" '
        unit_step wifi
        wpa_passphrase() { mock_log wpa_passphrase "$@"; [ "$(cat)" = "secret passphrase" ] && printf "\tpsk=abc123\n"; }
        PRIMER_STEP_WIFI_ESSID=IEEE
        PRIMER_STEP_WIFI_PSK="secret passphrase"
        assert_equal "abc123" "$(_primer_step_wifi_psk_hex)"
        assert_equal "wpa_passphrase IEEE" "$(mock_calls)"
        # Versions that only read from a terminal: as an argument.
        mock_reset
        wpa_passphrase() {
            mock_log wpa_passphrase "$@"
            [ $# = 2 ] || { echo "tcgetattr: Not a tty" >&2; return 1; }
            [ "$2" = "secret passphrase" ] && printf "\tpsk=def456\n"
        }
        assert_equal "def456" "$(_primer_step_wifi_psk_hex)"
        assert_equal "wpa_passphrase IEEE
wpa_passphrase IEEE secret passphrase" "$(mock_calls)"
        # And with the real one, either way.
        apk add -q wpa_supplicant >/dev/null
        unset -f wpa_passphrase
        PRIMER_STEP_WIFI_PSK=password
        assert_equal '"$WIFI_IEEE_PSK"' "$(_primer_step_wifi_psk_hex)"'
}

# Without ifupdown, e.g. on Fedora, or with NetworkManager running, the step
# fails and changes nothing.
test_wifi_unsupported_hosts() {
    unit "$IMG_ALPINE" '
        . test/data/wifi/setup.sh
        unit_step wifi
        mock primer_os_packages
        PRIMER_STEP_WIFI_ESSID=IEEE
        PRIMER_STEP_WIFI_INTERFACE=wlan0
        PRIMER_OS_DISTRO=fedora
        run primer_step_wifi install
        assert_equal 1 "$RUN_RC" "fedora"
        assert_contains "needs ifupdown, which fedora does not use" "$RUN_ERR"
        PRIMER_OS_DISTRO=debian
        mock -o NetworkManager primer_os_service
        run primer_step_wifi install
        assert_equal 1 "$RUN_RC" "NetworkManager"
        assert_contains "use nmcli" "$RUN_ERR"
        assert_not_contains "primer_os_packages" "$(mock_calls)"
        assert_equal "$(cat /primer/test/data/wifi/interfaces)" "$(cat /etc/network/interfaces)"
        assert_false test -e /etc/wpa_supplicant/primer-wlan0.conf'
}
