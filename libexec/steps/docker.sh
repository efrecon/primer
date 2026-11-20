#!/usr/bin/env sh

# Short GPG signature (last 8 hexadecimal digits of the fingerprint) of the key
# of the Docker repository on Debian derivatives, e.g. 0EBFCD88. When set, the
# convenience script only sets up the repository, and its key is verified
# against this before any package is installed from it.
PRIMER_STEP_DOCKER_APT_GPG=${PRIMER_STEP_DOCKER_APT_GPG:-}

# Space separated list of registry login information in the form
# username:password@host
PRIMER_STEP_DOCKER_REGISTRY=${PRIMER_STEP_DOCKER_REGISTRY:-}

# The convenience script (get.docker.com) is downloaded from its repository,
# https://github.com/docker/docker-install, at this commit. get.docker.com
# changes with every commit to the repository, which has no tags: a commit is
# the only fixed reference. To move to a newer commit, see the documentation.
PRIMER_STEP_DOCKER_INSTALL_COMMIT=${PRIMER_STEP_DOCKER_INSTALL_COMMIT:-8ad27bd3ac871feabe62f1d926c4067800c1732f}

# sha256 sum of the convenience script, as downloaded. The script only runs when
# its sum matches, it never runs when this is empty.
PRIMER_STEP_DOCKER_INSTALL_SHA256=${PRIMER_STEP_DOCKER_INSTALL_SHA256:-77f623a9f23857ebc45a50e37696fc406e3a60bda4ef17399444f792ecf8895d}

# Can be native (as in: OS native packaging), docker (as in: docker.com provided
# packages) or auto (as in: pick the best one of both worlds)
PRIMER_STEP_DOCKER_PACKAGING=${PRIMER_STEP_DOCKER_PACKAGING:-auto}

# All regular users matching this regular expression will be made member of the
# docker group. In practice these users will be given root access!
PRIMER_STEP_DOCKER_ACCESS=${PRIMER_STEP_DOCKER_ACCESS:-}

# Where to get the convenience script from. When empty, the default, the script
# of the repository at PRIMER_STEP_DOCKER_INSTALL_COMMIT.
PRIMER_STEP_DOCKER_GET_URL=${PRIMER_STEP_DOCKER_GET_URL:-}

# Version of the Docker compose plugin to download when it cannot be installed
# from packages. Empty, the default, means the latest as per the releases below.
# Setting a version forces installation from the binary releases.
PRIMER_STEP_DOCKER_COMPOSE_VERSION=${PRIMER_STEP_DOCKER_COMPOSE_VERSION:-}

# SHA256 of the compose plugin binary when downloading from the release
# repository. Setting a sum forces installation from the binary releases.
PRIMER_STEP_DOCKER_COMPOSE_SHA256=${PRIMER_STEP_DOCKER_COMPOSE_SHA256:-}

