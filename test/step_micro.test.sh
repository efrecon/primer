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
            assert_equal 1 "$RUN_RC"
            assert_contains "/v'"$MICRO_VERSION"'/micro-'"$MICRO_VERSION"'-${_pair#*:}.tar.gz" "$(mock_calls)" "asset for ${_pair%%:*}"
        done
        uname() { case "$1" in -m) echo mips;; *) echo Linux;; esac; }
        mock_reset
        run primer_step_micro install
        assert_equal 1 "$RUN_RC" "unknown platform"
        assert_contains "No known binaries" "$RUN_ERR"
        assert_equal "" "$(mock_calls)"'
}

# A missing release fails the step and leaves nothing behind, even at quiet log
# levels (curl must fail on HTTP errors).
test_micro_missing_release() {
    in_container "$IMG_ALPINE" '
        primer_run -v warn -s micro --micro:version 0.0.0 install
        assert_equal 1 "$PRIMER_RC"
        assert_contains "No binary at" "$PRIMER_ERR"
        assert_false test -e /usr/local/bin/micro'
}

# The tarpack is verified against the .sha file of the release, and installing
# the same version twice downloads nothing the second time.
test_micro_checksum() {
    unit "$IMG_ALPINE" '
        mkdir -p /tmp/fake/micro-'"$MICRO_VERSION"'
        printf "#!/bin/sh\necho Version: '"$MICRO_VERSION"'\n" > /tmp/fake/micro-'"$MICRO_VERSION"'/micro
        chmod a+x /tmp/fake/micro-'"$MICRO_VERSION"'/micro
        tar -C /tmp/fake -czf /tmp/fake.tar.gz micro-'"$MICRO_VERSION"'
        FAKE_SUM=$(printf "%064d" 0)
        primer_net_curl() {
            mock_log primer_net_curl "$@"
            case "$1" in
                *.sha) printf "%s  %s\n" "$FAKE_SUM" "$(basename "${1%.sha}")";;
                *.tar.gz) cat /tmp/fake.tar.gz;;
                *) return 22;;
            esac
        }
        uname() { case "$1" in -m) echo x86_64;; *) echo Linux;; esac; }
        unit_step micro
        primer_step_micro option --version '"$MICRO_VERSION"'
        run primer_step_micro install
        assert_equal 1 "$RUN_RC" "mismatch"
        assert_contains "Checksum mismatch" "$RUN_ERR"
        assert_false test -e /usr/local/bin/micro
        FAKE_SUM=$(sha256sum < /tmp/fake.tar.gz | cut -d" " -f1)
        run primer_step_micro install
        assert_equal 0 "$RUN_RC" "match"
        assert_true test -x /usr/local/bin/micro
        mock_reset
        run primer_step_micro install
        assert_equal 0 "$RUN_RC" "second install"
        assert_equal "" "$(mock_calls)" "downloads"'
}

# Clean only removes micro at the version the step installs.
test_micro_clean_other_version() {
    unit "$IMG_ALPINE" '
        mkdir -p /usr/local/bin
        printf "#!/bin/sh\necho version 0.1\n" > /usr/local/bin/micro
        chmod a+x /usr/local/bin/micro
        unit_step micro
        primer_step_micro option --version 2.0.15
        run primer_step_micro clean
        assert_equal 0 "$RUN_RC"
        assert_contains "Keeping /usr/local/bin/micro, at version 0.1" "$RUN_ERR"
        assert_true test -x /usr/local/bin/micro
        printf "#!/bin/sh\necho version 2.0.15\n" > /usr/local/bin/micro
        run primer_step_micro clean
        assert_equal 0 "$RUN_RC"
        assert_false test -e /usr/local/bin/micro'
}
