#!/bin/sh

# Test library for primer. This file is sourced in two places:
#
# - On the host, by test/run.sh, before sourcing a test file. Test functions
#   then use the container helpers (in_container, primer_in, unit) to run
#   scripts in throwaway containers.
# - Inside the containers, by the scripts that the container helpers run.
#   Assertions and mocks are meant to be used there, so that they can inspect
#   the state of the container.
#
# All tests run in containers, using docker or podman, whichever is found
# first, unless PRIMER_TEST_RUNTIME is set.

# Fully qualified images, so they also work with podman.
IMG_ALPINE=${IMG_ALPINE:-docker.io/library/alpine:3.23}
IMG_TRIXIE=${IMG_TRIXIE:-docker.io/library/debian:trixie}
IMG_BOOKWORM=${IMG_BOOKWORM:-docker.io/library/debian:bookworm}

# Root of the primer repository on the host. Set by run.sh.
TEST_ROOT=${TEST_ROOT:-}

# Container runtime (docker or podman) and whether it runs rootless. Set by
# container_runtime, cached and exported by run.sh.
PRIMER_TEST_RUNTIME=${PRIMER_TEST_RUNTIME:-}
PRIMER_TEST_ROOTLESS=${PRIMER_TEST_ROOTLESS:-}

# Where mocks log their calls (inside containers).
MOCK_LOG=${MOCK_LOG:-/tmp/mock.log}

# Where stub executables are created (inside containers).
STUB_DIR=${STUB_DIR:-/tmp/stubs}


#### Container runtime ########################################################

# Pick the container runtime: PRIMER_TEST_RUNTIME when set, otherwise the first
# of docker and podman that is installed and answers. Prints the runtime and
# sets PRIMER_TEST_RUNTIME and PRIMER_TEST_ROOTLESS.
container_runtime() {
    if [ -z "$PRIMER_TEST_RUNTIME" ]; then
        for _rt in docker podman; do
            if command -v "$_rt" >/dev/null 2>&1 && "$_rt" info >/dev/null 2>&1; then
                PRIMER_TEST_RUNTIME=$_rt
                break
            fi
        done
    fi
    [ -z "$PRIMER_TEST_RUNTIME" ] && return 1
    if [ -z "$PRIMER_TEST_ROOTLESS" ]; then
        PRIMER_TEST_ROOTLESS=0
        if [ "$(basename "$PRIMER_TEST_RUNTIME")" = "podman" ] \
                && [ "$("$PRIMER_TEST_RUNTIME" info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = "true" ]; then
            PRIMER_TEST_ROOTLESS=1
        fi
    fi
    printf %s\\n "$PRIMER_TEST_RUNTIME"
}

# Skip the current test when privileged containers cannot be relied upon, i.e.
# rootless podman. Use on the host, before calling in_container -P.
require_privileged() {
    if [ "$PRIMER_TEST_ROOTLESS" = "1" ]; then
        skip "needs privileged containers, not available with rootless $PRIMER_TEST_RUNTIME"
    fi
}

# Quote all arguments for safe inclusion in a shell command line.
_quote() {
    for _arg in "$@"; do
        printf "'%s' " "$(printf %s "$_arg" | sed "s/'/'\\\\''/g")"
    done
}

# Prelude executed in every container: extract the repository streamed on
# stdin to /primer, detach stdin, and arrange for authenticated GitHub API
# access when GITHUB_TOKEN is set (to avoid anonymous rate limits).
# shellcheck disable=SC2016
_TEST_PRELUDE='
set -e
mkdir -p /primer
tar -xf - -C /primer
exec </dev/null
cd /primer
if [ -n "${GITHUB_TOKEN:-}" ]; then
    printf "%s -u x-access-token:%s\n" "api%5C.github%5C.com" "$GITHUB_TOKEN" > /tmp/curl.opts
    PRIMER_CURL_OPTIONS=/tmp/curl.opts
    export PRIMER_CURL_OPTIONS
fi
. /primer/test/lib.sh
'

# Run a shell script in a fresh container, with the repository at /primer.
# in_container [-P] [-h HOSTNAME] [-e NAME=VALUE]... IMAGE SCRIPT
#   -P  privileged container
#   -h  hostname of the container
#   -e  environment variable for the container (can be repeated)
# The repository is streamed into the container rather than bind-mounted, so
# this works with remote daemons and podman machines alike. The status is the
# exit status of the script.
in_container() {
    _priv=; _host=; _envs=
    while [ $# -gt 0 ]; do
        case "$1" in
            -P) _priv=1; shift;;
            -h) _host=$2; shift 2;;
            -e) _envs="${_envs}${2}
