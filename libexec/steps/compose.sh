#!/usr/bin/env sh

# Version of Docker compose to download. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
PRIMER_STEP_COMPOSE_VERSION=${PRIMER_STEP_COMPOSE_VERSION:-}

# SHA256 of the compose binary when downloading from the release repository
PRIMER_STEP_COMPOSE_SHA256=${PRIMER_STEP_COMPOSE_SHA256:-}

# URL to JSON file where to find the list of releases of Docker compose. The
# code only supports github API.
PRIMER_STEP_COMPOSE_RELEASES=https://api.github.com/repos/docker/compose/releases

# Root URL to download location
PRIMER_STEP_COMPOSE_DOWNLOAD=https://github.com/docker/compose/releases/download

# When should we install compose through pip: can be one of never, prefer or
# failure (the default).
PRIMER_STEP_COMPOSE_PYTHON=${PRIMER_STEP_COMPOSE_PYTHON:-failure}

# glibc for Alpine package version to use. Can be set from the outside, defaults
# to empty, meaning the latest as per the variable below.
PRIMER_STEP_COMPOSE_GLIBC_VERSION=${PRIMER_STEP_COMPOSE_GLIBC_VERSION:-}

# URL to JSON file where to find the list of releases of the glibc for Alpine
# packages. The code only supports github API.
PRIMER_STEP_COMPOSE_GLIBC_RELEASES=https://api.github.com/repos/sgerrand/alpine-pkg-glibc/tags

# URL to the public key that has signed the glibc Alpine packages.
PRIMER_STEP_COMPOSE_GLIBC_PUBKEY=https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub


primer_step_compose() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--python --version --sha256"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --python)
                        PRIMER_STEP_COMPOSE_PYTHON=$2; shift 2;;
                    --version)
                        PRIMER_STEP_COMPOSE_VERSION=$2; shift 2;;
                    --sha256)
                        PRIMER_STEP_COMPOSE_SHA256=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if ! [ -x "$(command -v "docker-compose")" ]; then
                if [ -z "$PRIMER_STEP_COMPOSE_VERSION" ]; then
                    # Following uses the github API
                    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
                    # for getting the list of latest releases and focuses solely on
                    # "full" releases. Release candidates have -rcXXX in their version
                    # number, these are set away by the grep/sed combo.
                    yush_notice "Discovering latest Docker Compose version from $PRIMER_STEP_COMPOSE_RELEASES"
                    PRIMER_STEP_COMPOSE_VERSION=$(  primer_net_curl "$PRIMER_STEP_COMPOSE_RELEASES" |
                                        grep -E '"name"[[:space:]]*:[[:space:]]*"[0-9]+(\.[0-9]+)*"' |
                                        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([0-9]+(\.[0-9]+)*)",/\1/g' |
                                        head -1)
                fi
                yush_info "Installing Docker compose $PRIMER_STEP_COMPOSE_VERSION and bash completion"
                case "$PRIMER_STEP_COMPOSE_PYTHON" in
                    prefer)
                        _primer_step_compose_install_python
                        ;;

                    never)
                        _primer_step_compose_install_download
                        ;;

                    failure)
                        _primer_step_compose_install_download
                        if ! [ -x "$(command -v "docker-compose")" ]; then
                            _primer_step_compose_install_python
                        fi
                        ;;
                esac
                # Check version
                yush_debug "Verifying installed version against $PRIMER_STEP_COMPOSE_VERSION"
                if ! docker-compose --version | grep -q "$PRIMER_STEP_COMPOSE_VERSION"; then
                    yush_warn "Installed docker-compose version mismatch: $(docker-compose --version||true|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)"
                fi
            fi

            yush_debug "Installing bash completions"
            _completion_dir=$(primer_os_bash_completion_dir)
            if ! [ -d "$_completion_dir" ]; then
                $PRIMER_OS_SUDO mkdir -p "$_completion_dir"
            fi
            if ! [ -f "${_completion_dir}/docker-compose" ]; then
                primer_net_curl https://raw.githubusercontent.com/docker/compose/v"$PRIMER_STEP_COMPOSE_VERSION"/contrib/completion/bash/docker-compose |
                    $PRIMER_OS_SUDO tee "${_completion_dir}/docker-compose" > /dev/null
            fi
            ;;
        "clean")
            yush_info "Removing Docker Compose and bash completion"
            if [ -f "${PRIMER_BINDIR%%/}/docker-compose" ]; then
                $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/docker-compose"
            else
                $PRIMER_OS_SUDO pip3 uninstall docker-compose
            fi

            _completion_dir=$(primer_os_bash_completion_dir)
            if [ -f "${_completion_dir}/docker-compose" ]; then
                yush_debug "Removing compose command completion"
                $PRIMER_OS_SUDO rm -f "${_completion_dir}/docker-compose"
            fi
            ;;
    esac
}