# URL to JSON file where to find the list of releases of Docker compose. The
# code only supports github API.
PRIMER_STEP_DOCKER_COMPOSE_RELEASES=${PRIMER_STEP_DOCKER_COMPOSE_RELEASES:-https://api.github.com/repos/docker/compose/releases}

# Root URL to download location of Docker compose binary releases
PRIMER_STEP_DOCKER_COMPOSE_DOWNLOAD=${PRIMER_STEP_DOCKER_COMPOSE_DOWNLOAD:-https://github.com/docker/compose/releases/download}

# Version of the Docker buildx plugin to download when it cannot be installed
# from packages. Empty, the default, means the latest as per the releases below.
# Setting a version forces installation from the binary releases.
PRIMER_STEP_DOCKER_BUILDX_VERSION=${PRIMER_STEP_DOCKER_BUILDX_VERSION:-}

# SHA256 of the buildx plugin binary when downloading from the release
# repository. Setting a sum forces installation from the binary releases.
PRIMER_STEP_DOCKER_BUILDX_SHA256=${PRIMER_STEP_DOCKER_BUILDX_SHA256:-}

# URL to JSON file where to find the list of releases of Docker buildx. The
# code only supports github API.
PRIMER_STEP_DOCKER_BUILDX_RELEASES=${PRIMER_STEP_DOCKER_BUILDX_RELEASES:-https://api.github.com/repos/docker/buildx/releases}

# Root URL to download location of Docker buildx binary releases
PRIMER_STEP_DOCKER_BUILDX_DOWNLOAD=${PRIMER_STEP_DOCKER_BUILDX_DOWNLOAD:-https://github.com/docker/buildx/releases/download}

# System-wide directory where to install Docker CLI plugins downloaded from
# their releases.
PRIMER_STEP_DOCKER_PLUGINS_DIR=${PRIMER_STEP_DOCKER_PLUGINS_DIR:-/usr/local/lib/docker/cli-plugins}

primer_step_docker() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--registry --commit --sha256 --access --compose-version --compose-sha256 --buildx-version --buildx-sha256"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --registry)
                        PRIMER_STEP_DOCKER_REGISTRY="$PRIMER_STEP_DOCKER_REGISTRY $2"; shift 2;;
                    --commit)
                        PRIMER_STEP_DOCKER_INSTALL_COMMIT="$2"; shift 2;;
                    --sha256)
                        PRIMER_STEP_DOCKER_INSTALL_SHA256="$2"; shift 2;;
                    --access)
                        PRIMER_STEP_DOCKER_ACCESS="$2"; shift 2;;
                    --compose-version)
                        PRIMER_STEP_DOCKER_COMPOSE_VERSION="$2"; shift 2;;
                    --compose-sha256)
                        PRIMER_STEP_DOCKER_COMPOSE_SHA256="$2"; shift 2;;
                    --buildx-version)
                        PRIMER_STEP_DOCKER_BUILDX_VERSION="$2"; shift 2;;
                    --buildx-sha256)
                        PRIMER_STEP_DOCKER_BUILDX_SHA256="$2"; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if ! primer_utils_syscmd_exists dockerd; then
                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    alpine)
                        if [ "$PRIMER_STEP_DOCKER_PACKAGING" = "auto" ] \
                                || [ "$PRIMER_STEP_DOCKER_PACKAGING" = "native" ]; then
                            primer_os_packages add docker
                        else
                            yush_error "$PRIMER_STEP_DOCKER_PACKAGING packaging not supported on Alpine"
                        fi
                        ;;
                    clear*linux*)
                        if [ "$PRIMER_STEP_DOCKER_PACKAGING" = "auto" ] \
                                || [ "$PRIMER_STEP_DOCKER_PACKAGING" = "native" ]; then
                            primer_os_packages add containers-basic
                        else
                            yush_error "$PRIMER_STEP_DOCKER_PACKAGING packaging not supported on ClearLinux"
                        fi
                        ;;
                    *buntu|*bian)
                        _primer_step_docker_install_debian;;
                    fedora*)
                        # moby-engine requires iptables, which dnf resolves
                        # to iptables-legacy when none is installed. Prefer
                        # the default of Fedora, iptables-nft: recent kernels
                        # might not have the legacy modules. An existing
                        # iptables is kept as is.
                        if ! primer_utils_syscmd_exists iptables; then
                            primer_os_packages install iptables-nft
                        fi
                        primer_os_packages install "moby-engine";;
                    *)
                        # Prefer the docker installation whenever possible, do
                        # some guesswork otherwise. This is likely to fail...
                        case "$PRIMER_STEP_DOCKER_PACKAGING" in
                            "docker")
                                _primer_step_docker_install_getdocker
                                ;;
                            "native")
                                _primer_step_docker_install_guess
                                ;;
                            "auto")
                                if ! _primer_step_docker_install_getdocker; then
                                    _primer_step_docker_install_guess
                                fi
                               ;;
                        esac
                        ;;
                esac
            fi

            # Start docker and make sure it will always start
            if primer_utils_syscmd_exists dockerd; then
                if ! docker info 2>/dev/null; then
                    yush_info "Starting Docker daemon"
                    primer_os_service start docker
                fi
                yush_info "Enabling docker daemon at start"
                primer_os_service enable docker
            fi

            # Perform user operations only if we have a docker client installed.
            # Note that we cannot detect, nor call the docker client with the
            # single string "docker" since it is the name of the function
            # implemented by this module.
            if command -v docker; then
                # Create group and make sure relevant users are part of the
                # group
                primer_auth_group_add docker
                if [ -n "$PRIMER_STEP_DOCKER_ACCESS" ]; then
                    yush_info "Adding all users on system matching $PRIMER_STEP_DOCKER_ACCESS to group docker"
                    primer_auth_user_list | while IFS= read -r _username || [ -n "$_username" ]; do
                        if printf %s\\n "$_username" | grep -qE "$PRIMER_STEP_DOCKER_ACCESS" \
                                && [ "$(id -u "$_username")" != "0" ]; then
                            yush_debug "Making $_username a member of the docker group"
                            primer_auth_group_membership "$_username" docker
                        fi
                    done
                else
                    yush_info "Only root has access to Docker"
                fi

                # Arrange for access to docker registries
                _config=${PRIMER_STEP_DOCKER_CONFIG:-"$HOME/.docker"}/config.json
                _prior_settings=0; [ -f "$_config" ] && _prior_settings=1
                for _registry in $PRIMER_STEP_DOCKER_REGISTRY; do
                    if ! _primer_step_docker_registry_parse "$_registry"; then
                        yush_error "Registry login information must be user:password@host, not logged in"
                        return 1
                    fi
                    yush_info "Logging in at $_host as $_user"
                    printf %s\\n "$_pass" | docker login --password-stdin -u "$_user" "$_host"
                done

                # Copy the credentials to the users given access to Docker, and
                # to them only: an empty access means no user.
                if [ -n "$PRIMER_STEP_DOCKER_REGISTRY" ] && [ -n "$PRIMER_STEP_DOCKER_ACCESS" ]; then
                    if [ "$_prior_settings" = "0" ]; then
                        _me=$(id -un)
                        primer_auth_user_list | while IFS= read -r _username || [ -n "$_username" ]; do
                            [ "$_username" = "$_me" ] && continue
                            if printf %s\\n "$_username" | grep -qE "$PRIMER_STEP_DOCKER_ACCESS"; then
                                _home=$(getent passwd "$_username" | cut -d ":" -f 6)
                                if ! [ -f "$_home/.docker/config.json" ]; then
                                    if ! [ -d "$_home/.docker" ]; then
                                        $PRIMER_OS_SUDO mkdir -p "$_home/.docker"
                                        primer_utils_path_ownership "$_home/.docker" --user "$_username" --perm 700
                                    fi
                                    $PRIMER_OS_SUDO cp "$_config" "$_home/.docker/config.json"
                                    primer_utils_path_ownership "$_home/.docker/config.json" --as "$_config" --user "$_username"
                                    yush_info "Local user $_username logged in at all Docker registries from above"
                                else
                                    yush_warn "Skipped login for $_username, found existing settings at $_home/.docker/config.json"
                                fi
                            fi
                        done
                    else
                        yush_warn "Will not copy private Docker settings information to other users"
                    fi
                fi

                # Docker compose and buildx, as Docker CLI plugins
                _primer_step_docker_install_plugin compose || return 1
                _primer_step_docker_install_plugin buildx || return 1

                # Bash completion, if necessary
                _docker_version=$(docker --version|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)
                yush_debug "Installing bash completions for Docker v $_docker_version"
                _completion_dir=$(primer_os_bash_completion_dir)
                if ! [ -d "$_completion_dir" ]; then
                    $PRIMER_OS_SUDO mkdir -p "$_completion_dir"
                fi
                if ! [ -f "${_completion_dir}/docker" ]; then
                    primer_net_curl "https://raw.githubusercontent.com/docker/cli/v${_docker_version}/contrib/completion/bash/docker" |
                        $PRIMER_OS_SUDO tee "${_completion_dir}/docker" > /dev/null
                fi
            else
                yush_warn "No docker client installed!"
            fi

            ;;
        "clean")
            # Remove the plugins, if they had been downloaded by this step.
            for _plugin in compose buildx; do
                _primer_step_docker_plugin_clean "$_plugin"
            done

            # Stop docker and remove from autostart.
            if primer_utils_syscmd_exists dockerd; then
                if docker info >/dev/null 2>&1; then
                    yush_info "Stopping Docker daemon"
                    primer_os_service stop docker
                fi
                yush_info "Disabling docker daemon at start"
                primer_os_service disable docker

                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    alpine)
                        _primer_step_docker_uninstall_packages docker-cli-compose docker-cli-buildx
                        primer_os_packages del docker;;
                    clear*linux*)
                        primer_os_packages del containers-basic;;
                    *buntu|*bian)
                        _primer_step_docker_uninstall_debian;;
                    fedora*)
                        _primer_step_docker_uninstall_packages docker-compose docker-buildx
                        primer_os_packages del "moby-engine";;
                    *)
                        yush_warn "Cannot remove docker on $lsb_dist"
                        ;;
                esac
            fi
            ;;
    esac
}

