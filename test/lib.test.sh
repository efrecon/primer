#!/bin/sh
# shellcheck disable=SC2016

# Tests of the test framework itself: test/lib.sh and test/run.sh.

# Every assertion helper can fail, and explains why.
test_lib_assertions_fail() {
    unit "$IMG_ALPINE" '
        for a in "assert_equal a b" "assert_match ^b\$ a" "assert_contains b a" \
                "assert_not_contains a a" "assert_true false" "assert_false true" \
                "assert_exit 1 true" "fail"; do
            run sh -c ". /primer/test/lib.sh; $a; exit 0"
            assert_equal 1 "$RUN_RC" "$a must fail"
            assert_match "^ASSERT: " "$RUN_ERR" "$a must explain"
        done'
}

# The helpers run commands with set -e, as primer does: a failure in the
# middle of a function is not hidden by the commands after it.
test_lib_helpers_set_e() {
    unit "$IMG_ALPINE" '
        f() { false; echo after; }
        run f
        assert_equal 1 "$RUN_RC" "status of run"
        assert_equal "" "$RUN_OUT" "output of run"
        assert_false f
        assert_exit 1 f
        g() { false || true; echo after; }
        assert_true g
        # set -e is restored after the helpers.
        case "$-" in *e*) ;; *) fail "set -e lost";; esac'
}

# Scripts must reach their end: an early exit with status 0 fails, other
# statuses are kept, and commands registered with at_exit always run.
test_lib_early_exit() {
    unit "$IMG_ALPINE" '
        prelude() {
            tar -C /primer -cf - . | sh -c "$_TEST_PRELUDE" sh "$1"
        }
        run prelude "echo before; exit 0; echo after"
        assert_equal 1 "$RUN_RC" "early exit"
        assert_contains "before the end of the script" "$RUN_ERR"
        run prelude "true"
        assert_equal 0 "$RUN_RC" "complete script"
        run prelude "skip because"
        assert_equal 77 "$RUN_RC" "skip"
        run prelude "at_exit \"echo cleaned\"; false"
        assert_equal 1 "$RUN_RC" "failure"
        assert_equal cleaned "$RUN_OUT" "at_exit"
        run prelude "[ a = b ] && echo never"
        assert_equal 1 "$RUN_RC" "status of the last command"'
}

# The runner, on probe tests run from a copy of the framework, on the host:
# a failure followed by a success fails, exit status 77 is only a skip when
# skip was called, and tests that hang time out.
test_lib_runner() {
    _probe=$(mktemp -d)
    mkdir -p "$_probe/test"
    cp "$TEST_ROOT/test/run.sh" "$TEST_ROOT/test/lib.sh" "$_probe/test/"
    # Commented out, so that they are not discovered here.
    sed 's/^#//' > "$_probe/test/probe.test.sh" <<'EOF'
#test_probe_pass() { true; }
#test_probe_two_calls() { false; true; }
#test_probe_status77() { return 77; }
#test_probe_skip() { skip "for a reason"; }
#test_probe_hang () { sleep 20; }
EOF
    _out=$("$_probe/test/run.sh" -t -T 3 '^probe:' 2>&1 || true)
    _logs=$(printf %s\\n "$_out" | sed -n 's/^Logs kept in //p')
    rm -rf "$_probe" "$_logs"
    printf '%s\n' "$_out"
    assert_match "^ok [0-9]+ - probe:test_probe_pass$" "$_out"
    assert_match "^not ok [0-9]+ - probe:test_probe_two_calls$" "$_out"
    assert_match "^not ok [0-9]+ - probe:test_probe_status77$" "$_out"
    assert_match "^ok [0-9]+ - probe:test_probe_skip # SKIP for a reason$" "$_out"
    assert_match "^not ok [0-9]+ - probe:test_probe_hang$" "$_out"
    assert_match "timed out after 3s" "$_out"
    assert_match "^# passed: 1, failed: 3, skipped: 1$" "$_out"
}
