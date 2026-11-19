#!/bin/sh

# Snippets are single-quoted on purpose: they are expanded in containers.
# shellcheck disable=SC2016

# Unit tests for libexec/os.sh. Package managers and service managers are
# mocked unless the test explicitly exercises the real package manager of the
# image.

test_primer_os_sudo_root() {
    unit "$IMG_ALPINE" '
        primer_os_sudo
        assert_equal "" "$PRIMER_OS_SUDO"'
}

test_primer_os_sudo_nonroot() {
    unit "$IMG_ALPINE" '
        id() { if [ "${1:-}" = "-u" ]; then echo 1000; else command id "$@"; fi; }
        # No sudo: abort
        assert_false command -v sudo
        assert_exit 1 primer_os_sudo
        run primer_os_sudo
        assert_contains "Cannot find sudo" "$RUN_ERR"
        # With sudo
        stub_bin sudo "exec \"\$@\""
        primer_os_sudo
        assert_equal sudo "$PRIMER_OS_SUDO"'
}

test_primer_os_platform() {
    unit "$IMG_ALPINE" '
        assert_equal "$(uname -m)" "$(primer_os_platform)"
        uname() { echo i686; }
        assert_equal x86 "$(primer_os_platform)"
        uname() { echo i386; }
        assert_equal x86 "$(primer_os_platform)"
        uname() { echo aarch64; }
        assert_equal aarch64 "$(primer_os_platform)"
        uname() { echo armv7l; }
        assert_equal armv7l "$(primer_os_platform)"
        uname() { echo x86_64; }
        assert_equal x86_64 "$(primer_os_platform)"'
}

test_primer_os_distribution_alpine() {
    unit "$IMG_ALPINE" '
        assert_equal alpine "$(primer_os_distribution)"
        # The value is cached
        PRIMER_OS_DISTRO=fake
        assert_equal fake "$(primer_os_distribution)"'
}

test_primer_os_distribution_debian() {
    unit "$IMG_TRIXIE" '
        assert_equal debian "$(primer_os_distribution)"'
}

test_primer_os_distribution_unknown() {
    unit "$IMG_ALPINE" '
        rm -f /etc/os-release
        assert_equal "" "$(primer_os_distribution)"'
}

test_primer_os_version_alpine() {
    unit docker.io/library/alpine:3.24.4 '
        assert_equal 3.24.4 "$(primer_os_version)"
        PRIMER_OS_VERSION=42
        assert_equal 42 "$(primer_os_version)"'
}

test_primer_os_version_debian() {
    unit "$IMG_TRIXIE" '
        assert_equal 13 "$(primer_os_version)"'
}

test_primer_os_init() {
    unit "$IMG_ALPINE" '
        PRIMER_OS_SUDO=dummy
        primer_os_init
        assert_equal "" "$PRIMER_OS_SUDO"
        assert_equal alpine "$PRIMER_OS_DISTRO"
        assert_equal "$(cat /etc/alpine-release)" "$PRIMER_OS_VERSION"'
}

test_primer_os_update_alpine() {
    unit "$IMG_ALPINE" '
        mock _primer_os_apk
        primer_os_update
        primer_os_update
        assert_equal "_primer_os_apk update" "$(mock_calls)"
        assert_equal 1 "$PRIMER_OS_PKGIDX_UPDATED"'
}

test_primer_os_update_debian() {
    unit "$IMG_TRIXIE" '
        mock _primer_os_apt
        primer_os_update
        primer_os_update
        assert_equal "_primer_os_apt update" "$(mock_calls)"'
}

