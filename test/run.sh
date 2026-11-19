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

JOBS=
TIMEOUT=${PRIMER_TEST_TIMEOUT:-1200}
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
  -j N        Number of tests to run in parallel (default: number of CPUs of
              the container runtime, at least 2)
  -T SECS     Fail tests that run longer than this, 0 for no limit (default:
              1200, generous for tests installing Debian or docker packages)
  -t          Output results in TAP format
  -k          Keep the directory with test logs, even on success
  -l          List matching tests and exit
  -r RUNTIME  Container runtime to use (default: first of docker, podman)
  -h          Print this help and exit

Environment:
  PRIMER_TEST_RUNTIME  Same as -r
  PRIMER_TEST_TIMEOUT  Same as -T
  PRIMER_TEST_WARM     Set to 0 to use the official Debian images instead of
                       warm copies (see warm_image in test/lib.sh)
  GITHUB_TOKEN         When set, used for GitHub API calls in containers
  YUSH_LOG_LEVEL       Log level of primer in unit tests (default: warn)
USAGE
    exit "${1:-0}"
}

while getopts "j:T:tklr:h" opt; do
    case "$opt" in
        j) JOBS=$OPTARG;;
        T) TIMEOUT=$OPTARG;;
        t) TAP=1;;
        k) KEEP=1;;
        l) LIST=1;;
        r) PRIMER_TEST_RUNTIME=$OPTARG;;
        h) usage 0;;
        *) usage 1;;
    esac
done
shift $((OPTIND - 1))

case "$JOBS" in
    *[!0-9]*|0) echo "Invalid number of parallel tests: $JOBS" >&2; usage 1;;
esac
case "$TIMEOUT" in
    ''|*[!0-9]*) echo "Invalid timeout: $TIMEOUT" >&2; usage 1;;
esac

