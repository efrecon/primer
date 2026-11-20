#!/usr/bin/env sh

# Version of lazydocker to download. Can be set from the outside, defaults to
# empty, meaning the latest as per the variable below.
PRIMER_STEP_LAZYDOCKER_VERSION=${PRIMER_STEP_LAZYDOCKER_VERSION:-}

# URL to JSON file where to find the list of releases of lazydocker. The code
# only supports github API.
PRIMER_STEP_LAZYDOCKER_RELEASES=https://api.github.com/repos/jesseduffield/lazydocker/releases

# Root URL to download location
PRIMER_STEP_LAZYDOCKER_DOWNLOAD=https://github.com/jesseduffield/lazydocker/releases/download

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
                PRIMER_STEP_LAZYDOCKER_VERSION=$(primer_version_github_latest "$PRIMER_STEP_LAZYDOCKER_RELEASES" "lazydocker")
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
            yush_info "Removing lazydocker"
            if [ -f "${PRIMER_BINDIR%%/}/lazydocker" ]; then
                $PRIMER_OS_SUDO rm -f "${PRIMER_BINDIR%%/}/lazydocker"
            fi
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
    _release="${PRIMER_STEP_LAZYDOCKER_DOWNLOAD%%/}/v$PRIMER_STEP_LAZYDOCKER_VERSION"
    _tar="lazydocker_${PRIMER_STEP_LAZYDOCKER_VERSION}_$(uname -s)_${_arch}.tar.gz"
    _tmpdir=$(mktemp -d)
    _rc=1
    if ! primer_net_curl "${_release}/$_tar" > "${_tmpdir}/$_tar"; then
        yush_error "No binary at ${_release}/$_tar"
    else
        _remote_sum=$(primer_net_curl "${_release}/checksums.txt" |
            awk -v a="$_tar" '{f=$2; sub(/^\*/, "", f); if (f == a && !s) s = $1} END {print s}' || true)
        _local_sum=$(sha256sum < "${_tmpdir}/$_tar" | cut -d " " -f 1)
        if [ -z "$_remote_sum" ]; then
            yush_error "Could not find sha256 sum for $_tar in ${_release}/checksums.txt, will not install"
        elif [ "$_local_sum" != "$_remote_sum" ]; then
            yush_error "Checksum mismatch for downloaded file $_tar, should have been $(yush_red "$_remote_sum"). Giving up on lazydocker!"
        else
            tar -C "$_tmpdir" -zxf "$_tmpdir/${_tar}"
            if ! [ -f "$_tmpdir/lazydocker" ]; then
                yush_error "Cannot find lazydocker in $_tar"
            else
                chmod a+x "$_tmpdir/lazydocker"
                [ -d "$PRIMER_BINDIR" ] || $PRIMER_OS_SUDO mkdir -p "$PRIMER_BINDIR"
                $PRIMER_OS_SUDO mv -f "$_tmpdir/lazydocker" "${PRIMER_BINDIR%%/}/lazydocker"
                _rc=0
            fi
        fi
    fi
    rm -rf "$_tmpdir"
    return "$_rc"
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
