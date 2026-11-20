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
    primer_in "$IMG_ALPINE_PINNED" -v error -s test --test:test os_version -- '
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
        dev=$(primary_dev_or_skip)
        assert_equal "$dev" "$PRIMER_OUT"'
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

# A typo in the command is an error, not a silent success.
test_cli_unknown_command() {
    primer_in "$IMG_ALPINE" -s timezone instal -- '
        assert_equal 1 "$PRIMER_RC"
        assert_contains "Unknown command: instal" "$PRIMER_ERR"'
    primer_in "$IMG_ALPINE" -s timezone envfoo -- '
        assert_equal 1 "$PRIMER_RC"
        assert_contains "Unknown command: envfoo" "$PRIMER_ERR"'
}

# Values of --step:option=value can contain equal signs, e.g. URLs.
test_cli_step_option_value_with_equals() {
    primer_in "$IMG_ALPINE" -s timezone --timezone:location=a=b=c info -- '
        assert_equal 0 "$PRIMER_RC"
        assert_not_contains "Unknown option" "$PRIMER_ERR"
        assert_match "PRIMER_STEP_TIMEZONE_LOCATION.*a=b=c" "$PRIMER_OUT"'
}

test_cli_info_lists_step_options() {
    primer_in "$IMG_ALPINE" -s "docker compose" info -- '
        assert_equal 0 "$PRIMER_RC"
        assert_match "^docker: --registry .*--buildx-sha256" "$PRIMER_OUT"
        assert_match "^compose: *$" "$PRIMER_OUT"'
}

