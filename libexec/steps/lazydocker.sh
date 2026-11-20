#!/usr/bin/env sh

# Version of lazydocker to download. Can be set from the outside, defaults to
# empty, meaning the latest release.
PRIMER_STEP_LAZYDOCKER_VERSION=${PRIMER_STEP_LAZYDOCKER_VERSION:-}

# Project of lazydocker at GitHub.
PRIMER_STEP_LAZYDOCKER_PROJECT=jesseduffield/lazydocker

primer_step_lazydocker() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--version"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --version)
                        PRIMER_STEP_LAZYDOCKER_VERSION=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -z "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                PRIMER_STEP_LAZYDOCKER_VERSION=$(primer_github_latest "$PRIMER_STEP_LAZYDOCKER_PROJECT")
                PRIMER_STEP_LAZYDOCKER_VERSION=${PRIMER_STEP_LAZYDOCKER_VERSION#v}
                if [ -z "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                    yush_error "Could not find the latest version of lazydocker"
                    return 1
                fi
            fi
            if [ -x "$(command -v "lazydocker")" ] && \
                    [ "$(primer_version_current "lazydocker")" = "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                yush_debug "lazydocker $PRIMER_STEP_LAZYDOCKER_VERSION already installed"
            else
                _primer_step_lazydocker_install || return 1
            fi
            ;;
        "clean")
            # Only remove lazydocker at the version this step installs.
            _want=${PRIMER_STEP_LAZYDOCKER_VERSION:-$(primer_github_latest "$PRIMER_STEP_LAZYDOCKER_PROJECT")}
            primer_utils_remove_at_version "${PRIMER_BINDIR%%/}/lazydocker" "$_want"
            ;;
    esac
}

# Download from github, verify the tarpack against the checksums of the release
# and install the binary from it. Fails, installing nothing, when any of this
# fails.
_primer_step_lazydocker_install_download() {
    _arch=$(uname -m)
    case "$_arch" in
        aarch64|arm64) _arch=arm64;;
        armv7*) _arch=armv7;;
        armv6*) _arch=armv6;;
        i?86) _arch=x86;;
    esac
    primer_github_install --sum checksums.txt "$PRIMER_STEP_LAZYDOCKER_PROJECT" \
        "v$PRIMER_STEP_LAZYDOCKER_VERSION" \
        "lazydocker_${PRIMER_STEP_LAZYDOCKER_VERSION}_$(uname -s)_${_arch}.tar.gz" \
        lazydocker
}

_primer_step_lazydocker_install() {
    yush_info "Installing lazydocker $PRIMER_STEP_LAZYDOCKER_VERSION"
    _primer_step_lazydocker_install_download || return 1
    # Check version
    yush_debug "Verifying installed version against $PRIMER_STEP_LAZYDOCKER_VERSION"
    instver=$(primer_version_current "${PRIMER_BINDIR%%/}/lazydocker")
    yush_info "Installed lazydocker v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/lazydocker"
    if [ "$instver" != "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
        yush_warn "Installed lazydocker version mismatch: should have been $PRIMER_STEP_LAZYDOCKER_VERSION"
    fi
}