_primer_step_docker_uninstall_debian() {
    _primer_step_docker_uninstall_packages docker-compose-plugin docker-compose-v2 docker-buildx-plugin docker-buildx
    # Only remove the native docker-compose package when it is the CLI plugin.
    if dpkg -L docker-compose 2>/dev/null | grep -q 'cli-plugins/docker-compose$'; then
        primer_os_packages del docker-compose
    fi
    # Only remove the packages that are installed, apt fails on others.
    _primer_step_docker_uninstall_packages \
        docker-ce-cli docker-ce docker-ce-rootless-extras containerd.io docker.io

    # Remove the key of the Docker repository: in a keyring file with recent
    # versions of the convenience script, through apt-key with older ones (when
    # apt-key and gpg are still around, apt-key is gone since Debian 13).
    for _keyring in /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg; do
        if [ -f "$_keyring" ]; then
            yush_info "Removing docker GPG keyring $_keyring"
            $PRIMER_OS_SUDO rm -f "$_keyring"
        fi
    done
    if command -v apt-key >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
        dkey_present=$(apt-key list 2>/dev/null | grep -e "Docker" -e "docker\.com" -B 1 || true)
        if [ -n "$dkey_present" ]; then
            yush_info "Removing docker GPG key"
            dkey=$(echo "$dkey_present" | head -1 | awk '{print $9$10}')
            $PRIMER_OS_SUDO apt-key del "$dkey"
        fi
    fi

    if [ -f "/etc/apt/sources.list.d/docker.list" ]; then
        yush_info "Removing repo list /etc/apt/sources.list.d/docker.list"
        $PRIMER_OS_SUDO rm -f /etc/apt/sources.list.d/docker.list
    fi

    if [ -f /etc/apt/sources.list ] && grep -q docker /etc/apt/sources.list; then
        yush_info "Removing docker from main repo list at /etc/apt/sources.list"
        primer_utils_sysfile_clip /etc/apt/sources.list docker
    fi
}

