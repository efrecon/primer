#!/usr/bin/env sh

# Short GPG signature for Docker Repo on debian derivatives
PRIMER_STEP_DOCKER_APT_GPG=${PRIMER_STEP_DOCKER_APT_GPG:-}

# Space separated list of registry login information in the form
# username:password@host
PRIMER_STEP_DOCKER_REGISTRY=${PRIMER_STEP_DOCKER_REGISTRY:-}

# Commit SHA sum contained in script, so we do not run something that has not
# been verified. Every time the installation script is changed, the commit
# sha256 will change, meaning that this variable has to change. Setting it to
# empty will disable the check, which is a security risk as this means executing
# a script downloaded from the Internet...
PRIMER_STEP_DOCKER_INSTALL_SHA256=${PRIMER_STEP_DOCKER_INSTALL_SHA256:-8ad27bd3ac871feabe62f1d926c4067800c1732f}

# Can be native (as in: OS native packaging), docker (as in: docker.com provided
# packages) or auto (as in: pick the best one of both worlds)
PRIMER_STEP_DOCKER_PACKAGING=${PRIMER_STEP_DOCKER_PACKAGING:-auto}

# All regular users matching this regular expression will be made member of the
# docker group. In practice these users will be given root access!
PRIMER_STEP_DOCKER_ACCESS=${PRIMER_STEP_DOCKER_ACCESS:-}

# Where to get the docker installation script from
PRIMER_STEP_DOCKER_GET_URL=https://get.docker.com/

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
            [ "$#" = "0" ] && echo "--registry --sha256 --access --compose-version --compose-sha256 --buildx-version --buildx-sha256"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --registry)
                        PRIMER_STEP_DOCKER_REGISTRY="$PRIMER_STEP_DOCKER_REGISTRY $2"; shift 2;;
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
                    _user=$(printf %s\\n "$_registry" | sed -E -e 's/([^:]+)(:([^@]+))?@((([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])+)/\1/')
                    _pass=$(printf %s\\n "$_registry" | sed -E -e 's/([^:]+)(:([^@]+))?@((([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])+)/\3/')
                    _host=$(printf %s\\n "$_registry" | sed -E -e 's/([^:]+)(:([^@]+))?@((([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])+)/\4/')
                    yush_info "Logging in at $_host as $_user"
                    printf %s\\n "$_pass" | docker login --password-stdin -u "$_user" "$_host"
                done

                if [ -n "$PRIMER_STEP_DOCKER_REGISTRY" ]; then
                    if [ "$_prior_settings" = "0" ]; then
                        primer_auth_user_list | grep -v "$(id -un)" | while IFS= read -r _username || [ -n "$_username" ]; do
                            if printf %s\\n "$_username" | grep -qE "$PRIMER_STEP_DOCKER_ACCESS"; then
                                _home=$(getent passwd | grep -E "^${_username}:" | cut -d ":" -f 6)
                                if ! [ -f "$_home/.docker/config.json" ]; then
                                    $PRIMER_OS_SUDO mkdir -p "$_home/.docker"
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
                _primer_step_docker_install_plugin compose
                _primer_step_docker_install_plugin buildx

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
            # Remove the plugins, if they had been downloaded.
            for _plugin in compose buildx; do
                if [ -f "${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-${_plugin}" ]; then
                    yush_info "Removing Docker $_plugin plugin from $PRIMER_STEP_DOCKER_PLUGINS_DIR"
                    $PRIMER_OS_SUDO rm -f "${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-${_plugin}"
                fi
            done

            # Stop docker and remove from autostart.
            if primer_utils_syscmd_exists dockerd; then
                if docker info; then
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
    primer_os_packages del docker-ce-cli docker-ce docker.io
    dkey_present=$(apt-key list | grep -e "Docker" -e "docker\.com" -B 1)
    if [ -n "$dkey_present" ]; then
        yush_info "Removing docker GPG key"
        dkey=$(echo "$dkey_present" | head -1 | awk '{print $9$10}')
        $PRIMER_OS_SUDO apt-key del "$dkey"
    fi

    if [ -f "/etc/apt/sources.list.d/docker.list" ]; then
        yush_info "Removing repo list /etc/apt/sources.list.d/docker.list"
        $PRIMER_OS_SUDO rm -f /etc/apt/sources.list.d/docker.list
    fi

    if grep -q docker /etc/apt/sources.list; then
        yush_info "Removing docker from main repo list at /etc/apt/sources.list"
        listtemp=$(mktemp)
        grep -v "docker" /etc/apt/sources.list > "$listtemp"
        primer_utils_path_ownership "$listtemp" --as /etc/apt/sources.list
        $PRIMER_OS_SUDO mv "$listtemp" /etc/apt/sources.list
    fi
}

_primer_step_docker_install_debian() {
    method=${1:-$PRIMER_STEP_DOCKER_PACKAGING}
    case "$method" in
        "docker")
            _primer_step_docker_install_getdocker
            # On debian we try to ensure that we have the proper
            # repository so we have some additional degree of
            # security.
            lsb_dist=$(primer_os_distribution)
            case "$lsb_dist" in
                *buntu)
                    _primer_step_docker_install_apt_verify;;
                *bian)
                    _primer_step_docker_install_apt_verify;;
                *)
                    yush_warn "Cannot verify proper package provider on $lsb_dist"
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

