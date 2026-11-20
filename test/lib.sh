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
IMG_ALPINE=${IMG_ALPINE:-docker.io/library/alpine:3.24}
IMG_TRIXIE=${IMG_TRIXIE:-docker.io/library/debian:trixie}
IMG_BOOKWORM=${IMG_BOOKWORM:-docker.io/library/debian:bookworm}
IMG_UBUNTU=${IMG_UBUNTU:-docker.io/library/ubuntu:26.04}
IMG_FEDORA=${IMG_FEDORA:-docker.io/library/fedora:45}
# An exact Alpine release, for tests of version detection.
IMG_ALPINE_PINNED=${IMG_ALPINE_PINNED:-docker.io/library/alpine:3.24.4}

# Root of the primer repository on the host. Set by run.sh.
TEST_ROOT=${TEST_ROOT:-}

# Container runtime (docker or podman), whether it is podman (also behind the
# podman-docker shim, which installs podman as docker) and whether it runs
# rootless. Set by container_runtime, cached and exported by run.sh.
PRIMER_TEST_RUNTIME=${PRIMER_TEST_RUNTIME:-}
PRIMER_TEST_PODMAN=${PRIMER_TEST_PODMAN:-}
PRIMER_TEST_ROOTLESS=${PRIMER_TEST_ROOTLESS:-}

# Identifier of the current run of the suite, and name of the current test.
# Containers are labelled with both, so they can be removed when a test times
# out or the run is interrupted. Set by run.sh.
PRIMER_TEST_RUN=${PRIMER_TEST_RUN:-}
PRIMER_TEST_NAME=${PRIMER_TEST_NAME:-}

# Where mocks log their calls (inside containers).
MOCK_LOG=${MOCK_LOG:-/tmp/mock.log}

# Where stub executables are created (inside containers).
STUB_DIR=${STUB_DIR:-/tmp/stubs}


#### Container runtime ########################################################

# Pick the container runtime: PRIMER_TEST_RUNTIME when set, otherwise the first
# of docker and podman that is installed and answers. Prints the runtime and
# sets PRIMER_TEST_RUNTIME, PRIMER_TEST_PODMAN and PRIMER_TEST_ROOTLESS. The
# kind of runtime is detected from what it answers, not from its name: only
# podman knows about .Host in the output of info.
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
    if [ -z "$PRIMER_TEST_PODMAN" ]; then
        PRIMER_TEST_PODMAN=0
        if "$PRIMER_TEST_RUNTIME" info --format '{{.Host.OS}}' >/dev/null 2>&1; then
            PRIMER_TEST_PODMAN=1
        fi
    fi
    if [ -z "$PRIMER_TEST_ROOTLESS" ]; then
        PRIMER_TEST_ROOTLESS=0
        if [ "$PRIMER_TEST_PODMAN" = "1" ]; then
            if [ "$("$PRIMER_TEST_RUNTIME" info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = "true" ]; then
                PRIMER_TEST_ROOTLESS=1
            fi
        elif "$PRIMER_TEST_RUNTIME" info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q 'name=rootless'; then
            PRIMER_TEST_ROOTLESS=1
        fi
    fi
    printf %s\\n "$PRIMER_TEST_RUNTIME"
}

# Packages downloaded (not installed) in warm images: the ones that steps
# commonly install, so tests do not download them over and over again. For
# Debian and Ubuntu (apt), and Fedora (dnf).
WARM_PACKAGES=${WARM_PACKAGES:-"bash ca-certificates curl e2fsprogs git iproute2 iptables locales openssh-client tzdata ufw wpasupplicant"}
WARM_PACKAGES_DNF=${WARM_PACKAGES_DNF:-"e2fsprogs git iproute iptables-nft openssh-clients tzdata util-linux"}

