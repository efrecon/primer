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
            if [ -x "$(command -v "lazydocker")" ]; then
                if [ -z "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                    PRIMER_STEP_LAZYDOCKER_VERSION=$(primer_version_github_latest "$PRIMER_STEP_LAZYDOCKER_RELEASES" "lazydocker")
                fi
                if [ -n "$PRIMER_STEP_LAZYDOCKER_VERSION" ] && \
                    [ "$(primer_version_current "lazydocker")" != "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                    _primer_step_lazydocker_install
                fi
            else
                if [ -z "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                    PRIMER_STEP_LAZYDOCKER_VERSION=$(primer_version_github_latest "$PRIMER_STEP_LAZYDOCKER_RELEASES" "lazydocker")
                fi
                if [ -n "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
                    _primer_step_lazydocker_install
                fi
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

# Download from github, making sure we can actually execute the binary that we
# downloaded. We download the first byte to check all the redirects, and on
# success we will download everything and possibly check against the sha256 sum.
_primer_step_lazydocker_install_download() {
    tmpdir=$(mktemp -d)
    _arch=$(uname -m)
    case "$_arch" in
        armv7*) _arch=armv7;;
        armv6*) _arch=armv6;;
    esac
    tar_file="lazydocker_${PRIMER_STEP_LAZYDOCKER_VERSION}_$(uname -s)_${_arch}.tar.gz"
    if primer_net_curl "${PRIMER_STEP_LAZYDOCKER_DOWNLOAD%%/}/v$PRIMER_STEP_LAZYDOCKER_VERSION/$tar_file" > "${tmpdir}/$tar_file"; then
        primer_net_curl "${PRIMER_STEP_LAZYDOCKER_DOWNLOAD%%/}/v$PRIMER_STEP_LAZYDOCKER_VERSION/checksums.txt" > "${tmpdir}/checksums.txt"
        local_sum=$(sha256sum "${tmpdir}/$tar_file" | awk '{print $1};')
        remote_sum=$(grep "$tar_file" "${tmpdir}/checksums.txt"|awk '{print $1};')
        if [ "$local_sum" != "$remote_sum" ]; then
            yush_warn "Checksum mismatch for downloaded file $tar_file, should have been $(yush_red "$remote_sum"). Giving up on lazydocker!"
        else
            tar -C "$tmpdir" -zxf "$tmpdir/${tar_file}"
            if [ -f "$tmpdir/lazydocker" ]; then
                chmod a+x "$tmpdir/lazydocker"
                $PRIMER_OS_SUDO mv -f "$tmpdir/lazydocker" "${PRIMER_BINDIR%%/}/lazydocker"
            fi
        fi
    else
        yush_warn "No binary at ${PRIMER_STEP_LAZYDOCKER_DOWNLOAD%%/}/v$PRIMER_STEP_LAZYDOCKER_VERSION/$tar_file"
    fi
    rm -rf "$tmpdir"
}

_primer_step_lazydocker_install() {
    yush_info "Installing lazydocker $PRIMER_STEP_LAZYDOCKER_VERSION"
    _primer_step_lazydocker_install_download
    # Check version
    yush_debug "Verifying installed version against $PRIMER_STEP_LAZYDOCKER_VERSION"
    instver=$(primer_version_current "${PRIMER_BINDIR%%/}/lazydocker")
    yush_info "Installed lazydocker v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/lazydocker"
    if [ "$instver" != "$PRIMER_STEP_LAZYDOCKER_VERSION" ]; then
        yush_warn "Installed lazydocker version mismatch: should have been $PRIMER_STEP_LAZYDOCKER_VERSION"
    fi
}