_primer_step_docker_install_apt_verify() {
    if [ -n "$PRIMER_STEP_DOCKER_APT_GPG" ]; then
        yush_info "Verifying Docker GPG short key against: $(yush_green "$PRIMER_STEP_DOCKER_APT_GPG")"
        dkey=$(apt-key list | grep -e "Docker" -e "docker\.com" -B 1 | head -1 | awk '{print $9$10}')
        if [ "$dkey" != "$PRIMER_STEP_DOCKER_APT_GPG" ]; then
            primer_abort "System might have been compromised, installed short GPG key for Docker was: $dkey"
        fi
    fi
}

_primer_step_docker_install_getdocker() {
    # Download the installation script from getdocker
    yush_info "Downloading and running Docker installation script from $(yush_yellow "$PRIMER_STEP_DOCKER_GET_URL")"
    _get=$(mktemp)
    primer_net_curl "$PRIMER_STEP_DOCKER_GET_URL" -o "$_get"
    if [ -n "$PRIMER_STEP_DOCKER_INSTALL_SHA256" ]; then
        if grep 'SCRIPT_COMMIT_SHA=' "$_get" | grep -q "$PRIMER_STEP_DOCKER_INSTALL_SHA256"; then
            yush_info "Verified Docker installation script, running it now"
            sh "$_get"
        else
            yush_warn "Commit SHA in script diffs from $PRIMER_STEP_DOCKER_INSTALL_SHA256. Maybe a new version? Verify the script and run again with --docker:sha256"
            yush_error "Unable to verify Docker installation script!!"
            rm -f "$_get"
            return 1
        fi
    fi

    # Cleanup
    rm -f "$_get"
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
        _primer_step_docker_plugin_download "$1" || true
    fi

    if ! docker "$1" version >/dev/null 2>&1; then
        yush_warn "Could not install Docker $1 plugin!"
    elif ! _primer_step_docker_plugin_ok "$1"; then
        yush_warn "Installed Docker $1 version mismatch: $(docker "$1" version | head -1)"
    fi
}

# Download the Docker CLI plugin passed as an argument (compose or buildx) from
# github, making sure we can actually execute the binary that we downloaded and
# checking it against its sha256 sum. When no sum is specified, it is read from
# the checksums.txt file of the release.
_primer_step_docker_plugin_download() {
    _var=PRIMER_STEP_DOCKER_$(printf %s "$1" | tr '[:lower:]' '[:upper:]')
    _releases=$(primer_utils_var_value "${_var}_RELEASES")
    _version=$(primer_utils_var_value "${_var}_VERSION")
    if [ -z "$_version" ]; then
        # Following uses the github API
        # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
        # for getting the list of latest releases and focuses solely on
        # "full" releases. Release candidates have -rcXXX in their version
        # number, these are set away by the grep/sed combo.
        yush_notice "Discovering latest Docker $1 version from $_releases"
        _version=$(primer_net_curl "$_releases" |
                    grep -E '"name"[[:space:]]*:[[:space:]]*"v?[0-9]+(\.[0-9]+)*"' |
                    sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"(v?[0-9]+(\.[0-9]+)*)",/\1/g' |
                    head -1)
        if [ -z "$_version" ]; then
            yush_warn "Could not discover latest Docker $1 version"
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
                    awk -v a="$_asset" '{f=$2; sub(/^\*/, "", f); if (f == a) {print $1; exit}}')
        if [ -z "$_sha256" ]; then
            yush_error "Could not find sha256 sum for $_asset in ${_release}/checksums.txt, will not install"
            return 1
        fi
    fi

    yush_info "Installing Docker $1 plugin $_version from $_url"
    _tmpdir=$(mktemp -d)
    _bin="${_tmpdir}/docker-$1"
    if primer_net_curl "$_url" --progress-bar > "$_bin"; then
        yush_debug "Verifying sha256 sum against $_sha256"
        if ! printf "%s  %s\n" "$_sha256" "$_bin" | sha256sum -c -; then
            yush_error "SHA256 sum mismatch, should have been $_sha256"
            rm -f "$_bin"
        fi
        if [ -f "$_bin" ]; then
            # All Docker CLI plugins answer to the metadata sub-command.
            yush_debug "Verifying binary at $_bin"
            chmod a+x "$_bin"
            if ! "$_bin" docker-cli-plugin-metadata >/dev/null 2>&1; then
                yush_warn "Downloaded binary from $_url probably invalid, will not install"
            else
                yush_notice "Installing as ${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-$1"
                ! [ -d "$PRIMER_STEP_DOCKER_PLUGINS_DIR" ] && $PRIMER_OS_SUDO mkdir -p "$PRIMER_STEP_DOCKER_PLUGINS_DIR"
                $PRIMER_OS_SUDO mv -f "$_bin" "${PRIMER_STEP_DOCKER_PLUGINS_DIR%%/}/docker-$1"
            fi
        fi
    else
        yush_warn "No binary at $_url"
    fi
    rm -rf "$_tmpdir"
}
