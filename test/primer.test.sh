#!/bin/sh
# shellcheck disable=SC2016 # snippets expand inside containers

# Tests of the primer command-line interface. Most use the test step at
# test/steps/test.sh to observe what primer does from within a step.

test_cli_forwards_options() {
    primer_in "$IMG_ALPINE" -v error -s test --test:variable myTest --test:test variable -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal myTest "$PRIMER_OUT"'
}

test_cli_forwards_options_with_equal() {
    primer_in "$IMG_ALPINE" -v error -s test --test:variable="my value" --test:test=variable -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal "my value" "$PRIMER_OUT"'
}

test_cli_steps_from_environment() {
    primer_in -e PRIMER_STEPS=test -e TEST_TEST=variable -e TEST_VARIABLE=fromEnv "$IMG_ALPINE" -v error -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal fromEnv "$PRIMER_OUT"'
}

test_cli_detects_root() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test os_sudo -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal "" "$PRIMER_OUT"'
}

test_cli_detects_platform() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test os_platform -- '
        assert_equal 0 "$PRIMER_RC"
        assert_equal "$(uname -m)" "$PRIMER_OUT"'
}

test_cli_detects_distribution() {
    primer_in "$IMG_TRIXIE" -v error -s test --test:test os_distribution -- '
        assert_equal debian "$PRIMER_OUT"'
}

test_cli_detects_version() {
    primer_in docker.io/library/alpine:3.24.4 -v error -s test --test:test os_version -- '
        assert_equal 3.24.4 "$PRIMER_OUT"'
}

test_cli_detects_container() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test os_container -- '
        assert_equal 1 "$PRIMER_OUT"'
}

test_cli_installs_dependencies() {
    primer_in "$IMG_TRIXIE" -v error -s test --test:test os_curl -- '
        assert_equal 0 "$PRIMER_RC"
        assert_match "^Usage: curl" "$PRIMER_OUT"'
}

test_cli_locates_steps() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test utils_locate -- '
        assert_equal /primer/test/steps/test.sh "$PRIMER_OUT"'
}

test_cli_finds_local_interface() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test net_interfaces -- '
        assert_match "^lo$" "$PRIMER_OUT"'
}

test_cli_finds_mac_addresses() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test net_macaddr -- '
        assert_match "^([0-9a-f]{2}:){5}[0-9a-f]{2}$" "$PRIMER_OUT"'
}

test_cli_finds_primary_interface() {
    primer_in "$IMG_ALPINE" -v error -s test --test:test net_primary_interface -- '
        assert_match "^eth[0-9]+$" "$PRIMER_OUT"'
}

test_cli_help() {
    primer_in "$IMG_ALPINE" --help -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "Accepted commands" "$PRIMER_ERR"'
}

test_cli_unknown_option() {
    primer_in "$IMG_ALPINE" --no-such-option -- '
        assert_equal 1 "$PRIMER_RC"
        assert_contains "Unknown option: --no-such-option" "$PRIMER_ERR"'
}

test_cli_info_lists_step_options() {
    primer_in "$IMG_ALPINE" -s "docker compose" info -- '
        assert_equal 0 "$PRIMER_RC"
        assert_match "^docker: --registry .*--buildx-sha256" "$PRIMER_OUT"
        assert_match "^compose: *$" "$PRIMER_OUT"'
}

test_cli_env_lists_steps_and_host() {
    primer_in "$IMG_ALPINE" -s packages env -- '
        assert_equal 0 "$PRIMER_RC"
        assert_contains "PRIMER_STEP_PACKAGES_PACKAGES" "$PRIMER_OUT"'
}

test_cli_config_file() {
    in_container "$IMG_ALPINE" '
        printf "PRIMER_STEPS=test\nTEST_TEST=variable\nTEST_VARIABLE=fromConfig\n" > /tmp/primer.env
        primer_run -v error -c /tmp/primer.env
        assert_equal 0 "$PRIMER_RC"
        assert_equal fromConfig "$PRIMER_OUT"'
}

# Library mode is only for sourcing: executed, primer refuses to run rather
# than silently doing nothing, and ignores PRIMER_ROOT_DIR from the
# environment. Sourced, it loads everything and stops, also from a script.
test_cli_library_mode() {
    in_container "$IMG_TRIXIE" '
        apt-get update -qq >/dev/null && apt-get install -y -qq bash >/dev/null 2>&1 || true
        ./libexec/yu.sh/bin/amalgamation.sh primer > /tmp/primer.sh
        chmod a+x /tmp/primer.sh
        for p in ./primer /tmp/primer.sh; do
            run env PRIMER_LIBRARY=1 "$p" --help
            assert_equal 1 "$RUN_RC" "$p in library mode"
            assert_contains "PRIMER_LIBRARY=1 is only for sourcing primer" "$RUN_ERR"
            run env PRIMER_LIBRARY=1 bash "$p" --help
            assert_equal 1 "$RUN_RC" "$p in library mode, with bash"
            mkdir -p /tmp/elsewhere
            run env PRIMER_ROOT_DIR=/tmp/elsewhere "$p" --help
            assert_equal 0 "$RUN_RC" "$p with PRIMER_ROOT_DIR"
            assert_contains "Accepted commands" "$RUN_ERR"
        done
        printf "PRIMER_LIBRARY=1\n. /tmp/primer.sh\nprimer_step_docker option | head -c 10\n" > /tmp/lib.sh
        assert_equal "--registry" "$(sh /tmp/lib.sh)" "sourced amalgamation"
        assert_equal "/primer" "$(cd /tmp && PRIMER_LIBRARY=1 PRIMER_ROOT_DIR=/primer sh -c ". /primer/primer; echo \$PRIMER_ROOT_DIR")"'
}

test_cli_amalgamation() {
    in_container "$IMG_ALPINE" '
        ./libexec/yu.sh/bin/amalgamation.sh primer > /tmp/primer.sh
        chmod a+x /tmp/primer.sh
        out=$(/tmp/primer.sh -v notice -s compose install 2>&1)
        assert_contains "Docker compose is now a Docker CLI plugin" "$out"
        assert_true /tmp/primer.sh --help'
}