_primer_step_docker_install_debian() {
    method=${1:-$PRIMER_STEP_DOCKER_PACKAGING}
    case "$method" in
        "docker")
            lsb_dist=$(primer_os_distribution)
            case "$lsb_dist" in
                *buntu|*bian)
                    if [ -n "$PRIMER_STEP_DOCKER_APT_GPG" ]; then
                        # Only set up the repository, and verify its key
                        # before installing anything from it. The packages
                        # are the ones the script would install.
                        _primer_step_docker_install_getdocker --setup-repo
                        if ! _primer_step_docker_install_apt_verify; then
                            _primer_step_docker_apt_unsetup
                            return 1
                        fi
                        primer_os_packages add docker-ce docker-ce-cli containerd.io \
                            docker-ce-rootless-extras docker-compose-plugin docker-buildx-plugin
                    else
                        yush_notice "No key given for the Docker repository, its key is not verified"
                        _primer_step_docker_install_getdocker
                    fi
                    ;;
                *)
                    yush_warn "Cannot verify proper package provider on $lsb_dist"
                    _primer_step_docker_install_getdocker
                    ;;
            esac
            ;;
        "native")
            primer_os_packages add docker.io
            ;;
        "auto")
            lsb_dist=$(primer_os_distribution)
            case "$lsb_dist" in
                *buntu)
                    modern=$(primer_os_version | LC_ALL=c awk '{if ($1 > 19) print $1}')
                    if [ -n "$modern" ]; then
                        _primer_step_docker_install_debian "native"
                    else
                        _primer_step_docker_install_debian "docker"
                    fi
                    ;;
                *bian)
                    modern=$(primer_os_version | LC_ALL=c awk '{if ($1 > 9) print $1}')
                    if [ -n "$modern" ]; then
                        _primer_step_docker_install_debian "native"
                    else
                        _primer_step_docker_install_debian "docker"
                    fi
                    ;;
                *)
                    if ! _primer_step_docker_install_getdocker; then
                        _primer_step_docker_install_guess
                    fi
                    ;;
            esac
            ;;
    esac
}