# Print the name of the "warm" copy of the image passed as an argument, building
# it when it does not exist yet, from test/assets/Dockerfile.$2: apt (Debian,
# Ubuntu) or dnf (Fedora). Warm images are rebuilt every day and differ from
# the official images in ways that make tests much faster, without changing
# what primer has to do (no package is installed), and are closer to a real
# host:
# - apt caches are kept: the official images remove them after every apt call
#   (/etc/apt/apt.conf.d/docker-clean), so every call parses all package lists
#   again, which is costly on small machines.
# - Package lists (dnf metadata) are already fetched, so updating them only
#   checks for changes.
# - Common packages are downloaded, not installed.
# - Documentation is not installed (already the case on Fedora).
# Prints the official image when building fails, e.g. offline.
warm_image() {
    _warm_tag=localhost/primer-test-$(printf %s "${1##*/}" | tr ':' '-'):$(date +%Y%m%d)
    case "$2" in
        dnf) _warm_pkgs=$WARM_PACKAGES_DNF;;
        *) _warm_pkgs=$WARM_PACKAGES;;
    esac
    if ! "$PRIMER_TEST_RUNTIME" image inspect "$_warm_tag" >/dev/null 2>&1; then
        if "$PRIMER_TEST_RUNTIME" build -q -t "$_warm_tag" \
                --build-arg "BASE=$1" --build-arg "WARM_PACKAGES=$_warm_pkgs" \
                -f "$TEST_ROOT/test/assets/Dockerfile.$2" "$TEST_ROOT/test/assets" >/dev/null 2>&1; then
            # Remove the warm images of previous days.
            "$PRIMER_TEST_RUNTIME" images --format '{{.Repository}}:{{.Tag}}' \
                | grep -F "${_warm_tag%:*}:" | grep -vxF "$_warm_tag" \
                | while IFS= read -r _old; do
                    "$PRIMER_TEST_RUNTIME" rmi "$_old" >/dev/null 2>&1 || true
                done
        else
            _warm_tag=$1
        fi
    fi
    printf %s\\n "$_warm_tag"
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

# Prelude executed in every container, from test/assets/prelude.sh. It cannot
# run from the copy of the repository in the container, as it is what extracts
# it: its content is passed to sh -c instead. Read from the repository on the
# host, from its copy at /primer in containers (for the tests of the framework).
_TEST_PRELUDE=$(cat "${TEST_ROOT:-/primer}/test/assets/prelude.sh")

# Print the files to stream into containers, relative to TEST_ROOT: the files
# known to git, including submodules, and new files that are not ignored. Files
# ignored by git, e.g. a primer.env of the developer, which primer would read,
# are never streamed. Prints nothing outside a git checkout.
_test_files() {
    git -C "$TEST_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    {
        git -C "$TEST_ROOT" ls-files --recurse-submodules
        git -C "$TEST_ROOT" ls-files --others --exclude-standard
    } | while IFS= read -r _tf; do
        # Skip files deleted from the working tree, but not from git yet.
        if [ -e "$TEST_ROOT/$_tf" ] || [ -L "$TEST_ROOT/$_tf" ]; then
            printf %s\\n "$_tf"
        fi
    done
}

# Stream the repository to stdout, as a tar archive.
_test_stream() {
    _tfiles=$(_test_files)
    if [ -n "$_tfiles" ]; then
        printf %s\\n "$_tfiles" | tar -C "$TEST_ROOT" -cf - -T -
    else
        tar -C "$TEST_ROOT" --exclude=.git -cf - .
    fi
}

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
    set -- run -i --rm --label "primer-test=${PRIMER_TEST_RUN:-none}" \
        --label "primer-test.name=${PRIMER_TEST_NAME:-none}"
    [ -n "$_priv" ] && set -- "$@" --privileged
    # podman can be configured to share namespaces with the host (e.g. the
    # quay.io/podman/stable image does). Tests change firewall rules,
    # hostnames, etc. in privileged containers, so always ask for private
    # namespaces to never touch the host. These are docker's defaults.
    if [ "$PRIMER_TEST_PODMAN" = "1" ]; then
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
    _test_stream |
        "$PRIMER_TEST_RUNTIME" "$@" "$_img" sh -c "$_TEST_PRELUDE" sh "$_script"
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
    _verify='test_done; exit "$PRIMER_RC"'
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
    # Library mode is for this shell only, not exported: primer executed from
    # tests would refuse to run.
    # shellcheck disable=SC2034 # Used by primer, sourced below.
    PRIMER_ROOT_DIR=/primer
    # shellcheck disable=SC2034
    PRIMER_LIBRARY=1
    YUSH_APPNAME=primer
    YUSH_LOG_LEVEL=${YUSH_LOG_LEVEL:-warn}
    YUSH_LOG_COLOUR=0
    export YUSH_APPNAME YUSH_LOG_LEVEL YUSH_LOG_COLOUR
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
# primer reads primer.env files from its working directory: when called from
# the repository, it runs from an empty directory instead.
primer_run() {
    PRIMER_RC=0
    _prdir=$(pwd)
    if [ "$_prdir" = /primer ]; then
        mkdir -p /tmp/primer-cwd
        _prdir=/tmp/primer-cwd
    fi
    _test_set_e_off
    ( cd "$_prdir" && exec /primer/primer -p /primer/test/steps:/primer/libexec/steps "$@" ) \
        >/tmp/primer.out 2>/tmp/primer.err
    PRIMER_RC=$?
    _test_set_e_restore
    PRIMER_OUT=$(cat /tmp/primer.out)
    PRIMER_ERR=$(cat /tmp/primer.err)
    printf '>>> primer %s (exit status %s)\n' "$*" "$PRIMER_RC"
    [ -n "$PRIMER_OUT" ] && printf '%s\n' "$PRIMER_OUT"
    [ -n "$PRIMER_ERR" ] && printf '%s\n' "$PRIMER_ERR" >&2
    return 0
}


