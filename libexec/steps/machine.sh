#!/usr/bin/env sh

# Version of Docker machine to download. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
PRIMER_STEP_MACHINE_VERSION=${PRIMER_STEP_MACHINE_VERSION:-}

# SHA256 of the machine binary when downloading from the release repository
PRIMER_STEP_MACHINE_SHA256=${PRIMER_STEP_MACHINE_SHA256:-}

# URL to JSON file where to find the list of releases of Docker machine. The
# code only supports github API.
PRIMER_STEP_MACHINE_RELEASES=https://api.github.com/repos/docker/machine/releases

# Root URL to download location
PRIMER_STEP_MACHINE_DOWNLOAD=https://github.com/docker/machine/releases/download

primer_step_machine() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--version --sha256"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --version)
                        PRIMER_STEP_MACHINE_VERSION=$2; shift 2;;
                    --sha256)
                        PRIMER_STEP_MACHINE_SHA256=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -x "$(command -v "docker-machine")" ]; then
                if [ -z "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    PRIMER_STEP_MACHINE_VERSION=$(primer_version_github_latest "$PRIMER_STEP_MACHINE_RELEASES" "docker-machine")
                fi
                if [ -n "$PRIMER_STEP_MACHINE_VERSION" ] && \
                    [ "$(primer_version_current "docker-machine")" != "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    _primer_step_machine_install
                fi
            else
                if [ -z "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    PRIMER_STEP_MACHINE_VERSION=$(primer_version_github_latest "$PRIMER_STEP_MACHINE_RELEASES" "docker-machine")
                fi
                if [ -n "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    _primer_step_machine_install
                fi
            fi
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
_primer_step_machine_install_download() {
    tmpdir=$(mktemp -d)
    if primer_net_curl "${PRIMER_STEP_MACHINE_DOWNLOAD%%/}/v$PRIMER_STEP_MACHINE_VERSION/docker-machine-$(uname -s)-$(uname -m)" > "${tmpdir}/docker-machine"; then
        # Check against the sha256 sum if necessary.
        if [ -n "$PRIMER_STEP_MACHINE_SHA256" ]; then
            yush_debug "Verifying sha256 sum"
            if ! printf "%s  %s\n" "${PRIMER_STEP_MACHINE_SHA256}" "${tmpdir}/docker-machine" | sha256sum -c -; then
                yush_error "SHA256 sum mismatch, should have been $PRIMER_STEP_MACHINE_SHA256"
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
        yush_warn "No binary at ${PRIMER_STEP_MACHINE_DOWNLOAD%%/}/v$PRIMER_STEP_MACHINE_VERSION/docker-machine-$(uname -s)-$(uname -m)"
    fi
    rm -rf "$tmpdir"
}

_primer_step_machine_install() {
    yush_info "Installing Docker machine $PRIMER_STEP_MACHINE_VERSION and bash completion"
    _primer_step_machine_install_download

    # Check version
    yush_debug "Verifying installed version against $PRIMER_STEP_MACHINE_VERSION"
    instver=$(primer_version_current "${PRIMER_BINDIR%%/}/docker-machine")
    yush_info "Installed docker-machine v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/docker-machine"
    if [ "$instver" != "$PRIMER_STEP_MACHINE_VERSION" ]; then
        yush_warn "Installed docker-machine version mismatch: should have been $PRIMER_STEP_MACHINE_VERSION"
    fi

    yush_debug "Installing bash completions"
    _completion_dir=$(primer_os_bash_completion_dir)
    ! [ -d "$_completion_dir" ] && \
            $PRIMER_OS_SUDO mkdir -p "$_completion_dir"
    ! [ -f "${_completion_dir}/docker-machine" ] && \
            primer_net_curl https://raw.githubusercontent.com/docker/machine/v"$PRIMER_STEP_MACHINE_VERSION"/contrib/completion/bash/docker-machine.bash |
                $PRIMER_OS_SUDO tee "${_completion_dir}/docker-machine" > /dev/null
}