# Print the file of the key of the Docker repository: the keyring given to
# signed-by in the list of the repository, as installed by current versions of
# the convenience script, or the usual location.
_primer_step_docker_apt_keyring() {
    _keyring=
    if [ -f /etc/apt/sources.list.d/docker.list ]; then
        _keyring=$(sed -nE 's/.*signed-by=([^] ]+).*/\1/p' /etc/apt/sources.list.d/docker.list | head -n 1)
    fi
    for _k in "$_keyring" /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg; do
        if [ -n "$_k" ] && [ -f "$_k" ]; then
            printf %s\\n "$_k"
            return
        fi
    done
}

# Print the short key (last 8 hexadecimal digits of the fingerprint) of the
# Docker repository: from its keyring file, or through apt-key with older
# versions of the convenience script (apt-key is gone since Debian 13).
_primer_step_docker_apt_shortkey() {
    _keyring=$(_primer_step_docker_apt_keyring)
    if [ -n "$_keyring" ]; then
        primer_os_dependency gpg gnupg
        gpg --show-keys --with-colons "$_keyring" 2>/dev/null |
            awk -F: '$1 == "fpr" { print substr($10, length($10) - 7); exit }'
    elif command -v apt-key >/dev/null 2>&1; then
        apt-key list 2>/dev/null | grep -e "Docker" -e "docker\.com" -B 1 | head -1 | awk '{print $9$10}'
    fi
}

# Succeed when the key of the Docker repository matches the short key in
# PRIMER_STEP_DOCKER_APT_GPG.
_primer_step_docker_install_apt_verify() {
    yush_info "Verifying Docker GPG short key against: $(yush_green "$PRIMER_STEP_DOCKER_APT_GPG")"
    dkey=$(_primer_step_docker_apt_shortkey)
    if [ "$(printf %s "$dkey" | tr '[:lower:]' '[:upper:]')" != "$(printf %s "$PRIMER_STEP_DOCKER_APT_GPG" | tr '[:lower:]' '[:upper:]')" ]; then
        yush_error "Wrong key for the Docker repository: ${dkey:-none}, not $PRIMER_STEP_DOCKER_APT_GPG. Nothing installed from it."
        return 1
    fi
}

# Remove the Docker repository and its key, as just set up by the convenience
# script.
_primer_step_docker_apt_unsetup() {
    _keyring=$(_primer_step_docker_apt_keyring)
    $PRIMER_OS_SUDO rm -f /etc/apt/sources.list.d/docker.list
    if [ -n "$_keyring" ]; then
        $PRIMER_OS_SUDO rm -f "$_keyring"
    fi
}

# Split the registry login information $1, user:password@host, into _user,
# _pass and _host. The host is after the last @, the user before the first :,
# so passwords can contain both, and hosts a port. Fails when any is empty.
_primer_step_docker_registry_parse() {
    _user=; _pass=; _host=
    case "$1" in
        *@*) ;;
        *) return 1;;
    esac
    _host=${1##*@}
    _creds=${1%@*}
    case "$_creds" in
        *:*) ;;
        *) return 1;;
    esac
    _user=${_creds%%:*}
    _pass=${_creds#*:}
    [ -n "$_user" ] && [ -n "$_pass" ] && [ -n "$_host" ]
}

# Succeed when the sha256 sum of the file $1 is exactly $2 (in any case).
_primer_step_docker_sha256_ok() {
    [ -n "$2" ] || return 1
    _sum=$(sha256sum < "$1" | cut -d " " -f 1)
    [ "$_sum" = "$(printf %s "$2" | tr '[:upper:]' '[:lower:]')" ]
}

