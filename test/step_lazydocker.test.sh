#!/bin/sh
# shellcheck disable=SC2016

# Tests of the lazydocker step: binary from the official releases, verified
# against the release checksums.

# Pinned versions, so no GitHub API call is needed.
LAZYDOCKER_VERSION=0.25.2
LAZYDOCKER_OLD_VERSION=0.25.0

test_lazydocker_install() {
    in_container "$IMG_ALPINE" '
        primer_run -s lazydocker --lazydocker:version '"$LAZYDOCKER_VERSION"' install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Version: '"$LAZYDOCKER_VERSION"'" "$(/usr/local/bin/lazydocker --version)"
        assert_not_contains "mismatch" "$PRIMER_ERR"
        primer_run -s lazydocker clean
        assert_equal 0 "$PRIMER_RC"
        assert_false test -e /usr/local/bin/lazydocker'
}

test_lazydocker_upgrade() {
    in_container "$IMG_TRIXIE" '
        primer_run -s lazydocker --lazydocker:version '"$LAZYDOCKER_OLD_VERSION"' install
        assert_contains "Version: '"$LAZYDOCKER_OLD_VERSION"'" "$(lazydocker --version)"
        primer_run -s lazydocker --lazydocker:version '"$LAZYDOCKER_VERSION"' install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Version: '"$LAZYDOCKER_VERSION"'" "$(lazydocker --version)"'
}

test_lazydocker_bad_checksum() {
    unit "$IMG_ALPINE" '
        mkdir -p /tmp/fake
        printf "#!/bin/sh\necho Version: '"$LAZYDOCKER_VERSION"'\n" > /tmp/fake/lazydocker
        chmod a+x /tmp/fake/lazydocker
        tar -C /tmp/fake -czf /tmp/fake.tar.gz lazydocker
        primer_net_curl() {
            mock_log primer_net_curl "$@"
            case "$1" in
                */checksums.txt) printf "%s  %s\n" 0000 "$(basename "$(mock_calls | grep -o "lazydocker_[^ ]*tar.gz" | head -n 1)")";;
                *.tar.gz) cat /tmp/fake.tar.gz;;
                *) return 22;;
            esac
        }
        unit_step lazydocker
        primer_step_lazydocker option --version '"$LAZYDOCKER_VERSION"'
        run primer_step_lazydocker install
        assert_equal 0 "$RUN_RC"
        assert_contains "Checksum mismatch" "$RUN_ERR"
        assert_false test -e /usr/local/bin/lazydocker'
}

test_lazydocker_platform_assets() {
    unit "$IMG_ALPINE" '
        mock -r 22 primer_net_curl
        unit_step lazydocker
        primer_step_lazydocker option --version '"$LAZYDOCKER_VERSION"'
        for _pair in x86_64:x86_64 aarch64:arm64 armv7l:armv7 armv6l:armv6 i686:x86; do
            eval "uname() { case \"\$1\" in -m) echo ${_pair%%:*};; *) echo Linux;; esac; }"
            mock_reset
            run primer_step_lazydocker install
            assert_equal 0 "$RUN_RC"
            assert_contains "lazydocker_'"$LAZYDOCKER_VERSION"'_Linux_${_pair#*:}.tar.gz" "$(mock_calls)" "asset for ${_pair%%:*}"
            assert_contains "No binary at" "$RUN_ERR"
        done'
}
