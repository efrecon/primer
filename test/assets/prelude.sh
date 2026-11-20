# Prelude executed in every test container, see in_container in test/lib.sh:
# extract the repository streamed on stdin to /primer, detach stdin, and arrange
# for authenticated GitHub API access when GITHUB_TOKEN is set (to avoid
# anonymous rate limits). The test script is passed as $1. It runs with set -e,
# and must reach its end: an early exit with status 0 would skip the remaining
# assertions, so it fails the test (see _test_exit).
# Fail as soon as a command fails, as primer does.
set -e

# Extract the copy of the repository, streamed on stdin by in_container.
mkdir -p /primer
tar -xf - -C /primer

# Nothing more comes on stdin: commands reading it must not wait forever.
exec </dev/null
cd /primer

# Authenticate calls to the GitHub API only, through the curl options of primer,
# to avoid anonymous rate limits.
if [ -n "${GITHUB_TOKEN:-}" ]; then
    printf "%s -u x-access-token:%s\n" "^https%3A//api%5C.github%5C.com/" "$GITHUB_TOKEN" > /tmp/curl.opts
    PRIMER_CURL_OPTIONS=/tmp/curl.opts
    export PRIMER_CURL_OPTIONS
fi

# Assertions and mocks for the script. Only exists in the container.
# shellcheck source=/dev/null
. /primer/test/lib.sh

# Run at_exit commands whatever happens, and fail scripts exiting early with 0.
trap _test_exit EXIT

# Run the test script. With set -e, a failure exits right away, through the trap.
eval "$1"
_TEST_RC=$?

# Mark the end as reached, so the trap keeps the status of the script.
test_done
exit "$_TEST_RC"
