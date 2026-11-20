#!/bin/sh
# shellcheck disable=SC2016

# Tests of the git step: git and git LFS, from the official releases.

# Pinned git LFS version, so no GitHub API call is needed.
GIT_LFS_VERSION=3.8.1

# Container-side helpers for offline tests: a fake git LFS release tarball
# and its sha256 sum, and a primer_net_curl serving them. The URLs requested
# are logged as mock calls.
# shellcheck disable=SC2016
GIT_FAKE_RELEASE='
fake_lfs_release() {
    mkdir -p /tmp/fake/git-lfs-'"$GIT_LFS_VERSION"'
    printf "#!/bin/sh\necho \"git-lfs/'"$GIT_LFS_VERSION"' (fake)\"\n" > /tmp/fake/git-lfs-'"$GIT_LFS_VERSION"'/git-lfs
    chmod a+x /tmp/fake/git-lfs-'"$GIT_LFS_VERSION"'/git-lfs
    tar -C /tmp/fake -czf /tmp/fake.tar.gz git-lfs-'"$GIT_LFS_VERSION"'
    FAKE_SUM=$(sha256sum /tmp/fake.tar.gz | cut -d " " -f 1)
}
primer_net_curl() {
    mock_log primer_net_curl "$@"
    case "$1" in
        */sha256sums.asc)
            for _p in amd64 386 arm64 arm; do
                printf "%s *git-lfs-linux-%s-v'"$GIT_LFS_VERSION"'.tar.gz\n" "$FAKE_SUM" "$_p"
            done;;
        *.tar.gz) cat /tmp/fake.tar.gz;;
        *) return 22;;
    esac
}
'

test_git_install_alpine() {
    in_container "$IMG_ALPINE" '
        adduser -D tester
        primer_run -s git --git:lfs-version '"$GIT_LFS_VERSION"' --git:lfs-install "^tester$" install
        assert_equal 0 "$PRIMER_RC"
        assert_true command -v git
        assert_contains "'"$GIT_LFS_VERSION"'" "$(/usr/local/bin/git-lfs --version)"
        assert_contains "[filter \"lfs\"]" "$(cat /home/tester/.gitconfig)"
        # Only removed at the version that primer installs
        primer_run -s git --git:lfs-version 1.0.0 clean
        assert_equal 0 "$PRIMER_RC"
        assert_true test -x /usr/local/bin/git-lfs
        assert_contains "not installed by primer" "$PRIMER_ERR"
        primer_run -s git --git:lfs-version '"$GIT_LFS_VERSION"' clean
        assert_equal 0 "$PRIMER_RC"
        assert_false test -e /usr/local/bin/git-lfs'
}

test_git_install_debian() {
    in_container "$IMG_TRIXIE" '
        useradd -m tester
        primer_run -s git --git:lfs-version '"$GIT_LFS_VERSION"' --git:lfs-install= install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "'"$GIT_LFS_VERSION"'" "$(git-lfs --version)"
        # Empty --lfs-install: only the current user (root) gets LFS.
        assert_contains "[filter \"lfs\"]" "$(cat /root/.gitconfig)"
        assert_false test -e /home/tester/.gitconfig'
}

test_git_install_fedora() {
    in_container "$IMG_FEDORA" '
        useradd -m tester
        primer_run -s git --git:lfs-version '"$GIT_LFS_VERSION"' --git:lfs-install "^tester$" install
        assert_equal 0 "$PRIMER_RC"
        assert_true command -v git
        assert_contains "'"$GIT_LFS_VERSION"'" "$(/usr/local/bin/git-lfs --version)"
        assert_contains "[filter \"lfs\"]" "$(cat /home/tester/.gitconfig)"'
}

