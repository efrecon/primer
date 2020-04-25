#!/usr/bin/env sh

# Version of lazydocker to download. Can be set from the outside, defaults to
# empty, meaning the latest as per the variable below.
LAZYDOCKER_VERSION=${LAZYDOCKER_VERSION:-}

# URL to JSON file where to find the list of releases of lazydocker. The code
# only supports github API.
LAZYDOCKER_RELEASES=https://api.github.com/repos/jesseduffield/lazydocker/releases

# Root URL to download location
LAZYDOCKER_DOWNLOAD=https://github.com/jesseduffield/lazydocker/releases/download

# Decide curl options depending on log-level
if yush_loglevel_le verbose; then
    LAZYDOCKER_CURL_OPTS="-fSL --progress-bar"
else
    LAZYDOCKER_CURL_OPTS=-sSL
fi

lazydocker() {
    case "$1" in
        "option")
            shift;
            while [ $# -gt 0 ]; do
                case "$1" in
                    --version)
                        LAZYDOCKER_VERSION=$2; shift 2;;
                    -*)
                        yush_warn "Unknown option: $1 !"; shift 2;;
                    *)
                        break;;
                esac
            done
            ;;
        "install")
            primer_os_dependency curl
            if ! [ -x "$(command -v "lazydocker")" ]; then
                if [ -z "$LAZYDOCKER_VERSION" ]; then
                    # Following uses the github API
                    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
                    # for getting the list of latest releases and focuses solely on
                    # "full" releases. Release candidates have -rcXXX in their version
                    # number, these are set away by the grep/sed combo.
                    yush_notice "Discovering latest Docker Lazydocker version from $LAZYDOCKER_RELEASES"
                    LAZYDOCKER_VERSION=$(  curl $LAZYDOCKER_CURL_OPTS "$LAZYDOCKER_RELEASES" |
                                        grep -E '"name"[[:space:]]*:[[:space:]]*"v[0-9]+(\.[0-9]+)*"' |
                                        sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"v([0-9]+(\.[0-9]+)*)",/\1/g' |
                                        head -1)
                fi
                yush_info "Installing lazydocker $LAZYDOCKER_VERSION"
                _lazydocker_install_download
                # Check version
                yush_debug "Verifying installed version against $LAZYDOCKER_VERSION"
                instver=$("${PRIMER_BINDIR%%/}/lazydocker" --version|grep "Version"|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)
                yush_info "Installed lazydocker v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/lazydocker"
                if [ "$instver" != "$LAZYDOCKER_VERSION" ]; then
                    yush_warn "Installed lazydocker version mismatch: should have been $LAZYDOCKER_VERSION"
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
_lazydocker_install_download() {
    tmpdir=$(mktemp -d)
    tar_file="lazydocker_${LAZYDOCKER_VERSION}_$(uname -s)_$(uname -m).tar.gz"
    if curl $LAZYDOCKER_CURL_OPTS "${LAZYDOCKER_DOWNLOAD%%/}/v$LAZYDOCKER_VERSION/$tar_file" > "${tmpdir}/$tar_file"; then
        curl $LAZYDOCKER_CURL_OPTS "${LAZYDOCKER_DOWNLOAD%%/}/v$LAZYDOCKER_VERSION/checksums.txt" > "${tmpdir}/checksums.txt"
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
        yush_warn "No binary at ${LAZYDOCKER_DOWNLOAD%%/}/v$LAZYDOCKER_VERSION/$tar_file"
    fi
    rm -rf "$tmpdir"
}
