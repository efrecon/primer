#!/usr/bin/env sh

# Short GPG signature for Docker Repo on debian derivatives
DOCKER_APT_GPG=${DOCKER_APT_GPG:-0EBFCD88}

DOCKER_GET_URL=https://get.docker.com/

docker() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
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
                    yush_info "Downloading and running Docker installation script from $(yush_yellow "$DOCKER_GET_URL"), this is a security risk"
                    _get=$(mktemp)
                    curl -fsSL "$DOCKER_GET_URL" -o "$_get"
                    sh "$_get"

                    # On debian we try to ensure that we have the proper
                    # repository so we have some degree of security.
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

            # Start docker and make sure it will always start
            if [ -x "$(command -v dockerd)" ]; then
                if ! docker info; then
                    yush_info "Starting Docker daemon"
                    primer_service start docker
                fi
                yush_info "Enabling docker daemon at start"
                primer_service enable docker
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
            fi

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
                        primer_root_ownership "$listtemp" /etc/apt/sources.list
                        $PRIMER_SUDO mv "$listtemp" /etc/apt/sources.list
                    fi
                    ;;
                *)
                    yush_warn "Cannot remove docker on $lsb_dist"
                    ;;
            esac
            ;;
    esac
}
