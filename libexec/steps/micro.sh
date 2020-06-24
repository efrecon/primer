#!/usr/bin/env sh

# Version of micro to download. Can be set from the outside, defaults to
# empty, meaning the latest as per the variable below.
PRIMER_STEP_MICRO_VERSION=${PRIMER_STEP_MICRO_VERSION:-}

# URL to JSON file where to find the list of releases of micro. The code only
# supports github API.
PRIMER_STEP_MICRO_RELEASES=https://api.github.com/repos/zyedidia/micro/releases

# Root URL to download location
PRIMER_STEP_MICRO_DOWNLOAD=https://github.com/zyedidia/micro/releases/download

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
            if ! [ -x "$(command -v "micro")" ]; then
                if [ -z "$PRIMER_STEP_MICRO_VERSION" ]; then
                    # Following uses the github API
                    # https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
                    # for getting the list of latest releases and focuses solely on
                    # "full" releases. Release candidates have -rcXXX in their version
                    # number, these are set away by the grep/sed combo.
                    yush_notice "Discovering latest Docker Micro version from $PRIMER_STEP_MICRO_RELEASES"
                    PRIMER_STEP_MICRO_VERSION=$(   primer_net_curl "$PRIMER_STEP_MICRO_RELEASES" |
                                    grep -E '"name"[[:space:]]*:[[:space:]]*"[0-9]+(\.[0-9]+)*"' |
                                    sed -E 's/[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([0-9]+(\.[0-9]+)*)",/\1/g' |
                                    head -1)

                fi
                yush_info "Installing micro v$PRIMER_STEP_MICRO_VERSION"
                _primer_step_micro_install_download
                # Check version
                yush_debug "Verifying installed version against $PRIMER_STEP_MICRO_VERSION"
                instver=$("${PRIMER_BINDIR%%/}/micro" --version|grep "Version"|grep -E -o '[0-9]+(\.[0-9]+)*'|head -1)
                yush_info "Installed micro v$(yush_yellow "$instver") at ${PRIMER_BINDIR%%/}/micro"
                if [ "$instver" != "$PRIMER_STEP_MICRO_VERSION" ]; then
                    yush_warn "Installed micro version mismatch: should have been $PRIMER_STEP_MICRO_VERSION"
                fi
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

# Download from github
_primer_step_micro_install_download() {
    tmpdir=$(mktemp -d)
    ostype=$(printf %s\\n "$(uname -s)" | tr '[:upper:]' '[:lower:]')
    case "$(uname -m)" in
        x86_64)
            tar_file="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}$(getconf LONG_BIT)-static.tar.gz";;
        x86)
            tar_file="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}$(getconf LONG_BIT).tar.gz";;
        armv8*|aarch*)
            tar_file="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}-arm64.tar.gz";;
        armv7*)
            tar_file="micro-${PRIMER_STEP_MICRO_VERSION}-${ostype}-arm.tar.gz";;
        *)
            yush_error "No known binaries on this platform"; return;;
    esac

    if primer_net_curl "${PRIMER_STEP_MICRO_DOWNLOAD%%/}/v$PRIMER_STEP_MICRO_VERSION/$tar_file" > "${tmpdir}/$tar_file"; then
        tar -C "$tmpdir" -zxf "$tmpdir/${tar_file}"
        if [ -f "$tmpdir/micro-${PRIMER_STEP_MICRO_VERSION}/micro" ]; then
            $PRIMER_OS_SUDO mv -f "$tmpdir/micro-${PRIMER_STEP_MICRO_VERSION}/micro" "${PRIMER_BINDIR%%/}/micro"
        else
            yush_error "No micro binary found in tar file!"
        fi
    else
        yush_warn "No binary at ${PRIMER_STEP_MICRO_DOWNLOAD%%/}/v$PRIMER_STEP_MICRO_VERSION/$tar_file"
    fi
    rm -rf "$tmpdir"
}