# Download the convenience script, from the docker-install repository at the
# pinned commit unless another URL is given, and run it, with the arguments
# passed to this function, when its sha256 sum matches. The script runs with LOAD_SCRIPT_COMMIT_SHA set to the commit: the
# repository version of the script uses it for the commit it prints, a value
# that the upload to get.docker.com substitutes in the script.
_primer_step_docker_install_getdocker() {
    _url=${PRIMER_STEP_DOCKER_GET_URL:-"https://raw.githubusercontent.com/docker/docker-install/${PRIMER_STEP_DOCKER_INSTALL_COMMIT}/install.sh"}
    if [ -z "$PRIMER_STEP_DOCKER_INSTALL_SHA256" ]; then
        yush_error "No sha256 sum for the Docker installation script, refusing to run it unverified!"
        yush_error "Unable to verify Docker installation script!!"
        return 1
    fi
    if printf %s\\n "$PRIMER_STEP_DOCKER_INSTALL_SHA256" | grep -qE '^[0-9a-fA-F]{40}$'; then
        yush_error "$PRIMER_STEP_DOCKER_INSTALL_SHA256 is a git commit, not a sha256 sum: pass the commit with --commit, and the sum of the script with --sha256"
        yush_error "Unable to verify Docker installation script!!"
        return 1
    fi

    yush_info "Downloading Docker installation script from $(yush_yellow "$_url")"
    _get=$(mktemp)
    if ! primer_net_curl "$_url" -o "$_get"; then
        rm -f "$_get"
        yush_error "Could not download Docker installation script from $_url"
        return 1
    fi
    if ! _primer_step_docker_sha256_ok "$_get" "$PRIMER_STEP_DOCKER_INSTALL_SHA256"; then
        rm -f "$_get"
        yush_warn "The sha256 sum of the script differs from $PRIMER_STEP_DOCKER_INSTALL_SHA256. Verify the script and run again with --docker:sha256 (and --docker:commit)"
        yush_error "Unable to verify Docker installation script!!"
        return 1
    fi

    yush_info "Verified Docker installation script, running it now"
    _rc=0
    LOAD_SCRIPT_COMMIT_SHA=$PRIMER_STEP_DOCKER_INSTALL_COMMIT sh "$_get" "$@" || _rc=$?
    rm -f "$_get"
    if [ "$_rc" != "0" ]; then
        yush_error "Docker installation script failed. The script at commit $PRIMER_STEP_DOCKER_INSTALL_COMMIT might not support this distribution: try a newer --docker:commit, with its --docker:sha256"
        return "$_rc"
    fi
}

_primer_step_docker_install_guess() {
    for pkg in docker.io docker-ce docker-engine docker moby-engine; do
        yush_trace "Looking for package $pkg for Docker installation"
        candidate=$(primer_os_packages search "$pkg"|head -1)
        if [ -n "$candidate" ]; then
            yush_notice "Picked package $candidate for Docker installation"
            primer_os_packages install "$candidate"
            break
        fi
    done
}

# Remove the packages passed as arguments, but only those that are installed.
# Some package managers (apk) list installed packages with their version
# appended, e.g. docker-cli-compose-2.40.3-r6, so accept an optional version
# suffix, which always starts with a digit.
_primer_step_docker_uninstall_packages() {
    for _pkg in "$@"; do
        if primer_os_packages list | grep -qE "^${_pkg}(-[0-9].*)?\$"; then
            primer_os_packages del "$_pkg"
        fi
    done
}

# Print the list of candidate packages for the Docker CLI plugin passed as an
# argument (compose or buildx) on the current distribution, in preference order.
_primer_step_docker_plugin_packages() {
    lsb_dist=$(primer_os_distribution)
    case "$1:$lsb_dist" in
        compose:alpine*)
            echo "docker-cli-compose";;
        compose:fedora*)
            echo "docker-compose";;
        compose:*buntu|compose:*bian)
            # docker-compose-plugin comes from the Docker repositories,
            # docker-compose-v2 is the native Ubuntu package and docker-compose
            # is the native Debian package.
            echo "docker-compose-plugin docker-compose-v2 docker-compose";;
        buildx:alpine*)
            echo "docker-cli-buildx";;
        buildx:fedora*)
            echo "docker-buildx";;
        buildx:*buntu|buildx:*bian)
            # docker-buildx-plugin comes from the Docker repositories,
            # docker-buildx is the native Debian/Ubuntu package.
            echo "docker-buildx-plugin docker-buildx";;
    esac
}

# Print the name of the release asset for the Docker CLI plugin passed as a
# first argument (compose or buildx), at the version passed as a second
# argument, for the current OS and architecture.
_primer_step_docker_plugin_asset() {
    _os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$1" in
        compose)
            # compose uses uname -m names, except for 32-bit ARM, where the
            # trailing endianness letter (armv7l, armv6l) is dropped.
            case "$(uname -m)" in
                armv7*) _arch=armv7;;
                armv6*) _arch=armv6;;
                *) _arch=$(uname -m);;
            esac
            printf %s\\n "docker-compose-${_os}-${_arch}";;
        buildx)
            # buildx uses Go architecture names.
            case "$(uname -m)" in
                x86_64|amd64) _arch=amd64;;
                aarch64|arm64) _arch=arm64;;
                armv7*) _arch=arm-v7;;
                armv6*) _arch=arm-v6;;
                *) _arch=$(uname -m);;
            esac
            printf %s\\n "buildx-${2}.${_os}-${_arch}";;
    esac
}