test_primer_os_update_others() {
    unit "$IMG_ALPINE" '
        mock _primer_os_dnf _primer_os_swupd
        PRIMER_OS_DISTRO=fedora
        primer_os_update
        assert_equal "_primer_os_dnf makecache --refresh" "$(mock_calls)"
        mock_reset
        PRIMER_OS_DISTRO=clear-linux-os PRIMER_OS_PKGIDX_UPDATED=0
        primer_os_update
        assert_equal "" "$(mock_calls)"
        PRIMER_OS_DISTRO=plan9 PRIMER_OS_PKGIDX_UPDATED=0
        YUSH_LOG_LEVEL=warn
        run primer_os_update
        assert_equal 0 "$RUN_RC"
        assert_contains "System update NYI for plan9" "$RUN_ERR"'
}

test_primer_os_upgrade_alpine() {
    unit "$IMG_ALPINE" '
        mock _primer_os_apk
        primer_os_upgrade
        assert_equal "_primer_os_apk update
_primer_os_apk upgrade" "$(mock_calls)"
        mock_reset
        primer_os_upgrade
        assert_equal "" "$(mock_calls)"
        primer_os_upgrade -f
        assert_equal "_primer_os_apk upgrade" "$(mock_calls)"
        mock_reset
        primer_os_upgrade --force
        assert_equal "_primer_os_apk upgrade" "$(mock_calls)"'
}

test_primer_os_upgrade_debian() {
    unit "$IMG_TRIXIE" '
        mock _primer_os_apt
        primer_os_upgrade
        assert_equal "_primer_os_apt update
_primer_os_apt upgrade
_primer_os_apt autoremove" "$(mock_calls)"'
}

test_primer_os_dependency() {
    unit "$IMG_ALPINE" '
        mock primer_os_packages
        primer_os_dependency sh
        assert_equal "" "$(mock_calls)" "existing command"
        primer_os_dependency nosuchcmd
        assert_equal "primer_os_packages add nosuchcmd" "$(mock_calls)"
        mock_reset
        primer_os_dependency nosuchcmd pkg1 pkg2
        assert_equal "primer_os_packages add pkg1 pkg2" "$(mock_calls)"
        mock_reset
        primer_os_dependency "" openssh
        assert_equal "primer_os_packages add openssh" "$(mock_calls)"
        mock_reset
        primer_os_dependency sh some-package
        assert_equal "" "$(mock_calls)" "existing command with packages"'
}

test_primer_os_packages_alpine() {
    # jq rather than tree: busybox has a tree applet that its trigger
    # recreates when the package is removed.
    unit "$IMG_ALPINE" '
        assert_false primer_os_packages installed jq
        primer_os_packages add jq
        assert_true command -v jq
        assert_true primer_os_packages installed jq
        assert_match "^jq$" "$(primer_os_packages list)"
        assert_equal jq "$(primer_os_packages search jq)"
        assert_equal "" "$(primer_os_packages search nosuchpackage)"
        # Exact names: ca-certificates-bundle is installed, not ca-certificates
        assert_true primer_os_packages installed ca-certificates-bundle
        assert_false primer_os_packages installed ca-certificates
        assert_false primer_os_packages installed j
        # Listing and searching do not depend on the log level
        YUSH_LOG_LEVEL=debug
        assert_match "^jq$" "$(primer_os_packages list 2>/dev/null)"
        assert_equal jq "$(primer_os_packages search jq 2>/dev/null)"
        YUSH_LOG_LEVEL=warn
        primer_os_packages del jq
        assert_false test -e /usr/bin/jq
        assert_false primer_os_packages installed jq
        # Adding an installed package is a no-op
        mock _primer_os_apk
        primer_os_packages add ca-certificates-bundle musl
        assert_equal "" "$(mock_calls)"'
}

test_primer_os_packages_debian() {
    unit "$IMG_TRIXIE" '
        assert_false primer_os_packages installed tree
        primer_os_packages install tree
        assert_true command -v tree
        assert_true primer_os_packages installed tree
        assert_match "^tree$" "$(primer_os_packages list)"
        assert_equal tree "$(primer_os_packages search tree)"
        assert_equal "" "$(primer_os_packages search nosuchpackage || true)"
        # Exact names: perl-base is installed, not perl
        assert_true primer_os_packages installed perl-base
        assert_false primer_os_packages installed perl
        primer_os_packages remove tree
        assert_false test -e /usr/bin/tree
        assert_false primer_os_packages installed tree'
}