# Print the device of the default route of the container. Interface names
# depend on the runtime: eth0 with docker, the name of the host interface with
# rootless podman and pasta.
default_route_dev() {
    awk '$2 == "00000000" { print $1; exit }' /proc/net/route
}

# Print the device of the default route of the container when primer can
# select it as the primary interface (en* or eth*), or skip the test. Assign
# the output to a variable, e.g. dev=$(primary_dev_or_skip): set -e then exits
# with the status of the skip.
primary_dev_or_skip() {
    _dev=$(default_route_dev)
    case "$_dev" in
        en*|eth[0-9]*) printf %s\\n "$_dev";;
        *) skip "default route device [$_dev] is not named en* or eth*";;
    esac
}


#### Assertions ###############################################################

_assert_fail() {
    printf 'ASSERT: %s\n' "$*" >&2
    exit 1
}

# Tell that the script reached its end. Called by the prelude after the script,
# and before the default verification of primer_in.
test_done() {
    _TEST_DONE=1
}

# at_exit CMD : run the command when the script exits, whatever the reason,
# e.g. to release resources shared with the host. Do not set an EXIT trap in
# scripts, it would replace the one of the prelude.
at_exit() {
    _TEST_AT_EXIT="${_TEST_AT_EXIT:-}
$1"
}

# EXIT trap of the prelude: run the commands registered with at_exit, then fail
# a script that exits with status 0 before its end.
_test_exit() {
    _trc=$?
    set +e
    [ -n "${_TEST_AT_EXIT:-}" ] && eval "$_TEST_AT_EXIT"
    if [ "$_trc" = 0 ] && [ "${_TEST_DONE:-0}" != 1 ]; then
        printf 'ASSERT: %s\n' "exited with status 0 before the end of the script" >&2
        _trc=1
    fi
    exit "$_trc"
}

# Turn set -e off, remembering whether it was on, to capture the status of a
# command. The command itself runs in a subshell with set -e, like primer.
_test_set_e_off() {
    case "$-" in
        *e*) _TEST_SET_E=1;;
        *) _TEST_SET_E=0;;
    esac
    set +e
}

# Restore set -e as it was before _test_set_e_off.
_test_set_e_restore() {
    [ "$_TEST_SET_E" = 1 ] && set -e
    return 0
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

# The helpers below run the command in a subshell with set -e, as primer runs
# (set -eu): calling it in an || or if context would turn set -e off for the
# whole command, functions included, hiding failures in the middle of it.
# These helpers take no message argument: an extra argument goes to the
# command.

# assert_true CMD... : the command succeeds
assert_true() {
    _test_set_e_off
    ( set -e; "$@" )
    _rc=$?
    _test_set_e_restore
    [ "$_rc" = 0 ] || _assert_fail "command failed: $*"
}

# assert_false CMD... : the command fails
assert_false() {
    _test_set_e_off
    ( set -e; "$@" )
    _rc=$?
    _test_set_e_restore
    [ "$_rc" != 0 ] || _assert_fail "command succeeded: $*"
}

# assert_exit STATUS CMD... : the command, run in a subshell (so it can exit),
# returns that status.
assert_exit() {
    _want=$1; shift
    _test_set_e_off
    ( set -e; "$@" )
    _rc=$?
    _test_set_e_restore
    [ "$_rc" = "$_want" ] || _assert_fail "exit status of [$*]: expected $_want, got $_rc"
}

# run CMD... : run the command in a subshell, capture its stdout in RUN_OUT,
# its stderr in RUN_ERR and its exit status in RUN_RC. Never fails.
# shellcheck disable=SC2034 # RUN_* are read by the tests
run() {
    _test_set_e_off
    RUN_OUT=$( set -e; "$@" 2>/tmp/run.err )
    RUN_RC=$?
    _test_set_e_restore
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