# Return success when the Docker CLI plugin passed as an argument (compose or
# buildx) is installed and, when a version was requested, at that version. The
# requested version matches the installed one exactly, or as a prefix ending at
# a dot boundary, e.g. 2.29 matches 2.29.7, but 2.2 does not.
_primer_step_docker_plugin_ok() {
    docker "$1" version >/dev/null 2>&1 || return 1
    _want=$(primer_utils_var_value "PRIMER_STEP_DOCKER_$(printf %s "$1" | tr '[:lower:]' '[:upper:]')_VERSION")
    [ -z "$_want" ] && return 0
    _want=${_want#v}
    # First dotted version number in the output, e.g. "Docker Compose version
    # v2.29.7" or "github.com/docker/buildx 0.12.1 ..." (distro builds may add
    # a -N suffix, which is dropped here).
    _have=$(docker "$1" version | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1)
    case "$_have" in
        "$_want"|"$_want".*) return 0;;
    esac
    return 1
}

# Install the Docker CLI plugin passed as an argument (compose or buildx),
# unless it is already present at the requested version, if any (the
# convenience script installs both, for example). Packages are preferred, unless
# a specific version or sha256 sum was requested. Fall back to downloading the
# binary release from github into the system-wide CLI plugins directory, which
# takes precedence over the plugins installed by packages.
_primer_step_docker_install_plugin() {
    if _primer_step_docker_plugin_ok "$1"; then
        yush_debug "Docker $1 plugin already installed: $(docker "$1" version | head -1)"
        return 0
    elif docker "$1" version >/dev/null 2>&1; then
        yush_info "Docker $1 plugin installed at another version than requested: $(docker "$1" version | head -1)"
    fi

    _var=PRIMER_STEP_DOCKER_$(printf %s "$1" | tr '[:lower:]' '[:upper:]')
    if [ -z "$(primer_utils_var_value "${_var}_VERSION")" ] \
            && [ -z "$(primer_utils_var_value "${_var}_SHA256")" ]; then
        lsb_dist=$(primer_os_distribution)
        for _pkg in $(_primer_step_docker_plugin_packages "$1"); do
            if [ -n "$(primer_os_packages search "$_pkg"|head -1)" ]; then
                # The native Debian docker-compose package is the old python
                # version on older releases, only pick it when v2+ (the plugin).
                if [ "$_pkg" = "docker-compose" ] && yush_glob '*bian' "$lsb_dist"; then
                    _candidate=$(apt-cache policy "$_pkg" | awk '/Candidate:/ {print $2}' | sed -E 's/^[0-9]+://')
                    case "$_candidate" in
                        [01].*|"")
                            yush_debug "Skipping $_pkg package at version $_candidate, not a CLI plugin"
                            continue;;
                    esac
                fi
                yush_notice "Picked package $_pkg for Docker $1 installation"
                primer_os_packages add "$_pkg"
                break
            fi
        done
    fi

    if ! _primer_step_docker_plugin_ok "$1"; then
        if ! _primer_step_docker_plugin_download "$1"; then
            yush_error "Could not install Docker $1 plugin!"
            return 1
        fi
    fi

    if ! docker "$1" version >/dev/null 2>&1; then
        yush_error "Could not install Docker $1 plugin!"
        return 1
    elif ! _primer_step_docker_plugin_ok "$1"; then
        yush_warn "Installed Docker $1 version mismatch: $(docker "$1" version | head -1)"
    fi
}

# Print the latest version of the Docker CLI plugin passed as an argument
# (compose or buildx), from the list of its releases.
_primer_step_docker_plugin_latest() {
    # Following uses the github API
    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
    # for getting the list of latest releases and focuses solely on "full"
    # releases. Release candidates have -rcXXX in their version number, these
    # are set away by the grep/sed combo.
    _releases=$(primer_utils_var_value "PRIMER_STEP_DOCKER_$(printf %s "$1" | tr '[:lower:]' '[:upper:]')_RELEASES")
    yush_notice "Discovering latest Docker $1 version from $_releases"
    primer_net_curl "$_releases" |
        grep -E '"name"[[:space:]]*:[[:space:]]*"v?[0-9]+(\.[0-9]+)*"' |
        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"(v?[0-9]+(\.[0-9]+)*)",/\1/g' |
        head -1
}

