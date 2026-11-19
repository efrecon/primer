#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the timezone step.

_timezone_verify='
    primer_run -s timezone --timezone:location Europe/Stockholm install
    assert_equal 0 "$PRIMER_RC"
    assert_equal /usr/share/zoneinfo/Europe/Stockholm "$(readlink /etc/localtime)"
    assert_match "^CES?T$" "$(date +%Z)"
    # Changing the timezone replaces the link
    primer_run -s timezone --timezone:location America/New_York install
    assert_equal 0 "$PRIMER_RC"
    assert_equal /usr/share/zoneinfo/America/New_York "$(readlink /etc/localtime)"
    assert_match "^E[DS]T$" "$(date +%Z)"
'

test_timezone_debian() {
    in_container "$IMG_TRIXIE" "$_timezone_verify"
}

test_timezone_alpine() {
    in_container "$IMG_ALPINE" "$_timezone_verify"
}

test_timezone_replaces_dangling_link() {
    in_container "$IMG_TRIXIE" '
        ln -sf /nonexistent/zone /etc/localtime
        primer_run -s timezone --timezone:location Europe/Stockholm install
        assert_equal 0 "$PRIMER_RC"
        assert_equal /usr/share/zoneinfo/Europe/Stockholm "$(readlink /etc/localtime)"'
}

test_timezone_updates_etc_timezone() {
    in_container "$IMG_TRIXIE" '
        echo Etc/UTC > /etc/timezone
        primer_run -s timezone --timezone:location Asia/Tokyo install
        assert_equal 0 "$PRIMER_RC"
        assert_equal Asia/Tokyo "$(cat /etc/timezone)"'
}

test_timezone_unknown_location() {
    in_container "$IMG_TRIXIE" '
        before=$(readlink /etc/localtime)
        primer_run -s timezone --timezone:location Nowhere/Atlantis install
        assert_equal 1 "$PRIMER_RC"
        assert_contains "Unknown timezone Nowhere/Atlantis" "$PRIMER_ERR"
        assert_equal "$before" "$(readlink /etc/localtime)"'
}

test_timezone_no_location() {
    in_container "$IMG_ALPINE" '
        primer_run -s timezone install
        assert_equal 0 "$PRIMER_RC"
        assert_false [ -e /etc/localtime ]
        primer_run -v warn -s timezone clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "cannot be removed" "$PRIMER_ERR"'
}
