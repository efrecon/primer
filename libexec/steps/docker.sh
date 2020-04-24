#!/usr/bin/env sh

# Short GPG signature for Docker Repo on debian derivatives
DOCKER_APT_GPG=${DOCKER_APT_GPG:-0EBFCD88}

# Space separated list of registry login information in the form
# username:password@host
DOCKER_REGISTRY=${DOCKER_REGISTRY:-}

# Commit SHA sum contained in script, so we do not run something that has not
# been verified.
DOCKER_INSTALL_SHA256=${DOCKER_INSTALL_SHA256:-442e66405c304fa92af8aadaa1d9b31bf4b0ad94}

DOCKER_ACCESS_ALL_USERS=${DOCKER_ACCESS_ALL_USERS:-1}

# Where to get the docker installation script from
DOCKER_GET_URL=https://get.docker.com/

docker() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --registry)
                        DOCKER_REGISTRY="$DOCKER_REGISTRY $2"; shift 2;;
                    --sha256)
                        DOCKER_INSTALL_SHA256="$2"; shift 2;;
                    --access)
                        DOCKER_ACCESS_ALL_USERS="$2"; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if ! [ -x "$(command -v dockerd)" ]; then
                lsb_dist=$(primer_distribution)
                case "$lsb_dist" in
                    alpine)
                        primer_packages add docker
                        ;;
                    clear*linux*)
                        primer_packages add containers-basic
                        ;;
                    *)
                        # Ensure we have curl
                        primer_dependency curl

                        # Download the installation script from getdocker
                        yush_info "Downloading and running Docker installation script from $(yush_yellow "$DOCKER_GET_URL")"
                        _get=$(mktemp)
                        curl -fsSL "$DOCKER_GET_URL" -o "$_get"
                        if [ -n "$DOCKER_INSTALL_SHA" ]; then
                            if grep 'SCRIPT_COMMIT_SHA=' "$_get" | grep -q "$DOCKER_INSTALL_SHA256"; then
                                yush_info "Verified Docker installation script, running it now"
                                sh "$_get"
                            else
                                yush_warn "Commit SHA in script diffs from $DOCKER_INSTALL_SHA256. Maybe a new version? Verify the script and run again with --docker:sha256"
                                yush_error "Unable to verify Docker installation script!!"
                                return 1
                            fi
                        fi

                        # On debian we try to ensure that we have the proper
                        # repository so we have some additional degree of
                        # security.
                        case "$lsb_dist" in
                            ubuntu|*bian)
                                yush_info "Verifying Docker GPG short key against: $(yush_green $DOCKER_APT_GPG)"
                                dkey=$(apt-key list | grep -e "Docker" -e "docker\.com" -B 1 | head -1 | awk '{print $9$10}')
                                if [ "$dkey" != "$DOCKER_APT_GPG" ]; then
                                    abort "System might have been compromised, installed short GPG key for Docker was: $dkey"
                                fi
                                ;;
                            *)
                                yush_warn "Cannot verify proper package provider on $lsb_dist"
                                ;;
                        esac

                        rm -f "$_get"
                        ;;
                esac
            fi

            # Start docker and make sure it will always start
            if [ -x "$(command -v dockerd)" ]; then
                if ! docker info; then
                    yush_info "Starting Docker daemon"
                    primer_service start docker
                fi
                yush_info "Enabling docker daemon at start"
                primer_service enable docker
            fi

            # Perform user operations only if we have a docker client installed.
            # Note that we cannot detect, nor call the docker client with the
            # single string "docker" since it is the name of the function
            # implemented by this module.
            _docker_bin=$(which docker || true)
            if [ -n "$_docker_bin" ]; then
                # Create group and make sure user is part of the group
                primer_group_create docker
                primer_group_membership "$(id -un)" docker
                if yush_is_true "$DOCKER_ACCESS_ALL_USERS"; then
                    yush_debug "Adding all regular users on system to group docker"
                    primer_users | grep -v "$(id -un)" | while IFS= read -r _username; do
                        primer_group_membership "$_username" docker
                    done
                else
                    yush_info "Only $(id -un) has access to Docker"
                fi

                # Arrange for access to docker registries
                _config=${DOCKER_CONFIG:-"$HOME/.docker"}/config.json
                _prior_settings=0; [ -f "$_config" ] && _prior_settings=1
                for _registry in $DOCKER_REGISTRY; do
                    _user=$(printf %s\\n "$_registry" | sed -E -e 's/([^:]+)(:([^@]+))?@((([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])+)/\1/')
                    _pass=$(printf %s\\n "$_registry" | sed -E -e 's/([^:]+)(:([^@]+))?@((([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])+)/\3/')
                    _host=$(printf %s\\n "$_registry" | sed -E -e 's/([^:]+)(:([^@]+))?@((([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])+)/\4/')
                    yush_info "Logging in at $_host as $_user"
                    printf %s\\n "$_pass" | "$_docker_bin" login --password-stdin -u "$_user" "$_host"
                done

                if [ "$_prior_settings" = "0" ]; then
                    primer_users | grep -v "$(id -un)" | while IFS= read -r _username; do
                        _home=$(getent passwd | grep -E "^${_username}:" | cut -d ":" -f 6)
                        if ! [ -f "$_home/.docker/config.json" ]; then
                            $PRIMER_SUDO mkdir -p "$_home/.docker"
                            $PRIMER_SUDO cp "$_config" "$_home/.docker/config.json"
                            primer_ownership "$_home/.docker/config.json" --as "$_config" --user "$_username"
                            yush_info "Local user $_username logged in at all Docker registries from above"
                        else
                            yush_warn "Skipped login for $_username, found existing settings at $_home/.docker/config.json"
                        fi
                    done
                else
                    yush_warn "Will not copy private Docker settings information to other users"
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
                    primer_service stop docker
                fi
                yush_info "Disabling docker daemon at start"
                primer_service disable docker

                lsb_dist=$(primer_distribution)
                case "$lsb_dist" in
                    alpine)
                        primer_packages del docker
                        ;;
                    clear*linux*)
                        primer_packages del containers-basic
                        ;;
                    ubuntu|*bian)
                        primer_packages del docker-ce-cli docker-ce
                        dkey_present=$(apt-key list | grep -e "Docker" -e "docker\.com" -B 1)
                        if [ -n "$dkey_present" ]; then
                            yush_info "Removing docker GPG key"
                            dkey=$(echo "$dkey_present" | head -1 | awk '{print $9$10}')
                            $PRIMER_SUDO apt-key del $dkey
                        fi

                        if [ -f "/etc/apt/sources.list.d/docker.list" ]; then
                            yush_info "Removing repo list /etc/apt/sources.list.d/docker.list"
                            $PRIMER_SUDO rm -f /etc/apt/sources.list.d/docker.list
                        fi

                        if grep -q docker /etc/apt/sources.list; then
                            yush_info "Removing docker from main repo list at /etc/apt/sources.list"
                            listtemp=$(mktemp)
                            grep -v "docker" /etc/apt/sources.list > "$listtemp"
                            primer_ownership "$listtemp" --as /etc/apt/sources.list
                            $PRIMER_SUDO mv "$listtemp" /etc/apt/sources.list
                        fi
                        ;;
                    *)
                        yush_warn "Cannot remove docker on $lsb_dist"
                        ;;
                esac
            fi
            ;;
    esac
}
