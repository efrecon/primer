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
    # The build must succeed, with the expected builder: the output of a failed
    # build also starts like a successful one.
    case "${1:-buildkit}" in
        buildkit)
            run docker build --progress=plain -t primer-test-build /tmp/ctx
            assert_equal 0 "$RUN_RC" "BuildKit build: $RUN_ERR"
            assert_match "^#[0-9]+ " "$RUN_ERR" "BuildKit build"
            ;;
        legacy)
            run docker build -t primer-test-build /tmp/ctx
            assert_equal 0 "$RUN_RC" "legacy build: $RUN_ERR"
            assert_contains "Sending build context" "$RUN_OUT$RUN_ERR" "legacy build"
            ;;
    esac
    assert_true docker image inspect primer-test-build
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

# Fedora: Docker as packaged by the distribution (moby-engine).
test_docker_fedora() {
    require_privileged
    in_container -P "$IMG_FEDORA" "$DOCKER_LIB"'
        primer_run -s docker install
        docker_verify buildkit
        assert_true rpm -q moby-engine'
}

test_docker_alpine_pinned() {
    require_privileged
    in_container -P "$IMG_ALPINE" "$DOCKER_LIB"'
        primer_run -s docker --docker:compose-version '"$DOCKER_COMPOSE_VERSION"' --docker:buildx-version '"$DOCKER_BUILDX_VERSION"' install
        docker_verify buildkit
        # Pinned versions are downloaded, verified against the release
        # checksums.txt and take precedence over the packaged ones.
        assert_contains "Verified sha256 sum of docker-compose-linux-" "$PRIMER_ERR"
        assert_contains "Verified sha256 sum of buildx-v" "$PRIMER_ERR"
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-compose
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-buildx
        assert_contains "'"${DOCKER_COMPOSE_VERSION#v}"'" "$(docker compose version)"
        assert_contains "'"${DOCKER_BUILDX_VERSION#v}"'" "$(docker buildx version)"'
}

test_docker_alpine_bad_sha() {
    require_privileged
    in_container -P "$IMG_ALPINE" "$DOCKER_LIB"'
        primer_run -s docker --docker:buildx-version '"$DOCKER_BUILDX_VERSION"' --docker:buildx-sha256 0000 install
        # Verification failures fail the step, nothing is installed.
        assert_equal 1 "$PRIMER_RC" "primer exit status"
        assert_contains "SHA256 sum mismatch" "$PRIMER_ERR"
        assert_contains "Could not install Docker buildx plugin" "$PRIMER_ERR"
        assert_false test -e /usr/local/lib/docker/cli-plugins/docker-buildx
        assert_not_contains "'"${DOCKER_BUILDX_VERSION#v}"'" "$(docker buildx version 2>&1)"'
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
        assert_contains "Verified sha256 sum of docker-compose-linux-" "$PRIMER_ERR"
        assert_contains "Verified sha256 sum of buildx-v" "$PRIMER_ERR"'
}

# The convenience script, at the pinned commit, and the key of the Docker
# repository it installs (0EBFCD88 is the end of the fingerprint of the key of
# download.docker.com).
test_docker_bookworm_getdocker() {
    require_privileged
    in_container -P -e PRIMER_STEP_DOCKER_PACKAGING=docker -e PRIMER_STEP_DOCKER_APT_GPG=0ebfcd88 "$IMG_BOOKWORM" "$DOCKER_LIB"'
        primer_run -s docker install
        docker_verify buildkit
        assert_contains "Executing docker install script, commit: 8ad27bd3ac871feabe62f1d926c4067800c1732f" "$PRIMER_OUT"
        assert_contains "Verifying Docker GPG short key" "$PRIMER_ERR"
        assert_true test -f /etc/apt/sources.list.d/docker.list
        assert_true test -f /etc/apt/keyrings/docker.asc
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
        # Plugins are only removed at the versions that primer installs.
        primer_run -s docker --docker:compose-version v1.0.0 clean
        assert_true test -x /usr/local/lib/docker/cli-plugins/docker-compose
        assert_contains "not installed by primer" "$PRIMER_ERR"
        primer_run -s docker --docker:compose-version '"$DOCKER_COMPOSE_VERSION"' --docker:buildx-version '"$DOCKER_BUILDX_VERSION"' clean
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

# --access and --registry: group membership and credentials only for the
# users given, in a ~/.docker that they own. An empty --access is no user.
test_docker_access_registry() {
    unit "$IMG_ALPINE" '
        adduser -D alice; adduser -D bob
        stub_bin dockerd "exit 0"
        docker() {
            mock_log docker "$@"
            case "$1" in
                login) (umask 077; mkdir -p "$HOME/.docker"
                        echo "{\"auths\":{\"$5\":{\"auth\":\"c2VjcmV0\"}}}" > "$HOME/.docker/config.json");;
                --version) echo "Docker version 27.0.0, build 1";;
                compose|buildx) echo "$1 v9.9.9";;
            esac
        }
        mock primer_os_service primer_net_curl
        unit_step docker
        primer_step_docker option --access "^alice$" --registry "u:secret@reg.example.com"
        run primer_step_docker install
        assert_equal 0 "$RUN_RC"
        assert_contains "docker login --password-stdin -u u reg.example.com" "$(mock_calls)"
        assert_true sh -c "id -Gn alice | grep -qw docker"
        assert_false sh -c "id -Gn bob | grep -qw docker"
        assert_false sh -c "id -Gn root | grep -qw docker"
        assert_equal "600 alice" "$(stat -c "%a %U" /home/alice/.docker/config.json)" "credentials of alice"
        assert_equal "alice" "$(stat -c "%U" /home/alice/.docker)" "docker dir of alice"
        assert_false test -e /home/bob/.docker/config.json
        # Without --access, nobody but root gets access, nor the credentials.
        rm -rf /root/.docker /home/alice/.docker
        PRIMER_STEP_DOCKER_ACCESS=
        run primer_step_docker install
        assert_false test -e /home/bob/.docker/config.json
        assert_false test -e /home/alice/.docker/config.json'
}

# The convenience script is fetched from docker/docker-install at the pinned
# commit and only runs when the sha256 of the whole file matches.
test_docker_getdocker_verification() {
    unit "$IMG_ALPINE" '
        primer_net_curl() {
            mock_log primer_net_curl "$@"
            # Same shape as upstream: the commit line is filled at runtime.
            printf "#!/bin/sh\nSCRIPT_COMMIT_SHA=\"\${LOAD_SCRIPT_COMMIT_SHA}\"\necho \"\$SCRIPT_COMMIT_SHA\" > /tmp/script-ran\n" > "$3"
        }
        unit_step docker
        GOOD=$(primer_net_curl x -o /tmp/good.sh; sha256sum < /tmp/good.sh | cut -d" " -f1)
        rm -f /tmp/good.sh /tmp/script-ran; mock_reset
        PRIMER_STEP_DOCKER_INSTALL_COMMIT=0123456789abcdef0123456789abcdef01234567
        # Mismatch: nothing runs, the step fails.
        PRIMER_STEP_DOCKER_INSTALL_SHA256=$(printf "%064d" 0)
        run _primer_step_docker_install_getdocker
        assert_equal 1 "$RUN_RC" "mismatch status"
        assert_false test -e /tmp/script-ran
        assert_contains "Unable to verify Docker installation script" "$RUN_ERR"
        assert_contains "raw.githubusercontent.com/docker/docker-install/$PRIMER_STEP_DOCKER_INSTALL_COMMIT/install.sh" "$(mock_calls)"
        # A prefix of the right sum is not a match.
        PRIMER_STEP_DOCKER_INSTALL_SHA256=$(printf %s "$GOOD" | cut -c1-8)
        run _primer_step_docker_install_getdocker
        assert_equal 1 "$RUN_RC" "partial sum status"
        assert_false test -e /tmp/script-ran
        # Empty sum: refuse (decision 4).
        PRIMER_STEP_DOCKER_INSTALL_SHA256=
        run _primer_step_docker_install_getdocker
        assert_equal 1 "$RUN_RC" "empty sum status"
        assert_false test -e /tmp/script-ran
        # An old-style 40-character commit sum points to --commit.
        PRIMER_STEP_DOCKER_INSTALL_SHA256=$PRIMER_STEP_DOCKER_INSTALL_COMMIT
        run _primer_step_docker_install_getdocker
        assert_equal 1 "$RUN_RC" "commit as sum status"
        assert_contains "--commit" "$RUN_ERR"
        # Match: runs, with the commit passed in its environment.
        PRIMER_STEP_DOCKER_INSTALL_SHA256=$GOOD
        run _primer_step_docker_install_getdocker
        assert_equal 0 "$RUN_RC" "match status"
        assert_equal "$PRIMER_STEP_DOCKER_INSTALL_COMMIT" "$(cat /tmp/script-ran)" "commit given to script"
        assert_equal "" "$(ls /tmp/tmp.* 2>/dev/null)" "temporary script removed"
        # An explicit URL is honoured.
        mock_reset
        PRIMER_STEP_DOCKER_GET_URL=https://example.invalid/install.sh
        run _primer_step_docker_install_getdocker
        assert_contains "https://example.invalid/install.sh" "$(mock_calls)"'
}

# Registry login information: hosts with ports, passwords with : and @. Bad
# entries are refused without their password ever reaching the logs.
test_docker_registry_parse() {
    unit "$IMG_ALPINE" '
        unit_step docker
        check() {
            _primer_step_docker_registry_parse "$1"
            assert_equal "$2|$3|$4" "$_user|$_pass|$_host" "$1"
        }
        check "bob:pw@reg.example.com" bob pw reg.example.com
        check "bob:pw@localhost:5000" bob pw localhost:5000
        check "bob:p@ss:w0rd@ghcr.io" bob "p@ss:w0rd" ghcr.io
        check "me@example.com:pw@quay.io" "me@example.com" pw quay.io
        for bad in "bob:s3cret" "bob@host" ":s3cret@host" "bob:@host" "bob:s3cret@"; do
            assert_false _primer_step_docker_registry_parse "$bad"
        done
        # In the step: fails, and the password is not logged.
        mock docker primer_auth_group_add primer_utils_syscmd_exists
        YUSH_LOG_LEVEL=debug
        primer_step_docker option --registry "bob:s3cret"
        run primer_step_docker install
        assert_equal 1 "$RUN_RC"
        assert_contains "must be user:password@host" "$RUN_ERR"
        assert_not_contains "s3cret" "$RUN_ERR$RUN_OUT"
        assert_not_contains "docker login" "$(mock_calls)"'
}

# With a key for the Docker repository, the convenience script only sets the
# repository up: its key is verified before any package is installed from it.
# A wrong key installs nothing, and removes the repository.
test_docker_apt_key_before_install() {
    unit "$IMG_TRIXIE" '
        unit_step docker
        _primer_step_docker_install_getdocker() {
            mock_log getdocker "$@"
            mkdir -p /etc/apt/keyrings
            echo key > /etc/apt/keyrings/docker.asc
            echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://x y z" > /etc/apt/sources.list.d/docker.list
        }
        mock primer_os_packages
        PRIMER_STEP_DOCKER_APT_GPG=0ebfcd88
        mock -o DEADBEEF _primer_step_docker_apt_shortkey
        run _primer_step_docker_install_debian docker
        assert_equal 1 "$RUN_RC" "wrong key status"
        assert_contains "Wrong key for the Docker repository: DEADBEEF" "$RUN_ERR"
        assert_equal "getdocker --setup-repo
_primer_step_docker_apt_shortkey" "$(mock_calls)"
        assert_false test -e /etc/apt/sources.list.d/docker.list
        assert_false test -e /etc/apt/keyrings/docker.asc
        mock_reset
        mock -o 0EBFCD88 _primer_step_docker_apt_shortkey
        run _primer_step_docker_install_debian docker
        assert_equal 0 "$RUN_RC" "right key status"
        assert_equal "getdocker --setup-repo
_primer_step_docker_apt_shortkey
primer_os_packages add docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-compose-plugin docker-buildx-plugin" "$(mock_calls)"
        # No key to verify against: the script installs everything.
        mock_reset
        PRIMER_STEP_DOCKER_APT_GPG=
        run _primer_step_docker_install_debian docker
        assert_equal 0 "$RUN_RC" "no key status"
        assert_equal "getdocker" "$(mock_calls)"'
}

# Plugin downloads: verification and asset names per architecture, without
# privileges or network. Verification failures fail.
test_docker_plugin_download_offline() {
    unit "$IMG_ALPINE" '
        printf "#!/bin/sh\n[ \"\$1\" = docker-cli-plugin-metadata ] && echo {}\n" > /tmp/plugin
        printf "#!/bin/sh\nexit 1\n" > /tmp/notaplugin
        uname() { case "$1" in -s) echo Linux;; -m) echo "$FAKE_MACHINE";; esac; }
        primer_net_curl() {
            mock_log primer_net_curl "$@"
            case "$1" in
                */checksums.txt) printf "%s *buildx-v0.1.0.linux-amd64\n" "$(sha256sum < "$FAKE_BIN" | cut -d" " -f1)";;
                */buildx-v0.1.0.linux-*) cat "$FAKE_BIN";;
                *) return 22;;
            esac
        }
        unit_step docker
        PRIMER_STEP_DOCKER_PLUGINS_DIR=/tmp/plugins
        PRIMER_STEP_DOCKER_BUILDX_VERSION=v0.1.0
        FAKE_BIN=/tmp/plugin
        FAKE_MACHINE=x86_64
        run _primer_step_docker_plugin_download buildx
        assert_equal 0 "$RUN_RC" "status"
        assert_true test -x /tmp/plugins/docker-buildx
        rm -f /tmp/plugins/docker-buildx
        # No sum for the asset of this architecture: not installed.
        FAKE_MACHINE=armv7l
        run _primer_step_docker_plugin_download buildx
        assert_contains "buildx-v0.1.0.linux-arm-v7 in" "$RUN_ERR"
        assert_false test -e /tmp/plugins/docker-buildx
        assert_equal 1 "$RUN_RC" "no sum status"
        # Sum given and wrong: not installed.
        FAKE_MACHINE=x86_64
        PRIMER_STEP_DOCKER_BUILDX_SHA256=0000
        run _primer_step_docker_plugin_download buildx
        assert_contains "SHA256 sum mismatch" "$RUN_ERR"
        assert_equal 1 "$RUN_RC" "mismatch status"
        assert_false test -e /tmp/plugins/docker-buildx
        # Right sum, but not a CLI plugin: not installed.
        FAKE_BIN=/tmp/notaplugin
        PRIMER_STEP_DOCKER_BUILDX_SHA256=$(sha256sum < /tmp/notaplugin | cut -d" " -f1)
        run _primer_step_docker_plugin_download buildx
        assert_contains "probably invalid" "$RUN_ERR"
        assert_equal 1 "$RUN_RC" "invalid binary status"
        assert_false test -e /tmp/plugins/docker-buildx
        # Asset names
        FAKE_MACHINE=armv7l; assert_equal docker-compose-linux-armv7 "$(_primer_step_docker_plugin_asset compose v2)"
        FAKE_MACHINE=aarch64; assert_equal docker-compose-linux-aarch64 "$(_primer_step_docker_plugin_asset compose v2)"
        FAKE_MACHINE=aarch64; assert_equal buildx-v0.1.0.linux-arm64 "$(_primer_step_docker_plugin_asset buildx v0.1.0)"
        FAKE_MACHINE=x86_64; assert_equal buildx-v0.1.0.linux-amd64 "$(_primer_step_docker_plugin_asset buildx v0.1.0)"'
}

