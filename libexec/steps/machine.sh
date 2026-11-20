#!/usr/bin/env sh

# Version of Docker machine to download. Can be set from the
# outside, defaults to empty, meaning the latest as per the variable below.
PRIMER_STEP_MACHINE_VERSION=${PRIMER_STEP_MACHINE_VERSION:-}

# SHA256 of the machine binary when downloading from the release repository
PRIMER_STEP_MACHINE_SHA256=${PRIMER_STEP_MACHINE_SHA256:-}

# Project of Docker machine at GitHub.
PRIMER_STEP_MACHINE_PROJECT=docker/machine

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
                    PRIMER_STEP_MACHINE_VERSION=$(_primer_step_machine_latest)
                fi
                if [ -n "$PRIMER_STEP_MACHINE_VERSION" ] && \
                    [ "$(primer_version_current "docker-machine")" != "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    _primer_step_machine_install || return 1
                fi
            else
                if [ -z "$PRIMER_STEP_MACHINE_VERSION" ]; then
                    PRIMER_STEP_MACHINE_VERSION=$(_primer_step_machine_latest)
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
            # Only remove Docker machine at the version this step installs,
            # and its completion with it.
            yush_info "Removing Docker machine and bash completion"
            _want=${PRIMER_STEP_MACHINE_VERSION:-$(_primer_step_machine_latest)}
            primer_utils_remove_at_version "${PRIMER_BINDIR%%/}/docker-machine" "$_want"
            _completion_dir=$(primer_os_bash_completion_dir)
            if ! [ -e "${PRIMER_BINDIR%%/}/docker-machine" ] && [ -f "${_completion_dir}/docker-machine" ]; then
                yush_debug "Removing machine command completion"
                $PRIMER_OS_SUDO rm -f "${_completion_dir}/docker-machine"
            fi
            ;;
    esac
}

# Print the latest version of Docker machine, without the leading v.
_primer_step_machine_latest() {
    _latest=$(primer_github_latest "$PRIMER_STEP_MACHINE_PROJECT")
    printf %s\\n "${_latest#v}"
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
    primer_github_install --sum "$PRIMER_STEP_MACHINE_SHA256" --check --version \
        --name docker-machine "$PRIMER_STEP_MACHINE_PROJECT" \
        "v$PRIMER_STEP_MACHINE_VERSION" "$(_primer_step_machine_asset)" docker-machine
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
        primer_net_install_file \
            "https://raw.githubusercontent.com/docker/machine/v${PRIMER_STEP_MACHINE_VERSION}/contrib/completion/bash/docker-machine.bash" \
            "${_completion_dir}/docker-machine" ||
            yush_warn "Could not download bash completion for docker-machine"
    fi
}