test_cli_env_lists_steps_and_host() {
    primer_in -h primer-env "$IMG_ALPINE" -s packages env -- '
        assert_equal 0 "$PRIMER_RC"
        assert_match "^_hostinfo:$" "$PRIMER_OUT"
        assert_match "^[[:space:]]+distribution: alpine$" "$PRIMER_OUT"
        assert_match "^[[:space:]]+version: $(cat /etc/alpine-release)$" "$PRIMER_OUT"
        assert_match "^[[:space:]]+hostname: primer-env$" "$PRIMER_OUT"
        assert_match "^[[:space:]]+mac: ([0-9a-f]{2}:){5}[0-9a-f]{2}$" "$PRIMER_OUT"
        assert_match "^packages: " "$PRIMER_OUT"
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


#### Functions of primer itself, in library mode #############################

# Variables changing how commands run cannot come from configuration files.
test_primer_config_refused_variables() {
    unit "$IMG_ALPINE" '
        printf "PATH=/tmp/evil\nLD_PRELOAD=/tmp/x.so\nPRIMER_OS_SUDO=/tmp/x\nIFS=x\nPRIMER_OK=yes\n" > /tmp/cfg.env
        path=$PATH
        run primer_config /tmp/cfg.env
        assert_equal 0 "$RUN_RC"
        for v in PATH LD_PRELOAD PRIMER_OS_SUDO IFS; do
            assert_contains "$v cannot be set from configuration files" "$RUN_ERR"
        done
        primer_config /tmp/cfg.env 2>/dev/null
        assert_equal "$path" "$PATH"
        assert_equal "" "${LD_PRELOAD:-}"
        assert_equal "" "$PRIMER_OS_SUDO"
        assert_equal yes "$PRIMER_OK"'
}

# Remote configuration over plain HTTP is refused, before any download.
test_cli_config_http_refused() {
    primer_in "$IMG_ALPINE" -c http://config.invalid/primer.env -s timezone install -- '
        assert_equal 1 "$PRIMER_RC"
        assert_contains "over plain HTTP refused, use https://" "$PRIMER_ERR"'
}

test_primer_abort() {
    unit "$IMG_ALPINE" '
        run primer_abort "Something went wrong"
        assert_equal 1 "$RUN_RC"
        assert_contains "Something went wrong" "$RUN_ERR"'
}

# Comments are skipped, values are exported and substituted, invalid names
# only warn, a missing file is ignored, the last line needs no newline.
test_primer_config() {
    unit "$IMG_ALPINE" '
        printf "# A comment=1\nPRIMER_A=one\nPRIMER_B=\${PRIMER_A}-two\nnot-a-name=3\nPRIMER_C=last" > /tmp/cfg.env
        run primer_config /tmp/cfg.env
        assert_equal 0 "$RUN_RC"
        assert_contains "not-a-name is not a valid variable name" "$RUN_ERR"
        primer_config /tmp/cfg.env 2>/dev/null
        assert_equal one "$PRIMER_A"
        assert_equal one-two "$PRIMER_B" "substituted"
        assert_equal last "$PRIMER_C" "last line without newline"
        assert_equal one "$(sh -c "echo \$PRIMER_A")" "exported"
        PRIMER_SUBST=0
        primer_config /tmp/cfg.env 2>/dev/null
        assert_equal "\${PRIMER_A}-two" "$PRIMER_B" "not substituted"
        run primer_config /tmp/missing.env
        assert_equal 0 "$RUN_RC" "missing file"
        assert_equal "" "$RUN_ERR$RUN_OUT"'
}

test_primer_steps() {
    unit "$IMG_ALPINE" '
        PRIMER_PATH=/primer/test/steps:/primer/libexec/steps
        steps=$(primer_steps 2>/dev/null)
        assert_match "^test$" "$steps"
        assert_match "^docker$" "$steps"
        assert_match "^users$" "$steps"
        assert_not_contains ".sh" "$steps"'
}

# The options of the step, and its variables that can be set from outside.
test_primer_info() {
    unit "$IMG_ALPINE" '
        PRIMER_PATH=/primer/libexec/steps
        out=$(primer_info packages)
        assert_match "^packages: " "$out"
        assert_match "^	PRIMER_STEP_PACKAGES_PACKAGES=" "$out"
        assert_equal "" "$(primer_info nosuchstep 2>/dev/null)"'
}

test_primer_hostinfo() {
    unit -h primer-host "$IMG_ALPINE" '
        out=$(primer_hostinfo)
        assert_match "^_hostinfo:$" "$out"
        assert_match "^	distribution: alpine$" "$out"
        assert_match "^	version: $(cat /etc/alpine-release)$" "$out"
        assert_match "^	hostname: primer-host$" "$out"'
}

# The default configuration is ./primer.env, then ./primer_<mac>.env (MAC of
# the primary interface, lowercase, no separators). Command-line options win.
# Passes now.
test_cli_config_mac_file() {
    in_container "$IMG_ALPINE" '
        mac=$(unit_load; primer_net_macaddr "$(primer_net_primary_interface)" | tr -d :)
        assert_match "^[0-9a-f]{12}$" "$mac"
        mkdir -p /tmp/cfg && cd /tmp/cfg
        printf "PRIMER_STEPS=test\nTEST_TEST=variable\nTEST_VARIABLE=generic\n" > primer.env
        printf "TEST_VARIABLE=host-%s\n" "$mac" > "primer_${mac}.env"
        primer_run -v error
        assert_equal 0 "$PRIMER_RC"
        assert_equal "host-$mac" "$PRIMER_OUT"
        primer_run -v error --test:variable fromCli
        assert_equal fromCli "$PRIMER_OUT"'
}

# Unknown steps abort before later steps run, failing steps fail primer.
# Passes now.
test_cli_failing_steps() {
    in_container "$IMG_ALPINE" '
        primer_run -v error -s "nosuchstep test" --test:test variable --test:variable ran
        assert_equal 1 "$PRIMER_RC"
        assert_contains "primer_step_nosuchstep not implemented" "$PRIMER_ERR"
        assert_not_contains ran "$PRIMER_OUT"
        primer_run -v error -s test --test:test os_nosuchfunction
        assert_false [ "$PRIMER_RC" = 0 ]'
}