# Clean on Debian: only docker lines and files go, sources.list keeps its
# mode.
test_docker_clean_debian_sources() {
    unit "$IMG_TRIXIE" '
        mock primer_os_packages
        unit_step docker
        printf "deb http://deb.debian.org/debian trixie main\ndeb [arch=amd64] https://download.docker.com/linux/debian trixie stable\ndeb http://security.debian.org/debian-security trixie-security main\n" > /etc/apt/sources.list
        chmod 644 /etc/apt/sources.list
        mkdir -p /etc/apt/keyrings
        echo key > /etc/apt/keyrings/docker.asc
        echo key > /etc/apt/keyrings/other.asc
        echo "deb https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
        _primer_step_docker_uninstall_debian
        assert_equal "$(printf "deb http://deb.debian.org/debian trixie main\ndeb http://security.debian.org/debian-security trixie-security main")" "$(cat /etc/apt/sources.list)"
        assert_equal "644 0 0" "$(stat -c "%a %u %g" /etc/apt/sources.list)"
        assert_false test -e /etc/apt/sources.list.d/docker.list
        assert_false test -e /etc/apt/keyrings/docker.asc
        assert_true test -f /etc/apt/keyrings/other.asc
        assert_true test -f /etc/apt/sources.list.d/debian.sources'
}