# Remove the Docker CLI plugin passed as an argument (compose or buildx) from
# the plugins directory, but only when it is at the version that this step
# installs: the one requested, or the latest one. Other binaries might not have
# been installed by this step, and are kept.
_primer_step_docker_plugin_clean() {
    _path="${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-$1"
    [ -f "$_path" ] || return 0
    _want=$(primer_utils_var_value "PRIMER_STEP_DOCKER_$(printf %s "$1" | tr '[:lower:]' '[:upper:]')_VERSION")
    [ -z "$_want" ] && _want=$(_primer_step_docker_plugin_latest "$1" || true)
    _have=$("$_path" docker-cli-plugin-metadata 2>/dev/null |
        sed -nE 's/.*"Version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' || true)
    if [ -n "$_want" ] && [ "${_have#v}" = "${_want#v}" ]; then
        yush_info "Removing Docker $1 plugin $_have from $PRIMER_STEP_DOCKER_PLUGINS_DIR"
        $PRIMER_OS_SUDO rm -f "$_path"
    else
        yush_warn "Keeping $_path, at version ${_have:-unknown}, not installed by primer (version ${_want:-unknown})"
    fi
}

# Download the Docker CLI plugin passed as an argument (compose or buildx) from
# github, making sure we can actually execute the binary that we downloaded and
# checking it against its sha256 sum. When no sum is specified, it is read from
# the checksums.txt file of the release.
_primer_step_docker_plugin_download() {
    _var=PRIMER_STEP_DOCKER_$(printf %s "$1" | tr '[:lower:]' '[:upper:]')
    _version=$(primer_utils_var_value "${_var}_VERSION")
    if [ -z "$_version" ]; then
        _version=$(_primer_step_docker_plugin_latest "$1" || true)
        if [ -z "$_version" ]; then
            yush_error "Could not discover latest Docker $1 version"
            return 1
        fi
        # Remember the version for the verification after installation
        eval "${_var}_VERSION=\$_version"
    fi

    _release="$(primer_utils_var_value "${_var}_DOWNLOAD")"
    _release="${_release%%/}/$_version"
    _asset=$(_primer_step_docker_plugin_asset "$1" "$_version")
    _url="${_release}/${_asset}"

    # Pick the sha256 sum to verify against: the one specified, or the one from
    # the checksums.txt file of the release. Lines in that file are formatted as
    # <sha256> *<asset>.
    _sha256=$(primer_utils_var_value "${_var}_SHA256")
    if [ -z "$_sha256" ]; then
        yush_debug "Reading sha256 sum for $_asset from ${_release}/checksums.txt"
        _sha256=$(primer_net_curl "${_release}/checksums.txt" |
                    awk -v a="$_asset" '{f=$2; sub(/^\*/, "", f); if (f == a && !s) s = $1} END {print s}')
        if [ -z "$_sha256" ]; then
            yush_error "Could not find sha256 sum for $_asset in ${_release}/checksums.txt, will not install"
            return 1
        fi
    fi

    yush_info "Installing Docker $1 plugin $_version from $_url"
    _tmpdir=$(mktemp -d)
    _bin="${_tmpdir}/docker-$1"
    _rc=1
    if ! primer_net_curl "$_url" --progress-bar > "$_bin"; then
        yush_error "No binary at $_url"
    elif ! _primer_step_docker_sha256_ok "$_bin" "$_sha256"; then
        yush_error "SHA256 sum mismatch, should have been $_sha256"
    else
        yush_info "Verified sha256 sum of $_asset"
        # All Docker CLI plugins answer to the metadata sub-command.
        yush_debug "Verifying binary at $_bin"
        chmod a+x "$_bin"
        if ! "$_bin" docker-cli-plugin-metadata >/dev/null 2>&1; then
            yush_error "Downloaded binary from $_url probably invalid, will not install"
        else
            yush_notice "Installing as ${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-$1"
            if ! [ -d "$PRIMER_STEP_DOCKER_PLUGINS_DIR" ]; then
                $PRIMER_OS_SUDO mkdir -p "$PRIMER_STEP_DOCKER_PLUGINS_DIR"
            fi
            primer_utils_install_bin "$_bin" "${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-$1"
            _rc=0
        fi
    fi
    rm -rf "$_tmpdir"
    return "$_rc"
}