# Print all tests, as file:function, from the test files, without executing
# them. Functions are declared as "test_name()" or "test_name ()".
discover() {
    for _f in "$TEST_ROOT"/test/*.test.sh; do
        [ -f "$_f" ] || continue
        _base=$(basename "$_f" .test.sh)
        grep -oE '^test_[A-Za-z0-9_]*[[:space:]]*\(\)' "$_f" \
            | sed -e 's/[[:space:]]*()$//' -e "s/^/${_base}:/"
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

# Print missing coverage: functions of primer and of the library modules
# without a unit test named test_<function>[_suffix], and steps without a test
# file. usage() of primer is tested through --help.
coverage() {
    _tests=$(discover | cut -d: -f2)
    for _lib in "$TEST_ROOT"/primer "$TEST_ROOT"/libexec/*.sh; do
        # shellcheck disable=SC2013 # function names have no spaces
        for _fn in $(grep -oE '^[_a-z][a-z0-9_]*[[:space:]]*\(\)' "$_lib" | sed 's/[[:space:]]*()$//'); do
            [ "$_fn" = usage ] && continue
            if ! printf %s\\n "$_tests" | grep -qE "^test_${_fn}(_[a-z0-9]+)*\$"; then
                printf 'function %s (%s)\n' "$_fn" "${_lib#"$TEST_ROOT"/}"
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
export PRIMER_TEST_RUNTIME PRIMER_TEST_PODMAN PRIMER_TEST_ROOTLESS

# Default parallelism: as many tests as the container runtime has CPUs. Most
# of the time goes to installing packages, so running more only slows down all
# of them.
if [ -z "$JOBS" ]; then
    if [ "$PRIMER_TEST_PODMAN" = "1" ]; then
        JOBS=$("$PRIMER_TEST_RUNTIME" info --format '{{.Host.CPUs}}' 2>/dev/null || true)
    else
        JOBS=$("$PRIMER_TEST_RUNTIME" info --format '{{.NCPU}}' 2>/dev/null || true)
    fi
    case "$JOBS" in
        ''|*[!0-9]*|0|1) JOBS=2;;
    esac
fi

LOGS=$(mktemp -d "${TMPDIR:-/tmp}/primer-tests.XXXXXX")
# Containers of this run are labelled with its identifier.
PRIMER_TEST_RUN=$(basename "$LOGS")
export PRIMER_TEST_RUN

# Remove the containers of this run, or of one test of this run when a test
# name is given.
remove_containers() {
    if [ -n "${1:-}" ]; then
        _ids=$("$PRIMER_TEST_RUNTIME" ps -aq --filter "label=primer-test=$PRIMER_TEST_RUN" \
            --filter "label=primer-test.name=$1" 2>/dev/null || true)
    else
        _ids=$("$PRIMER_TEST_RUNTIME" ps -aq --filter "label=primer-test=$PRIMER_TEST_RUN" 2>/dev/null || true)
    fi
    # shellcheck disable=SC2086 # One identifier per word
    [ -n "$_ids" ] && "$PRIMER_TEST_RUNTIME" rm -f $_ids >/dev/null 2>&1
    return 0
}

# When interrupted, stop the running tests, remove their containers and the
# logs.
interrupted() {
    trap - INT TERM
    echo "Interrupted, removing containers and logs" >&2
    # shellcheck disable=SC2046 # One process identifier per word
    kill $(jobs -p) 2>/dev/null || true
    remove_containers
    rm -rf "$LOGS"
    exit 130
}
trap interrupted INT TERM
TOTAL=$(printf %s\\n "$TESTS" | wc -l | tr -d ' ')
[ "$#" = "0" ] && TOTAL=$((TOTAL + 1))

if [ "$TAP" = "1" ]; then
    echo "1..$TOTAL"
else
    _rootless=; [ "$PRIMER_TEST_ROOTLESS" = "1" ] && _rootless=" (rootless)"
    echo "Running $TOTAL tests with $PRIMER_TEST_RUNTIME${_rootless}, $JOBS in parallel, logs in $LOGS"
fi

# Pull images once, quietly, so parallel tests do not race to pull them.
for _img in "$IMG_ALPINE" "$IMG_ALPINE_PINNED" "$IMG_TRIXIE" "$IMG_BOOKWORM"; do
    "$PRIMER_TEST_RUNTIME" pull -q "$_img" >/dev/null 2>&1 || true
done

# Use warm copies of the Debian images, when the selected tests use them.
if [ "${PRIMER_TEST_WARM:-1}" != "0" ]; then
    for _var in IMG_TRIXIE IMG_BOOKWORM; do
        for _file in $(printf %s\\n "$TESTS" | cut -d: -f1 | sort -u); do
            if grep -qF -e "\$$_var" -e "\${$_var}" "$TEST_ROOT/test/${_file}.test.sh"; then
                eval "_img=\$$_var"
                if [ "$TAP" = "1" ]; then
                    echo "# Preparing warm copy of $_img"
                else
                    echo "Preparing warm copy of $_img"
                fi
                _warm=$(warm_image "$_img")
                eval "$_var=\$_warm"
                break
            fi
        done
    done
fi
export IMG_ALPINE IMG_TRIXIE IMG_BOOKWORM

NUM=0
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=

# Report the result of a test: report NAME STATUS SECONDS
report() {
    _log="$LOGS/$(printf %s "$1" | tr ':' '.').log"
    case "$2" in
        0)
            NUM=$((NUM + 1))
            PASSED=$((PASSED + 1))
            if [ "$TAP" = "1" ]; then
                echo "ok $NUM - $1"
            else
                printf 'ok    %s (%ss)\n' "$1" "$3"
            fi
            ;;
        77)
            # Only a call to skip (that explains why) is a skip: other
            # commands, e.g. curl, also use this status.
            _reason=$(grep -m1 '^SKIP: ' "$_log" 2>/dev/null | sed 's/^SKIP: //' || true)
            if [ -z "$_reason" ]; then
                report "$1" 1 "$3"
                return
            fi
            NUM=$((NUM + 1))
            SKIPPED=$((SKIPPED + 1))
            if [ "$TAP" = "1" ]; then
                echo "ok $NUM - $1 # SKIP ${_reason}"
            else
                printf 'SKIP  %s: %s\n' "$1" "$_reason"
            fi
            ;;
        *)
            NUM=$((NUM + 1))
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
# The test runs with set -e, outside of any || or if context, which would
# turn set -e off: a test whose first container call fails must fail, even
# when the next calls pass. Tests running longer than TIMEOUT seconds are
# stopped, and their containers removed.
launch() {
    _file=${1%%:*}
    _fn=${1#*:}
    _base="$LOGS/$(printf %s "$1" | tr ':' '.')"
    (
        PRIMER_TEST_NAME=$1
        export PRIMER_TEST_NAME
        _start=$(date +%s)
        set +e
        (
            set -e
            cd "$TEST_ROOT"
            # shellcheck disable=SC1090
            . "$TEST_ROOT/test/${_file}.test.sh"
            "$_fn"
        ) > "${_base}.log" 2>&1 < /dev/null &
        _pid=$!
        if [ "$TIMEOUT" -gt 0 ]; then
            # Watchdog: polls, so it ends with the test.
            (
                _waited=0
                while kill -0 "$_pid" 2>/dev/null; do
                    if [ "$_waited" -ge "$TIMEOUT" ]; then
                        echo "ASSERT: timed out after ${TIMEOUT}s" >> "${_base}.log"
                        kill "$_pid" 2>/dev/null
                        remove_containers "$PRIMER_TEST_NAME"
                        break
                    fi
                    sleep 1
                    _waited=$((_waited + 1))
                done
            ) &
        fi
        wait "$_pid"
        _rc=$?
        set -e
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
