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

# A fake release, served by primer_net_curl, with the checksum FAKE_SUM (the
# real one when empty).
LAZYDOCKER_FAKE='
mkdir -p /tmp/fake
printf "#!/bin/sh\necho Version: '"$LAZYDOCKER_VERSION"'\n" > /tmp/fake/lazydocker
chmod a+x /tmp/fake/lazydocker
tar -C /tmp/fake -czf /tmp/fake.tar.gz lazydocker
FAKE_SUM=
primer_net_curl() {
    mock_log primer_net_curl "$@"
    case "$1" in
        */checksums.txt)
            printf "%s  %s\n" "${FAKE_SUM:-$(sha256sum < /tmp/fake.tar.gz | cut -d" " -f1)}" \
                "lazydocker_'"$LAZYDOCKER_VERSION"'_Linux_x86_64.tar.gz";;
        *.tar.gz) cat /tmp/fake.tar.gz;;
        *) return 22;;
    esac
}
uname() { case "$1" in -m) echo x86_64;; *) echo Linux;; esac; }
'

test_lazydocker_bad_checksum() {
    unit "$IMG_ALPINE" "$LAZYDOCKER_FAKE"'
        FAKE_SUM=$(printf "%064d" 0)
        unit_step lazydocker
        primer_step_lazydocker option --version '"$LAZYDOCKER_VERSION"'
        run primer_step_lazydocker install
        assert_equal 1 "$RUN_RC"
        assert_contains "Checksum mismatch" "$RUN_ERR"
        assert_false test -e /usr/local/bin/lazydocker'
}

# Installing the same version twice downloads nothing the second time.
test_lazydocker_install_twice() {
    unit "$IMG_ALPINE" "$LAZYDOCKER_FAKE"'
        unit_step lazydocker
        primer_step_lazydocker option --version '"$LAZYDOCKER_VERSION"'
        run primer_step_lazydocker install
        assert_equal 0 "$RUN_RC"
        assert_true test -x /usr/local/bin/lazydocker
        mock_reset
        run primer_step_lazydocker install
        assert_equal 0 "$RUN_RC" "second install"
        assert_equal "" "$(mock_calls)" "downloads"'
}

# Without a version, and when the latest one cannot be found, the step fails.
test_lazydocker_no_latest() {
    unit "$IMG_ALPINE" '
        mock primer_github_latest primer_net_curl
        unit_step lazydocker
        run primer_step_lazydocker install
        assert_equal 1 "$RUN_RC"
        assert_contains "Could not find the latest version of lazydocker" "$RUN_ERR"
        assert_not_contains primer_net_curl "$(mock_calls)"'
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
            assert_equal 1 "$RUN_RC"
            assert_contains "lazydocker_'"$LAZYDOCKER_VERSION"'_Linux_${_pair#*:}.tar.gz" "$(mock_calls)" "asset for ${_pair%%:*}"
            assert_contains "No binary at" "$RUN_ERR"
        done'
}

# Clean only removes lazydocker at the version the step installs.
test_lazydocker_clean_other_version() {
    unit "$IMG_ALPINE" '
        mkdir -p /usr/local/bin
        printf "#!/bin/sh\necho version 0.1\n" > /usr/local/bin/lazydocker
        chmod a+x /usr/local/bin/lazydocker
        unit_step lazydocker
        primer_step_lazydocker option --version 0.25.2
        run primer_step_lazydocker clean
        assert_equal 0 "$RUN_RC"
        assert_contains "Keeping /usr/local/bin/lazydocker, at version 0.1" "$RUN_ERR"
        assert_true test -x /usr/local/bin/lazydocker
        printf "#!/bin/sh\necho version 0.25.2\n" > /usr/local/bin/lazydocker
        run primer_step_lazydocker clean
        assert_equal 0 "$RUN_RC"
        assert_false test -e /usr/local/bin/lazydocker'
}