test_primer_os_packages_unknown() {
    unit "$IMG_ALPINE" '
        PRIMER_OS_DISTRO=plan9
        mock primer_os_update
        for cmd in "add foo" "del foo" "list" "search foo"; do
            run primer_os_packages $cmd
            assert_equal 0 "$RUN_RC" "$cmd"
            assert_contains "NYI for plan9" "$RUN_ERR" "$cmd"
        done'
}

test_primer_os_packages_others() {
    unit "$IMG_ALPINE" '
        mock _primer_os_dnf _primer_os_swupd primer_os_update
        mock -r 1 rpm
        PRIMER_OS_DISTRO=fedora
        primer_os_packages add foo
        primer_os_packages del foo
        assert_equal "rpm -q foo
primer_os_update
_primer_os_dnf install foo
_primer_os_dnf remove foo
_primer_os_dnf autoremove" "$(mock_calls | sed "s/ *\$//")"
        mock_reset
        PRIMER_OS_DISTRO=clear-linux-os
        mock -o "Installed bundles:" swupd
        primer_os_packages add foo
        primer_os_packages del foo
        assert_contains "_primer_os_swupd bundle-add foo" "$(mock_calls)"
        assert_contains "_primer_os_swupd bundle-remove foo" "$(mock_calls)"'
}

test_primer_os_in_container() {
    unit "$IMG_ALPINE" '
        assert_true primer_os_in_container
        # Remove the markers left by the runtimes: on cgroup v2 hosts, nothing
        # else tells we are in a container, unless systemd-detect-virt says so.
        # podman bind-mounts /run/.containerenv, it cannot always be removed.
        rm -f /.dockerenv /run/.containerenv 2>/dev/null || true
        if [ -e /.dockerenv ] || [ -e /run/.containerenv ] \
                || grep -qE "(docker|lxc|kubepods|containerd|libpod|podman|garden)" /proc/1/cgroup \
                || tr "\\0" "\\n" < /proc/1/environ | grep -q "^container="; then
            assert_true primer_os_in_container
        else
            assert_false primer_os_in_container
            mock -o docker systemd-detect-virt
            assert_true primer_os_in_container
            mock -o wsl systemd-detect-virt
            assert_false primer_os_in_container
            mock -o none -r 1 systemd-detect-virt
            assert_false primer_os_in_container
        fi
        touch /run/.containerenv
        assert_true primer_os_in_container'
}

test_primer_os_service_container() {
    unit "$IMG_ALPINE" '
        mock systemctl service rc-service
        YUSH_LOG_LEVEL=notice
        run primer_os_service start docker
        assert_contains "Service docker start is not relevant in a container" "$RUN_ERR"
        assert_equal "" "$(mock_calls)"'
}

test_primer_os_service_systemctl() {
    unit "$IMG_ALPINE" '
        primer_os_in_container() { return 1; }
        mock -o "docker.service loaded active running Docker
ssh.service loaded active running SSH" systemctl
        primer_os_service start docker
        primer_os_service stop docker
        primer_os_service restart docker
        primer_os_service enable docker
        primer_os_service disable docker
        assert_equal "systemctl start docker
systemctl stop docker
systemctl restart docker
systemctl unmask docker
systemctl enable docker
systemctl disable docker
systemctl mask docker" "$(mock_calls)"
        assert_equal "docker
ssh" "$(primer_os_service list)"'
}

test_primer_os_service_service() {
    unit "$IMG_ALPINE" '
        primer_os_in_container() { return 1; }
        mock -o " [ + ]  docker
 [ - ]  ssh" service
        primer_os_service start docker
        primer_os_service enable docker
        assert_equal "service start docker
service enable docker" "$(mock_calls)"
        assert_equal "docker
ssh" "$(primer_os_service list)"'
}

