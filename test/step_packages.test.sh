#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the packages step.

test_packages_alpine() {
    in_container "$IMG_ALPINE" '
        primer_run -s packages --packages:packages "jq tree" --packages:fresh 0 install
        assert_equal 0 "$PRIMER_RC"
        assert_true apk info -e jq
        assert_true apk info -e tree
        assert_true [ -x /usr/bin/jq ]
        primer_run -s packages --packages:packages "jq tree" clean
        assert_equal 0 "$PRIMER_RC"
        assert_false apk info -e jq
        assert_false apk info -e tree'
}

test_packages_debian() {
    in_container "$IMG_TRIXIE" '
        primer_run -s packages --packages:packages "jq tree" --packages:fresh 0 install
        assert_equal 0 "$PRIMER_RC"
        assert_true dpkg -s jq
        assert_true [ -x /usr/bin/tree ]
        primer_run -s packages --packages:packages "jq tree" clean
        assert_equal 0 "$PRIMER_RC"
        assert_false dpkg -s jq
        assert_false [ -e /usr/bin/tree ]'
}

# Packages whose name is a prefix of an installed package are still installed:
# perl-base is part of Debian images, perl is not.
test_packages_prefix_debian() {
    in_container "$IMG_TRIXIE" '
        assert_true dpkg -s perl-base
        primer_run -s packages --packages:packages perl --packages:fresh 0 install
        assert_equal 0 "$PRIMER_RC"
        assert_equal "install ok installed" "$(dpkg-query -W -f "\${Status}" perl 2>/dev/null)"'
}

# Same on Alpine: ca-certificates-bundle is part of the image, ca-certificates
# is not.
test_packages_prefix_alpine() {
    in_container "$IMG_ALPINE" '
        assert_true apk info -e ca-certificates-bundle
        primer_run -s packages --packages:packages ca-certificates --packages:fresh 0 install
        assert_equal 0 "$PRIMER_RC"
        assert_true apk info -e ca-certificates'
}

# The system is freshened up (index update and upgrade) by default only.
test_packages_fresh() {
    unit "$IMG_ALPINE" '
        mock primer_os_update primer_os_upgrade primer_os_packages
        unit_step packages
        primer_step_packages option --packages "jq tree"
        primer_step_packages install
        assert_equal "primer_os_update
primer_os_upgrade
primer_os_packages add jq tree" "$(mock_calls)"
        mock_reset
        primer_step_packages option --fresh 0
        primer_step_packages install
        assert_equal "primer_os_update
primer_os_packages add jq tree" "$(mock_calls)"
        mock_reset
        primer_step_packages clean
        assert_equal "primer_os_packages del jq tree" "$(mock_calls)"'
}

test_packages_none() {
    unit "$IMG_ALPINE" '
        mock primer_os_update primer_os_upgrade primer_os_packages
        unit_step packages
        primer_step_packages option --fresh 0
        primer_step_packages install
        primer_step_packages clean
        assert_equal "primer_os_update" "$(mock_calls)"'
}