test_git_bad_checksum() {
    unit "$IMG_ALPINE" "$GIT_FAKE_RELEASE"'
        fake_lfs_release
        FAKE_SUM=0000000000000000000000000000000000000000000000000000000000000000
        primer_os_platform() { echo x86_64; }
        mock git
        unit_step git
        primer_step_git option --lfs-version '"$GIT_LFS_VERSION"' --lfs-install ""
        run primer_step_git install
        assert_equal 1 "$RUN_RC"
        assert_contains "SHA256 sum mismatch" "$RUN_ERR"
        assert_false test -e /usr/local/bin/git-lfs'
}

test_git_platform_assets() {
    unit "$IMG_ALPINE" "$GIT_FAKE_RELEASE"'
        fake_lfs_release
        mock git
        unit_step git
        primer_step_git option --lfs-version '"$GIT_LFS_VERSION"' --lfs-install ""
        for _pair in x86_64:amd64 i686:386 aarch64:arm64 armv7l:arm; do
            _machine=${_pair%%:*}
            _asset=${_pair#*:}
            eval "primer_os_platform() { echo $_machine; }"
            rm -f /usr/local/bin/git-lfs
            mock_reset
            run primer_step_git install
            assert_equal 0 "$RUN_RC" "install on $_machine"
            assert_contains "/v'"$GIT_LFS_VERSION"'/git-lfs-linux-${_asset}-v'"$GIT_LFS_VERSION"'.tar.gz" "$(mock_calls)" "asset for $_machine"
            assert_true test -x /usr/local/bin/git-lfs
        done
        # Unknown platforms are reported, nothing is downloaded.
        primer_os_platform() { echo mips; }
        rm -f /usr/local/bin/git-lfs
        mock_reset
        run primer_step_git install
        assert_equal 1 "$RUN_RC" "unknown platform status"
        assert_contains "Cannot download for this platform" "$RUN_ERR"
        assert_not_contains "tar.gz" "$(mock_calls)"'
}

# Installing the same version twice downloads nothing the second time.
test_git_install_twice() {
    unit "$IMG_ALPINE" "$GIT_FAKE_RELEASE"'
        fake_lfs_release
        primer_os_platform() { echo x86_64; }
        mock git
        unit_step git
        primer_step_git option --lfs-version '"$GIT_LFS_VERSION"' --lfs-install ""
        run primer_step_git install
        assert_equal 0 "$RUN_RC"
        assert_true test -x /usr/local/bin/git-lfs
        mock_reset
        run primer_step_git install
        assert_equal 0 "$RUN_RC" "second install"
        assert_not_contains primer_net_curl "$(mock_calls)"'
}

# The checksum file has no line for the asset: nothing is installed, the step
# fails.
test_git_missing_checksum() {
    unit "$IMG_ALPINE" '
        mkdir -p /tmp/fake/git-lfs-'"$GIT_LFS_VERSION"'
        printf "#!/bin/sh\necho git-lfs/'"$GIT_LFS_VERSION"'\n" > /tmp/fake/git-lfs-'"$GIT_LFS_VERSION"'/git-lfs
        chmod a+x /tmp/fake/git-lfs-'"$GIT_LFS_VERSION"'/git-lfs
        tar -C /tmp/fake -czf /tmp/fake.tar.gz git-lfs-'"$GIT_LFS_VERSION"'
        primer_net_curl() {
            mock_log primer_net_curl "$@"
            case "$1" in
                */sha256sums.asc) printf "%s *git-lfs-linux-arm64-v'"$GIT_LFS_VERSION"'.tar.gz\n" 0123;;
                *.tar.gz) cat /tmp/fake.tar.gz;;
                *) return 22;;
            esac
        }
        primer_os_platform() { echo x86_64; }
        mock git
        unit_step git
        primer_step_git option --lfs-version '"$GIT_LFS_VERSION"' --lfs-install ""
        run primer_step_git install
        assert_equal 1 "$RUN_RC"
        assert_contains "Could not find sha256 sum" "$RUN_ERR"
        assert_false test -e /usr/local/bin/git-lfs'
}