"; shift 2;;
            *) break;;
        esac
    done
    _img=$1
    _script=$2
    set -- run -i --rm
    [ -n "$_priv" ] && set -- "$@" --privileged
    # podman can be configured to share namespaces with the host (e.g. the
    # quay.io/podman/stable image does). Tests change firewall rules,
    # hostnames, etc. in privileged containers, so always ask for private
    # namespaces to never touch the host. These are docker's defaults.
    if [ "$(basename "$PRIMER_TEST_RUNTIME")" = "podman" ]; then
        set -- "$@" --network=private --uts=private --pid=private --ipc=private
    fi
    [ -n "$_host" ] && set -- "$@" --hostname "$_host"
    [ -n "${GITHUB_TOKEN:-}" ] && set -- "$@" -e GITHUB_TOKEN
    _oldifs=$IFS
    IFS='
'
    for _env in $_envs; do
        set -- "$@" -e "$_env"
    done
    IFS=$_oldifs
    # shellcheck disable=SC2016
    tar -C "$TEST_ROOT" --exclude=.git -cf - . |
        "$PRIMER_TEST_RUNTIME" "$@" "$_img" sh -c "$_TEST_PRELUDE"'
eval "$1"' sh "$_script"
}

# Run the primer CLI in a fresh container, then a verification script in the
# same container. The test steps directory comes first in the path, so the
# test step is available.
# primer_in [-P] [-h HOSTNAME] [-e NAME=VALUE]... IMAGE [primer args...] [-- VERIFY]
# The exit status, stdout and stderr of primer are available as $PRIMER_RC,
# $PRIMER_OUT and $PRIMER_ERR in VERIFY (see primer_run). Without VERIFY, the
# status is the one of primer.
primer_in() {
    _copts=
    while [ $# -gt 0 ]; do
        case "$1" in
            -P) _copts="$_copts -P"; shift;;
            -h|-e) _copts="$_copts $1 $(_quote "$2")"; shift 2;;
            *) break;;
        esac
    done
    _pimg=$1; shift
    _args=
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        _args="$_args $(_quote "$1")"; shift
    done
    # shellcheck disable=SC2016
    _verify='exit "$PRIMER_RC"'
    [ "${1:-}" = "--" ] && _verify=$2
    _pscript="primer_run $_args
$_verify"
    eval "in_container $_copts \"\$_pimg\" \"\$_pscript\""
}

# Run a snippet in a fresh container, with primer sourced in library mode: all
# modules are loaded, but nothing is run. Assertions and mocks are available.
# unit [-P] [-h HOSTNAME] [-e NAME=VALUE]... IMAGE SNIPPET
unit() {
    _uopts=
    while [ $# -gt 0 ]; do
        case "$1" in
            -P) _uopts="$_uopts -P"; shift;;
            -h|-e) _uopts="$_uopts $1 $(_quote "$2")"; shift 2;;
            *) break;;
        esac
    done
    _uimg=$1
    _uscript="unit_load
$2"
    eval "in_container $_uopts \"\$_uimg\" \"\$_uscript\""
}


#### Inside containers: library loading #######################################

# Source primer in library mode. Logging defaults to warnings, and goes to
# stderr as usual.
unit_load() {
    PRIMER_ROOT_DIR=/primer
    PRIMER_LIBRARY=1
    YUSH_APPNAME=primer
    YUSH_LOG_LEVEL=${YUSH_LOG_LEVEL:-warn}
    YUSH_LOG_COLOUR=0
    export PRIMER_ROOT_DIR PRIMER_LIBRARY YUSH_APPNAME YUSH_LOG_LEVEL YUSH_LOG_COLOUR
    # shellcheck disable=SC1091
    . /primer/primer
}

# Load a step from the regular step directory and the test step directory.
unit_step() {
    # shellcheck disable=SC2034 # used by primer_utils_loadif
    PRIMER_PATH=/primer/test/steps:/primer/libexec/steps
    primer_utils_loadif "$1"
}


# Run the primer CLI with the test steps directory first in the path. Sets
# PRIMER_RC, PRIMER_OUT and PRIMER_ERR, and copies the output to the test log.
# Never fails, check PRIMER_RC. Can be called several times in a container.
primer_run() {
    PRIMER_RC=0
    /primer/primer -p /primer/test/steps:/primer/libexec/steps "$@" \
        >/tmp/primer.out 2>/tmp/primer.err || PRIMER_RC=$?
    PRIMER_OUT=$(cat /tmp/primer.out)
    PRIMER_ERR=$(cat /tmp/primer.err)
    printf '>>> primer %s (exit status %s)\n' "$*" "$PRIMER_RC"
    [ -n "$PRIMER_OUT" ] && printf '%s\n' "$PRIMER_OUT"
    [ -n "$PRIMER_ERR" ] && printf '%s\n' "$PRIMER_ERR" >&2
    return 0
}


#### Assertions ###############################################################

