#!/usr/bin/env sh

# Version of micro to download. Can be set from the outside, defaults to
# empty, meaning the latest as per the variable below.
PRIMER_STEP_MICRO_VERSION=${PRIMER_STEP_MICRO_VERSION:-}

# URL to JSON file where to find the list of releases of micro. The code only
# supports github API.
PRIMER_STEP_MICRO_RELEASES=https://api.github.com/repos/micro-editor/micro/releases

# Root URL to download location
PRIMER_STEP_MICRO_DOWNLOAD=https://github.com/micro-editor/micro/releases/download

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
                PRIMER_STEP_MICRO_VERSION=$(primer_version_github_latest "$PRIMER_STEP_MICRO_RELEASES" "micro")
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
            yush_info "Removing micro"
            if [ -f "${PRIMER_BINDIR%%/}/micro" ]; then
                $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/micro"
            fi
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

    _url="${PRIMER_STEP_MICRO_DOWNLOAD%%/}/v$PRIMER_STEP_MICRO_VERSION/$_tar"
    _tmpdir=$(mktemp -d)
    _rc=1
    if ! primer_net_curl "$_url" > "${_tmpdir}/$_tar"; then
        yush_error "No binary at $_url"
    else
        # The .sha file contains: <sha256>  <file>
        _remote_sum=$(primer_net_curl "${_url}.sha" |
            awk -v a="$_tar" '{f=$2; sub(/^\*/, "", f); if (f == a && !s) s = $1} END {print s}' || true)
        if [ -z "$_remote_sum" ]; then
            yush_error "Could not find sha256 sum for $_tar in ${_url}.sha, will not install"
        elif [ "$(sha256sum < "${_tmpdir}/$_tar" | cut -d " " -f 1)" != "$_remote_sum" ]; then
            yush_error "SHA256 sum mismatch for $_tar, should have been $_remote_sum"
        else
            tar -C "$_tmpdir" -zxf "$_tmpdir/${_tar}"
            if [ -f "$_tmpdir/micro-${PRIMER_STEP_MICRO_VERSION}/micro" ]; then
                [ -d "$PRIMER_BINDIR" ] || $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                primer_utils_install_bin "$_tmpdir/micro-${PRIMER_STEP_MICRO_VERSION}/micro" "${PRIMER_BINDIR%%/}/micro"
                _rc=0
            else
                yush_error "No micro binary found in tar file!"
            fi
        fi
    fi
    rm -rf "$_tmpdir"
    return "$_rc"
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
