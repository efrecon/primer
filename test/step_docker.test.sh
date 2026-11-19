#!/bin/sh
# shellcheck disable=SC2016

# Tests of the docker step: Docker daemon, client, compose and buildx plugins,
# for the various packaging methods. These run privileged containers in which
# the Docker daemon is started for real.

# Pinned plugin versions, used when forcing installation from the releases.
DOCKER_COMPOSE_VERSION=v5.8.0
DOCKER_BUILDX_VERSION=v0.39.0

# Functions available in the containers: start the daemon and verify the
# installation. docker_verify takes the expected builder: buildkit or legacy.
# shellcheck disable=SC2016
DOCKER_LIB='
export PATH="$PATH:/usr/sbin:/sbin"
docker_start() {
    (dockerd >/tmp/dockerd.log 2>&1 &)
    _i=0
    while [ "$_i" -lt 30 ] && ! docker info >/dev/null 2>&1; do
        sleep 1; _i=$((_i + 1))
    done
    docker info >/dev/null 2>&1 || { cat /tmp/dockerd.log >&2; fail "Docker daemon did not start"; }
}
docker_verify() {
    assert_equal 0 "$PRIMER_RC" "primer exit status"
    assert_match "^Docker version" "$(docker --version 2>&1)" "docker client"
    assert_match "^Docker version" "$(dockerd --version 2>&1)" "docker daemon"
    assert_match "[Cc]ompose" "$(docker compose version 2>&1)" "compose plugin"
    assert_match "buildx" "$(docker buildx version 2>&1)" "buildx plugin"
    docker_start
    assert_match "^[0-9]" "$(docker info --format "{{.ServerVersion}}")" "server version"
    mkdir -p /tmp/ctx
    printf "FROM scratch\nCOPY Dockerfile /\n" > /tmp/ctx/Dockerfile
    _build=$(docker build --progress=plain /tmp/ctx 2>&1 || docker build /tmp/ctx 2>&1)
    case "${1:-buildkit}" in
        buildkit) assert_match "^#[0-9]+ " "$_build" "BuildKit build";;
        legacy) assert_contains "Sending build context" "$_build" "legacy build";;
    esac
}
deb_installed() {
    dpkg-query -W -f="\${Status}" "$1" 2>/dev/null | grep -q "^install ok installed"
}
docker_absent() {
    assert_equal 0 "$PRIMER_RC" "primer exit status"
    # Forget command locations remembered by the shell, e.g. after docker_verify
    hash -r 2>/dev/null || true
    for _f in /usr/bin/docker /usr/bin/dockerd /usr/sbin/dockerd; do
        if [ -e "$_f" ]; then
            fail "$_f still present ($(dpkg -S "$_f" 2>/dev/null || apk info -W "$_f" 2>/dev/null))"
        fi
    done
    assert_false command -v docker
    assert_false command -v dockerd
    assert_equal "" "$(ls /usr/local/lib/docker/cli-plugins 2>/dev/null)" "downloaded plugins"
}
'

test_docker_alpine_auto() {
    require_privileged
    in_container -P "$IMG_ALPINE" "$DOCKER_LIB"'
        primer_run -s docker install
        docker_verify buildkit
        assert_true test -x /usr/libexec/docker/cli-plugins/docker-compose
        assert_true test -x /usr/libexec/docker/cli-plugins/docker-buildx'
}

test_docker_alpine_pinned() {
    require_privileged
    in_container -P "$IMG_ALPINE" "$DOCKER_LIB"'
        primer_run -s docker --docker:compose-version '"$DOCKER_COMPOSE_VERSION"' --docker:buildx-version '"$DOCKER_BUILDX_VERSION"' install
        docker_verify buildkit
        # Pinned versions are downloaded, verified against the release
        # checksums.txt and take precedence over the packaged ones.
        assert_contains "docker-compose: OK" "$PRIMER_OUT"
        assert_contains "docker-buildx: OK" "$PRIMER_OUT"
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-compose
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-buildx
        assert_contains "'"${DOCKER_COMPOSE_VERSION#v}"'" "$(docker compose version)"
        assert_contains "'"${DOCKER_BUILDX_VERSION#v}"'" "$(docker buildx version)"'
}

test_docker_alpine_bad_sha() {
    require_privileged
    in_container -P "$IMG_ALPINE" "$DOCKER_LIB"'
        primer_run -s docker --docker:buildx-version '"$DOCKER_BUILDX_VERSION"' --docker:buildx-sha256 0000 install
        docker_verify buildkit
        assert_contains "SHA256 sum mismatch" "$PRIMER_ERR"
        assert_contains "version mismatch" "$PRIMER_ERR"
        assert_false test -e /usr/local/lib/docker/cli-plugins/docker-buildx
        assert_not_contains "'"${DOCKER_BUILDX_VERSION#v}"'" "$(docker buildx version)"'
}

test_docker_bookworm_auto() {
    require_privileged
    # Debian 12 native packages: Docker 20.10, without compose v2 nor buildx
    # packages, so both plugins are downloaded (latest releases). Plain docker
    # build still uses the legacy builder with Docker 20.10.
    in_container -P "$IMG_BOOKWORM" "$DOCKER_LIB"'
        primer_run -s docker install
        docker_verify legacy
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-compose
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-buildx
        assert_contains "docker-compose: OK" "$PRIMER_OUT"
        assert_contains "docker-buildx: OK" "$PRIMER_OUT"'
}

test_docker_bookworm_getdocker() {
    require_privileged
    in_container -P -e PRIMER_STEP_DOCKER_PACKAGING=docker "$IMG_BOOKWORM" "$DOCKER_LIB"'
        primer_run -s docker install
        docker_verify buildkit
        assert_true deb_installed docker-ce
        assert_true deb_installed docker-compose-plugin
        assert_true deb_installed docker-buildx-plugin
        primer_run -s docker clean
        docker_absent
        assert_false deb_installed docker-ce
        assert_false deb_installed docker-compose-plugin
        assert_false test -e /etc/apt/keyrings/docker.asc
        assert_false test -e /etc/apt/sources.list.d/docker.list'
}

test_docker_bookworm_clean() {
    require_privileged
    in_container -P "$IMG_BOOKWORM" "$DOCKER_LIB"'
        primer_run -s docker --docker:compose-version '"$DOCKER_COMPOSE_VERSION"' --docker:buildx-version '"$DOCKER_BUILDX_VERSION"' install
        assert_equal 0 "$PRIMER_RC"
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-compose
        primer_run -s docker clean
        docker_absent'
}

test_docker_trixie_auto() {
    require_privileged
    # Debian 13 native packages, including compose v2 and buildx.
    in_container -P "$IMG_TRIXIE" "$DOCKER_LIB"'
        primer_run -s docker install
        docker_verify buildkit
        assert_true deb_installed docker.io
        assert_true deb_installed docker-compose
        assert_true deb_installed docker-buildx
        assert_true test -x /usr/libexec/docker/cli-plugins/docker-compose
        assert_false test -e /usr/local/lib/docker/cli-plugins/docker-compose'
}

test_docker_trixie_clean() {
    require_privileged
    in_container -P "$IMG_TRIXIE" "$DOCKER_LIB"'
        primer_run -s docker install
        assert_equal 0 "$PRIMER_RC"
        primer_run -s docker clean
        docker_absent
        assert_false deb_installed docker.io
        assert_false deb_installed docker-compose
        assert_false deb_installed docker-buildx'
}
