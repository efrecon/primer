#!/bin/sh

# Test runner for primer. Discovers test functions (test_*) in test/*.test.sh,
# runs them in parallel and reports results, optionally in TAP format. Tests run
# in throwaway containers, using docker or podman (the first one found, unless
# PRIMER_TEST_RUNTIME or -r is set). See usage() below.

set -eu

TEST_ROOT=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
export TEST_ROOT

# shellcheck source=/dev/null
. "$TEST_ROOT/test/lib.sh"

JOBS=4
TAP=0
KEEP=0
LIST=0
TAIL=25

usage() {
    cat <<USAGE >&2
Usage: $(basename "$0") [options] [PATTERN...]

Run the primer test suite in containers. PATTERNs are extended regular
expressions matched against test names, formatted as file:function, e.g.
'^unit_', 'step_docker:' or 'test_primer_os_version'. Without patterns, all
tests run, together with a coverage check.

Options:
  -j N        Number of tests to run in parallel (default: $JOBS)
  -t          Output results in TAP format
  -k          Keep the directory with test logs, even on success
  -l          List matching tests and exit
  -r RUNTIME  Container runtime to use (default: first of docker, podman)
  -h          Print this help and exit

Environment:
  PRIMER_TEST_RUNTIME  Same as -r
  GITHUB_TOKEN         When set, used for GitHub API calls in containers
  YUSH_LOG_LEVEL       Log level of primer in unit tests (default: warn)
USAGE
    exit "${1:-0}"
}

while getopts "j:tklr:h" opt; do
    case "$opt" in
        j) JOBS=$OPTARG;;
        t) TAP=1;;
        k) KEEP=1;;
        l) LIST=1;;
        r) PRIMER_TEST_RUNTIME=$OPTARG;;
        h) usage 0;;
        *) usage 1;;
    esac
done
shift $((OPTIND - 1))