test_primer_os_service_openrc() {
    unit "$IMG_ALPINE" '
        primer_os_in_container() { return 1; }
        mock rc-service rc-update
        for verb in start stop restart enable disable list; do
            primer_os_service "$verb" docker
        done
        assert_equal "rc-service docker start
rc-service docker stop
rc-service docker restart
rc-update add docker
rc-update del docker
rc-service -l" "$(mock_calls)"'
}

test_primer_os_service_none() {
    unit "$IMG_ALPINE" '
        primer_os_in_container() { return 1; }
        run primer_os_service start docker
        assert_contains "Only service, systemctl" "$RUN_ERR"
        run primer_os_service frobnicate docker
        assert_contains "frobnicate is not a known command" "$RUN_ERR"'
}

test_primer_os_bash_completion_dir() {
    unit "$IMG_ALPINE" '
        assert_equal /etc/bash_completion.d "$(primer_os_bash_completion_dir)"
        PRIMER_OS_DISTRO=clear-linux-os
        assert_equal /usr/share/bash-completion/completions "$(primer_os_bash_completion_dir)"
        PRIMER_OS_DISTRO=debian
        assert_equal /etc/bash_completion.d "$(primer_os_bash_completion_dir)"'
}

test__primer_os_apk() {
    unit "$IMG_ALPINE" '
        mock apk sudo
        _primer_os_apk add foo bar
        YUSH_LOG_LEVEL=debug
        _primer_os_apk add foo 2>/dev/null
        YUSH_LOG_LEVEL=warn
        PRIMER_OS_SUDO=sudo
        _primer_os_apk del foo
        assert_equal "apk add -q foo bar
apk add foo
sudo apk del -q foo" "$(mock_calls)"'
}

test__primer_os_apt() {
    unit "$IMG_ALPINE" '
        stub_bin apt-get "echo \"\$DEBIAN_FRONTEND apt-get \$*\" >> $MOCK_LOG"
        sudo() { echo "sudo $*" >> "$MOCK_LOG"; }
        _primer_os_apt install foo
        YUSH_LOG_LEVEL=debug
        _primer_os_apt install foo 2>/dev/null
        YUSH_LOG_LEVEL=warn
        PRIMER_OS_SUDO=sudo
        _primer_os_apt remove foo
        assert_equal "noninteractive apt-get install -y -qq foo
noninteractive apt-get install -y -q foo
sudo --preserve-env=DEBIAN_FRONTEND apt-get remove -y -qq foo" "$(mock_calls)"'
}

test__primer_os_swupd() {
    unit "$IMG_ALPINE" '
        mock swupd sudo
        _primer_os_swupd bundle-add foo
        YUSH_LOG_LEVEL=debug
        _primer_os_swupd bundle-add foo 2>/dev/null
        YUSH_LOG_LEVEL=warn
        PRIMER_OS_SUDO=sudo
        _primer_os_swupd update
        assert_equal "swupd bundle-add --assume=yes --quiet foo
swupd bundle-add --assume=yes foo
sudo swupd update --assume=yes --quiet" "$(mock_calls)"'
}

test__primer_os_dnf() {
    unit "$IMG_ALPINE" '
        mock dnf sudo
        _primer_os_dnf install foo
        YUSH_LOG_LEVEL=debug
        _primer_os_dnf install foo 2>/dev/null
        YUSH_LOG_LEVEL=warn
        PRIMER_OS_SUDO=sudo
        _primer_os_dnf remove foo
        assert_equal "dnf install -y -q foo
dnf install -y foo
sudo dnf remove -y -q foo" "$(mock_calls)"'
}

test_primer_os_service_list_without_name() {
    unit "$IMG_ALPINE" '
        YUSH_LOG_LEVEL=notice
        run primer_os_service list
        assert_equal 0 "$RUN_RC"
        assert_contains "not relevant in a container" "$RUN_ERR"'
}
