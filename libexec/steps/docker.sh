#!/usr/bin/env sh

# Short GPG signature for Docker Repo on debian derivatives
PRIMER_STEP_DOCKER_APT_GPG=${PRIMER_STEP_DOCKER_APT_GPG:-0EBFCD88}

# Space separated list of registry login information in the form
# username:password@host
PRIMER_STEP_DOCKER_REGISTRY=${PRIMER_STEP_DOCKER_REGISTRY:-}

# Commit SHA sum contained in script, so we do not run something that has not
# been verified. Every time the installation script is changed, the commit
# sha256 will change, meaning that this variable has to change. Setting it to
# empty will disable the check, which is a security risk as this means executing
# a script downloaded from the Internet...
PRIMER_STEP_DOCKER_INSTALL_SHA256=${PRIMER_STEP_DOCKER_INSTALL_SHA256:-4f282167c425347a931ccfd95cc91fab041d414f}

# Can be native (as in: OS native packaging), docker (as in: docker.com provided
# packages) or auto (as in: pick the best one of both worlds)
PRIMER_STEP_DOCKER_PACKAGING=${PRIMER_STEP_DOCKER_PACKAGING:-auto}

# All regular users matching this regular expression will be made member of the
# docker group. In practice these users will be given root access!
PRIMER_STEP_DOCKER_ACCESS=${PRIMER_STEP_DOCKER_ACCESS:-}

# Where to get the docker installation script from
PRIMER_STEP_DOCKER_GET_URL=https://get.docker.com/

primer_step_docker() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--registry --sha256 --access"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --registry)
                        PRIMER_STEP_DOCKER_REGISTRY="$PRIMER_STEP_DOCKER_REGISTRY $2"; shift 2;;
                    --sha256)
                        PRIMER_STEP_DOCKER_INSTALL_SHA256="$2"; shift 2;;
                    --access)
                        PRIMER_STEP_DOCKER_ACCESS="$2"; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if ! [ -x "$(command -v dockerd)" ]; then
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
                    *buntu)
                        _primer_step_docker_install_debian;;
                    *bian)
                        _primer_step_docker_install_debian;;
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
            if [ -x "$(command -v dockerd)" ]; then
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

                # Bash completion, if necessary
                _docker_version=$(docker --version|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)
                yush_debug "Installing bash completions for Docker v $_docker_version"
                _completion_dir=$(primer_os_bash_completion_dir)
                if ! [ -d "$_completion_dir" ]; then
                    $PRIMER_OS_SUDO mkdir -p "$_completion_dir"
                fi
                if ! [ -f "${_completion_dir}/docker" ]; then
                    primer_net_curl https://raw.githubusercontent.com/docker/docker-ce/v${_docker_version}/components/cli/contrib/completion/bash/docker |
                        $PRIMER_OS_SUDO tee "${_completion_dir}/docker" > /dev/null
                fi
            else
                yush_warn "No docker client installed!"
            fi

            ;;
        "clean")
            # Stop docker and remove from autostart.
            if [ -x "$(command -v dockerd)" ]; then
                if docker info; then
                    yush_info "Stopping Docker daemon"
                    primer_os_service stop docker
                fi
                yush_info "Disabling docker daemon at start"
                primer_os_service disable docker

                lsb_dist=$(primer_os_distribution)
                case "$lsb_dist" in
                    alpine)
                        primer_os_packages del docker;;
                    clear*linux*)
                        primer_os_packages del containers-basic;;
                    *buntu)
                        _primer_step_docker_uninstall_debian;;
                    *bian)
                        _primer_step_docker_uninstall_debian;;
                    *)
                        yush_warn "Cannot remove docker on $lsb_dist"
                        ;;
                esac
            fi
            ;;
    esac
}

_primer_step_docker_uninstall_debian() {
    primer_os_packages del docker-ce-cli docker-ce docker.io
    dkey_present=$(apt-key list | grep -e "Docker" -e "docker\.com" -B 1)
    if [ -n "$dkey_present" ]; then
        yush_info "Removing docker GPG key"
        dkey=$(echo "$dkey_present" | head -1 | awk '{print $9$10}')
        $PRIMER_OS_SUDO apt-key del $dkey
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
    yush_info "Verifying Docker GPG short key against: $(yush_green "$PRIMER_STEP_DOCKER_APT_GPG")"
    dkey=$(apt-key list | grep -e "Docker" -e "docker\.com" -B 1 | head -1 | awk '{print $9$10}')
    if [ "$dkey" != "$PRIMER_STEP_DOCKER_APT_GPG" ]; then
        primer_abort "System might have been compromised, installed short GPG key for Docker was: $dkey"
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
    for pkg in docker.io docker-ce docker-engine docker; do
        candidate=$(primer_os_packages search "$pkg"|head -1)
        if [ -n "$candidate" ]; then
            yush_notice "Picked package $candidate for Docker installation"
            primer_os_packages install "$candidate"
            break
        fi
    done
}