# Print all tests, as file:function, from the test files, without executing
# them.
discover() {
    for _f in "$TEST_ROOT"/test/*.test.sh; do
        [ -f "$_f" ] || continue
        _base=$(basename "$_f" .test.sh)
        grep -oE '^test_[A-Za-z0-9_]*\(\)' "$_f" | sed -e 's/()$//' -e "s/^/${_base}:/"
    done
}

# Print test names matching at least one of the patterns passed as arguments,
# or all when none.
select_tests() {
    if [ "$#" = "0" ]; then
        discover
    else
        _all=$(discover)
        for _t in $_all; do
            for _p in "$@"; do
                if printf %s\\n "$_t" | grep -qE -- "$_p"; then
                    printf %s\\n "$_t"
                    break
                fi
            done
        done
    fi
}

# Print missing coverage: library functions without a unit test named
# test_<function>[_suffix], and steps without a test file.
coverage() {
    _tests=$(discover | cut -d: -f2)
    for _lib in "$TEST_ROOT"/libexec/*.sh; do
        # shellcheck disable=SC2013 # function names have no spaces
        for _fn in $(grep -oE '^[_a-z][a-z0-9_]*\(\)' "$_lib" | sed 's/()$//'); do
            if ! printf %s\\n "$_tests" | grep -qE "^test_${_fn}(_[a-z0-9]+)*\$"; then
                printf 'function %s (%s)\n' "$_fn" "libexec/$(basename "$_lib")"
            fi
        done
    done
    for _step in "$TEST_ROOT"/libexec/steps/*.sh; do
        _name=$(basename "$_step" .sh)
        if ! [ -f "$TEST_ROOT/test/step_${_name}.test.sh" ]; then
            printf 'step %s (test/step_%s.test.sh)\n' "$_name" "$_name"
        fi
    done
}

TESTS=$(select_tests "$@")
if [ -z "$TESTS" ]; then
    echo "No test matches: $*" >&2
    exit 1
fi

if [ "$LIST" = "1" ]; then
    printf %s\\n "$TESTS"
    if [ "$#" = "0" ]; then
        _missing=$(coverage)
        if [ -n "$_missing" ]; then
            printf '\nMissing coverage:\n%s\n' "$_missing" >&2
            exit 1
        fi
    fi
    exit 0
fi

if ! container_runtime >/dev/null; then
    echo "No working container runtime found (tried: ${PRIMER_TEST_RUNTIME:-docker podman})" >&2
    exit 1
fi
export PRIMER_TEST_RUNTIME PRIMER_TEST_ROOTLESS

LOGS=$(mktemp -d "${TMPDIR:-/tmp}/primer-tests.XXXXXX")
TOTAL=$(printf %s\\n "$TESTS" | wc -l | tr -d ' ')
[ "$#" = "0" ] && TOTAL=$((TOTAL + 1))

if [ "$TAP" = "1" ]; then
    echo "1..$TOTAL"
else
    _rootless=; [ "$PRIMER_TEST_ROOTLESS" = "1" ] && _rootless=" (rootless)"
    echo "Running $TOTAL tests with $PRIMER_TEST_RUNTIME${_rootless}, $JOBS in parallel, logs in $LOGS"
fi

# Pull images once, quietly, so parallel tests do not race to pull them.
for _img in "$IMG_ALPINE" "$IMG_TRIXIE" "$IMG_BOOKWORM"; do
    "$PRIMER_TEST_RUNTIME" pull -q "$_img" >/dev/null 2>&1 || true
done

NUM=0
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=

# Report the result of a test: report NAME STATUS SECONDS
report() {
    NUM=$((NUM + 1))
    _log="$LOGS/$(printf %s "$1" | tr ':' '.').log"
    case "$2" in
        0)
            PASSED=$((PASSED + 1))
            if [ "$TAP" = "1" ]; then
                echo "ok $NUM - $1"
            else
                printf 'ok    %s (%ss)\n' "$1" "$3"
            fi
            ;;
        77)
            SKIPPED=$((SKIPPED + 1))
            _reason=$(grep -m1 '^SKIP: ' "$_log" 2>/dev/null | sed 's/^SKIP: //' || true)
            if [ "$TAP" = "1" ]; then
                echo "ok $NUM - $1 # SKIP ${_reason}"
            else
                printf 'SKIP  %s: %s\n' "$1" "$_reason"
            fi
            ;;
        *)
            FAILED=$((FAILED + 1))
            FAILURES="$FAILURES $1"
            if [ "$TAP" = "1" ]; then
                echo "not ok $NUM - $1"
                tail -n "$TAIL" "$_log" 2>/dev/null | sed 's/^/# /'
            else
                printf 'FAIL  %s (%ss, status %s)\n' "$1" "$3" "$2"
                tail -n "$TAIL" "$_log" 2>/dev/null | sed 's/^/      | /'
            fi
            ;;
    esac
}

# Coverage check, only when running the whole suite.
if [ "$#" = "0" ]; then
    _missing=$(coverage)
    printf %s\\n "$_missing" > "$LOGS/coverage.check.log"
    if [ -z "$_missing" ]; then report "coverage:check" 0 0; else report "coverage:check" 1 0; fi
fi

# Run one test in the background, writing "status seconds" to its .rc file.
launch() {
    _file=${1%%:*}
    _fn=${1#*:}
    _base="$LOGS/$(printf %s "$1" | tr ':' '.')"
    (
        _start=$(date +%s)
        _rc=0
        (
            cd "$TEST_ROOT"
            # shellcheck disable=SC1090
            . "$TEST_ROOT/test/${_file}.test.sh"
            "$_fn"
        ) > "${_base}.log" 2>&1 < /dev/null || _rc=$?
        echo "$_rc $(( $(date +%s) - _start ))" > "${_base}.rc.tmp"
        mv "${_base}.rc.tmp" "${_base}.rc"
    ) &
}

# Simple job pool: launch tests while fewer than JOBS are running, report and
# reap finished ones by polling their .rc files.
PENDING=$TESTS
RUNNING=
while [ -n "$PENDING" ] || [ -n "$RUNNING" ]; do
    _count=$(printf %s "$RUNNING" | wc -w | tr -d ' ')
    while [ -n "$PENDING" ] && [ "$_count" -lt "$JOBS" ]; do
        _next=$(printf %s\\n "$PENDING" | head -n 1)
        PENDING=$(printf %s\\n "$PENDING" | sed '1d')
        launch "$_next"
        RUNNING="$RUNNING $_next"
        _count=$((_count + 1))
    done
    _still=
    for _t in $RUNNING; do
        _rcf="$LOGS/$(printf %s "$_t" | tr ':' '.').rc"
        if [ -f "$_rcf" ]; then
            read -r _st _secs < "$_rcf"
            report "$_t" "$_st" "$_secs"
        else
            _still="$_still $_t"
        fi
    done
    RUNNING=$_still
    [ -n "$RUNNING" ] && sleep 1
done
wait

if [ "$TAP" = "1" ]; then
    echo "# passed: $PASSED, failed: $FAILED, skipped: $SKIPPED"
else
    echo "Passed: $PASSED, failed: $FAILED, skipped: $SKIPPED"
fi

if [ "$FAILED" -gt 0 ]; then
    [ "$TAP" = "1" ] || echo "Failed:$FAILURES"
    echo "Logs kept in $LOGS" >&2
    exit 1
fi
if [ "$KEEP" = "1" ]; then
    echo "Logs kept in $LOGS" >&2
else
    rm -rf "$LOGS"
fi
