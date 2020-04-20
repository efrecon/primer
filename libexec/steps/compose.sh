#!/usr/bin/env sh

# Version of Docker compose to download when not found. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
COMPOSE_VERSION=${COMPOSE_VERSION:-}

# SHA256 of the compose binary when downloading from the release repository
COMPOSE_SHA256=${COMPOSE_SHA256:-}

# URL to JSON file where to find the list of releases of Docker compose. The
# code only supports github API.
COMPOSE_RELEASES=https://api.github.com/repos/docker/compose/releases

# Root URL to download location
COMPOSE_DOWNLOAD=https://github.com/docker/compose/releases/download

# Prefer the pure-python pip3-based installation in all cases. Otherwise, this
# will be what we do when downloading the binary fails.
COMPOSE_PYTHON_PREFER=${COMPOSE_PYTHON_PREFER:-0}

# glibc for Alpine package version to use. Can be set from the outside, defaults
# to empty, meaning the latest as per the variable below.
GLIBC_VERSION=${GLIBC_VERSION:-}

# URL to JSON file where to find the list of releases of the glibc for Alpine
# packages. The code only supports github API.
GLIBC_RELEASES=https://api.github.com/repos/sgerrand/alpine-pkg-glibc/tags

# URL to the public key that has signed the glibc Alpine packages.
GLIBC_PUBKEY=https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub


compose() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --python)
                        COMPOSE_PYTHON_PREFER=$2; shift 2;;
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
            if ! [ -x "$(command -v "docker-compose")" ]; then
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
                if ! yush_is_true "$COMPOSE_PYTHON_PREFER"; then
                    # Try downloadling from github first, making sure we can
                    # actually execute the binary that we downloaded. We
                    # download the first byte to check all the redirects, and on
                    # success we will download everything and possibly check
                    # against the sha256 sum.
                    ! [ -d "$PRIMER_BINDIR" ] && $PRIMER_SUDO mkdir -p "$PRIMER_BINDIR"
                    if curl -fsSL  "${COMPOSE_DOWNLOAD%%/}/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -r 0-0 >/dev/null 2>&1; then
                        curl --progress-bar -fSL "${COMPOSE_DOWNLOAD%%/}/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" |
                            $PRIMER_SUDO tee "${PRIMER_BINDIR%%/}/docker-compose" > /dev/null
                        # Check against the sha256 sum if necessary.
                        if [ -n "$COMPOSE_SHA256" ]; then
                            yush_debug "Verifying sha256 sum"
                            if ! printf "%s  %s\n" "${COMPOSE_SHA256}" "${PRIMER_BINDIR%%/}/docker-compose" | sha256sum -c -; then
                                yush_error "SHA256 sum mismatch, should have been $COMPOSE_SHA256"
                                $PRIMER_SUDO rm -f "${PRIMER_BINDIR%%/}/docker-compose"
                            fi
                        fi
                        # Install glibc on Alpine to ensure that docker-compose
                        # works.
                        if yush_glob 'alpine*' "$lsb_dist"; then
                            _compose_glibc_install
                        fi
                        # Verify the binary actually works properly.
                        if [ -f "${PRIMER_BINDIR%%/}/docker-compose" ]; then
                            yush_debug "Verifying binary at ${PRIMER_BINDIR%%/}/docker-compose"
                            chmod a+x "${PRIMER_BINDIR%%/}/docker-compose"
                            if ! "${PRIMER_BINDIR%%/}/docker-compose" --version >/dev/null 2>&1; then
                                yush_info "Downloaded binary at ${PRIMER_BINDIR%%/}/docker-compose probaby invalid, removing"
                                $PRIMER_SUDO rm -f "${PRIMER_BINDIR%%/}/docker-compose"
                            fi
                        fi
                    fi
                fi

                # It failed, install the hard way through pip3. This has
                # dependencies, so we need to be distro specific.
                if ! [ -x "${PRIMER_BINDIR%%/}/docker-compose" ]; then
                    yush_info "Direct installation from $COMPOSE_DOWNLOAD failed, installing through pip3"
                    case "$lsb_dist" in
                        ubuntu|*bian)
                            primer_packages add python3 python3-pip libffi-dev libssl-dev build-essential
                            ;;
                        *)
                            ;;
                    esac
                    $PRIMER_SUDO pip3 install docker-compose=="$COMPOSE_VERSION"
                fi

                # Check version
                yush_debug "Verifying installed version against $COMPOSE_VERSION"
                if ! docker-compose --version | grep -q "$COMPOSE_VERSION"; then
                    yush_warn "Installed docker-compose version mismatch: $(docker-compose --version||true|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)"
                fi
            fi

            yush_debug "Installing bash completions"
            _completion_dir=$(_compose_completion_dir)
            ! [ -d "$_completion_dir" ] && \
                    $PRIMER_SUDO mkdir -p "$_completion_dir"
            ! [ -f "${_completion_dir}/docker-compose" ] && \
                    curl -sSL https://raw.githubusercontent.com/docker/compose/v"$COMPOSE_VERSION"/contrib/completion/bash/docker-compose |
                        $PRIMER_SUDO tee ${_completion_dir}/docker-compose > /dev/null
            ;;
        "clean")
            yush_info "Removing Docker Compose and bash completion"
            if [ -f "${PRIMER_BINDIR%%/}/docker-compose" ]; then
                $PRIMER_SUDO rm -f "${PRIMER_BINDIR%%/}/docker-compose"
            else
                $PRIMER_SUDO pip3 uninstall docker-compose
            fi

            _completion_dir=$(_compose_completion_dir)
            if [ -f "${_completion_dir}/docker-compose" ]; then
                yush_debug "Removing compose command completion"
                $PRIMER_SUDO rm -f "${_completion_dir}/docker-compose"
            fi
            ;;
    esac
}

# Automatically install glibc dependencies in order for docker compose to work
# on Alpine. This looks up the latest version if none was specified at the
# command line.
_compose_glibc_install() {
    # Detect latest version
    if [ -z "$GLIBC_VERSION" ]; then
        yush_info "Discovering latest glibc support release version"
        GLIBC_VERSION=$(    curl -fSL --progress-bar "$GLIBC_RELEASES" |
                            grep -E '"name"[[:space:]]*:[[:space:]]*"[0-9]+(\.[0-9]+)*(-r[0-9])"' |
                            sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([0-9]+(\.[0-9]+)*(-r[0-9]))",/\1/g' |
                            head -1)
    fi

    yush_info "Installing glibc support at version $GLIBC_VERSION"
    GLIBC_TMPDIR=$(mktemp -d)
    $PRIMER_SUDO curl -fSL --progress-bar "$GLIBC_PUBKEY" -o /etc/apk/keys/sgerrand.rsa.pub
    curl -fSL --progress-bar "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk" -o "$GLIBC_TMPDIR/glibc-${GLIBC_VERSION}.apk"
    $PRIMER_SUDO apk add "$GLIBC_TMPDIR/glibc-${GLIBC_VERSION}.apk"
    curl -fSL --progress-bar "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk" -o "$GLIBC_TMPDIR/glibc-bin-${GLIBC_VERSION}.apk"
    $PRIMER_SUDO apk add "$GLIBC_TMPDIR/glibc-bin-${GLIBC_VERSION}.apk"
    rm -rf "$GLIBC_TMPDIR"
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