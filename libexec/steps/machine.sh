#!/usr/bin/env sh

# Version of Docker machine to download. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
MACHINE_VERSION=${MACHINE_VERSION:-}

# SHA256 of the machine binary when downloading from the release repository
MACHINE_SHA256=${MACHINE_SHA256:-}

# URL to JSON file where to find the list of releases of Docker compose. The
# code only supports github API.
MACHINE_RELEASES=https://api.github.com/repos/docker/machine/releases

# Root URL to download location
MACHINE_DOWNLOAD=https://github.com/docker/machine/releases/download

# Decide curl options depending on log-level
if yush_loglevel_le verbose; then
    MACHINE_CURL_OPTS="-fSL --progress-bar"
else
    MACHINE_CURL_OPTS=-sSL
fi

machine() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --version)
                        MACHINE_VERSION=$2; shift 2;;
                    --sha256)
                        MACHINE_SHA256=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            primer_os_dependency curl
            if ! [ -x "$(command -v "docker-machine")" ]; then
                if [ -z "$MACHINE_VERSION" ]; then
                    # Following uses the github API
                    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
                    # for getting the list of latest releases and focuses solely on
                    # "full" releases. Release candidates have -rcXXX in their version
                    # number, these are set away by the grep/sed combo.
                    yush_notice "Discovering latest Docker Machine version from $MACHINE_RELEASES"
                    MACHINE_VERSION=$(  curl $MACHINE_CURL_OPTS "$MACHINE_RELEASES" |
                                        grep -E '"name"[[:space:]]*:[[:space:]]*"v[0-9]+(\.[0-9]+)*"' |
                                        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"v([0-9]+(\.[0-9]+)*)",/\1/g' |
                                        head -1)
                fi
                yush_info "Installing Docker machine $MACHINE_VERSION and bash completion"
                _machine_install_download
                # Check version
                yush_debug "Verifying installed version against $MACHINE_VERSION"
                if ! docker-machine --version | grep -q "$MACHINE_VERSION"; then
                    yush_warn "Installed docker-machine version mismatch: $(docker-machine --version||true|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)"
                fi
            fi

            yush_debug "Installing bash completions"
            _completion_dir=$(primer_os_bash_completion_dir)
            ! [ -d "$_completion_dir" ] && \
                    $PRIMER_OS_SUDO mkdir -p "$_completion_dir"
            ! [ -f "${_completion_dir}/docker-machine" ] && \
                    curl $MACHINE_CURL_OPTS https://raw.githubusercontent.com/docker/machine/v"$MACHINE_VERSION"/contrib/completion/bash/docker-machine |
                        $PRIMER_OS_SUDO tee "${_completion_dir}/docker-machine" > /dev/null
            ;;
        "clean")
            yush_info "Removing Docker Compose and bash completion"
            if [ -f "${PRIMER_BINDIR%%/}/docker-machine" ]; then
                $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/docker-machine"
            fi

            _completion_dir=$(primer_os_bash_completion_dir)
            if [ -f "${_completion_dir}/docker-machine" ]; then
                yush_debug "Removing machine command completion"
                $PRIMER_OS_SUDO rm -f "${_completion_dir}/docker-machine"
            fi
            ;;
    esac
}

# Download from github, making sure we can actually execute the binary that we
# downloaded. We download the first byte to check all the redirects, and on
# success we will download everything and possibly check against the sha256 sum.
_machine_install_download() {
    tmpdir=$(mktemp -d)
    if curl $MACHINE_CURL_OPTS "${MACHINE_DOWNLOAD%%/}/v$MACHINE_VERSION/docker-machine-$(uname -s)-$(uname -m)" > "${tmpdir}/docker-machine"; then
        # Check against the sha256 sum if necessary.
        if [ -n "$MACHINE_SHA256" ]; then
            yush_debug "Verifying sha256 sum"
            if ! printf "%s  %s\n" "${MACHINE_SHA256}" "${tmpdir}/docker-machine" | sha256sum -c -; then
                yush_error "SHA256 sum mismatch, should have been $MACHINE_SHA256"
                rm -f "${tmpdir}/docker-machine"
            fi
        fi
        if [ -f "${tmpdir}/docker-machine" ]; then
            # Verify the binary actually works properly.
            yush_debug "Verifying binary at ${tmpdir}/docker-machine"
            chmod a+x "${tmpdir}/docker-machine"
            if ! "${tmpdir}/docker-machine" --version >/dev/null 2>&1; then
                yush_info "Downloaded binary at ${PRIMER_BINDIR%%/}/docker-machine probaby invalid, will not install"
                rm -f "${tmpdir}/docker-machine"
            else
                yush_notice "Installing as ${PRIMER_BINDIR%%/}/docker-machine"
                ! [ -d "$PRIMER_BINDIR" ] && $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                $PRIMER_OS_SUDO mv -f "${tmpdir}/docker-machine" "${PRIMER_BINDIR%%/}/docker-machine"
            fi
        fi
    else
        yush_warn "No binary at ${MACHINE_DOWNLOAD%%/}/v$MACHINE_VERSION/docker-machine-$(uname -s)-$(uname -m)"
    fi
    rm -rf "$tmpdir"
}
