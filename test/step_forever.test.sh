#!/bin/sh

# Snippets in single quotes are expanded in the containers, not here.
# shellcheck disable=SC2016

# Tests for the forever step, which never returns: it is run under timeout.

# Start primer in the background, wait until the forever step has started (the
# OS might need packages first) and check it is still running seconds later.
_forever_running='
    /primer/primer -s forever --forever:sleep 1 install > /tmp/forever.log 2>&1 &
    pid=$!
    i=0
    while ! grep -q "Will sleep forever" /tmp/forever.log && [ "$i" -lt 300 ]; do
        sleep 1; i=$((i + 1))
    done
    assert_true grep -q "Will sleep forever with at 1s intervals" /tmp/forever.log
    sleep 3
    assert_true kill -0 "$pid"
    kill "$pid"
'

test_forever_keeps_running_alpine() {
    in_container "$IMG_ALPINE" "$_forever_running"
}

test_forever_keeps_running_debian() {
    in_container "$IMG_TRIXIE" "$_forever_running"
}

# An invalid sleep value makes the step fail at once, rather than spin.
test_forever_invalid_sleep() {
    in_container "$IMG_ALPINE" '
        start=$(date +%s)
        rc=0
        timeout 60 /primer/primer -s forever --forever:sleep abc install || rc=$?
        assert_false [ "$rc" = 0 ]
        assert_true [ "$(( $(date +%s) - start ))" -lt 50 ]'
}

test_forever_clean() {
    primer_in "$IMG_ALPINE" -s forever clean -- '
        assert_equal 0 "$PRIMER_RC"'
}