_assert_fail() {
    printf 'ASSERT: %s\n' "$*" >&2
    exit 1
}

fail() { _assert_fail "${1:-failed}"; }

# Skip the current test with a reason (exit status 77).
skip() {
    printf 'SKIP: %s\n' "${1:-skipped}" >&2
    exit 77
}

# assert_equal EXPECTED ACTUAL [MESSAGE]
assert_equal() {
    [ "$1" = "$2" ] || _assert_fail "${3:-values differ}: expected [$1], got [$2]"
}

# assert_match ERE ACTUAL [MESSAGE]
assert_match() {
    printf %s\\n "$2" | grep -qE -- "$1" ||
        _assert_fail "${3:-no match}: [$2] does not match /$1/"
}

# assert_contains NEEDLE HAYSTACK [MESSAGE]
assert_contains() {
    case "$2" in
        *"$1"*) ;;
        *) _assert_fail "${3:-not found}: [$1] not in [$2]";;
    esac
}

# assert_not_contains NEEDLE HAYSTACK [MESSAGE]
assert_not_contains() {
    case "$2" in
        *"$1"*) _assert_fail "${3:-found}: [$1] in [$2]";;
    esac
}

# assert_true CMD... : the command succeeds
assert_true() {
    "$@" || _assert_fail "command failed: $*"
}

# assert_false CMD... : the command fails
assert_false() {
    if "$@"; then
        _assert_fail "command succeeded: $*"
    fi
}

# assert_exit STATUS CMD... : the command, run in a subshell (so it can exit),
# returns that status.
assert_exit() {
    _want=$1; shift
    _rc=0
    ( "$@" ) || _rc=$?
    [ "$_rc" = "$_want" ] || _assert_fail "exit status of [$*]: expected $_want, got $_rc"
}

# run CMD... : run the command in a subshell, capture its stdout in RUN_OUT,
# its stderr in RUN_ERR and its exit status in RUN_RC. Never fails.
# shellcheck disable=SC2034 # RUN_* are read by the tests
run() {
    RUN_RC=0
    RUN_OUT=$( ( "$@" ) 2>/tmp/run.err ) || RUN_RC=$?
    RUN_ERR=$(cat /tmp/run.err)
}


#### Mocks ####################################################################

# mock [-o OUTPUT] [-r STATUS] NAME... : replace commands by mocks that log
# their calls (as "NAME args...") to $MOCK_LOG, print OUTPUT and return STATUS.
# Names that are valid shell identifiers become functions (they shadow
# commands, and command -v finds them). Others (e.g. firewall-cmd) become stub
# executables at the front of the PATH, as dash refuses such function names.
mock() {
    _mout=; _mrc=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -o) _mout=$2; shift 2;;
            -r) _mrc=$2; shift 2;;
            *) break;;
        esac
    done
    for _mname in "$@"; do
        if printf %s "$_mname" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
            eval "_MOCK_OUT_${_mname}=\$_mout"
            eval "${_mname}() {
                printf '%s\\n' \"${_mname}\${*:+ \$*}\" >> \"\$MOCK_LOG\"
                [ -n \"\$_MOCK_OUT_${_mname}\" ] && printf '%s\\n' \"\$_MOCK_OUT_${_mname}\"
                return ${_mrc}
            }"
        else
            mkdir -p "$STUB_DIR"
            printf %s\\n "$_mout" > "${STUB_DIR}/${_mname}.out"
            stub_bin "$_mname" "printf '%s\\n' \"${_mname}\${*:+ \$*}\" >> \"$MOCK_LOG\"
[ -s \"${STUB_DIR}/${_mname}.out\" ] && [ -n \"\$(cat \"${STUB_DIR}/${_mname}.out\")\" ] && cat \"${STUB_DIR}/${_mname}.out\"
exit ${_mrc}"
        fi
    done
}

# Record a call in the mock log, for hand-written mocks: mock_log NAME ARGS...
mock_log() {
    printf '%s\n' "$*" >> "$MOCK_LOG"
}

# Print all calls recorded so far.
mock_calls() {
    [ -f "$MOCK_LOG" ] && cat "$MOCK_LOG"
    return 0
}

# Forget all calls recorded so far.
mock_reset() {
    : > "$MOCK_LOG"
}

# stub_bin NAME BODY : create an executable NAME in $STUB_DIR with the shell
# script BODY, and put $STUB_DIR first in the PATH. Unlike functions, these
# are also visible to child processes.
stub_bin() {
    mkdir -p "$STUB_DIR"
    printf '#!/bin/sh\n%s\n' "$2" > "${STUB_DIR}/$1"
    chmod a+x "${STUB_DIR}/$1"
    case ":$PATH:" in
        *":${STUB_DIR}:"*) ;;
        *) PATH="${STUB_DIR}:$PATH"; export PATH;;
    esac
}
