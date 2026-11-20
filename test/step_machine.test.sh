#!/bin/sh
# shellcheck disable=SC2016

# Tests of the machine step: Docker machine (deprecated upstream, but still
# downloadable) and its bash completion.

# Pinned versions, so no GitHub API call is needed.
MACHINE_VERSION=0.16.2
MACHINE_OLD_VERSION=0.16.1
MACHINE_OLD_SHA256=44a008c14549156222b314b1448c22ef255b446419fcf96570f3f288dff318a9

test_machine_install() {
    in_container "$IMG_TRIXIE" '
        primer_run -s machine --machine:version '"$MACHINE_VERSION"' install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "'"$MACHINE_VERSION"'" "$(docker-machine --version)"
        assert_true test -s /etc/bash_completion.d/docker-machine
        primer_run -s machine clean
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Removing Docker machine" "$PRIMER_ERR"
        assert_false test -e /usr/local/bin/docker-machine
        assert_false test -e /etc/bash_completion.d/docker-machine'
}

test_machine_sha256() {
    in_container "$IMG_TRIXIE" '
        primer_run -s machine --machine:version '"$MACHINE_OLD_VERSION"' --machine:sha256 '"$MACHINE_OLD_SHA256"' install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "'"$MACHINE_OLD_VERSION"'" "$(docker-machine --version)"'
}

test_machine_bad_sha256() {
    in_container "$IMG_TRIXIE" '
        primer_run -s machine --machine:version '"$MACHINE_OLD_VERSION"' --machine:sha256 0000 install
        assert_equal 1 "$PRIMER_RC"
        assert_contains "SHA256 sum mismatch" "$PRIMER_ERR"
        assert_false test -e /usr/local/bin/docker-machine'
}

# Upgrading keeps the existing completion file and must not fail.
test_machine_upgrade() {
    in_container "$IMG_TRIXIE" '
        primer_run -s machine --machine:version '"$MACHINE_OLD_VERSION"' install
        assert_contains "'"$MACHINE_OLD_VERSION"'" "$(docker-machine --version)"
        primer_run -s machine --machine:version '"$MACHINE_VERSION"' install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "'"$MACHINE_VERSION"'" "$(docker-machine --version)"'
}

# Asset names per architecture, and no completion file when the binary could
# not be downloaded, which fails the step.
test_machine_platform_assets() {
    unit "$IMG_ALPINE" '
        mock -r 22 primer_net_curl
        unit_step machine
        primer_step_machine option --version 0.16.2
        for _pair in x86_64:x86_64 aarch64:aarch64 armv7l:armhf; do
            eval "uname() { case \"\$1\" in -m) echo ${_pair%%:*};; *) echo Linux;; esac; }"
            mock_reset
            run primer_step_machine install
            assert_equal 1 "$RUN_RC"
            assert_match "/v0.16.2/docker-machine-Linux-${_pair#*:}$" "$(mock_calls)" "asset for ${_pair%%:*}"
        done
        assert_false [ -e "$(primer_os_bash_completion_dir)/docker-machine" ]'
}
