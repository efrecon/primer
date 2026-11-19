#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in the containers.
# shellcheck disable=SC2016

# Tests of the wifi step. Containers have no wifi interface, so ip, iwlist,
# ifup and ifdown are replaced by stubs (see test/data/wifi/setup.sh), while
# wpa_passphrase is the real one, installed by the step.

# PSK for SSID IEEE and passphrase "password", test vector from IEEE 802.11i.
WIFI_IEEE_PSK=f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e

# Install with a passphrase, check the block, the original content and the
# commands used to bring the interface up. $1 is the image.
_wifi_install_psk() {
    in_container "$1" '
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:essid IEEE --wifi:psk password install
        assert_equal 0 "$PRIMER_RC" "install status"
        ifs=$(cat /etc/network/interfaces)
        assert_contains "$(cat test/data/wifi/interfaces)" "$ifs" "original content kept"
        block=$(sed -n "/^# primer autoadd wifi settings: wlan0$/,/^# primer endof wifi settings: wlan0$/p" /etc/network/interfaces)
        assert_contains "auto wlan0" "$block"
        assert_contains "allow-hotplug wlan0" "$block"
        assert_contains "iface wlan0 inet dhcp" "$block"
        assert_contains "wpa-ssid \"IEEE\"" "$block"
        assert_contains "wpa-psk '"$WIFI_IEEE_PSK"'" "$block"
        assert_not_contains "password" "$block" "no cleartext passphrase"
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
    _wifi_install_psk "$IMG_ALPINE"
}

test_wifi_install_psk_debian() {
    _wifi_install_psk "$IMG_TRIXIE"
}

test_wifi_install_open_network() {
    in_container "$IMG_ALPINE" '
        WIFI_INRANGE=Other
        . test/data/wifi/setup.sh
        primer_run -s wifi --wifi:interface wlan0 --wifi:ssid "Open Cafe" install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Open Cafe seems not in range" "$PRIMER_ERR"
        assert_true grep -qxF "    wpa-ssid \"Open Cafe\"" /etc/network/interfaces
        assert_true grep -qxF "    wpa-key-mgmt NONE" /etc/network/interfaces
        assert_false grep -q "wpa-psk" /etc/network/interfaces'
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
        assert_not_contains "Replacing wifi settings" "$PRIMER_ERR" "unchanged settings"
        primer_run -s wifi --wifi:essid Other --wifi:psk "another secret" install
        assert_equal 0 "$PRIMER_RC" "second install"
        assert_contains "Replacing wifi settings for wlan0" "$PRIMER_ERR"
        ifs=$(cat /etc/network/interfaces)
        assert_equal 1 "$(grep -c "^# primer autoadd wifi settings: wlan0$" /etc/network/interfaces)" "blocks"
        assert_contains "wpa-ssid \"Other\"" "$ifs"
        assert_not_contains "IEEE" "$ifs"
        assert_not_contains "'"$WIFI_IEEE_PSK"'" "$ifs"
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
        primer_run -s wifi clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_equal "$(cat /tmp/before)" "$(cat /etc/network/interfaces)" "content after clean"
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
