#!/bin/sh
# shellcheck disable=SC2016

# Tests of the micro step: binary from the official releases.

# Pinned version, so no GitHub API call is needed.
MICRO_VERSION=2.0.15

test_micro_install() {
    in_container "$IMG_ALPINE" '
        primer_run -s micro --micro:version '"$MICRO_VERSION"' install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Version: '"$MICRO_VERSION"'" "$(/usr/local/bin/micro --version)"
        assert_not_contains "mismatch" "$PRIMER_ERR"
        primer_run -s micro clean
        assert_equal 0 "$PRIMER_RC"
        assert_false test -e /usr/local/bin/micro'
}

test_micro_platform_assets() {
    unit "$IMG_ALPINE" '
        mock -r 22 primer_net_curl
        unit_step micro
        primer_step_micro option --version '"$MICRO_VERSION"'
        for _pair in x86_64:linux64-static i686:linux32 aarch64:linux-arm64 armv7l:linux-arm armv6l:linux-arm; do
            eval "uname() { case \"\$1\" in -m) echo ${_pair%%:*};; *) echo Linux;; esac; }"
            mock_reset
            run primer_step_micro install
            assert_equal 0 "$RUN_RC"
            assert_contains "/v'"$MICRO_VERSION"'/micro-'"$MICRO_VERSION"'-${_pair#*:}.tar.gz" "$(mock_calls)" "asset for ${_pair%%:*}"
        done
        uname() { case "$1" in -m) echo mips;; *) echo Linux;; esac; }
        mock_reset
        run primer_step_micro install
        assert_contains "No known binaries" "$RUN_ERR"
        assert_equal "" "$(mock_calls)"'
}

# A missing release must not leave anything behind, nor fail, even at quiet
# log levels (curl must fail on HTTP errors).
test_micro_missing_release() {
    in_container "$IMG_ALPINE" '
        primer_run -v warn -s micro --micro:version 0.0.0 install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No binary at" "$PRIMER_ERR"
        assert_false test -e /usr/local/bin/micro'
}