# Clean on Alpine, before and after installation. Downloaded plugins are only
# removed at the version that primer installs.
test_docker_clean_alpine() {
    unit "$IMG_ALPINE" '
        unit_step docker
        mock primer_os_service
        primer_os_packages() {
            mock_log primer_os_packages "$@"
            [ "$1" = list ] && printf "docker-cli-compose-2.40.3-r6\ndocker-27.3.1-r0\nbusybox-1.37.0-r0\n"
            return 0
        }
        mkdir -p /usr/local/lib/docker/cli-plugins
        # Not a plugin at the version primer installs: kept.
        touch /usr/local/lib/docker/cli-plugins/docker-compose
        PRIMER_STEP_DOCKER_COMPOSE_VERSION=v2.0.0
        # Before installation: nothing to remove, no package touched.
        run primer_step_docker clean
        assert_equal 0 "$RUN_RC"
        assert_not_contains "primer_os_packages del" "$(mock_calls)"
        assert_true test -e /usr/local/lib/docker/cli-plugins/docker-compose
        assert_contains "not installed by primer" "$RUN_ERR"
        # The plugin at the version primer installs: removed.
        cat > /usr/local/lib/docker/cli-plugins/docker-compose <<"EOF"
#!/bin/sh
echo "{\"SchemaVersion\":\"0.1.0\",\"Version\":\"v2.0.0\"}"
EOF
        chmod a+x /usr/local/lib/docker/cli-plugins/docker-compose
        run primer_step_docker clean
        assert_false test -e /usr/local/lib/docker/cli-plugins/docker-compose
        stub_bin dockerd "exit 0"
        docker() { return 1; }
        mock_reset
        run primer_step_docker clean
        calls=$(mock_calls)
        assert_contains "primer_os_packages del docker-cli-compose" "$calls"
        assert_not_contains "del docker-cli-buildx" "$calls"
        assert_contains "primer_os_packages del docker" "$calls"
        assert_contains "primer_os_service disable docker" "$calls"'
}