# Install using pip3. This will only work on debian-derivatives as we need to
# figure out the list of dependent packages on the other distros.
_primer_step_compose_install_python() {
    yush_info "Installing through pip3"
    lsb_dist=$(primer_os_distribution)
    case "$lsb_dist" in
        *bian)
            primer_os_packages add python3 python3-pip libffi-dev libssl-dev build-essential;;
        *buntu)
            primer_os_packages add python3 python3-pip libffi-dev libssl-dev build-essential;;
        *)
            ;;
    esac
    $PRIMER_OS_SUDO pip3 install docker-compose=="$PRIMER_STEP_COMPOSE_VERSION"
}

# Download from github, making sure we can actually execute the binary that we
# downloaded. We download the first byte to check all the redirects, and on
# success we will download everything and possibly check against the sha256 sum.
_primer_step_compose_install_download() {
    lsb_dist=$(primer_os_distribution)
    tmpdir=$(mktemp -d)
    if primer_net_curl "${PRIMER_STEP_COMPOSE_DOWNLOAD%%/}/$PRIMER_STEP_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"  --progress-bar > "${tmpdir}/docker-compose"; then
        # Check against the sha256 sum if necessary.
        if [ -n "$PRIMER_STEP_COMPOSE_SHA256" ]; then
            yush_debug "Verifying sha256 sum"
            if ! printf "%s  %s\n" "${PRIMER_STEP_COMPOSE_SHA256}" "${tmpdir}/docker-compose" | sha256sum -c -; then
                yush_error "SHA256 sum mismatch, should have been $PRIMER_STEP_COMPOSE_SHA256"
                rm -f "${tmpdir}/docker-compose"
            fi
        fi
        if [ -f "${tmpdir}/docker-compose" ]; then
            # Install glibc on Alpine to ensure that docker-compose
            # works.
            if yush_glob 'alpine*' "$lsb_dist"; then
                _primer_step_compose_install_glibc
            fi
            # Verify the binary actually works properly.
            yush_debug "Verifying binary at ${tmpdir}/docker-compose"
            chmod a+x "${tmpdir}/docker-compose"
            if ! "${tmpdir}/docker-compose" --version >/dev/null 2>&1; then
                yush_info "Downloaded binary at ${PRIMER_BINDIR%%/}/docker-compose probaby invalid, will not install"
                rm -f "${tmpdir}/docker-compose"
            else
                yush_notice "Installing as ${PRIMER_BINDIR%%/}/docker-compose"
                ! [ -d "$PRIMER_BINDIR" ] && $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                $PRIMER_OS_SUDO mv -f "${tmpdir}/docker-compose" "${PRIMER_BINDIR%%/}/docker-compose"
            fi
        fi
    else
        yush_warn "No binary at ${PRIMER_STEP_COMPOSE_DOWNLOAD%%/}/$PRIMER_STEP_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"
    fi
    rm -rf "$tmpdir"
}

# Automatically install glibc dependencies in order for docker compose to work
# on Alpine. This looks up the latest version if none was specified at the
# command line.
_primer_step_compose_install_glibc() {
    # Detect latest version
    if [ -z "$PRIMER_STEP_COMPOSE_GLIBC_VERSION" ]; then
        yush_info "Discovering latest glibc support release version"
        PRIMER_STEP_COMPOSE_GLIBC_VERSION=$(    primer_net_curl "$PRIMER_STEP_COMPOSE_GLIBC_RELEASES" --progress-bar |
                            grep -E '"name"[[:space:]]*:[[:space:]]*"[0-9]+(\.[0-9]+)*(-r[0-9])"' |
                            sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([0-9]+(\.[0-9]+)*(-r[0-9]))",/\1/g' |
                            head -1)
    fi

    yush_info "Installing glibc support at version $PRIMER_STEP_COMPOSE_GLIBC_VERSION"
    GLIBC_TMPDIR=$(mktemp -d)
    primer_net_curl "$PRIMER_STEP_COMPOSE_GLIBC_PUBKEY" --progress-bar | $PRIMER_OS_SUDO tee /etc/apk/keys/sgerrand.rsa.pub > /dev/null
    primer_net_curl "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${PRIMER_STEP_COMPOSE_GLIBC_VERSION}/glibc-${PRIMER_STEP_COMPOSE_GLIBC_VERSION}.apk" --progress-bar -o "$GLIBC_TMPDIR/glibc-${PRIMER_STEP_COMPOSE_GLIBC_VERSION}.apk"
    $PRIMER_OS_SUDO apk add "$GLIBC_TMPDIR/glibc-${PRIMER_STEP_COMPOSE_GLIBC_VERSION}.apk"
    primer_net_curl "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${PRIMER_STEP_COMPOSE_GLIBC_VERSION}/glibc-bin-${PRIMER_STEP_COMPOSE_GLIBC_VERSION}.apk" --progress-bar -o "$GLIBC_TMPDIR/glibc-bin-${PRIMER_STEP_COMPOSE_GLIBC_VERSION}.apk"
    $PRIMER_OS_SUDO apk add "$GLIBC_TMPDIR/glibc-bin-${PRIMER_STEP_COMPOSE_GLIBC_VERSION}.apk"
    rm -rf "$GLIBC_TMPDIR"
}
