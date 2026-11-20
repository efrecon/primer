#!/usr/bin/env sh

# Version of micro to download. Can be set from the outside, defaults to
# empty, meaning the latest release.
PRIMER_STEP_MICRO_VERSION=${PRIMER_STEP_MICRO_VERSION:-}

# Project of micro at GitHub.
PRIMER_STEP_MICRO_PROJECT=micro-editor/micro

primer_step_micro() {
    case "$1" in
        "option")
            shift;
            [ "$#" = "0" ] && echo "--version"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --version)
                        PRIMER_STEP_MICRO_VERSION=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            if [ -z "$PRIMER_STEP_MICRO_VERSION" ]; then
                PRIMER_STEP_MICRO_VERSION=$(primer_github_latest "$PRIMER_STEP_MICRO_PROJECT")
                PRIMER_STEP_MICRO_VERSION=${PRIMER_STEP_MICRO_VERSION#v}
                if [ -z "$PRIMER_STEP_MICRO_VERSION" ]; then
                    yush_error "Could not find the latest version of micro"
                    return 1
                fi
            fi
            if [ -x "$(command -v "micro")" ] && \
                    [ "$(primer_version_current "micro")" = "$PRIMER_STEP_MICRO_VERSION" ]; then
                yush_debug "micro $PRIMER_STEP_MICRO_VERSION already installed"
            else
                _primer_step_micro_install || return 1
            fi
            ;;
        "clean")
            # Only remove micro at the version this step installs.
            _want=${PRIMER_STEP_MICRO_VERSION:-$(primer_github_latest "$PRIMER_STEP_MICRO_PROJECT")}
            primer_utils_remove_at_version "${PRIMER_BINDIR%%/}/micro" "$_want"
            ;;
    esac
}

# Download from github, verify the tarpack against the .sha file published
# next to it, and install the binary from it. Fails, installing nothing, when
# any of this fails.
_primer_step_micro_install_download() {
    ostype=$(printf %s\\n "$(uname -s)" | tr '[:upper:]' '[:lower:]')
    case "$(uname -m)" in
        x86_64|amd64)
            _tar="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}64-static.tar.gz";;
        i?86|x86)
            _tar="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}32.tar.gz";;
        armv8*|aarch*)
            _tar="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}-arm64.tar.gz";;
        armv7*|armv6*)
            _tar="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}-arm.tar.gz";;
        *)
            yush_error "No known binaries on this platform"; return 1;;
    esac

    # The .sha file next to the tarpack contains: <sha256>  <file>
    primer_github_install --sum '%asset%.sha' "$PRIMER_STEP_MICRO_PROJECT" \
        "v$PRIMER_STEP_MICRO_VERSION" "$_tar" micro
}

_primer_step_micro_install() {
    yush_info "Installing micro v$PRIMER_STEP_MICRO_VERSION"
    _primer_step_micro_install_download || return 1
    # Check version
    yush_debug "Verifying installed version against $PRIMER_STEP_MICRO_VERSION"
    instver=$(primer_version_current "${PRIMER_BINDIR%%/}/micro")
    yush_info "Installed micro v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/micro"
    if [ "$instver" != "$PRIMER_STEP_MICRO_VERSION" ]; then
        yush_warn "Installed micro version mismatch: should have been $PRIMER_STEP_MICRO_VERSION"
    fi
}
