#!/usr/bin/env sh

# Version of Docker compose to download when not found. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
COMPOSE_VERSION=${COMPOSE_VERSION:-}

# URL to JSON file where to find the list of releases of Docker compose. The
# code only supports github API.
COMPOSE_RELEASES=https://api.github.com/repos/docker/compose/releases

compose() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --python)
                        COMPOSE_PYTHON=$2; shift 2;;
                    --version)
                        COMPOSE_VERSION=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !";;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -z "$COMPOSE_VERSION" ]; then
                primer_dependency curl
                # Following uses the github API
                # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
                # for getting the list of latest releases and focuses solely on
                # "full" releases. Release candidates have -rcXXX in their version
                # number, these are set away by the grep/sed combo.
                yush_notice "Discovering latest Docker Compose version from $COMPOSE_RELEASES"
                COMPOSE_VERSION=$(  curl -sSL "$COMPOSE_RELEASES" |
                                    grep -E '"name"[[:space:]]*:[[:space:]]*"[0-9]+(\.[0-9]+)*"' |
                                    sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([0-9]+(\.[0-9]+)*)",/\1/g' |
                                    head -1)
            fi
            yush_info "Installing Docker compose $COMPOSE_VERSION and bash completion"
            lsb_dist=$(primer_distribution)
            case "$lsb_dist" in
                alpine)
                    primer_packages add python libffi-dev libssl-dev build-essential
                    $PRIMER_SUDO pip3 install docker-compose=="$COMPOSE_VERSION"
                    ;;
                *)
                    ! [ -d "$PRIMER_BINDIR" ] && $PRIMER_SUDO mkdir -p "$PRIMER_BINDIR"
                    curl --progress-bar -fSL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" | $PRIMER_SUDO tee "${PRIMER_BINDIR%%/}/docker-compose" > /dev/null
                    chmod a+x "${PRIMER_BINDIR%%/}/docker-compose"
                    if ! "${PRIMER_BINDIR%%/}/docker-compose" --version | grep -q "$COMPOSE_VERSION"; then
                        yush_warn "Installed docker-compose version mismatch: $("${PRIMER_BINDIR%%/}/docker-compose" --version|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)"
                    fi
                    ;;
            esac

            _completion_dir=$(_compose_completion_dir)
            ! [ -d "$_completion_dir" ] && $PRIMER_SUDO mkdir -p "$_completion_dir"
            curl -sSL https://raw.githubusercontent.com/docker/compose/v"$COMPOSE_VERSION"/contrib/completion/bash/docker-compose | $PRIMER_SUDO tee ${_completion_dir}/docker-compose > /dev/null
            ;;
        "clean")
            yush_info "Removing Docker Compose and bash completion"
            lsb_dist=$(primer_distribution)
            case "$lsb_dist" in
                alpine)
                    $PRIMER_SUDO pip3 uninstall docker-compose
                    ;;
                *)
                    [ -x "${PRIMER_BINDIR%%/}/docker-compose" ] && rm -f "${PRIMER_BINDIR%%/}/docker-compose"
                    ;;
            esac
            _completion_dir=$(_compose_completion_dir)
            if [ -f "${_completion_dir}/docker-compose" ]; then
                yush_debug "Removing compose command completion"
                $PRIMER_SUDO rm -f "${_completion_dir}/docker-compose"
            fi
            ;;
    esac
}

_compose_completion_dir() {
    lsb_dist=$(primer_distribution)
        case "$lsb_dist" in
        clear*linux*)
            _completion_dir=/usr/share/bash-completion/completions;;
        *)
            _completion_dir=/etc/bash_completion.d;;
    esac
    printf %s\\n "$_completion_dir"
}