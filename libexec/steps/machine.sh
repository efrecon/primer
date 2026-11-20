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
                    _primer_step_machine_install || return 1
                fi
            else
                if [ -z "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    PRIMER_STEP_MACHINE_VERSION=$(primer_version_github_latest "$PRIMER_STEP_MACHINE_RELEASES" "docker-machine")
                fi
                if [ -n "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    _primer_step_machine_install || return 1
                else
                    yush_error "Could not find the latest version of Docker machine"
                    return 1
                fi
            fi
            ;;
        "clean")
            yush_info "Removing Docker machine and bash completion"
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

# Print the name of the release asset for the current OS and architecture, as
# named in the releases of Docker machine, e.g. docker-machine-Linux-armhf.
_primer_step_machine_asset() {
    case "$(uname -m)" in
        armv6*|armv7*) _arch=armhf;;
        arm64) _arch=aarch64;;
        amd64) _arch=x86_64;;
        *) _arch=$(uname -m);;
    esac
    printf 'docker-machine-%s-%s\n' "$(uname -s)" "$_arch"
}

# Download from github, making sure we can actually execute the binary that we
# downloaded and possibly check against the sha256 sum. Fails, installing
# nothing, when any of this fails.
_primer_step_machine_install_download() {
    _url="${PRIMER_STEP_MACHINE_DOWNLOAD%%/}/v$PRIMER_STEP_MACHINE_VERSION/$(_primer_step_machine_asset)"
    _tmpdir=$(mktemp -d)
    _bin="${_tmpdir}/docker-machine"
    _rc=1
    if ! primer_net_curl "$_url" > "$_bin"; then
        yush_error "No binary at $_url"
    elif [ -n "$PRIMER_STEP_MACHINE_SHA256" ] \
            && [ "$(sha256sum < "$_bin" | cut -d " " -f 1)" != "$PRIMER_STEP_MACHINE_SHA256" ]; then
        yush_error "SHA256 sum mismatch, should have been $PRIMER_STEP_MACHINE_SHA256"
    else
        # Verify the binary actually works properly.
        yush_debug "Verifying binary at $_bin"
        chmod a+x "$_bin"
        if ! "$_bin" --version >/dev/null 2>&1; then
            yush_error "Downloaded binary from $_url probably invalid, will not install"
        else
            yush_notice "Installing as ${PRIMER_BINDIR%%/}/docker-machine"
            if ! [ -d "$PRIMER_BINDIR" ]; then
                $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
            fi
            primer_utils_install_bin "$_bin" "${PRIMER_BINDIR%%/}/docker-machine"
            _rc=0
        fi
    fi
    rm -rf "$_tmpdir"
    return "$_rc"
}

_primer_step_machine_install() {
    yush_info "Installing Docker machine $PRIMER_STEP_MACHINE_VERSION and bash completion"
    _primer_step_machine_install_download || return 1

    # Check version
    yush_debug "Verifying installed version against $PRIMER_STEP_MACHINE_VERSION"
    instver=$(primer_version_current "${PRIMER_BINDIR%%/}/docker-machine")
    yush_info "Installed docker-machine v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/docker-machine"
    if [ "$instver" != "$PRIMER_STEP_MACHINE_VERSION" ]; then
        yush_warn "Installed docker-machine version mismatch: should have been $PRIMER_STEP_MACHINE_VERSION"
    fi

    # Bash completion, through a temporary file: never leave an empty or
    # partial file behind.
    yush_debug "Installing bash completions"
    _completion_dir=$(primer_os_bash_completion_dir)
    if ! [ -f "${_completion_dir}/docker-machine" ]; then
        _completion=$(mktemp)
        if primer_net_curl "https://raw.githubusercontent.com/docker/machine/v${PRIMER_STEP_MACHINE_VERSION}/contrib/completion/bash/docker-machine.bash" > "$_completion" \
                && [ -s "$_completion" ]; then
            if ! [ -d "$_completion_dir" ]; then
                $PRIMER_OS_SUDO mkdir -p "$_completion_dir"
            fi
            primer_utils_sysfile_replace "${_completion_dir}/docker-machine" < "$_completion"
        else
            yush_warn "Could not download bash completion for docker-machine"
        fi
        rm -f "$_completion"
    fi
}
